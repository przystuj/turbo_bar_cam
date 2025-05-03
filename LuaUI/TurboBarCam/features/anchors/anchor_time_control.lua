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
    -- Validate speed controls
    if not speedControls or #speedControls < 2 then
        Log.warn("Invalid speed controls, using constant speed")
        return pathInfo
    end

    speedControls = AnchorTimeControl.optimizeSpeedControls(speedControls)

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

    -- Build time mapping
    local timeMap = AnchorTimeControl.buildTimeMapping(speedControls, easing)

    -- Remap all step times
    AnchorTimeControl.remapStepTimes(pathInfo, timeMap)

    Log.debug(string.format("Applied time reparameterization with %d control points%s",
            #speedControls, easing and " and " .. tostring(easingFunc) .. " easing" or ""))
    return pathInfo
end

--- Build a time mapping from speed control points with improved interpolation
---@param speedControlPoints table Array of {time, speed} control points
---@param easingFunc function|nil Optional easing function to apply between control points
---@return table timeMap Time mapping information
function AnchorTimeControl.buildTimeMapping(speedControlPoints, easingFunc)
    -- Sort speed control points by time
    table.sort(speedControlPoints, function(a, b) return a.time < b.time end)

    -- Ensure we have points at t=0 and t=1
    if speedControlPoints[1].time > 0 then
        table.insert(speedControlPoints, 1, {time = 0, speed = speedControlPoints[1].speed})
    end

    if speedControlPoints[#speedControlPoints].time < 1 then
        table.insert(speedControlPoints, {time = 1, speed = speedControlPoints[#speedControlPoints].speed})
    end

    local timeMap = {
        points = {},
        totalTime = 0,
        easingFunc = easingFunc,
        speedPoints = speedControlPoints -- Keep the reference for debugging
    }

    -- Add first mapping point
    table.insert(timeMap.points, {
        inputTime = 0,
        outputTime = 0
    })

    -- Use sub-segments for better integration
    local numSegments = #speedControlPoints - 1
    local segmentPoints = 10 -- Improved quality of integration
    local currentTime = 0

    for i = 1, numSegments do
        local cp1 = speedControlPoints[i]
        local cp2 = speedControlPoints[i+1]

        local normalProgress = cp2.time - cp1.time
        local totalTimeForSegment = 0

        -- Integrate over smaller sub-segments for higher accuracy
        for j = 1, segmentPoints do
            local t = (j - 1) / (segmentPoints - 1)
            -- Use cubic interpolation for smoother speed transitions
            local segmentSpeed = cp1.speed + (cp2.speed - cp1.speed) *
                    (3 * t * t - 2 * t * t * t)
            totalTimeForSegment = totalTimeForSegment +
                    (normalProgress / segmentPoints) / segmentSpeed
        end

        currentTime = currentTime + totalTimeForSegment

        -- Add mapping point
        table.insert(timeMap.points, {
            inputTime = cp2.time,
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

--- Remap step times based on time mapping
---@param pathInfo table Path information structure
---@param timeMap table Time mapping information
function AnchorTimeControl.remapStepTimes(pathInfo, timeMap)
    -- Get original total duration
    local originalDuration = pathInfo.totalDuration

    -- Remap each step's time
    for i, step in ipairs(pathInfo.steps) do
        -- Normalize current time to 0-1 range
        local normalizedTime = step.time / originalDuration

        -- Get remapped time
        local remappedNormalizedTime = AnchorTimeControl.getRemappedTime(normalizedTime, timeMap)

        -- Update step time
        step.time = remappedNormalizedTime * originalDuration
    end

    -- Resort steps by time (remapping might change order in edge cases)
    table.sort(pathInfo.steps, function(a, b) return a.time < b.time end)

    -- Update step time differences
    for i = 1, #pathInfo.steps - 1 do
        pathInfo.stepTimes[i] = pathInfo.steps[i+1].time - pathInfo.steps[i].time
    end

    -- Update last step time
    if #pathInfo.steps > 0 then
        pathInfo.stepTimes[#pathInfo.stepTimes] = 0.01
    end
end

--- Get remapped time based on time mapping with improved interpolation
---@param t number Normalized time (0-1)
---@param timeMap table Time mapping information
---@return number remappedTime Remapped normalized time (0-1)
function AnchorTimeControl.getRemappedTime(t, timeMap)
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

    -- Map to output time
    return o1 + segmentT * (o2 - o1)
end

--- Create a speed control configuration for slowing down at specific points
---@param position number Normalized position (0-1) where to apply slowdown
---@param factor number Speed reduction factor (lower = slower)
---@param width number|nil Width of slowdown zone
---@return table speedControls Speed control points
function AnchorTimeControl.addSpeedPoint(position, factor, width)
    -- Validate state
    if not STATE.anchorQueue or not STATE.anchorQueue.queue then
        Log.warn("Cannot add slowdown - no active queue")
        return nil
    end

    local pathInfo = STATE.anchorQueue.queue

    -- Default width
    width = width or 0.2
    local points = pathInfo.points
    local totalLength = 0

    -- Calculate segment lengths and find total path length
    local segmentLengths = {}
    for i = 2, #points do
        local p1 = points[i-1].state
        local p2 = points[i].state

        local dist = math.sqrt(
                (p2.px - p1.px)^2 +
                        (p2.py - p1.py)^2 +
                        (p2.pz - p1.pz)^2
        )

        table.insert(segmentLengths, {
            start = totalLength,
            length = dist,
            time = points[i-1].transitionTime
        })

        totalLength = totalLength + dist
    end

    -- Convert normalized position to actual distance
    local targetDist = position * totalLength

    -- Find segment containing this position
    local targetSegment = nil
    for i, segment in ipairs(segmentLengths) do
        if targetDist >= segment.start and
                targetDist <= segment.start + segment.length then
            targetSegment = i
            break
        end
    end

    -- Create speed control points
    local speedControls = {}
    table.insert(speedControls, {time = 0, speed = 1.0})

    if targetSegment then
        -- Calculate normalized position for slowdown
        local segStart = segmentLengths[targetSegment].start
        local segLength = segmentLengths[targetSegment].length
        local normalizedPos = (targetDist - segStart) / segLength
        normalizedPos = (normalizedPos + (targetSegment - 1)) / (#points - 1)

        -- Add slowdown points
        table.insert(speedControls, {
            time = math.max(0, normalizedPos - width/2),
            speed = 1.0
        })

        table.insert(speedControls, {
            time = normalizedPos,
            speed = factor
        })

        table.insert(speedControls, {
            time = math.min(1, normalizedPos + width/2),
            speed = 1.0
        })
    end

    table.insert(speedControls, {time = 1, speed = 1.0})

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
        -- Only add if sufficiently far from previous point
        if point.time - lastTime > timeThreshold then
            table.insert(optimized, {
                time = point.time,
                speed = point.speed
            })
            lastTime = point.time
        elseif #optimized > 0 then
            -- Points are very close, use the minimum speed for safety
            optimized[#optimized].speed = math.min(optimized[#optimized].speed, point.speed)
        end
    end

    return optimized
end

return {
    AnchorTimeControl = AnchorTimeControl
}