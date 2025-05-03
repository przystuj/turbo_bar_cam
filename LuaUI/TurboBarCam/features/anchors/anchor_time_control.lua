---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type EasingFunctions
local EasingFunctions = VFS.Include("LuaUI/TurboBarCam/features/anchors/anchor_easing_functions.lua").EasingFunctions

local Log = CommonModules.Log
local STATE = WidgetContext.STATE

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

    -- Remap all step times
    pathInfo = AnchorTimeControl.remapPathTimes(pathInfo, timeMap)

    -- Store the speed controls for future reference
    pathInfo.speedControls = speedControls
    pathInfo.easingFunction = easingFunc

    Log.debug(string.format("Applied time control with %d speed points",
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

    -- Middle control points at waypoints
    for i = 1, #segmentLengths do
        currentLength = currentLength + segmentLengths[i]
        currentTime = currentTime + segmentTimes[i]

        -- Normalized position along the path
        local normalizedPos = currentLength / totalLength

        -- Speed at this point (average of incoming and outgoing if available)
        local inSpeed = segmentLengths[i] / segmentTimes[i]
        local outSpeed = (i < #segmentLengths) and
                (segmentLengths[i+1] / segmentTimes[i+1]) or
                inSpeed

        -- Add control point with average speed
        table.insert(speedControls, {
            time = normalizedPos,
            speed = (inSpeed + outSpeed) / 2
        })

        -- Add transition points halfway between waypoints for smoother transitions
        if i < #segmentLengths then
            -- Halfway point between this and next waypoint
            local halfwayPos = normalizedPos +
                    (segmentLengths[i+1] / totalLength) / 2

            -- Weighted blend of speeds - creates transition region
            local blendedSpeed = (inSpeed * 0.3) + (outSpeed * 0.7)

            table.insert(speedControls, {
                time = halfwayPos,
                speed = blendedSpeed
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

        -- Add mapping point at regular intervals
        if i % 10 == 0 or i == numSegments then
            table.insert(timeMap.points, {
                inputTime = nextT,
                outputTime = currentTime
            })
        end
    end

    -- Normalize the output times to 0-1 range
    timeMap.totalTime = timeMap.points[#timeMap.points].outputTime
    for i = 1, #timeMap.points do
        timeMap.points[i].outputTime = timeMap.points[i].outputTime / timeMap.totalTime
    end

    return timeMap
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