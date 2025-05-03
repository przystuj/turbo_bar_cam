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
    local speedControls = {}
    local totalTime = 0
    local totalLength = 0
    local segmentLengths = {}
    local segmentTimes = {}

    -- Calculate total path length and segment times
    for i = 2, #points do
        local p1 = points[i-1].state
        local p2 = points[i].state

        -- Calculate segment length
        local dist = math.sqrt(
                (p2.px - p1.px)^2 +
                        (p2.py - p1.py)^2 +
                        (p2.pz - p1.pz)^2
        )

        table.insert(segmentLengths, dist)
        totalLength = totalLength + dist

        -- Get transition time for this segment
        local time = points[i-1].transitionTime or 1.0
        table.insert(segmentTimes, time)
        totalTime = totalTime + time
    end

    -- Calculate speeds and normalized positions for each segment
    local currentTime = 0
    local currentLength = 0

    -- First control point at the beginning
    table.insert(speedControls, {
        time = 0,
        speed = segmentTimes[1] > 0 and segmentLengths[1]/segmentTimes[1] or 1.0
    })

    -- Middle control points at waypoints with proper transition regions
    for i = 1, #segmentLengths do
        currentLength = currentLength + segmentLengths[i]

        -- Normalized position along the path for this waypoint
        local normalizedPos = currentLength / totalLength

        -- Calculate speeds
        local inSpeed = segmentLengths[i] / segmentTimes[i]
        local outSpeed = (i < #segmentLengths) and
                (segmentLengths[i+1] / segmentTimes[i+1]) or
                inSpeed

        -- If this isn't the last segment, create smooth transition between segments
        if i < #segmentLengths then
            -- Create 5 transition points BEFORE the waypoint for smooth approach
            local transitionStart = normalizedPos - 0.15 -- Start transition 15% before waypoint
            transitionStart = math.max(0.01, transitionStart) -- Ensure we don't go below 0

            -- Generate transition points leading up to the waypoint
            for j = 1, 5 do
                local t = j / 5
                local blendPos = transitionStart + (normalizedPos - transitionStart) * t

                -- Cubic easing for speed transition - more weight to incoming speed near start
                -- and more weight to average speed near waypoint
                local blend = t * t * (3 - 2 * t)  -- Smooth step function
                local blendedSpeed = inSpeed * (1 - blend) + ((inSpeed + outSpeed) / 2) * blend

                table.insert(speedControls, {
                    time = blendPos,
                    speed = blendedSpeed
                })
            end

            -- Add point exactly at the waypoint with average speed
            table.insert(speedControls, {
                time = normalizedPos,
                speed = (inSpeed + outSpeed) / 2
            })

            -- Create 5 transition points AFTER the waypoint for smooth departure
            local transitionEnd = normalizedPos + 0.15 -- End transition 15% after waypoint
            transitionEnd = math.min(0.99, transitionEnd) -- Ensure we don't exceed 1

            -- Generate transition points moving away from the waypoint
            for j = 1, 5 do
                local t = j / 5
                local blendPos = normalizedPos + (transitionEnd - normalizedPos) * t

                -- Cubic easing for speed transition - more weight to average at waypoint
                -- and more weight to outgoing speed as we move away
                local blend = t * t * (3 - 2 * t)  -- Smooth step function
                local blendedSpeed = ((inSpeed + outSpeed) / 2) * (1 - blend) + outSpeed * blend

                table.insert(speedControls, {
                    time = blendPos,
                    speed = blendedSpeed
                })
            end
        else
            -- For the last waypoint, just add the final point
            table.insert(speedControls, {
                time = normalizedPos,
                speed = inSpeed -- Use incoming speed for last point
            })
        end
    end

    -- Make sure we have an endpoint
    if speedControls[#speedControls].time < 1.0 then
        table.insert(speedControls, {
            time = 1.0,
            speed = speedControls[#speedControls].speed
        })
    end

    return AnchorTimeControl.optimizeSpeedControls(speedControls)
end

--- Build a continuous time mapping from speed control points
---@param speedControls table Array of {time, speed} control points
---@param easingFunc function|nil Optional easing function
---@return table timeMap Time mapping information
function AnchorTimeControl.buildContinuousTimeMapping(speedControls, easingFunc)
    -- Ensure we have normalized time points (0-1)
    table.sort(speedControls, function(a, b) return a.time < b.time end)

    -- Ensure we have control points at 0 and 1
    if speedControls[1].time > 0 then
        table.insert(speedControls, 1, {time = 0, speed = speedControls[1].speed})
    end
    if speedControls[#speedControls].time < 1 then
        table.insert(speedControls, {time = 1, speed = speedControls[#speedControls].speed})
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
        if t <= 0 then return speedControls[1].speed end
        if t >= 1 then return speedControls[#speedControls].speed end

        -- Find which segment contains this time
        local i = 1
        while i < #speedControls and t > speedControls[i+1].time do
            i = i + 1
        end

        local p1 = speedControls[i]
        local p2 = speedControls[i+1]

        -- Calculate normalized position in this segment
        local segmentT = 0
        if p2.time > p1.time then
            segmentT = (t - p1.time) / (p2.time - p1.time)
        end

        -- Use cubic interpolation for smooth transition
        return p1.speed + (p2.speed - p1.speed) *
                (3 * segmentT * segmentT - 2 * segmentT * segmentT * segmentT)
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
    for i = 1, numSegments do
        local t = (i - 1) * segmentSize
        local nextT = i * segmentSize

        -- Average speed in this tiny segment (trapezoidal integration)
        local speed1 = speedFunction(t)
        local speed2 = speedFunction(nextT)
        local avgSpeed = (speed1 + speed2) / 2

        -- Calculate segment duration (slower = more time)
        local segmentDuration = segmentSize / math.max(0.001, avgSpeed)
        currentTime = currentTime + segmentDuration

        -- Add mapping point at EVERY segment for maximum precision
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
            200, -- minimum number of steps for smooth movement
            math.floor(originalDuration * CONFIG.PERFORMANCE.ANCHOR_STEPS_PER_SECOND)
    )

    -- Recreate steps with even time distribution
    local newSteps = {}
    local stepTimeInterval = originalDuration / (numSteps - 1)

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
        pathInfo.stepTimes[i] = pathInfo.steps[i+1].time - pathInfo.steps[i].time
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
    if normalizedOutputTime <= 0 then return 0 end
    if normalizedOutputTime >= 1 then return 1 end

    -- Find the segment in the time map
    local segmentIndex = 1
    for i = 1, #timeMap.points - 1 do
        if normalizedOutputTime >= timeMap.points[i].outputTime and
                normalizedOutputTime <= timeMap.points[i+1].outputTime then
            segmentIndex = i
            break
        end
    end

    -- Get the output/input time ranges for this segment
    local o1 = timeMap.points[segmentIndex].outputTime
    local o2 = timeMap.points[segmentIndex+1].outputTime
    local t1 = timeMap.points[segmentIndex].inputTime
    local t2 = timeMap.points[segmentIndex+1].inputTime

    -- Calculate segment progress
    local segmentT = 0
    if o2 > o1 then -- Avoid division by zero
        segmentT = (normalizedOutputTime - o1) / (o2 - o1)
    end

    -- Map to input time
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
    if segmentIndex and pathInfo.points[segmentIndex].tangent and pathInfo.points[segmentIndex+1].tangent then
        local p0 = pathInfo.points[segmentIndex].state
        local p1 = pathInfo.points[segmentIndex+1].state
        local v0 = pathInfo.points[segmentIndex].tangent
        local v1 = pathInfo.points[segmentIndex+1].tangent

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
        if time >= pathInfo.steps[i].time and time <= pathInfo.steps[i+1].time then
            beforeStep = pathInfo.steps[i]
            afterStep = pathInfo.steps[i+1]

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

--- Remap all path times based on time mapping
---@param pathInfo table Path information structure
---@param timeMap table Time mapping information
---@return table pathInfo Updated path information
function AnchorTimeControl.remapPathTimes(pathInfo, timeMap)
    -- Get original total duration
    local originalDuration = pathInfo.totalDuration

    -- Remap each step's time
    for i, step in ipairs(pathInfo.steps) do
        -- Normalize current time to 0-1 range
        local normalizedTime = step.time / originalDuration

        -- Get remapped time
        local remappedTime = AnchorTimeControl.interpolateTime(normalizedTime, timeMap)

        -- Update step time
        step.time = remappedTime * originalDuration
    end

    -- Resort steps by time
    table.sort(pathInfo.steps, function(a, b)
        return a.time < b.time
    end)

    -- Update step time differences
    for i = 1, #pathInfo.steps - 1 do
        pathInfo.stepTimes[i] = pathInfo.steps[i+1].time - pathInfo.steps[i].time
    end

    -- Update last step time
    if #pathInfo.steps > 0 then
        pathInfo.stepTimes[#pathInfo.stepTimes] = 0.01
    end

    return pathInfo
end

--- Interpolate time based on time mapping with cubic easing
---@param t number Normalized time (0-1)
---@param timeMap table Time mapping information
---@return number remappedTime Remapped normalized time (0-1)
function AnchorTimeControl.interpolateTime(t, timeMap)
    -- Handle edge cases
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end

    -- Find the segment in the time map
    local segmentIndex = 1
    for i = 1, #timeMap.points - 1 do
        if t >= timeMap.points[i].inputTime and t <= timeMap.points[i+1].inputTime then
            segmentIndex = i
            break
        end
    end

    -- Get the input/output time ranges for this segment
    local t1 = timeMap.points[segmentIndex].inputTime
    local t2 = timeMap.points[segmentIndex+1].inputTime
    local o1 = timeMap.points[segmentIndex].outputTime
    local o2 = timeMap.points[segmentIndex+1].outputTime

    -- Calculate segment progress
    local segmentT = 0
    if t2 > t1 then -- Avoid division by zero
        segmentT = (t - t1) / (t2 - t1)
    end

    -- Apply easing function if available
    if timeMap.easingFunc then
        segmentT = timeMap.easingFunc(segmentT)
    end

    -- Map to output time with cubic interpolation for smoother transitions
    return o1 + (o2 - o1) * (3 * segmentT * segmentT - 2 * segmentT * segmentT * segmentT)
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
    width = width or 0.2

    -- Transition region edges
    local startPos = math.max(0, position - width/2)
    local endPos = math.min(1, position + width/2)

    -- Find baseline speed at this position
    local baseSpeed = 1.0
    for i = 1, #speedControls - 1 do
        if position >= speedControls[i].time and position <= speedControls[i+1].time then
            -- Interpolate between control points
            local t = (position - speedControls[i].time) /
                    (speedControls[i+1].time - speedControls[i].time)

            baseSpeed = speedControls[i].speed +
                    (speedControls[i+1].speed - speedControls[i].speed) * t
            break
        end
    end

    -- Add control points for smooth transition
    table.insert(speedControls, {
        time = startPos,
        speed = baseSpeed -- Original speed at start of transition
    })

    table.insert(speedControls, {
        time = position,
        speed = baseSpeed * factor -- Modified speed at center
    })

    table.insert(speedControls, {
        time = endPos,
        speed = baseSpeed -- Return to original speed
    })

    -- Optimize and return
    return AnchorTimeControl.optimizeSpeedControls(speedControls)
end

--- Optimize speed controls by merging very close points
---@param speedControls table Array of speed control points
---@return table optimizedControls Optimized speed control points
function AnchorTimeControl.optimizeSpeedControls(speedControls)
    -- Sort by time
    table.sort(speedControls, function(a, b) return a.time < b.time end)

    -- Merge threshold
    local timeThreshold = 0.01

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
            -- Points are very close, use minimum speed for safety
            optimized[#optimized].speed = math.min(optimized[#optimized].speed, point.speed)
        end
    end

    return optimized
end

return {
    AnchorTimeControl = AnchorTimeControl
}