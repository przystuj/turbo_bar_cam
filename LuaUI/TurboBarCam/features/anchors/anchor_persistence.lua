---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/settings/settings_manager.lua").SettingsManager
---@type CameraAnchorQueues
local CameraAnchorQueues = VFS.Include("LuaUI/TurboBarCam/features/anchors/anchor_queues.lua").CameraAnchorQueues

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log

---@class CameraAnchorPersistence
local CameraAnchorPersistence = {}

-- Function to get the map name without version number
-- Removes version patterns like "1.2.3" or "V1.2.3" from the end of map names
local function getCleanMapName()
    local mapName = Game.mapName

    -- Remove version numbers at the end (patterns like 1.2.3 or V1.2.3)
    local cleanName = mapName:gsub("%s+[vV]?%d+%.?%d*%.?%d*$", "")

    return cleanName
end

--- Serializes the current camera anchors and queue to a storable format
---@param includeQueue boolean Whether to include the current queue
---@return table serializedData Serialized anchors and queue data
local function serializeAnchorsAndQueue(includeQueue)
    local data = {
        anchors = {},
        queue = nil,
        speedControl = nil, -- Added field for speed control
        easingFunction = nil    -- Added field for easing function
    }

    -- Serialize anchors
    for id, anchorState in pairs(STATE.anchors) do
        data.anchors[tostring(id)] = {
            px = anchorState.px,
            py = anchorState.py,
            pz = anchorState.pz,
            rx = anchorState.rx,
            ry = anchorState.ry,
            rz = anchorState.rz,
            dx = anchorState.dx,
            dy = anchorState.dy,
            dz = anchorState.dz
        }
    end

    -- Serialize queue if requested
    if includeQueue and STATE.anchorQueue and STATE.anchorQueue.queue and STATE.anchorQueue.queue.points then
        local queueString = ""
        local isFirst = true

        for i, point in ipairs(STATE.anchorQueue.queue.points) do
            -- Skip the first point if it's just the starting position with no transition
            if i == 1 and point.transitionTime == 0 and not point.slowdownFactor then
                -- Skip
            else
                -- For anchors, check if any matches this point
                local foundAnchor = false
                for id, anchor in pairs(STATE.anchors) do
                    -- Compare position to find matching anchor
                    if math.abs(point.state.px - anchor.px) < 0.1 and
                            math.abs(point.state.py - anchor.py) < 0.1 and
                            math.abs(point.state.pz - anchor.pz) < 0.1 then
                        -- Found matching anchor, add to queue string
                        if not isFirst then
                            queueString = queueString .. ";"
                        end
                        queueString = queueString .. tostring(id) .. "," ..
                                tostring(point.transitionTime)

                        -- Include slowdown parameters if present
                        if point.slowdownFactor then
                            queueString = queueString .. "," .. tostring(point.slowdownFactor)

                            -- Include slowdown width if different from default
                            if point.slowdownWidth and
                                    point.slowdownWidth ~= CONFIG.CAMERA_MODES.ANCHOR.DEFAULT_SLOWDOWN_WIDTH then
                                queueString = queueString .. "," .. tostring(point.slowdownWidth)
                            end
                        end

                        isFirst = false
                        foundAnchor = true
                        break
                    end
                end

                -- If no matching anchor was found, represent as position
                if not foundAnchor then
                    if not isFirst then
                        queueString = queueString .. ";"
                    end
                    queueString = queueString .. "p," ..
                            tostring(point.transitionTime)

                    -- Include slowdown parameters if present
                    if point.slowdownFactor then
                        queueString = queueString .. "," .. tostring(point.slowdownFactor)

                        -- Include slowdown width if different from default
                        if point.slowdownWidth and
                                point.slowdownWidth ~= CONFIG.CAMERA_MODES.ANCHOR.DEFAULT_SLOWDOWN_WIDTH then
                            queueString = queueString .. "," .. tostring(point.slowdownWidth)
                        end
                    end

                    isFirst = false
                end
            end
        end

        -- Store queue string
        data.queue = queueString

        -- Store speed control settings if present
        if STATE.anchorQueue.speedControlSettings then
            data.speedControl = STATE.anchorQueue.speedControlSettings

            -- Handle easing function
            if STATE.anchorQueue.easingFunction then
                if type(STATE.anchorQueue.easingFunction) == "string" then
                    data.easingFunction = STATE.anchorQueue.easingFunction
                else
                    -- For custom functions, just save a generic indicator
                    data.easingFunction = "custom"
                end
            end
        end
    end

    return data
end

--- Deserializes and loads anchors and queue from stored data
---@param data table Stored anchor and queue data
---@return boolean success Whether loading was successful
local function deserializeAnchorsAndQueue(data)
    if not data then
        return false
    end

    -- Clear current anchors if we're loading new ones
    if data.anchors and next(data.anchors) then
        STATE.anchors = {}

        -- Load anchors
        for idStr, anchorData in pairs(data.anchors) do
            local id = tonumber(idStr)
            if id and id >= 0 and id <= 9 then
                STATE.anchors[id] = {
                    mode = 0,
                    name = "fps",
                    px = anchorData.px,
                    py = anchorData.py,
                    pz = anchorData.pz,
                    rx = anchorData.rx,
                    ry = anchorData.ry,
                    rz = anchorData.rz,
                    dx = anchorData.dx,
                    dy = anchorData.dy,
                    dz = anchorData.dz
                }
                Log.info("Loaded anchor " .. id)
            end
        end
    end

    -- Load queue if present
    if data.queue and data.queue ~= "" then
        -- Clear current queue
        CameraAnchorQueues.clearQueue()

        -- Set the queue using the stored string
        local success = CameraAnchorQueues.setQueue(data.queue)
        if success then
            Log.info("Loaded queue: " .. data.queue)

            -- Apply speed control settings if present
            if data.speedControl then
                if CameraAnchorQueues.applySpeedControl then
                    -- Apply the saved speed control with easing function if available
                    CameraAnchorQueues.applySpeedControl(data.speedControl, data.easingFunction)
                    Log.info("Applied saved speed control" ..
                            (data.easingFunction and (" with " .. data.easingFunction .. " easing") or ""))
                else
                    Log.warn("Cannot apply saved speed control - function not available")
                end
            end
        else
            Log.warn("Failed to load queue: " .. data.queue)
        end

        return success
    end

    return true
end

--- Saves current anchors and optionally the queue to a settings file, organized by map
---@param queueId string Identifier for the saved configuration
---@param includeQueue boolean Whether to include the current queue
---@return boolean success Whether saving was successful
function CameraAnchorPersistence.saveToFile(queueId, includeQueue)
    if not queueId or queueId == "" then
        Log.warn("Cannot save - no identifier specified")
        return false
    end

    -- Check if we have any anchors to save
    local anchorCount = 0
    for _ in pairs(STATE.anchors) do
        anchorCount = anchorCount + 1
    end

    if anchorCount == 0 then
        Log.warn("No anchors to save")
        return false
    end

    -- Check if we have a queue to save if requested
    if includeQueue and (not STATE.anchorQueue or not STATE.anchorQueue.queue or
            not STATE.anchorQueue.queue.points or #STATE.anchorQueue.queue.points < 2) then
        Log.warn("No valid queue to save")
        includeQueue = false
    end

    -- Serialize the data
    local data = serializeAnchorsAndQueue(includeQueue)

    -- Get clean map name
    local mapName = getCleanMapName()

    -- Load existing camera presets for all maps
    local mapPresets = SettingsManager.loadUserSetting("camera_presets", mapName) or {}

    -- Save preset for current map
    mapPresets[queueId] = data

    -- Save the entire structure back to storage
    local success = SettingsManager.saveUserSetting("camera_presets", mapName, mapPresets)

    if success then
        Log.info(string.format("Saved %d anchors%s with ID: %s for map: %s",
                anchorCount, includeQueue and " and queue with speed settings" or "", queueId, mapName))
    else
        Log.error("Failed to save configuration")
    end

    return success
end

--- Loads anchors and optionally a queue from a settings file for the current map
---@param id string Identifier for the saved configuration
---@return boolean success Whether loading was successful
function CameraAnchorPersistence.loadFromFile(id)
    if not id or id == "" then
        Log.warn("Cannot load - no identifier specified")
        return false
    end

    -- Get clean map name
    local mapName = getCleanMapName()

    -- Load all map presets
    local mapPresets = SettingsManager.loadUserSetting("camera_presets", mapName)

    -- Check if we have presets for this map
    if not mapPresets or not mapPresets[id] then
        Log.warn("No saved configuration found with ID: " .. id .. " for map: " .. mapName)
        return false
    end

    -- Get data for this specific preset
    local data = mapPresets[id]

    -- Deserialize and load the data
    local success = deserializeAnchorsAndQueue(data)

    if success then
        Log.info("Successfully loaded configuration with ID: " .. id .. " for map: " .. mapName)
    else
        Log.error("Failed to load configuration with ID: " .. id)
    end

    return success
end

-- Safe velocity calculation helper
local function calculateStepVelocity(step1, step2, dt)
    if not step1 or not step1.state or not step2 or not step2.state then
        return 0
    end

    if not dt or dt <= 0.000001 then
        return 0
    end

    local dx = (step2.state.px or 0) - (step1.state.px or 0)
    local dy = (step2.state.py or 0) - (step1.state.py or 0)
    local dz = (step2.state.pz or 0) - (step1.state.pz or 0)

    return math.sqrt(dx * dx + dy * dy + dz * dz) / dt
end

--- Prints a detailed description of the current queue
---@return boolean success Whether queue information was printed
function CameraAnchorPersistence.describeQueue()
    if not STATE.anchorQueue or not STATE.anchorQueue.queue or
            not STATE.anchorQueue.queue.points or #STATE.anchorQueue.queue.points < 2 then
        Log.info("No valid queue to describe")
        return false
    end

    local queue = STATE.anchorQueue.queue

    -- Print general queue information
    Log.info("==== CAMERA QUEUE DESCRIPTION ====")
    Log.info(string.format("Total points: %d", #queue.points))

    if queue.steps then
        Log.info(string.format("Total steps: %d", #queue.steps))
    end

    Log.info(string.format("Total duration: %.2f seconds", queue.totalDuration))
    Log.info(string.format("Queue active: %s", tostring(STATE.anchorQueue.active)))
    Log.info(string.format("Current step: %d", STATE.anchorQueue.currentStep or 0))

    -- Print tangent debug information
    if queue.tangents then
        Log.info("\n-- TANGENT VECTORS DEBUG --")
        for i, tangent in ipairs(queue.tangents) do
            if tangent then
                local mag = math.sqrt((tangent.x or 0) ^ 2 + (tangent.y or 0) ^ 2 + (tangent.z or 0) ^ 2)
                Log.info(string.format("  Point %d tangent: (%.3f, %.3f, %.3f), magnitude: %.3f",
                        i, tangent.x or 0, tangent.y or 0, tangent.z or 0, mag))
            else
                Log.info(string.format("  Point %d tangent: MISSING", i))
            end
        end
    end

    -- Print speed control information if available
    if STATE.anchorQueue.speedControlSettings then
        Log.info("\n-- SPEED CONTROL --")
        if type(STATE.anchorQueue.speedControlSettings) == "string" then
            Log.info(string.format("Speed preset: %s", STATE.anchorQueue.speedControlSettings))
        elseif type(STATE.anchorQueue.speedControlSettings) == "table" then
            Log.info(string.format("Custom speed control with %d points",
                    #STATE.anchorQueue.speedControlSettings))
            for i, point in ipairs(STATE.anchorQueue.speedControlSettings) do
                Log.info(string.format("  Point %d: time=%.2f, speed=%.2f",
                        i, point.time or 0, point.speed or 1.0))
            end
        end

        if STATE.anchorQueue.easingFunction then
            Log.info(string.format("Easing function: %s",
                    type(STATE.anchorQueue.easingFunction) == "string"
                            and STATE.anchorQueue.easingFunction
                            or "custom"))
        end
    end

    -- Print anchor points information with tangent analysis
    Log.info("\n-- ANCHOR POINTS WITH TANGENT ANALYSIS --")
    local cumulativeTime = 0
    for i, point in ipairs(queue.points) do
        local anchorInfo = string.format("Point %d: (%.1f, %.1f, %.1f)",
                i, point.state.px, point.state.py, point.state.pz)

        -- Check if this matches a saved anchor
        local matchingAnchor = "none"
        for id, anchor in pairs(STATE.anchors) do
            if math.abs(point.state.px - anchor.px) < 0.1 and
                    math.abs(point.state.py - anchor.py) < 0.1 and
                    math.abs(point.state.pz - anchor.pz) < 0.1 then
                matchingAnchor = id
                break
            end
        end

        -- Add timing information
        local timeInfo = string.format("  Time: %.2fs", cumulativeTime)
        if point.transitionTime and point.transitionTime > 0 then
            timeInfo = timeInfo .. string.format(", transition: %.2fs", point.transitionTime)
            cumulativeTime = cumulativeTime + point.transitionTime
        end

        -- Assemble and print information
        Log.info(anchorInfo)
        Log.info(string.format("  Anchor ID: %s", matchingAnchor))
        Log.info(timeInfo)

        -- Add tangent information
        if point.tangent then
            local mag = math.sqrt((point.tangent.x or 0) ^ 2 + (point.tangent.y or 0) ^ 2 + (point.tangent.z or 0) ^ 2)
            Log.info(string.format("  Tangent: (%.3f, %.3f, %.3f), magnitude: %.3f",
                    point.tangent.x or 0, point.tangent.y or 0, point.tangent.z or 0, mag))

            -- Analyze tangent direction
            if i > 1 and i < #queue.points then
                local prevPoint = queue.points[i - 1]
                local nextPoint = queue.points[i + 1]

                -- Calculate incoming and outgoing directions
                local inDir = {
                    x = point.state.px - prevPoint.state.px,
                    y = point.state.py - prevPoint.state.py,
                    z = point.state.pz - prevPoint.state.pz
                }

                local outDir = {
                    x = nextPoint.state.px - point.state.px,
                    y = nextPoint.state.py - point.state.py,
                    z = nextPoint.state.pz - point.state.pz
                }

                -- Normalize directions for comparison
                local inMag = math.sqrt(inDir.x ^ 2 + inDir.y ^ 2 + inDir.z ^ 2)
                local outMag = math.sqrt(outDir.x ^ 2 + outDir.y ^ 2 + outDir.z ^ 2)

                if inMag > 0.001 then
                    inDir.x = inDir.x / inMag
                    inDir.y = inDir.y / inMag
                    inDir.z = inDir.z / inMag
                end

                if outMag > 0.001 then
                    outDir.x = outDir.x / outMag
                    outDir.y = outDir.y / outMag
                    outDir.z = outDir.z / outMag
                end

                -- Calculate alignment of tangent with directions
                local tangentNorm = { x = 0, y = 0, z = 0 }
                if mag > 0.001 then
                    tangentNorm.x = point.tangent.x / mag
                    tangentNorm.y = point.tangent.y / mag
                    tangentNorm.z = point.tangent.z / mag
                end

                local inDot = tangentNorm.x * inDir.x + tangentNorm.y * inDir.y + tangentNorm.z * inDir.z
                local outDot = tangentNorm.x * outDir.x + tangentNorm.y * outDir.y + tangentNorm.z * outDir.z

                Log.info(string.format("  Tangent alignment: incoming=%.3f, outgoing=%.3f", inDot, outDot))
            end
        else
            Log.info("  Tangent: MISSING")
        end

        -- Add slowdown information
        if point.slowdownFactor then
            Log.info(string.format("  Slowdown factor: %.2f%s",
                    point.slowdownFactor,
                    point.slowdownWidth and string.format(", width: %.2f", point.slowdownWidth) or ""))
        end

        Log.info("") -- Empty line for readability
    end

    -- Print step information with velocity analysis
    Log.info("-- STEP INFORMATION WITH VELOCITY ANALYSIS --")
    if queue.steps and #queue.steps > 0 then
        Log.info(string.format("First step: time=%.2fs, pos=(%.1f, %.1f, %.1f)",
                queue.steps[1].time or 0,
                queue.steps[1].state.px or 0,
                queue.steps[1].state.py or 0,
                queue.steps[1].state.pz or 0))

        -- Print velocity at critical points
        if #queue.steps >= 3 then
            -- Calculate velocity at start, middle, and end
            local velocityPoints = {
                { index = 1, name = "Start" },
                { index = math.floor(#queue.steps / 2), name = "Middle" },
                { index = #queue.steps - 1, name = "Near end" }
            }

            for _, vp in ipairs(velocityPoints) do
                local i = vp.index
                if i < #queue.steps then
                    local currStep = queue.steps[i]
                    local nextStep = queue.steps[i + 1]
                    local dt = queue.stepTimes[i] or 0.01

                    if dt > 0 then
                        local velocity = {
                            x = (nextStep.state.px - currStep.state.px) / dt,
                            y = (nextStep.state.py - currStep.state.py) / dt,
                            z = (nextStep.state.pz - currStep.state.pz) / dt
                        }

                        local mag = math.sqrt(velocity.x ^ 2 + velocity.y ^ 2 + velocity.z ^ 2)
                        Log.info(string.format("%s velocity: %.3f units/sec at step %d",
                                vp.name, mag, i))
                    end
                end
            end
        end

        -- Print last step
        Log.info(string.format("Last step: time=%.2fs, pos=(%.1f, %.1f, %.1f)",
                queue.steps[#queue.steps].time or 0,
                queue.steps[#queue.steps].state.px or 0,
                queue.steps[#queue.steps].state.py or 0,
                queue.steps[#queue.steps].state.pz or 0))
    end

    -- Print queue representation
    Log.info("\n-- QUEUE PARAMETER STRING --")
    local queueString = ""
    local isFirst = true
    for i, point in ipairs(queue.points) do
        -- Skip the first point if it's just the starting position
        if i == 1 and point.transitionTime == 0 and not point.slowdownFactor then
            -- Skip
        else
            if not isFirst then
                queueString = queueString .. ";"
            end

            -- Look for matching anchor
            local matchingAnchor = nil
            for id, anchor in pairs(STATE.anchors) do
                if math.abs(point.state.px - anchor.px) < 0.1 and
                        math.abs(point.state.py - anchor.py) < 0.1 and
                        math.abs(point.state.pz - anchor.pz) < 0.1 then
                    matchingAnchor = id
                    break
                end
            end

            if matchingAnchor then
                queueString = queueString .. tostring(matchingAnchor)
            else
                queueString = queueString .. "p"
            end

            queueString = queueString .. "," .. tostring(point.transitionTime)

            -- Add slowdown parameters if present
            if point.slowdownFactor then
                queueString = queueString .. "," .. tostring(point.slowdownFactor)

                if point.slowdownWidth and
                        point.slowdownWidth ~= CONFIG.CAMERA_MODES.ANCHOR.DEFAULT_SLOWDOWN_WIDTH then
                    queueString = queueString .. "," .. tostring(point.slowdownWidth)
                end
            end

            isFirst = false
        end
    end

    Log.info(queueString)

    -- Print speed control string representation if applicable
    if STATE.anchorQueue.speedControlSettings then
        Log.info("\n-- SPEED CONTROL PARAMETER STRING --")
        if type(STATE.anchorQueue.speedControlSettings) == "string" then
            Log.info(string.format('CameraAnchorQueues.applySpeedControl("%s"%s)',
                    STATE.anchorQueue.speedControlSettings,
                    STATE.anchorQueue.easingFunction and
                            (', "' .. STATE.anchorQueue.easingFunction .. '"') or ""))
        else
            -- For complex speed control, provide a guideline rather than exact code
            Log.info("Custom speed control (see above for details)")
        end
    end

    -- Enhanced step information with better velocity analysis
    Log.info("-- STEP INFORMATION WITH VELOCITY ANALYSIS --")
    if queue.steps and #queue.steps > 0 then
        Log.info(string.format("First step: time=%.2fs, pos=(%.1f, %.1f, %.1f)",
                queue.steps[1].time or 0,
                queue.steps[1].state.px or 0,
                queue.steps[1].state.py or 0,
                queue.steps[1].state.pz or 0))

        -- Print velocity at critical points
        if #queue.steps >= 3 then
            -- Calculate velocity at start, middle, and end
            local velocityPoints = {
                { index = 1, name = "Start" },
                { index = math.floor(#queue.steps / 2), name = "Middle" },
                { index = #queue.steps - 1, name = "Near end" }
            }

            for _, vp in ipairs(velocityPoints) do
                local i = vp.index
                if i < #queue.steps then
                    local currStep = queue.steps[i]
                    local nextStep = queue.steps[i + 1]
                    local dt = queue.stepTimes[i] or 0.01

                    local vel = calculateStepVelocity(currStep, nextStep, dt)

                    Log.info(string.format("%s velocity: %.3f units/sec at step %d",
                            vp.name, vel, i))
                end
            end

            -- Additional: Check velocity at each waypoint
            Log.info("\nVelocity near waypoints:")
            for i, point in ipairs(queue.points) do
                if point and point.state then
                    -- Find closest step to this waypoint
                    local closestStepIndex = 1
                    local minDist = math.huge

                    for j = 1, #queue.steps do
                        local step = queue.steps[j]
                        if step and step.state then
                            local dist = math.sqrt(
                                    (step.state.px - point.state.px) ^ 2 +
                                            (step.state.py - point.state.py) ^ 2 +
                                            (step.state.pz - point.state.pz) ^ 2
                            )
                            if dist < minDist then
                                minDist = dist
                                closestStepIndex = j
                            end
                        end
                    end

                    -- Calculate velocity at this waypoint
                    if closestStepIndex > 0 and closestStepIndex < #queue.steps then
                        local currStep = queue.steps[closestStepIndex]
                        local nextStep = queue.steps[closestStepIndex + 1]
                        local dt = queue.stepTimes[closestStepIndex] or 0.01

                        local vel = calculateStepVelocity(currStep, nextStep, dt)

                        Log.info(string.format("  Waypoint %d velocity: %.3f units/sec", i, vel))
                    end
                end
            end
        end

        -- Print last step
        Log.info(string.format("Last step: time=%.2fs, pos=(%.1f, %.1f, %.1f)",
                queue.steps[#queue.steps].time or 0,
                queue.steps[#queue.steps].state.px or 0,
                queue.steps[#queue.steps].state.py or 0,
                queue.steps[#queue.steps].state.pz or 0))
    end

    Log.info("=================================")

    return true
end

--- Lists all maps that have saved presets
---@return boolean success Whether any maps with presets were found
function CameraAnchorPersistence.listAllMapsWithPresets()
    if Util.isTurboBarCamDisabled() then
        return false
    end

    -- Load all map presets
    local allMapPresets = SettingsManager.loadUserSetting("camera_presets")

    -- Check if we have any presets
    if not allMapPresets or not next(allMapPresets) then
        Log.info("No saved camera presets found for any maps")
        return false
    end

    -- Display all maps with presets
    Log.info("Maps with saved camera presets:")
    for mapName, mapPresets in pairs(allMapPresets) do
        local presetCount = 0
        for _ in pairs(mapPresets) do
            presetCount = presetCount + 1
        end

        Log.info(string.format("  - %s: %d presets", mapName, presetCount))
    end

    return true
end

return {
    CameraAnchorPersistence = CameraAnchorPersistence
}