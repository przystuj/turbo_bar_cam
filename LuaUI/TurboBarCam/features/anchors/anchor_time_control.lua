---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type EasingFunctions
local EasingFunctions = VFS.Include("LuaUI/TurboBarCam/features/anchors/anchor_easing_functions.lua").EasingFunctions

local Log = CommonModules.Log

---@class AnchorTimeControl
local AnchorTimeControl = {}

--- Apply speed control to a camera path
---@param pathInfo table Path information structure
---@param speedControls table|string Array of {time, speed} control points or preset name
---@param easingFunc string|function Optional easing function name or function
---@return table pathInfo Updated path information
function AnchorTimeControl.applySpeedControl(pathInfo, speedControls, easingFunc)
    -- Handle preset names
    if type(speedControls) == "string" then
        speedControls = EasingFunctions.getPresetSpeedControls(speedControls)
        if not speedControls then
            Log.warn("Unknown speed control preset, using constant speed")
            return pathInfo
        end
    end

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
                easing = EasingFunctions.linear()
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

--- Build a time mapping from speed control points
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
        easingFunc = easingFunc
    }

    -- Add first mapping point
    table.insert(timeMap.points, {
        inputTime = 0,
        outputTime = 0
    })

    -- Calculate time mapping for each segment
    local currentTime = 0
    for i = 1, #speedControlPoints - 1 do
        local cp1 = speedControlPoints[i]
        local cp2 = speedControlPoints[i+1]

        -- Calculate average speed in this segment
        local avgSpeed = (cp1.speed + cp2.speed) / 2

        -- Calculate how much progress we'd make at normal speed
        local normalProgress = cp2.time - cp1.time

        -- Adjust for actual speed (slower speed = more time)
        local actualProgress = normalProgress / avgSpeed

        -- Add to time mapping
        currentTime = currentTime + actualProgress
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

--- Get remapped time based on time mapping
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
---@param points table Array of waypoints
---@param slowdownFactor number|nil Speed reduction factor at waypoints (lower = slower)
---@param slowdownWidthBase number|nil Base width of slowdown zone around each waypoint (0-1)
---@param adaptiveWidth boolean|nil Whether to adapt width based on path length
---@return table speedControls Speed control points
function AnchorTimeControl.createSlowdownAtPoints(points, slowdownFactor, slowdownWidthBase, adaptiveWidth)
    -- Default values
    slowdownFactor = slowdownFactor or 0.3     -- 30% of normal speed
    slowdownWidthBase = slowdownWidthBase or 0.2   -- 20% of path length as slowdown zone
    adaptiveWidth = (adaptiveWidth ~= false)   -- Default to true

    local speedControls = {}

    -- Special case: if only 2 points, just go at constant speed
    if #points <= 2 then
        return {{time = 0, speed = 1}, {time = 1, speed = 1}}
    end

    -- Add first point
    table.insert(speedControls, {time = 0, speed = 1})

    -- Calculate relative positions of points along the path
    local totalLength = 0
    local pointPositions = {0} -- First point is at 0
    local segmentLengths = {}

    for i = 2, #points do
        local p1 = points[i-1].state
        local p2 = points[i].state

        -- Calculate distance
        local dist = math.sqrt(
                (p2.px - p1.px)^2 +
                        (p2.py - p1.py)^2 +
                        (p2.pz - p1.pz)^2
        )

        table.insert(segmentLengths, dist)
        totalLength = totalLength + dist
        table.insert(pointPositions, totalLength)
    end

    -- Normalize point positions to 0-1 range
    for i = 1, #pointPositions do
        pointPositions[i] = pointPositions[i] / totalLength
    end

    -- Calculate average segment length for adaptive width
    local avgSegmentLength = totalLength / (#points - 1)

    -- Create slowdown zones around intermediate points
    for i = 2, #points - 1 do
        local pointPos = pointPositions[i]

        -- Calculate adaptive width if enabled
        local slowdownWidth = slowdownWidthBase
        if adaptiveWidth then
            -- Get this point's adjacent segments
            local prevSegLen = segmentLengths[i-1]
            local nextSegLen = segmentLengths[i]

            -- Use smaller of the two segments to determine width scale
            local segScale = math.min(prevSegLen, nextSegLen) / avgSegmentLength

            -- Scale width inversely to segment length (shorter segments get smaller width)
            -- but clamp between 0.5-2 times the base width
            local widthScale = math.max(0.5, math.min(2.0, 1.0 / segScale))
            slowdownWidth = slowdownWidthBase * widthScale

            -- Ensure width doesn't exceed available space
            local maxWidth = math.min(pointPos, 1-pointPos) * 1.8  -- 90% of available space
            slowdownWidth = math.min(slowdownWidth, maxWidth)

            Log.debug(string.format("Point %d: adaptive width %.3f (segments: %.1f, %.1f, avg: %.1f)",
                    i, slowdownWidth, prevSegLen, nextSegLen, avgSegmentLength))
        end

        -- Add speed control points around this waypoint
        -- Start slowing down
        table.insert(speedControls, {
            time = math.max(0, pointPos - slowdownWidth/2),
            speed = 1
        })

        -- Slowest at the waypoint
        table.insert(speedControls, {
            time = pointPos,
            speed = slowdownFactor
        })

        -- Return to normal speed
        table.insert(speedControls, {
            time = math.min(1, pointPos + slowdownWidth/2),
            speed = 1
        })
    end

    -- Add final point
    table.insert(speedControls, {time = 1, speed = 1})

    -- Sort and merge close control points
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

--- Creates a composite speed control by combining multiple effects
---@param baseControls table Base speed control (preset name or control points)
---@param slowdownPoints table Array of {position, factor, width} for slowdowns
---@param easingFunc string|function Optional global easing function
---@return table compositeControls Combined speed control
function AnchorTimeControl.createCompositeSpeedControl(baseControls, slowdownPoints, easingFunc)
    -- Get base controls if specified as preset
    if type(baseControls) == "string" then
        baseControls = EasingFunctions.getPresetSpeedControls(baseControls)
        if not baseControls then
            baseControls = {{time = 0, speed = 1}, {time = 1, speed = 1}}
        end
    elseif not baseControls or #baseControls < 2 then
        baseControls = {{time = 0, speed = 1}, {time = 1, speed = 1}}
    end

    -- If no slowdown points, just return base controls
    if not slowdownPoints or #slowdownPoints == 0 then
        return baseControls, easingFunc
    end

    -- Copy base controls
    local composite = {}
    for _, point in ipairs(baseControls) do
        table.insert(composite, {time = point.time, speed = point.speed})
    end

    -- Add slowdown points
    for _, slowdown in ipairs(slowdownPoints) do
        local pos = slowdown.position
        local factor = slowdown.factor or 0.3
        local width = slowdown.width or 0.2

        -- Add control points for this slowdown
        table.insert(composite, {
            time = math.max(0, pos - width/2),
            speed = 1 * slowdown.baseSpeed or 1
        })

        table.insert(composite, {
            time = pos,
            speed = factor * (slowdown.baseSpeed or 1)
        })

        table.insert(composite, {
            time = math.min(1, pos + width/2),
            speed = 1 * (slowdown.baseSpeed or 1)
        })
    end

    return AnchorTimeControl.optimizeSpeedControls(composite), easingFunc
end

return {
    AnchorTimeControl = AnchorTimeControl
}