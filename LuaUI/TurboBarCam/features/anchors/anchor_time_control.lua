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

--- Apply speed control to a camera path
---@param pathInfo table Path information structure
---@param speedControls table Array of {time, speed} control points
---@param easingFunc string|function Optional easing function name or function
---@return table pathInfo Updated path information
function AnchorTimeControl.applySpeedControl(pathInfo, speedControls, easingFunc)
    -- Calculate speed control points from transition times if not provided
    if not speedControls or #speedControls < 2 then
        speedControls = AnchorTimeControl.deriveSpeedFromTransitions(pathInfo.points)
    end

    -- Get easing function if specified
    local easing = nil
    if easingFunc then
        if type(easingFunc) == "string" then
            easing = EasingFunctions[easingFunc]
            if not easing then
                Log.warn("Unknown easing function '" .. easingFunc .. "', using linear")
                easing = EasingFunctions.linear
            end
        elseif type(easingFunc) == "function" then
            easing = easingFunc
        end
    end

    -- Build time mapping with continuous speed transitions
    local timeMap = AnchorTimeControl.buildContinuousTimeMapping(speedControls, easing)

    -- Instead of just remapping times, regenerate steps with proper spacing
    pathInfo = AnchorTimeControl.regeneratePathSteps(pathInfo, timeMap)

    -- Store the speed controls for future reference
    pathInfo.speedControls = speedControls
    pathInfo.easingFunction = easingFunc

    Log.debug(string.format("Applied time control with %d speed points and regenerated steps",
            #speedControls))
    return pathInfo
end

--- Derive speed control points from anchor point transition times
---@param points table Array of path points with transition times
---@return table speedControls Array of {time, speed} control points
function AnchorTimeControl.deriveSpeedFromTransitions(points)
    -- Analyze path segments to find extreme velocity changes that need special handling
    local rawSegments = {}
    local totalDist = 0
    local totalTime = 0

    -- First calculate segment lengths, times, and segment velocities
    for i = 2, #points do
        local p1 = points[i - 1].state
        local p2 = points[i].state

        -- Calculate segment distance
        local dist = math.sqrt(
                (p2.px - p1.px) ^ 2 +
                        (p2.py - p1.py) ^ 2 +
                        (p2.pz - p1.pz) ^ 2
        )

        -- Get transition time
        local time = points[i - 1].transitionTime or 1.0

        -- Calculate raw speed
        local speed = dist / math.max(0.01, time)

        -- Store segment data
        table.insert(rawSegments, {
            index = i - 1,
            startNdx = i - 1,
            endNdx = i,
            dist = dist,
            time = time,
            speed = speed
        })

        totalDist = totalDist + dist
        totalTime = totalTime + time
    end

    -- Detect and analyze extreme velocity changes
    Log.debug("Analyzing segment velocity changes:")
    local extremeThreshold = 3.0 -- If next segment is 3x faster or slower, it's extreme
    local extremeTransitions = {}

    for i = 1, #rawSegments - 1 do
        local current = rawSegments[i]
        local next = rawSegments[i + 1]
        local ratio = next.speed / current.speed

        -- Use logarithmic difference to treat speedups and slowdowns equally
        local logRatio = math.abs(math.log(ratio))

        if logRatio > math.log(extremeThreshold) then
            Log.debug(string.format("Extreme velocity change detected at segment %d->%d: %.1f -> %.1f (ratio: %.2f)",
                    i, i + 1, current.speed, next.speed, ratio))

            table.insert(extremeTransitions, {
                segmentIndex = i,
                nextIndex = i + 1,
                ratio = ratio,
                logRatio = logRatio
            })
        end
    end

    -- Create normalized waypoints with position along path
    local waypoints = {}
    local currentDist = 0

    for i, segment in ipairs(rawSegments) do
        if i == 1 then
            -- First point
            table.insert(waypoints, {
                index = segment.startNdx,
                position = 0,
                speed = segment.speed
            })
        end

        -- Add ending point of segment
        currentDist = currentDist + segment.dist
        local normalizedPos = currentDist / totalDist

        -- Special handling for last point to ensure it's exactly at 1.0
        if i == #rawSegments then
            normalizedPos = 1.0
        end

        table.insert(waypoints, {
            index = segment.endNdx,
            position = normalizedPos,
            speed = i < #rawSegments and rawSegments[i + 1].speed or segment.speed
        })
    end

    -- Generate smooth speed profile with focus on extreme transitions
    local speedControls = {}

    -- Add starting point
    table.insert(speedControls, {
        time = 0,
        speed = rawSegments[1].speed
    })

    -- For each waypoint (except first which we already added)
    for i = 2, #waypoints do
        local wp = waypoints[i]
        local prevWp = waypoints[i - 1]

        -- Check if this is part of an extreme transition
        local isExtreme = false
        local extremeTransition = nil

        for _, et in ipairs(extremeTransitions) do
            if et.segmentIndex == i - 1 then
                isExtreme = true
                extremeTransition = et
                break
            end
        end

        if isExtreme then
            -- For extreme transitions, we need very gradual speed changes
            -- This is the key improvement - we create a much longer, more gradual transition
            -- that starts much earlier and finishes much later than before

            -- Calculate the severity of the transition (more extreme = wider transition)
            local severity = math.min(0.9, math.max(0.5, extremeTransition.logRatio / 4))

            -- Create a very wide transition region
            local startPos = math.max(0.01, prevWp.position)
            local midPos = wp.position
            local segmentWidth = midPos - startPos

            -- Extend the transition region beyond the waypoint
            local transitionStart = startPos + segmentWidth * (1 - severity)
            local transitionEnd = math.min(0.99, midPos + segmentWidth * severity)

            Log.debug(string.format("Creating extended transition from %.2f to %.2f for extreme change",
                    transitionStart, transitionEnd))

            -- Generate many points throughout the transition zone for a smoother curve
            local numPoints = 40 -- Use significantly more points for extreme transitions
            local prevSpeed = prevWp.speed
            local nextSpeed = wp.speed

            -- Create logarithmically spaced points for better handling of extreme changes
            for j = 0, numPoints do
                -- Use a logarithmic spacing for control points - more dense near the waypoint
                local t
                if j <= numPoints / 2 then
                    -- First half - gradually approach the waypoint
                    t = j / (numPoints / 2)
                    t = t * t  -- quadratic ease-in
                    local pos = transitionStart + (midPos - transitionStart) * t

                    -- Calculate speed using a customized sigmoid transition
                    -- This provides very gradual changes at the beginning and end
                    local blend = AnchorTimeControl.sigmoidBlend(t, 0.2)
                    local speed = prevSpeed * (1 - blend) + nextSpeed * blend

                    table.insert(speedControls, {
                        time = pos,
                        speed = speed
                    })
                else
                    -- Second half - gradually move away from waypoint
                    t = (j - numPoints / 2) / (numPoints / 2)
                    t = t * t  -- quadratic ease-in for second half
                    local pos = midPos + (transitionEnd - midPos) * t

                    -- Final deceleration/acceleration after the waypoint
                    local blend = AnchorTimeControl.sigmoidBlend(0.5 + t / 2, 0.2)
                    local speed = prevSpeed * (1 - blend) + nextSpeed * blend

                    table.insert(speedControls, {
                        time = pos,
                        speed = speed
                    })
                end
            end
        else
            -- For normal transitions, add fewer control points
            local numPoints = 15
            local segmentWidth = 0.3 -- 30% of the distance around waypoint
            local transitionStart = math.max(0.01, wp.position - segmentWidth / 2)
            local transitionEnd = math.min(0.99, wp.position + segmentWidth / 2)

            for j = 0, numPoints do
                local t = j / numPoints
                local pos = transitionStart + (transitionEnd - transitionStart) * t

                -- Cubic easing function for smoother transition
                local blend = t * t * (3 - 2 * t)
                local speed = prevWp.speed * (1 - blend) + wp.speed * blend

                table.insert(speedControls, {
                    time = pos,
                    speed = speed
                })
            end
        end
    end

    -- Make sure we have an endpoint
    if speedControls[#speedControls].time < 1.0 then
        table.insert(speedControls, {
            time = 1.0,
            speed = rawSegments[#rawSegments].speed
        })
    end

    -- Apply multiple rounds of global smoothing to eliminate any remaining discontinuities
    Log.debug(string.format("Generated %d raw speed control points", #speedControls))
    speedControls = AnchorTimeControl.globalSpeedSmoothing(speedControls, 5)
    Log.debug(string.format("Final smoothed speed control points: %d", #speedControls))

    return speedControls
end

--- Custom sigmoid blending function for ultra-smooth transitions
---@param t number Input parameter (0-1)
---@param steepness number Controls the steepness of the sigmoid
---@return number blend Blended value
function AnchorTimeControl.sigmoidBlend(t, steepness)
    -- Center the input around 0
    local x = (t - 0.5) / steepness
    -- Apply sigmoid function: 1/(1+e^-x)
    local sigmoid = 1 / (1 + math.exp(-x))
    return sigmoid
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
        local smoothed = { result[1] }  -- Keep first point unchanged

        -- Apply smoothing to all interior points
        for i = 2, #result - 1 do
            local prevSpeed = result[i - 1].speed
            local currSpeed = result[i].speed
            local nextSpeed = result[i + 1].speed

            -- Weighted average with special handling for extreme differences
            local maxChange = math.max(prevSpeed, nextSpeed) * 0.3
            local targetSpeed = prevSpeed * 0.25 + currSpeed * 0.5 + nextSpeed * 0.25

            -- Limit maximum change per pass for extreme transitions
            if math.abs(targetSpeed - currSpeed) > maxChange then
                if targetSpeed > currSpeed then
                    targetSpeed = currSpeed + maxChange
                else
                    targetSpeed = currSpeed - maxChange
                end
            end

            table.insert(smoothed, {
                time = result[i].time,
                speed = targetSpeed
            })
        end

        -- Keep last point unchanged
        table.insert(smoothed, result[#result])

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
    end
    if speedControls[#speedControls].time < 1 then
        table.insert(speedControls, { time = 1, speed = speedControls[#speedControls].speed })
    end

    -- Initialize time mapping structure
    local timeMap = {
        points = {},
        totalTime = 0,
        easingFunc = easingFunc,
        speedControls = speedControls
    }

    -- Create continuous speed function with improved interpolation
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

        -- Use improved quintintic interpolation for smoother transitions
        local t2 = segmentT * segmentT
        local t3 = t2 * segmentT
        local t4 = t3 * segmentT
        local t5 = t4 * segmentT

        -- 6t^5 - 15t^4 + 10t^3 (improved smoothstep that's C2 continuous)
        local easedT = 6 * t5 - 15 * t4 + 10 * t3

        return p1.speed * (1 - easedT) + p2.speed * easedT
    end

    -- Add first mapping point
    table.insert(timeMap.points, {
        inputTime = 0,
        outputTime = 0
    })

    -- Use many more segments for accurate numerical integration
    local numSegments = 300
    local segmentSize = 1.0 / numSegments
    local currentTime = 0

    -- Calculate time mapping through numerical integration with enhanced accuracy
    for i = 1, numSegments do
        local t = (i - 1) * segmentSize
        local nextT = i * segmentSize

        -- Use Simpsons rule for better numerical integration
        local speed1 = speedFunction(t)
        local speed2 = speedFunction(nextT)
        local speedMid = speedFunction(t + segmentSize / 2)

        -- Simpson's integration: (b-a)/6 * [f(a) + 4*f((a+b)/2) + f(b)]
        local invSpeed1 = 1 / math.max(0.001, speed1)
        local invSpeed2 = 1 / math.max(0.001, speed2)
        local invSpeedMid = 1 / math.max(0.001, speedMid)

        local segmentDuration = segmentSize / 6 * (invSpeed1 + 4 * invSpeedMid + invSpeed2)
        currentTime = currentTime + segmentDuration

        -- Add mapping point for this segment
        table.insert(timeMap.points, {
            inputTime = nextT,
            outputTime = currentTime
        })
    end

    -- Normalize the output times to 0-1 range
    timeMap.totalTime = timeMap.points[#timeMap.points].outputTime
    for i = 1, #timeMap.points do
        timeMap.points[i].outputTime = timeMap.points[i].outputTime / timeMap.totalTime
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
            400, -- use more steps for smoother motion
            math.floor(originalDuration * CONFIG.PERFORMANCE.ANCHOR_STEPS_PER_SECOND * 2)
    )

    -- Recreate steps with even time distribution
    local newSteps = {}
    local stepTimeInterval = originalDuration / (numSteps - 1)

    -- Distribute steps with higher density at problem areas
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
    end

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

    -- Apply easing function if available
    if timeMap.easingFunc then
        segmentT = timeMap.easingFunc(segmentT)
    end

    -- Map to input time with quintic interpolation for smoother transitions
    local t2 = segmentT * segmentT
    local t3 = t2 * segmentT
    local t4 = t3 * segmentT
    local t5 = t4 * segmentT
    local easedT = 6 * t5 - 15 * t4 + 10 * t3

    return t1 + (t2 - t1) * easedT
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

    local pathInfo = STATE.anchorQueue.queue

    -- Get existing speed controls or derive them
    local speedControls = pathInfo.speedControls
    if not speedControls then
        speedControls = AnchorTimeControl.deriveSpeedFromTransitions(pathInfo.points)
    end

    -- Default width
    width = width or 0.3

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

    -- Add control points for smooth transition - use more points for smoother effect
    local numPoints = 15
    for i = 0, numPoints do
        local t = i / numPoints
        local pos = startPos + (endPos - startPos) * t

        -- Quintic ease in/out for smoother speed change
        local t2 = t * t
        local t3 = t2 * t
        local t4 = t3 * t
        local t5 = t4 * t
        local easedT = 6 * t5 - 15 * t4 + 10 * t3

        -- Speed adjustment with the eased blending
        local speed
        if t < 0.5 then
            -- First half - ease from base speed to modified speed
            local blend = easedT * 2 -- remap 0-0.5 to 0-1
            speed = baseSpeed * (1 - blend) + (baseSpeed * factor) * blend
        else
            -- Second half - ease from modified speed back to base speed
            local blend = (easedT - 0.5) * 2 -- remap 0.5-1 to 0-1
            speed = (baseSpeed * factor) * (1 - blend) + baseSpeed * blend
        end

        table.insert(speedControls, {
            time = pos,
            speed = speed
        })
    end

    -- Apply global smoothing
    return AnchorTimeControl.globalSpeedSmoothing(speedControls, 3)
end

--- Optimize speed controls by merging very close points
---@param speedControls table Array of speed control points
---@return table optimizedControls Optimized speed control points
function AnchorTimeControl.optimizeSpeedControls(speedControls)
    -- Sort by time
    table.sort(speedControls, function(a, b)
        return a.time < b.time
    end)

    -- Merge threshold
    local timeThreshold = 0.005

    local optimized = {}
    local lastTime = -1

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
            -- Points are very close, use average speed for smoother result
            optimized[#optimized].speed = (optimized[#optimized].speed + point.speed) / 2
        end
    end

    return optimized
end

return {
    AnchorTimeControl = AnchorTimeControl
}