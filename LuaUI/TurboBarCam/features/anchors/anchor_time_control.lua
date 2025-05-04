---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type EasingFunctions
local EasingFunctions = VFS.Include("LuaUI/TurboBarCam/features/anchors/anchor_easing_functions.lua").EasingFunctions

local Log = CommonModules.Log
local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG
local Util = CommonModules.Util
local CameraCommons = CommonModules.CameraCommons

---@class AnchorTimeControl
local AnchorTimeControl = {}

-- Safety velocity limits to prevent extreme speeds without affecting normal operation
local MAX_VELOCITY = 5000  -- Maximum allowed velocity (prevents extreme speeds)
local MIN_VELOCITY = 50    -- Minimum velocity (prevents stopping)

-- Add detailed logging of the detected velocities
local function logVelocityInfo(pathInfo)
    Log.info("=========== VELOCITY DIAGNOSTICS ===========")
    Log.info("Path contains " .. #pathInfo.points .. " points and " .. #pathInfo.steps .. " steps")

    -- Log segment velocities from points
    Log.info("--- SEGMENT VELOCITIES FROM ANCHOR POINTS ---")
    local segmentStartTime = 0
    for i = 1, #pathInfo.points - 1 do
        local p1 = pathInfo.points[i].state
        local p2 = pathInfo.points[i + 1].state

        -- Calculate distance
        local dist = math.sqrt(
                (p2.px - p1.px) ^ 2 +
                        (p2.py - p1.py) ^ 2 +
                        (p2.pz - p1.pz) ^ 2
        )

        -- Get transition time
        local transTime = pathInfo.points[i].transitionTime or 1.0

        -- Calculate raw velocity
        local rawVelocity = dist / transTime

        Log.info(string.format("Segment %d: %.1f units in %.1f seconds = %.1f units/sec (%.1f-%1.f)",
                i, dist, transTime, rawVelocity, segmentStartTime, segmentStartTime + transTime))

        segmentStartTime = segmentStartTime + transTime
    end

    -- Sample velocities along the path
    Log.info("--- VELOCITIES AT KEY POINTS ALONG PATH ---")
    if pathInfo.steps and #pathInfo.steps >= 2 then
        -- Check beginning, middle, and end, plus transitions between segments
        local checkPoints = {
            { index = 1, name = "Start" },
            { index = math.floor(#pathInfo.steps * 0.25), name = "25%" },
            { index = math.floor(#pathInfo.steps * 0.5), name = "Middle" },
            { index = math.floor(#pathInfo.steps * 0.75), name = "75%" },
            { index = #pathInfo.steps - 1, name = "End" }
        }

        -- Add segment transition points
        local segmentStartTime = 0
        for i = 1, #pathInfo.points - 1 do
            local transTime = pathInfo.points[i].transitionTime or 1.0
            segmentStartTime = segmentStartTime + transTime

            -- Find step closest to this segment transition
            local bestIndex = 1
            local minDiff = math.huge

            for j = 1, #pathInfo.steps do
                local diff = math.abs(pathInfo.steps[j].time - segmentStartTime)
                if diff < minDiff then
                    minDiff = diff
                    bestIndex = j
                end
            end

            if bestIndex > 1 and bestIndex < #pathInfo.steps then
                table.insert(checkPoints, {
                    index = bestIndex - 1,
                    name = "Before Transition " .. i .. "->" .. (i + 1)
                })
                table.insert(checkPoints, {
                    index = bestIndex,
                    name = "At Transition " .. i .. "->" .. (i + 1)
                })
                table.insert(checkPoints, {
                    index = bestIndex + 1,
                    name = "After Transition " .. i .. "->" .. (i + 1)
                })
            end
        end

        -- Sort check points by index
        table.sort(checkPoints, function(a, b)
            return a.index < b.index
        end)

        -- Calculate velocities at check points
        for _, cp in ipairs(checkPoints) do
            if cp.index < #pathInfo.steps then
                local step1 = pathInfo.steps[cp.index]
                local step2 = pathInfo.steps[cp.index + 1]

                local dx = step2.state.px - step1.state.px
                local dy = step2.state.py - step1.state.py
                local dz = step2.state.pz - step1.state.pz
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

                local dt = step2.time - step1.time
                local velocity = dt > 0.0001 and dist / dt or 0

                Log.info(string.format("  %s (step %d): %s -> %s in %.5f sec = %.1f units/sec",
                        cp.name,
                        cp.index,
                        Util.formatVector({ x = step1.state.px, y = step1.state.py, z = step1.state.pz }),
                        Util.formatVector({ x = step2.state.px, y = step2.state.py, z = step2.state.pz }),
                        dt,
                        velocity))

                -- Alert on extreme velocities
                if velocity > MAX_VELOCITY * 0.5 then
                    Log.warn(string.format("  !!! EXTREME VELOCITY DETECTED: %.1f units/sec at %s !!!",
                            velocity, cp.name))
                end
            end
        end
    end

    Log.info("=========== END VELOCITY DIAGNOSTICS ===========")
end

-- Add a helper function to format vectors for logging
if not Util.formatVector then
    Util.formatVector = function(v)
        return string.format("(%.1f, %.1f, %.1f)", v.x, v.y, v.z)
    end
end

--- Apply speed control to a camera path
---@param pathInfo table Path information structure
---@param speedControls table Array of {time, speed} control points
---@param easingFunc string|function Optional easing function name or function
---@return table pathInfo Updated path information
function AnchorTimeControl.applySpeedControl(pathInfo, speedControls, easingFunc)
    Log.info("======= STARTING SPEED CONTROL APPLICATION =======")

    -- Calculate speed control points from transition times if not provided
    if not speedControls or #speedControls < 2 then
        Log.info("No speed controls provided, deriving from transition times")
        speedControls = AnchorTimeControl.deriveSpeedFromTransitions(pathInfo.points)
    else
        Log.info(string.format("Using provided speed controls with %d points", #speedControls))
    end

    -- Log speed control points
    Log.info("--- SPEED CONTROL POINTS ---")
    for i, point in ipairs(speedControls) do
        Log.info(string.format("  Point %d: pos=%.3f, speed=%.1f", i, point.time, point.speed))
    end

    -- Get easing function if specified
    local easing = EasingFunctions.cameraCurve
    if easingFunc then
        if type(easingFunc) == "string" then
            Log.info("Using easing function: " .. easingFunc)
            easing = EasingFunctions[easingFunc]
            if not easing then
                Log.warn("Unknown easing function '" .. easingFunc .. "', using default")
                easing = EasingFunctions.cameraCurve
            end
        elseif type(easingFunc) == "function" then
            Log.info("Using custom easing function")
            easing = easingFunc
        end
    else
        Log.info("No easing function specified, using default")
    end

    -- Build time mapping with continuous speed transitions
    Log.info("Building continuous time mapping...")
    local timeMap = AnchorTimeControl.buildContinuousTimeMapping(speedControls, easing)

    -- Log time mapping diagnostics
    Log.info("--- TIME MAPPING DIAGNOSTICS ---")
    Log.info(string.format("  Total time factor: %.3f", timeMap.totalTime))
    Log.info(string.format("  Time map points: %d", #timeMap.points))

    -- Log some sample points from the time map
    local sampleIndices = { 1, 10, math.floor(#timeMap.points / 2), #timeMap.points - 10, #timeMap.points }
    for _, idx in ipairs(sampleIndices) do
        if idx <= #timeMap.points then
            Log.info(string.format("  Map point %d: input=%.3f -> output=%.3f",
                    idx, timeMap.points[idx].inputTime, timeMap.points[idx].outputTime))
        end
    end

    -- Log original path statistics
    Log.info("--- ORIGINAL PATH STATS ---")
    Log.info(string.format("  Total duration: %.2f seconds", pathInfo.totalDuration))
    Log.info(string.format("  Total steps: %d", #pathInfo.steps))
    if pathInfo.steps and #pathInfo.steps > 1 then
        local firstStep = pathInfo.steps[1]
        local lastStep = pathInfo.steps[#pathInfo.steps]
        Log.info(string.format("  Start position: %s",
                Util.formatVector({ x = firstStep.state.px, y = firstStep.state.py, z = firstStep.state.pz })))
        Log.info(string.format("  End position: %s",
                Util.formatVector({ x = lastStep.state.px, y = lastStep.state.py, z = lastStep.state.pz })))
    end

    -- Calculate original path length
    local originalLength = 0
    for i = 2, #pathInfo.steps do
        local p1 = pathInfo.steps[i - 1].state
        local p2 = pathInfo.steps[i].state
        local dist = math.sqrt(
                (p2.px - p1.px) ^ 2 +
                        (p2.py - p1.py) ^ 2 +
                        (p2.pz - p1.pz) ^ 2
        )
        originalLength = originalLength + dist
    end
    Log.info(string.format("  Original path length: %.1f units", originalLength))

    -- Instead of just remapping times, regenerate steps with proper spacing
    Log.info("Regenerating path steps using time mapping...")
    local oldStepCount = #pathInfo.steps
    pathInfo = AnchorTimeControl.regeneratePathSteps(pathInfo, timeMap)

    -- Log regenerated path statistics
    Log.info("--- REGENERATED PATH STATS ---")
    Log.info(string.format("  Total duration: %.2f seconds", pathInfo.totalDuration))
    Log.info(string.format("  Total steps: %d (was %d)", #pathInfo.steps, oldStepCount))

    -- Calculate new path length
    local newLength = 0
    for i = 2, #pathInfo.steps do
        local p1 = pathInfo.steps[i - 1].state
        local p2 = pathInfo.steps[i].state
        local dist = math.sqrt(
                (p2.px - p1.px) ^ 2 +
                        (p2.py - p1.py) ^ 2 +
                        (p2.pz - p1.pz) ^ 2
        )
        newLength = newLength + dist
    end
    Log.info(string.format("  New path length: %.1f units", newLength))
    Log.info(string.format("  Path length ratio: %.3f", newLength / originalLength))

    -- Store the speed controls for future reference
    pathInfo.speedControls = speedControls
    pathInfo.easingFunction = easingFunc

    -- Check for extreme velocities and log comprehensive velocity info
    logVelocityInfo(pathInfo)

    Log.info("======= COMPLETED SPEED CONTROL APPLICATION =======")

    return pathInfo
end

--- Derive speed control points from anchor point transition times
---@param points table Array of path points with transition times
---@return table speedControls Array of {time, speed} control points
function AnchorTimeControl.deriveSpeedFromTransitions(points)
    Log.info("Deriving speed controls from transitions for " .. #points .. " points")

    local speedControls = {}
    local totalDist = 0
    local segmentDistances = {}

    -- First, calculate all segment distances
    Log.info("--- CALCULATING SEGMENT DISTANCES AND SPEEDS ---")
    for i = 2, #points do
        local p1 = points[i - 1].state
        local p2 = points[i].state

        local dist = math.sqrt(
                (p2.px - p1.px) ^ 2 +
                        (p2.py - p1.py) ^ 2 +
                        (p2.pz - p1.pz) ^ 2
        )

        local time = points[i - 1].transitionTime or 1.0
        local rawSpeed = dist / time
        Log.info(string.format("Segment %d: distance=%.1f, time=%.1f, raw speed=%.1f",
                i - 1, dist, time, rawSpeed))

        table.insert(segmentDistances, dist)
        totalDist = totalDist + dist
    end

    -- Calculate normalized positions and speeds for each anchor
    local currentDist = 0

    -- Add starting point with its speed
    local firstSegmentTime = points[1].transitionTime or 1.0
    local firstSegmentSpeed = segmentDistances[1] / firstSegmentTime

    -- Apply velocity limits
    local clampedSpeed = math.max(MIN_VELOCITY, math.min(MAX_VELOCITY, firstSegmentSpeed))
    if clampedSpeed ~= firstSegmentSpeed then
        Log.warn(string.format("Clamped start speed from %.1f to %.1f", firstSegmentSpeed, clampedSpeed))
    end
    firstSegmentSpeed = clampedSpeed

    table.insert(speedControls, {
        time = 0,
        speed = firstSegmentSpeed
    })

    Log.info("--- GENERATING SPEED CONTROL POINTS ---")
    Log.info(string.format("Added control point: pos=0.000, speed=%.1f", firstSegmentSpeed))

    -- Add interior points with their speeds
    for i = 2, #points - 1 do
        currentDist = currentDist + segmentDistances[i - 1]
        local normalizedPos = currentDist / totalDist

        local segmentTime = points[i].transitionTime or 1.0
        local segmentSpeed = segmentDistances[i] / segmentTime

        -- Apply velocity limits
        local clampedSpeed = math.max(MIN_VELOCITY, math.min(MAX_VELOCITY, segmentSpeed))
        if clampedSpeed ~= segmentSpeed then
            Log.warn(string.format("Clamped segment %d speed from %.1f to %.1f",
                    i, segmentSpeed, clampedSpeed))
        end
        segmentSpeed = clampedSpeed

        table.insert(speedControls, {
            time = normalizedPos,
            speed = segmentSpeed
        })

        Log.info(string.format("Added control point: pos=%.3f, speed=%.1f", normalizedPos, segmentSpeed))
    end

    -- Add endpoint
    table.insert(speedControls, {
        time = 1.0,
        speed = firstSegmentSpeed  -- End with same speed as start for smooth looping
    })

    Log.info(string.format("Added control point: pos=1.000, speed=%.1f", firstSegmentSpeed))

    -- Add extra control points for smooth transitions between speeds
    Log.info("--- ADDING TRANSITION CONTROL POINTS ---")
    local smoothedControls = {}

    -- Add more transition points around anchor boundaries for smoother blending
    local transitionPointCount = 3 -- Increase for even smoother transitions

    -- Add first point
    table.insert(smoothedControls, speedControls[1])

    -- Process interior points with improved transitions
    for i = 1, #speedControls - 1 do
        local p1 = speedControls[i]
        local p2 = speedControls[i + 1]
        local segmentLength = p2.time - p1.time

        if segmentLength > 0.1 then
            -- Only add points for reasonably large segments
            -- Add multiple transition points for smoother blending
            -- Don't remove the last point to avoid issues

            for j = 1, transitionPointCount - 1 do
                local position = p1.time + (j / transitionPointCount) * segmentLength
                local blend = j / transitionPointCount
                -- Cubic blending function for smoother transition
                local smoothBlend = blend * blend * (3 - 2 * blend)
                local speed = p1.speed * (1 - smoothBlend) + p2.speed * smoothBlend

                table.insert(smoothedControls, {
                    time = position,
                    speed = speed
                })
            end
        end

        -- Always add the endpoint
        table.insert(smoothedControls, p2)
    end

    Log.info(string.format("Raw control points: %d", #smoothedControls))

    -- Apply global smoothing to eliminate any remaining discontinuities
    Log.info("Applying global smoothing to speed curve...")
    speedControls = AnchorTimeControl.globalSpeedSmoothing(smoothedControls, 3)

    Log.info(string.format("Final smoothed control points: %d", #speedControls))

    return speedControls
end

--- Apply global smoothing to speed curve
---@param speedControls table Array of speed control points
---@param passes number Number of smoothing passes
---@return table smoothedControls Smoothed speed control points
function AnchorTimeControl.globalSpeedSmoothing(speedControls, passes)
    local result = Util.deepCopy(speedControls)

    -- Sort by time
    table.sort(result, function(a, b)
        return a.time < b.time
    end)

    -- Apply multiple passes of smoothing
    for pass = 1, passes do
        local extremeChangesCount = 0
        local smoothed = { result[1] }  -- Keep first point unchanged

        -- Apply smoothing to all interior points
        for i = 2, #result - 1 do
            local prevSpeed = result[i - 1].speed
            local currSpeed = result[i].speed
            local nextSpeed = result[i + 1].speed

            -- Check for extreme changes
            local ratio1 = currSpeed / prevSpeed
            local ratio2 = nextSpeed / currSpeed
            if ratio1 > 2 or ratio1 < 0.5 or ratio2 > 2 or ratio2 < 0.5 then
                extremeChangesCount = extremeChangesCount + 1
                Log.warn(string.format("Extreme speed change at pos=%.3f: %d->%d->%d (ratios: %.2f, %.2f)",
                        result[i].time, prevSpeed, currSpeed, nextSpeed, ratio1, ratio2))
            end

            -- Weighted average
            local smoothedSpeed = prevSpeed * 0.25 + currSpeed * 0.5 + nextSpeed * 0.25

            -- Apply velocity limits
            smoothedSpeed = math.max(MIN_VELOCITY, math.min(MAX_VELOCITY, smoothedSpeed))

            table.insert(smoothed, {
                time = result[i].time,
                speed = smoothedSpeed
            })
        end

        -- Keep last point unchanged
        table.insert(smoothed, result[#result])

        -- Log pass results
        Log.info(string.format("Smoothing pass %d: found %d extreme changes", pass, extremeChangesCount))

        -- Update result for next pass
        result = smoothed
    end

    return result
end

--- Build a continuous time mapping from speed control points
---@param speedControls table Array of {time, speed} control points
---@param easingFunc function|nil Optional easing function
---@return table timeMap Time mapping information
function AnchorTimeControl.buildContinuousTimeMapping(speedControls, easingFunc)
    -- Ensure we have normalized time points (0-1)
    table.sort(speedControls, function(a, b)
        return a.time < b.time
    end)

    -- Ensure we have control points at 0 and 1
    if speedControls[1].time > 0 then
        table.insert(speedControls, 1, { time = 0, speed = speedControls[1].speed })
        Log.info("Added missing control point at position 0")
    end
    if speedControls[#speedControls].time < 1 then
        table.insert(speedControls, { time = 1, speed = speedControls[#speedControls].speed })
        Log.info("Added missing control point at position 1")
    end

    -- Initialize time mapping structure
    local timeMap = {
        points = {},
        totalTime = 0,
        easingFunc = easingFunc,
        speedControls = speedControls
    }

    -- Create continuous speed function
    local speedFunction = function(t)
        -- Handle edge cases
        if t <= 0 then
            return speedControls[1].speed
        end
        if t >= 1 then
            return speedControls[#speedControls].speed
        end

        -- Find which segment contains this time
        local i = 1
        while i < #speedControls and t > speedControls[i + 1].time do
            i = i + 1
        end

        local p1 = speedControls[i]
        local p2 = speedControls[i + 1]

        -- Calculate normalized position in this segment
        local segmentT = 0
        if p2.time > p1.time then
            segmentT = (t - p1.time) / (p2.time - p1.time)
        end

        -- Use smooth cubic interpolation
        local t2 = segmentT * segmentT
        local t3 = t2 * segmentT
        -- Cubic Hermite spline (smoothstep): 3t² - 2t³
        local easedT = 3 * t2 - 2 * t3

        local speed = p1.speed * (1 - easedT) + p2.speed * easedT

        return speed
    end

    -- Log speed at various points
    Log.info("--- SPEED FUNCTION SAMPLES ---")
    for i = 0, 10 do
        local t = i / 10
        Log.info(string.format("Speed at %.1f: %.1f units/sec", t, speedFunction(t)))
    end

    -- Add first mapping point
    table.insert(timeMap.points, {
        inputTime = 0,
        outputTime = 0
    })

    -- Use smaller segments for accurate numerical integration
    local numSegments = 100
    local segmentSize = 1.0 / numSegments
    local currentTime = 0

    -- Calculate time mapping through numerical integration
    Log.info("--- NUMERICAL INTEGRATION OF SPEED FUNCTION ---")
    local maxTimeDelta = 0
    local minTimeDelta = 999999

    for i = 1, numSegments do
        local t = (i - 1) * segmentSize
        local nextT = i * segmentSize

        -- Get speeds at segment boundaries
        local speed1 = speedFunction(t)
        local speed2 = speedFunction(nextT)

        -- Use trapezoidal rule for integration
        local avgSpeed = (speed1 + speed2) / 2

        -- Calculate segment duration (distance/speed)
        local segmentDuration = segmentSize / math.max(0.001, avgSpeed)
        currentTime = currentTime + segmentDuration

        -- Track max/min time deltas for stability analysis
        maxTimeDelta = math.max(maxTimeDelta, segmentDuration)
        minTimeDelta = math.min(minTimeDelta, segmentDuration)

        -- Add mapping point
        table.insert(timeMap.points, {
            inputTime = nextT,
            outputTime = currentTime
        })

        -- Log sample points for diagnostics
        if i % 10 == 0 or i == 1 or i == numSegments then
            Log.info(string.format("Segment %d: t=%.2f, speed=%.1f, duration=%.5f, total=%.5f",
                    i, nextT, avgSpeed, segmentDuration, currentTime))
        end
    end

    Log.info(string.format("Integration complete: max delta=%.5f, min delta=%.5f, ratio=%.1f",
            maxTimeDelta, minTimeDelta, maxTimeDelta / minTimeDelta))

    -- Normalize the output times to 0-1 range
    timeMap.totalTime = timeMap.points[#timeMap.points].outputTime
    for i = 1, #timeMap.points do
        timeMap.points[i].outputTime = timeMap.points[i].outputTime / timeMap.totalTime
    end

    Log.info(string.format("Time mapping normalized with totalTime=%.5f", timeMap.totalTime))

    -- Apply global easing function if provided
    if easingFunc then
        Log.info("Applying global easing function to time mapping")

        -- First pre-process output times to ensure smooth derivatives at boundaries
        local outputTimes = {}
        for i = 1, #timeMap.points do
            outputTimes[i] = timeMap.points[i].outputTime
        end

        -- Apply easing with boundary preservation
        for i = 1, #timeMap.points do
            local originalT = timeMap.points[i].outputTime
            local easedT = easingFunc(originalT)

            -- Critical fix: Ensure first derivative is continuous at boundaries
            -- by preserving the original slope at boundaries
            if i <= 3 then
                -- First few points: gradually blend from linear to eased
                local blendFactor = (i - 1) / 3
                easedT = originalT * (1 - blendFactor) + easedT * blendFactor
            elseif i >= #timeMap.points - 2 then
                -- Last few points: gradually blend from eased to linear
                local blendFactor = (#timeMap.points - i) / 3
                easedT = originalT * blendFactor + easedT * (1 - blendFactor)
            end

            -- Apply and ensure within bounds (for safety)
            timeMap.points[i].outputTime = math.max(0, math.min(1, easedT))

            -- Log some sample points
            if i % 20 == 0 or i == 1 or i == #timeMap.points then
                Log.info(string.format("Easing applied at point %d: %.3f -> %.3f",
                        i, originalT, timeMap.points[i].outputTime))
            end
        end
    end

    return timeMap
end

--- Regenerates the path steps with even time distribution but positioned according to speed profile
---@param pathInfo table Path information structure
---@param timeMap table Time mapping information
---@return table pathInfo Updated path information with redistributed steps
function AnchorTimeControl.regeneratePathSteps(pathInfo, timeMap)
    -- Original total duration
    local originalDuration = pathInfo.totalDuration

    -- Calculate desired number of steps based on duration and steps per second
    local numSteps = math.max(
            300, -- minimum number of steps for smooth movement
            math.floor(originalDuration * CONFIG.PERFORMANCE.ANCHOR_STEPS_PER_SECOND)
    )

    Log.info(string.format("Regenerating path with %d steps (duration=%.2f, steps/sec=%d)",
            numSteps, originalDuration, CONFIG.PERFORMANCE.ANCHOR_STEPS_PER_SECOND))

    -- Recreate steps with even time distribution
    local newSteps = {}
    local stepTimeInterval = originalDuration / (numSteps - 1)

    -- Track max velocity for diagnostics
    local maxVelocity = 0
    local maxVelocityIndex = 0
    local maxVelocityTime = 0

    -- Log detailed diagnostics at problematic parts of the path
    Log.info("--- STEP REGENERATION DIAGNOSTICS ---")

    -- Sample points to log
    local samplePoints = { 1, 10, numSteps / 4, numSteps / 2, 3 * numSteps / 4, numSteps - 10, numSteps }

    for i = 1, numSteps do
        -- Even time distribution
        local stepTime = (i - 1) * stepTimeInterval

        -- Convert to normalized time (0-1)
        local normalizedTime = stepTime / originalDuration

        -- Find corresponding source time using the inverse of our time mapping
        local sourceTime = AnchorTimeControl.inverseInterpolateTime(normalizedTime, timeMap)

        -- Find the position at this source time by interpolating original path
        local stepState = AnchorTimeControl.interpolatePathAtTime(pathInfo, sourceTime * originalDuration)

        -- Add the new step
        table.insert(newSteps, {
            time = stepTime,
            state = stepState
        })

        -- Calculate velocity for diagnostics (if not the first step)
        if i > 1 then
            local prev = newSteps[i - 1]
            local curr = newSteps[i]

            local dx = curr.state.px - prev.state.px
            local dy = curr.state.py - prev.state.py
            local dz = curr.state.pz - prev.state.pz

            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            local dt = curr.time - prev.time

            local velocity = dt > 0.0001 and dist / dt or 0

            -- Track maximum velocity
            if velocity > maxVelocity then
                maxVelocity = velocity
                maxVelocityIndex = i
                maxVelocityTime = stepTime
            end

            -- Log sample points
            local doLog = false
            for _, sampleIndex in ipairs(samplePoints) do
                if math.abs(i - sampleIndex) < 2 then
                    doLog = true
                    break
                end
            end

            -- Also log extreme velocities
            if velocity > MAX_VELOCITY * 0.5 then
                doLog = true
            end

            if doLog then
                Log.info(string.format("Step %d (t=%.2f): norm=%.3f, source=%.3f, velocity=%.1f",
                        i, stepTime, normalizedTime, sourceTime, velocity))

                if velocity > MAX_VELOCITY * 0.5 then
                    Log.warn(string.format("  HIGH VELOCITY DETECTED: %.1f units/sec", velocity))

                    -- Log nearby steps for context
                    for j = math.max(1, i - 5), math.min(numSteps, i + 5) do
                        if j ~= i and newSteps[j] then
                            local neighborTime = (j - 1) * stepTimeInterval
                            local neighborNorm = neighborTime / originalDuration
                            local neighborSource = AnchorTimeControl.inverseInterpolateTime(neighborNorm, timeMap)

                            Log.info(string.format("  Context - Step %d (t=%.2f): norm=%.3f, source=%.3f",
                                    j, neighborTime, neighborNorm, neighborSource))
                        end
                    end
                end
            end
        end
    end

    Log.info(string.format("Max velocity: %.1f units/sec at step %d (time=%.2f)",
            maxVelocity, maxVelocityIndex, maxVelocityTime))

    -- Replace steps with new evenly-distributed ones
    pathInfo.steps = newSteps

    -- Update step time differences
    pathInfo.stepTimes = {}
    for i = 1, #pathInfo.steps - 1 do
        pathInfo.stepTimes[i] = pathInfo.steps[i + 1].time - pathInfo.steps[i].time
    end

    -- Update last step time
    if #pathInfo.steps > 0 then
        pathInfo.stepTimes[#pathInfo.stepTimes] = 0.01
    end

    pathInfo = AnchorTimeControl.smoothVelocityProfile(pathInfo)

    return pathInfo
end

--- Inverse interpolates time from output to input using time mapping
---@param normalizedOutputTime number Normalized output time (0-1)
---@param timeMap table Time mapping information
---@return number normalizedInputTime Remapped input time (0-1)
function AnchorTimeControl.inverseInterpolateTime(normalizedOutputTime, timeMap)
    -- Handle edge cases
    if normalizedOutputTime <= 0 then
        return 0
    end
    if normalizedOutputTime >= 1 then
        return 1
    end

    -- Find the segment in the time map
    local segmentIndex = 1
    for i = 1, #timeMap.points - 1 do
        if normalizedOutputTime >= timeMap.points[i].outputTime and
                normalizedOutputTime <= timeMap.points[i + 1].outputTime then
            segmentIndex = i
            break
        end
    end

    -- Get the output/input time ranges for this segment
    local o1 = timeMap.points[segmentIndex].outputTime
    local o2 = timeMap.points[segmentIndex + 1].outputTime
    local t1 = timeMap.points[segmentIndex].inputTime
    local t2 = timeMap.points[segmentIndex + 1].inputTime

    -- Calculate segment progress
    local segmentT = 0
    if o2 > o1 then
        -- Avoid division by zero
        segmentT = (normalizedOutputTime - o1) / (o2 - o1)
    end

    -- Map to input time with linear interpolation (keeps interpolation more stable)
    return t1 + (t2 - t1) * segmentT
end

--- Interpolates the path at a specific time
---@param pathInfo table Path information structure
---@param time number Time to interpolate at
---@return table state Interpolated camera state
function AnchorTimeControl.interpolatePathAtTime(pathInfo, time)
    -- Handle edge cases
    if time <= 0 then
        return Util.deepCopy(pathInfo.steps[1].state)
    end
    if time >= pathInfo.totalDuration then
        return Util.deepCopy(pathInfo.steps[#pathInfo.steps].state)
    end

    -- First attempt: Find waypoint segment that contains this time
    -- This allows us to use proper Hermite spline interpolation with tangents
    local segmentIndex = nil
    local segmentT = 0
    local segmentStartTime = 0

    for i = 1, #pathInfo.points - 1 do
        -- Calculate start time for this segment
        local startTime = segmentStartTime
        -- Calculate end time for this segment
        local transitionTime = pathInfo.points[i].transitionTime or 0
        local endTime = startTime + transitionTime

        if time >= startTime and time <= endTime then
            segmentIndex = i
            -- Calculate normalized position in this segment
            segmentT = transitionTime > 0 and (time - startTime) / transitionTime or 0
            break
        end

        segmentStartTime = endTime
    end

    -- If we found a waypoint segment, use Hermite interpolation with tangents
    if segmentIndex and pathInfo.points[segmentIndex].tangent and pathInfo.points[segmentIndex + 1].tangent then
        local p0 = pathInfo.points[segmentIndex].state
        local p1 = pathInfo.points[segmentIndex + 1].state
        local v0 = pathInfo.points[segmentIndex].tangent
        local v1 = pathInfo.points[segmentIndex + 1].tangent

        -- Use existing Hermite interpolation
        local pos = Util.hermiteInterpolate(p0, p1, v0, v1, segmentT)

        -- Handle rotation with special care
        local rx, ry = Util.hermiteInterpolateRotation(
                p0.rx or 0, p0.ry or 0,
                p1.rx or 0, p1.ry or 0,
                { rx = (p1.rx - p0.rx) / (pathInfo.points[segmentIndex].transitionTime or 1),
                  ry = (p1.ry - p0.ry) / (pathInfo.points[segmentIndex].transitionTime or 1) },
                { rx = (p1.rx - p0.rx) / (pathInfo.points[segmentIndex].transitionTime or 1),
                  ry = (p1.ry - p0.ry) / (pathInfo.points[segmentIndex].transitionTime or 1) },
                segmentT
        )

        -- Calculate camera direction from rotation
        local cosRx = math.cos(rx)
        local dx = math.sin(ry) * cosRx
        local dy = math.sin(rx)
        local dz = math.cos(ry) * cosRx

        local state = {
            mode = 0,
            name = "fps",
            px = pos.x,
            py = pos.y,
            pz = pos.z,
            rx = rx,
            ry = ry,
            rz = 0,
            dx = dx,
            dy = dy,
            dz = dz
        }

        return state
    end

    -- Fallback: find the steps that contain this time
    local beforeStep = nil
    local afterStep = nil
    local stepT = 0

    for i = 1, #pathInfo.steps - 1 do
        if time >= pathInfo.steps[i].time and time <= pathInfo.steps[i + 1].time then
            beforeStep = pathInfo.steps[i]
            afterStep = pathInfo.steps[i + 1]

            -- Calculate normalized position in this segment
            local stepDuration = afterStep.time - beforeStep.time
            stepT = stepDuration > 0 and (time - beforeStep.time) / stepDuration or 0
            break
        end
    end

    if not beforeStep or not afterStep then
        Log.warn("Could not find steps for time: " .. time)
        return Util.deepCopy(pathInfo.steps[1].state)
    end

    -- Perform linear interpolation between steps
    local interpolatedState = {
        mode = 0,
        name = "fps",
        px = CameraCommons.lerp(beforeStep.state.px, afterStep.state.px, stepT),
        py = CameraCommons.lerp(beforeStep.state.py, afterStep.state.py, stepT),
        pz = CameraCommons.lerp(beforeStep.state.pz, afterStep.state.pz, stepT),
        rx = CameraAnchorUtils.lerpAngle(beforeStep.state.rx, afterStep.state.rx, stepT),
        ry = CameraAnchorUtils.lerpAngle(beforeStep.state.ry, afterStep.state.ry, stepT),
        rz = 0
    }

    -- Calculate direction from rotation
    local cosRx = math.cos(interpolatedState.rx)
    interpolatedState.dx = math.sin(interpolatedState.ry) * cosRx
    interpolatedState.dy = math.sin(interpolatedState.rx)
    interpolatedState.dz = math.cos(interpolatedState.ry) * cosRx

    return interpolatedState
end

--- Create a speed control configuration for adding a slowdown/speedup at specific position
---@param position number Normalized position (0-1) where to apply speed factor
---@param factor number Speed factor (lower = slower, higher = faster)
---@param width number|nil Width of the effect zone
---@return table speedControls Speed control points
function AnchorTimeControl.addSpeedPoint(position, factor, width)
    -- Validate state
    if not STATE.anchorQueue or not STATE.anchorQueue.queue then
        Log.warn("Cannot add speed point - no active queue")
        return nil
    end

    Log.info(string.format("Adding speed point at position %.2f with factor %.2f and width %.2f",
            position, factor, width or 0.2))

    local pathInfo = STATE.anchorQueue.queue

    -- Get existing speed controls or derive them
    local speedControls = pathInfo.speedControls
    if not speedControls then
        Log.info("No existing speed controls, deriving new ones")
        speedControls = AnchorTimeControl.deriveSpeedFromTransitions(pathInfo.points)
    else
        Log.info(string.format("Using existing speed controls with %d points", #speedControls))
    end

    -- Default width
    width = width or 0.2

    -- Transition region edges
    local startPos = math.max(0, position - width / 2)
    local endPos = math.min(1, position + width / 2)

    -- Find baseline speed at this position
    local baseSpeed = 1.0
    for i = 1, #speedControls - 1 do
        if position >= speedControls[i].time and position <= speedControls[i + 1].time then
            -- Interpolate between control points
            local t = (position - speedControls[i].time) /
                    (speedControls[i + 1].time - speedControls[i].time)

            baseSpeed = speedControls[i].speed +
                    (speedControls[i + 1].speed - speedControls[i].speed) * t
            break
        end
    end

    Log.info(string.format("Baseline speed at position %.2f: %.1f", position, baseSpeed))

    -- Add control points for smooth transition
    table.insert(speedControls, {
        time = startPos,
        speed = baseSpeed -- Original speed at start of transition
    })

    Log.info(string.format("Added transition start at %.3f with speed %.1f", startPos, baseSpeed))

    table.insert(speedControls, {
        time = position,
        speed = baseSpeed * factor -- Modified speed at center
    })

    Log.info(string.format("Added speed point at %.3f with speed %.1f (factor %.2f)",
            position, baseSpeed * factor, factor))

    table.insert(speedControls, {
        time = endPos,
        speed = baseSpeed -- Return to original speed
    })

    Log.info(string.format("Added transition end at %.3f with speed %.1f", endPos, baseSpeed))

    -- Optimize and return
    return AnchorTimeControl.optimizeSpeedControls(speedControls)
end

--- Optimize speed controls by merging very close points
---@param speedControls table Array of speed control points
---@return table optimizedControls Optimized speed control points
function AnchorTimeControl.optimizeSpeedControls(speedControls)
    Log.info(string.format("Optimizing speed controls - input: %d points", #speedControls))

    -- Sort by time
    table.sort(speedControls, function(a, b)
        return a.time < b.time
    end)

    -- Merge threshold
    local timeThreshold = 0.01

    local optimized = {}
    local lastTime = -1
    local mergeCount = 0

    for i, point in ipairs(speedControls) do
        -- Round position to avoid floating point issues
        point.time = math.floor(point.time * 1000) / 1000

        -- Only add if sufficiently far from previous point
        if point.time - lastTime > timeThreshold then
            table.insert(optimized, {
                time = point.time,
                speed = point.speed
            })
            lastTime = point.time
        elseif #optimized > 0 then
            -- Points are very close, use minimum speed for safety
            local oldSpeed = optimized[#optimized].speed
            optimized[#optimized].speed = math.min(optimized[#optimized].speed, point.speed)

            if oldSpeed ~= optimized[#optimized].speed then
                Log.info(string.format("Merged close points at %.3f - speed: %.1f -> %.1f",
                        point.time, oldSpeed, optimized[#optimized].speed))
            end

            mergeCount = mergeCount + 1
        end
    end

    Log.info(string.format("Optimization complete - merged %d points, final: %d points",
            mergeCount, #optimized))

    return optimized
end

-- Add this function to anchor_time_control.lua
function AnchorTimeControl.smoothVelocityProfile(pathInfo)
    Log.info("Applying post-process velocity smoothing...")

    -- We need at least 3 steps for smoothing
    if not pathInfo.steps or #pathInfo.steps < 3 then
        return pathInfo
    end

    -- 1. Calculate all original velocities
    local velocities = {}
    for i = 2, #pathInfo.steps do
        local prev = pathInfo.steps[i - 1]
        local curr = pathInfo.steps[i]

        -- Calculate distance
        local dx = curr.state.px - prev.state.px
        local dy = curr.state.py - prev.state.py
        local dz = curr.state.pz - prev.state.pz
        local dist = math.sqrt(dx ^ 2 + dy ^ 2 + dz ^ 2)

        -- Calculate time
        local dt = curr.time - prev.time

        -- Calculate velocity
        velocities[i - 1] = dt > 0.0001 and dist / dt or 0
    end

    -- 2. Find average velocity across entire path for reference
    local totalVelocity = 0
    for _, vel in ipairs(velocities) do
        totalVelocity = totalVelocity + vel
    end
    local avgVelocity = totalVelocity / #velocities

    -- 3. Apply a moving average with larger window at boundaries
    local smoothedVelocities = {}

    for i = 1, #velocities do
        -- Use variable window size - larger at boundaries
        local windowSize = 5  -- Default for middle

        -- Increase window near boundaries
        local distFromEdge = math.min(i, #velocities - i + 1)
        if distFromEdge < 100 then
            -- Gradually increase window size near edges
            windowSize = windowSize + math.ceil((100 - distFromEdge) / 10)
        end

        -- Calculate weighted average with higher weight on normal velocities
        local sum = 0
        local totalWeight = 0

        for j = math.max(1, i - windowSize), math.min(#velocities, i + windowSize) do
            -- Use velocity but with weight inversely proportional to its deviation
            local v = velocities[j]

            -- Give more weight to velocities close to average
            local weight = 1.0
            if math.abs(v - avgVelocity) > avgVelocity * 0.5 then
                -- Reduce weight for extreme velocities
                weight = 0.5
            end

            -- Also prioritize closer samples
            local distWeight = 1.0 - math.abs(j - i) / (windowSize + 1)
            weight = weight * distWeight

            sum = sum + v * weight
            totalWeight = totalWeight + weight
        end

        if totalWeight > 0 then
            smoothedVelocities[i] = sum / totalWeight
        else
            smoothedVelocities[i] = velocities[i]
        end
    end

    -- 4. Apply a second pass specifically for edge handling
    -- Special treatment for start and end with gradual ramp
    local rampSize = 50  -- Adjust for more/less gradual start/end

    -- Start ramp (gradually accelerate)
    local startVel = smoothedVelocities[rampSize]
    for i = 1, rampSize do
        local factor = (i / rampSize) ^ 2  -- Quadratic ramp up
        smoothedVelocities[i] = startVel * factor
    end

    -- End ramp (gradually decelerate)
    local endVel = smoothedVelocities[#smoothedVelocities - rampSize]
    for i = 0, rampSize - 1 do
        local factor = ((rampSize - i) / rampSize) ^ 2  -- Quadratic ramp down
        smoothedVelocities[#smoothedVelocities - i] = endVel * factor
    end

    -- 5. Reconstruct path positions based on smoothed velocities
    -- Keep first point fixed
    local fixedPoints = { pathInfo.steps[1] }

    for i = 2, #pathInfo.steps do
        local prev = fixedPoints[i - 1]
        local curr = pathInfo.steps[i]
        local dt = curr.time - prev.time

        -- Get direction vector from original path
        local dx = curr.state.px - prev.state.px
        local dy = curr.state.py - prev.state.py
        local dz = curr.state.pz - prev.state.pz
        local dist = math.sqrt(dx ^ 2 + dy ^ 2 + dz ^ 2)

        if dist > 0.001 then
            -- Normalize direction vector
            dx = dx / dist
            dy = dy / dist
            dz = dz / dist

            -- Calculate new distance based on smoothed velocity
            local newDist = smoothedVelocities[i - 1] * dt

            -- Create new position
            local newPos = {
                px = prev.state.px + dx * newDist,
                py = prev.state.py + dy * newDist,
                pz = prev.state.pz + dz * newDist
            }

            -- Create new state with smoothed position
            local newState = Util.deepCopy(curr.state)
            newState.px = newPos.px
            newState.py = newPos.py
            newState.pz = newPos.pz

            -- Calculate camera direction from rotation
            local cosRx = math.cos(newState.rx)
            newState.dx = math.sin(newState.ry) * cosRx
            newState.dy = math.sin(newState.rx)
            newState.dz = math.cos(newState.ry) * cosRx

            table.insert(fixedPoints, {
                time = curr.time,
                state = newState
            })
        else
            -- If distance is too small, just keep original point
            table.insert(fixedPoints, curr)
        end
    end

    -- 6. Special handling for end point to ensure we reach exact destination
    -- Make sure the final position exactly matches the original target
    local originalEnd = pathInfo.steps[#pathInfo.steps].state
    if #fixedPoints > 0 then
        local finalPoint = fixedPoints[#fixedPoints]
        finalPoint.state.px = originalEnd.px
        finalPoint.state.py = originalEnd.py
        finalPoint.state.pz = originalEnd.pz

        -- Also adjust the last few points to create a gradual approach
        local blendSteps = 10
        for i = math.max(1, #fixedPoints - blendSteps), #fixedPoints - 1 do
            local factor = (i - (#fixedPoints - blendSteps)) / blendSteps
            local invFactor = 1 - factor

            -- Interpolate between smoothed position and a position on direct line to end
            local directPos = {
                px = originalEnd.px * factor + fixedPoints[#fixedPoints - blendSteps].state.px * invFactor,
                py = originalEnd.py * factor + fixedPoints[#fixedPoints - blendSteps].state.py * invFactor,
                pz = originalEnd.pz * factor + fixedPoints[#fixedPoints - blendSteps].state.pz * invFactor
            }

            -- Blend between smoothed and direct path
            fixedPoints[i].state.px = fixedPoints[i].state.px * 0.5 + directPos.px * 0.5
            fixedPoints[i].state.py = fixedPoints[i].state.py * 0.5 + directPos.py * 0.5
            fixedPoints[i].state.pz = fixedPoints[i].state.pz * 0.5 + directPos.pz * 0.5

        end

    end

    -- Replace path steps with smoothed version
    pathInfo.steps = fixedPoints

    return pathInfo
end

return {
    AnchorTimeControl = AnchorTimeControl
}