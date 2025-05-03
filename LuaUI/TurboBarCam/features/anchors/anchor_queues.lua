---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type CameraAnchorUtils
local CameraAnchorUtils = VFS.Include("LuaUI/TurboBarCam/features/anchors/anchor_utils.lua").CameraAnchorUtils
---@type AnchorTimeControl
local AnchorTimeControl = VFS.Include("LuaUI/TurboBarCam/features/anchors/anchor_time_control.lua").AnchorTimeControl

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local CameraCommons = CommonModules.CameraCommons
local Util = CommonModules.Util
local Log = CommonModules.Log

---@class CameraAnchorQueues
local CameraAnchorQueues = {}

--- Add a single camera state to the queue
---@param state table Camera state to add
---@param transitionTime number Transition time in seconds
---@param slowdownFactor number|nil Optional slowdown factor
---@param slowdownWidth number|nil Optional slowdown width
---@param description string Description for logging
local function addStateToQueue(state, transitionTime, slowdownFactor, slowdownWidth, description)
    if not state then
        return
    end

    table.insert(STATE.anchorQueue.points, {
        state = state,
        transitionTime = transitionTime,
        slowdownFactor = slowdownFactor,
        slowdownWidth = slowdownWidth
    })

    Log.info(string.format("Added %s with transition time %.1f%s",
            description,
            transitionTime,
            slowdownFactor and string.format(", slowdown %.2f", slowdownFactor) or ""))
end

--- Get anchor state from ID or current position
---@param id number|string Anchor ID or "p" for current position
---@return table|nil state Camera state or nil if not found
---@return string description Description for logging
local function getAnchorState(id)
    if id == "p" then
        return CameraManager.getCameraState("CameraAnchorQueues.getAnchorState"), "current position"
    elseif STATE.anchors[id] then
        return STATE.anchors[id], "anchor " .. id
    else
        Log.warn("No anchor found with ID: " .. id)
        return nil, ""
    end
end

--- Process a range of anchors
---@param startId number|string Start anchor ID or "p" for current position
---@param endId number|string End anchor ID or "p" for current position
---@param transitionTime number Transition time in seconds
---@param slowdownFactor number|nil Optional slowdown factor
---@param slowdownWidth number|nil Optional slowdown width
local function processAnchorRange(startId, endId, transitionTime, slowdownFactor, slowdownWidth)
    -- Handle p-Y range
    if startId == "p" then
        -- Add current position first
        local state, desc = getAnchorState("p")
        addStateToQueue(state, transitionTime, slowdownFactor, slowdownWidth, desc .. " from range")

        -- Then add numerical anchors
        for id = 1, endId do
            state, desc = getAnchorState(id)
            if state then
                addStateToQueue(state, transitionTime, slowdownFactor, slowdownWidth, desc .. " from range")
            end
        end
        -- Handle X-p range
    elseif endId == "p" then
        -- Add numerical anchors first
        for id = startId, 9 do
            local state, desc = getAnchorState(id)
            if state then
                addStateToQueue(state, transitionTime, slowdownFactor, slowdownWidth, desc .. " from range")
            end
        end

        -- Then add current position
        local state, desc = getAnchorState("p")
        addStateToQueue(state, transitionTime, slowdownFactor, slowdownWidth, desc .. " from range")
        -- Handle X-Y range (both numeric)
    else
        for id = startId, endId do
            local state, desc = getAnchorState(id)
            if state then
                addStateToQueue(state, transitionTime, slowdownFactor, slowdownWidth, desc .. " from range")
            end
        end
    end
end

--- Parse a single anchor specification
---@param anchorSpec string Anchor specification string
---@param isLastPoint boolean Whether this is the last point in the queue
---@return table|nil anchor Parsed anchor data
local function parseAnchorSpec(anchorSpec)
    -- Trim whitespace
    anchorSpec = anchorSpec:match("^%s*(.-)%s*$")

    -- Skip empty specs
    if anchorSpec == "" then
        return nil
    end

    local parts = {}
    for part in anchorSpec:gmatch("[^,]+") do
        table.insert(parts, part:match("^%s*(.-)%s*$"))
    end

    -- First part should be either:
    -- - a digit (anchor ID)
    -- - "p" (current position)
    -- - range format "X-Y", "p-Y", or "X-p" (anchor range)
    local usePosition = false
    local anchorRange = nil
    local anchorId = nil

    if parts[1] == "p" then
        usePosition = true
    elseif parts[1]:match("^p%-%d+$") then
        -- Range format: "p-Y"
        local endId = parts[1]:match("p%-(%d+)")
        endId = tonumber(endId)

        if endId and endId >= 0 and endId <= 9 then
            anchorRange = { start = "p", ["end"] = endId }
        else
            Log.warn("Invalid anchor range: " .. parts[1])
            return nil
        end
    elseif parts[1]:match("^%d+%-p$") then
        -- Range format: "X-p"
        local startId = parts[1]:match("(%d+)%-p")
        startId = tonumber(startId)

        if startId and startId >= 0 and startId <= 9 then
            anchorRange = { start = startId, ["end"] = "p" }
        else
            Log.warn("Invalid anchor range: " .. parts[1])
            return nil
        end
    elseif parts[1]:match("^%d+%-%d+$") then
        -- Range format: "X-Y"
        local startId, endId = parts[1]:match("(%d+)%-(%d+)")
        startId, endId = tonumber(startId), tonumber(endId)

        if startId and endId and startId >= 0 and endId <= 9 and startId <= endId then
            anchorRange = { start = startId, ["end"] = endId }
        else
            Log.warn("Invalid anchor range: " .. parts[1])
            return nil
        end
    else
        anchorId = tonumber(parts[1])
        if not anchorId or anchorId < 0 or anchorId > 9 then
            Log.warn("Invalid anchor ID: " .. parts[1])
            return nil
        end
    end

    local transitionTime = tonumber(parts[2] or tostring(CONFIG.CAMERA_MODES.ANCHOR.DURATION)) or CONFIG.CAMERA_MODES.ANCHOR.DURATION

    -- Extract slowdown parameters (either factor or both factor and width)
    local slowdownFactor = nil
    local slowdownWidth = nil

    if #parts >= 3 then
        slowdownFactor = tonumber(parts[3])
        if slowdownFactor then
            -- Only store if different from default (to keep queue string cleaner)
            if slowdownFactor == CONFIG.CAMERA_MODES.ANCHOR.DEFAULT_SLOWDOWN_FACTOR then
                slowdownFactor = nil
            end
        end
    end

    if #parts >= 4 then
        slowdownWidth = tonumber(parts[4])
        if slowdownWidth and slowdownFactor then
            -- Only store if different from default
            if slowdownWidth == CONFIG.CAMERA_MODES.ANCHOR.DEFAULT_SLOWDOWN_WIDTH then
                slowdownWidth = nil
            end
        end
    end

    -- Create result
    local result = {
        usePosition = usePosition,
        anchorId = anchorId,
        anchorRange = anchorRange,
        transitionTime = transitionTime,
        slowdownFactor = slowdownFactor,
        slowdownWidth = slowdownWidth
    }

    return result
end

--- Initialize the queue if needed
---@return boolean initialized Whether we initialized a new queue
local function ensureQueueInitialized()
    if not STATE.anchorQueue then
        STATE.anchorQueue = {
            queue = nil,
            active = false,
            currentStep = 1,
            startTime = 0,
            stepStartTime = 0,
            points = {},
            speedControlSettings = nil,
            easingFunction = nil
        }
        return true
    end
    return false
end

--- Parse anchor parameter string into individual specs
---@param anchorParams string Parameters string
---@return table specs Array of parsed anchor specifications
local function parseAnchorParams(anchorParams)
    local specs = {}
    if not anchorParams or anchorParams == "" then
        -- If no params, add current position with default transition time
        table.insert(specs, "p," .. CONFIG.CAMERA_MODES.ANCHOR.DURATION)
        return specs
    end

    for spec in anchorParams:gmatch("[^;]+") do
        table.insert(specs, spec)
    end
    return specs
end

--- Update the queue path without starting it
function CameraAnchorQueues.updateQueuePath()
    if not STATE.anchorQueue or not STATE.anchorQueue.points or #STATE.anchorQueue.points < 2 then
        -- Not enough points for a path yet
        STATE.anchorQueue.queue = nil
        return false
    end

    -- Create path info from the points
    STATE.anchorQueue.queue = CameraAnchorUtils.createPathTransition(STATE.anchorQueue.points)

    -- Apply speed control settings if they exist
    STATE.anchorQueue.queue = AnchorTimeControl.applySpeedControl(
            STATE.anchorQueue.queue,
            STATE.anchorQueue.speedControlSettings,
            STATE.anchorQueue.easingFunction
    )
    Log.debug("Applied saved speed control settings to queue")

    return true
end

--- Add to the camera anchor queue
---@param anchorParams string Parameters for the queue
---@return boolean success Whether the queue was updated successfully
function CameraAnchorQueues.addToQueue(anchorParams)
    -- Initialize queue if needed
    ensureQueueInitialized()

    -- If queue is empty, initialize points array first
    if not STATE.anchorQueue.points then
        STATE.anchorQueue.points = {}
    end

    -- Parse the params to create anchor points
    local specs = parseAnchorParams(anchorParams)

    -- Process each spec and add to queue
    for i, spec in ipairs(specs) do
        -- Check if this is the last point in the set
        local anchorData = parseAnchorSpec(spec)

        if anchorData then
            if anchorData.anchorRange then
                -- Process the range using the helper function
                processAnchorRange(
                        anchorData.anchorRange.start,
                        anchorData.anchorRange["end"],
                        anchorData.transitionTime,
                        anchorData.slowdownFactor,
                        anchorData.slowdownWidth
                )
            else
                -- Handle single anchor or position
                local state, desc
                if anchorData.usePosition then
                    state, desc = getAnchorState("p")
                else
                    state, desc = getAnchorState(anchorData.anchorId)
                end

                -- Add to queue if we got a valid state
                if state then
                    addStateToQueue(
                            state,
                            anchorData.transitionTime,
                            anchorData.slowdownFactor,
                            anchorData.slowdownWidth,
                            desc
                    )
                end
            end
        end
    end

    -- Update the queue path whenever we add points
    CameraAnchorQueues.updateQueuePath()

    return true
end

--- Set the camera anchor queue
---@param anchorParams string Parameters for the queue
---@return boolean success Whether the queue was set successfully
function CameraAnchorQueues.setQueue(anchorParams)
    -- Initialize a new queue
    if not STATE.anchorQueue then
        STATE.anchorQueue = {
            queue = nil,
            active = false,
            currentStep = 1,
            stepStartTime = 0,
            points = {},
            speedControlSettings = nil,
            easingFunction = nil
        }
    else
        -- Clear existing queue but keep speed settings
        STATE.anchorQueue.queue = nil
        STATE.anchorQueue.points = {}
        -- We deliberately keep speedControlSettings and easingFunction
    end

    -- Add the specified anchor points
    local success = CameraAnchorQueues.addToQueue(anchorParams)

    -- Update the queue path after setting all points
    CameraAnchorQueues.updateQueuePath()

    return success
end

--- Clear the current queue
---@return boolean success Always returns true
function CameraAnchorQueues.clearQueue()
    -- Reset queue state
    if STATE.anchorQueue then
        STATE.anchorQueue.queue = nil
        STATE.anchorQueue.active = false
        STATE.anchorQueue.currentStep = 1
        STATE.anchorQueue.stepStartTime = 0
        STATE.anchorQueue.points = {}
        STATE.anchorQueue.speedControlSettings = nil
        STATE.anchorQueue.easingFunction = nil
    end

    Log.info("Queue cleared")
    return true
end

--- Apply speed control to the current queue
---@param speedControls table|string Speed control configuration or preset name
---@param easingFunc string|function|nil Optional easing function name or function
---@return boolean success Whether speed control was applied successfully
function CameraAnchorQueues.applySpeedControl(speedControls, easingFunc)
    -- Validate
    if not STATE.anchorQueue then
        Log.warn("Cannot apply speed control - no queue exists")
        return false
    end

    -- Store the speed control settings for persistence and future use
    STATE.anchorQueue.speedControlSettings = speedControls
    STATE.anchorQueue.easingFunction = easingFunc

    -- If we already have a queue path, apply speed control to it
    if STATE.anchorQueue.queue then
        STATE.anchorQueue.queue = AnchorTimeControl.applySpeedControl(
                STATE.anchorQueue.queue,
                speedControls,
                easingFunc
        )
    else
        -- Try to create the queue path with at least 2 points
        if STATE.anchorQueue.points and #STATE.anchorQueue.points >= 2 then
            CameraAnchorQueues.updateQueuePath()
        else
            Log.warn("Not enough points to create queue path for speed control")
        end
    end

    -- Log what we did
    if type(speedControls) == "string" then
        Log.debug(string.format("Applied '%s' speed profile%s",
                speedControls,
                easingFunc and (", with " .. tostring(easingFunc) .. " easing") or "")
        )
    else
        Log.debug(string.format("Applied custom speed control%s",
                easingFunc and (", with " .. tostring(easingFunc) .. " easing") or "")
        )
    end

    return true
end

--- Start the camera anchor queue
---@return boolean success Whether the queue was started successfully
function CameraAnchorQueues.startQueue()
    -- Check if we have a valid queue
    if not STATE.anchorQueue or not STATE.anchorQueue.points or #STATE.anchorQueue.points < 2 then
        Log.warn("Cannot start queue - not enough points")
        return false
    end

    -- If queue is already active, stop it
    if STATE.anchorQueue.active then
        CameraAnchorQueues.stopQueue()
    end

    -- Ensure we have a queue path
    if not STATE.anchorQueue.queue then
        CameraAnchorQueues.updateQueuePath()
    end

    -- Final check if we still don't have a queue
    if not STATE.anchorQueue.queue then
        Log.warn("Cannot start queue - failed to create path")
        return false
    end

    -- Activate the queue
    STATE.anchorQueue.active = true
    STATE.anchorQueue.currentStep = 1
    STATE.anchorQueue.stepStartTime = Spring.GetTimer()
    STATE.anchorQueue.startTime = Spring.GetTimer()

    Log.debug(string.format("Started queue with %d points, %d steps",
            #STATE.anchorQueue.points, #STATE.anchorQueue.queue.steps))

    return true
end

--- Update the anchor queue with proper error handling and NaN protection
---@return boolean active Whether the queue is still active
function CameraAnchorQueues.updateQueue()
    if Util.isTurboBarCamDisabled() then
        return false
    end

    -- Check if queue is active
    if not STATE.anchorQueue or not STATE.anchorQueue.active then
        return false
    end

    if STATE.tracking.mode then
        CameraAnchorQueues.stopQueue()
        return
    end

    -- Get the queue
    local queue = STATE.anchorQueue.queue
    if not queue or not queue.steps or #queue.steps == 0 then
        STATE.anchorQueue.active = false
        Log.debug("Queue stopped - no steps available")
        return false
    end

    -- Check if we're at the end of the queue
    if STATE.anchorQueue.currentStep >= #queue.steps then
        STATE.anchorQueue.active = false
        Log.info("Queue completed")

        -- Log final statistics
        local totalTime = Spring.DiffTimers(Spring.GetTimer(), STATE.anchorQueue.startTime)
        Log.debug(string.format("Queue execution completed in %.2f seconds", totalTime))
        return false
    end

    -- Get the current step
    local currentStep = queue.steps[STATE.anchorQueue.currentStep]

    -- Get normalized progress through current step (0-1)
    local elapsed = Spring.DiffTimers(Spring.GetTimer(), STATE.anchorQueue.stepStartTime)
    local stepDuration = queue.stepTimes[STATE.anchorQueue.currentStep] or 0.01

    -- Use our standardized time helper
    local progressTime = Util.TimeHelpers.normalizeTime(elapsed, stepDuration)

    -- Determine if we need to advance to the next step
    if progressTime >= 1.0 then
        -- Move to next step
        STATE.anchorQueue.currentStep = STATE.anchorQueue.currentStep + 1
        STATE.anchorQueue.stepStartTime = Spring.GetTimer()

        -- Get the new current step
        currentStep = queue.steps[STATE.anchorQueue.currentStep]

        -- Reset progress time for next interpolation
        progressTime = 0
    end

    -- Apply the current step's camera state
    if currentStep and currentStep.state then
        -- Interpolate between steps for smoother motion
        if STATE.anchorQueue.currentStep < #queue.steps then
            local nextStep = queue.steps[STATE.anchorQueue.currentStep + 1]
            if nextStep and nextStep.state then
                -- Clamp interpolation factor to prevent issues
                local t = math.max(0, math.min(1, progressTime))

                -- Create interpolated state using existing lerp functions
                local interpolatedState = {
                    mode = 0,
                    name = "fps",
                    px = CameraCommons.lerp(currentStep.state.px, nextStep.state.px, t),
                    py = CameraCommons.lerp(currentStep.state.py, nextStep.state.py, t),
                    pz = CameraCommons.lerp(currentStep.state.pz, nextStep.state.pz, t),
                    rx = CameraAnchorUtils.lerpAngle(currentStep.state.rx, nextStep.state.rx, t),
                    ry = CameraAnchorUtils.lerpAngle(currentStep.state.ry, nextStep.state.ry, t),
                    rz = 0
                }

                -- Calculate direction from rotation (with NaN protection)
                local cosRx = math.cos(interpolatedState.rx or 0)
                local rx = interpolatedState.rx or 0
                local ry = interpolatedState.ry or 0

                interpolatedState.dx = math.sin(ry) * cosRx
                interpolatedState.dy = math.sin(rx)
                interpolatedState.dz = math.cos(ry) * cosRx

                -- Check for NaN values before applying
                local hasNaN = false
                for key, value in pairs(interpolatedState) do
                    if type(value) == "number" and value ~= value then
                        -- NaN check
                        hasNaN = true
                        Log.error(string.format("NaN detected in interpolatedState.%s", key))
                        break
                    end
                end

                if not hasNaN then
                    -- Apply interpolated state
                    CameraManager.setCameraState(interpolatedState, 1, "CameraAnchorQueues.updateQueue")
                else
                    -- Fallback: use current step without interpolation
                    Log.warn("Using fallback: applying current step without interpolation")
                    CameraManager.setCameraState(currentStep.state, 1, "CameraAnchorQueues.updateQueue")
                end
            else
                -- Just apply current state if no valid next step
                CameraManager.setCameraState(currentStep.state, 1, "CameraAnchorQueues.updateQueue")
            end
        else
            -- Just apply current state if at end
            CameraManager.setCameraState(currentStep.state, 1, "CameraAnchorQueues.updateQueue")
        end

        -- Log progress periodically
        if STATE.anchorQueue.currentStep % 20 == 0 then
            -- Use standardized time to report progress
            local overallProgress = Util.TimeHelpers.stepToNormalizedTime(
                    STATE.anchorQueue.currentStep,
                    #queue.steps
            )

            --Log.trace(string.format("Queue progress: %d/%d (%.1f%%)",
            --        STATE.anchorQueue.currentStep, #queue.steps,
            --        overallProgress * 100))
        end
    end

    return STATE.anchorQueue.active
end

--- Stops the currently playing camera queue
---@return boolean success Whether the queue was actively stopped
function CameraAnchorQueues.stopQueue()
    -- Check if there's an active queue to stop
    if not STATE.anchorQueue or not STATE.anchorQueue.active then
        return false
    end

    -- Stop the queue
    STATE.anchorQueue.active = false
    STATE.anchorQueue.currentStep = 1
    STATE.anchorQueue.stepStartTime = 0

    Log.info("Camera queue manually stopped")
    return true
end

return {
    CameraAnchorQueues = CameraAnchorQueues
}