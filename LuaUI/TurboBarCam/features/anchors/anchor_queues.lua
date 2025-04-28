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

--- Parse a single anchor specification
---@param anchorSpec string Anchor specification string
---@param isLastPoint boolean Whether this is the last point in the queue
---@return table|nil anchor Parsed anchor data
local function parseAnchorSpec(anchorSpec, isLastPoint)
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

    -- First part should be either a digit (anchor ID) or "p" (current position)
    local usePosition = false
    local anchorId = nil

    if parts[1] == "p" then
        usePosition = true
    else
        anchorId = tonumber(parts[1])
        if not anchorId or anchorId < 0 or anchorId > 9 then
            Log.warn("Invalid anchor ID: " .. parts[1])
            return nil
        end
    end

    -- Extract transition time
    -- Last point shouldn't have a transition time
    local transitionTime = 0
    if not isLastPoint then
        transitionTime = tonumber(parts[2] or "0") or 0
    end

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
            speedControlSettings = nil, -- Add speed control tracking
            easingFunction = nil         -- Add easing function tracking
        }
        return true
    end
    return false
end

--- Update the queue path without starting it
local function updateQueuePath()
    if not STATE.anchorQueue or not STATE.anchorQueue.points or #STATE.anchorQueue.points < 2 then
        -- Not enough points for a path yet
        STATE.anchorQueue.queue = nil
        return false
    end

    -- Create path info from the points
    STATE.anchorQueue.queue = CameraAnchorUtils.createPathTransition(STATE.anchorQueue.points)

    -- Apply speed control settings if they exist
    if STATE.anchorQueue.speedControlSettings then
        STATE.anchorQueue.queue = AnchorTimeControl.applySpeedControl(
                STATE.anchorQueue.queue,
                STATE.anchorQueue.speedControlSettings,
                STATE.anchorQueue.easingFunction
        )
        Log.debug("Applied saved speed control settings to queue")
    end

    return true
end

--- Parse anchor parameter string into individual specs
---@param anchorParams string Parameters string
---@return table specs Array of parsed anchor specifications
local function parseAnchorParams(anchorParams)
    local specs = {}
    for spec in anchorParams:gmatch("[^;]+") do
        table.insert(specs, spec)
    end
    return specs
end

--- Add to the camera anchor queue
---@param anchorParams string Parameters for the queue
---@return boolean success Whether the queue was updated successfully
function CameraAnchorQueues.addToQueue(anchorParams)
    -- Initialize queue if needed
    ensureQueueInitialized()

    -- If queue is empty, need to add start position first
    if #STATE.anchorQueue.points == 0 then
        -- Get current camera position
        local currentState = CameraManager.getCameraState("CameraAnchorQueues.addToQueue")

        -- Add first point with no transition
        local startPoint = {
            state = currentState,
            transitionTime = 0,
            slowdownFactor = nil,
            slowdownWidth = nil
        }

        STATE.anchorQueue.points = { startPoint }
    end

    -- Parse the params to create anchor points
    local specs = parseAnchorParams(anchorParams)

    -- Process each spec and add to queue
    for i, spec in ipairs(specs) do
        -- Check if this is the last point in the set
        local isLastPoint = (i == #specs)
        local anchorData = parseAnchorSpec(spec, isLastPoint)

        if anchorData then
            -- Get state based on anchor ID or current position
            local anchorState = nil

            if anchorData.usePosition then
                anchorState = CameraManager.getCameraState("CameraAnchorQueues.addToQueue")
            elseif STATE.anchors[anchorData.anchorId] then
                anchorState = STATE.anchors[anchorData.anchorId]
            else
                Log.warn("No anchor found with ID: " .. anchorData.anchorId)
            end

            -- Add to queue only if anchorState is valid
            if anchorState then
                table.insert(STATE.anchorQueue.points, {
                    state = anchorState,
                    transitionTime = anchorData.transitionTime,
                    slowdownFactor = anchorData.slowdownFactor,
                    slowdownWidth = anchorData.slowdownWidth
                })

                Log.info(string.format("Added %s to queue with transition time %.1f%s",
                        anchorData.usePosition and "current position" or ("anchor " .. anchorData.anchorId),
                        anchorData.transitionTime,
                        anchorData.slowdownFactor and string.format(", slowdown %.2f", anchorData.slowdownFactor) or ""))
            end
        end
    end

    -- Update the queue path whenever we add points
    updateQueuePath()

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
            speedControlSettings = nil, -- Add speed control tracking
            easingFunction = nil         -- Add easing function tracking
        }
    else
        -- Clear existing queue but keep speed settings
        STATE.anchorQueue.queue = nil
        STATE.anchorQueue.points = {}
        -- We deliberately keep speedControlSettings and easingFunction
    end

    -- Get current camera state for first point
    local currentState = CameraManager.getCameraState("CameraAnchorQueues.setQueue")

    -- Add starting point with no transition
    table.insert(STATE.anchorQueue.points, {
        state = currentState,
        transitionTime = 0,
        slowdownFactor = nil,
        slowdownWidth = nil
    })

    -- If no params, just return with the starting point
    if not anchorParams or anchorParams == "" then
        return true
    end

    -- Add the specified anchor points
    local success = CameraAnchorQueues.addToQueue(anchorParams)

    -- Update the queue path after setting all points
    updateQueuePath()

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
        STATE.anchorQueue.speedControlSettings = nil  -- Clear speed control
        STATE.anchorQueue.easingFunction = nil        -- Clear easing function
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
            updateQueuePath()
        else
            Log.warn("Not enough points to create queue path for speed control")
        end
    end

    -- Log what we did
    if type(speedControls) == "string" then
        Log.info(string.format("Applied '%s' speed profile%s",
                speedControls,
                easingFunc and (", with " .. tostring(easingFunc) .. " easing") or "")
        )
    else
        Log.info(string.format("Applied custom speed control%s",
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
        updateQueuePath()
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

    Log.info(string.format("Started queue with %d points, %d steps",
            #STATE.anchorQueue.points, #STATE.anchorQueue.queue.steps))

    return true
end

--- Create slowdown points at waypoints
---@param slowdownFactor number Speed reduction factor (0-1)
---@param slowdownWidth number|nil Width of slowdown zones (0-1)
---@param adaptiveWidth boolean|nil Whether to use adaptive width based on segment length
---@return boolean success Whether slowdown was applied successfully
function CameraAnchorQueues.createSlowdownAtPoints(slowdownFactor, slowdownWidth, adaptiveWidth)
    if Util.isTurboBarCamDisabled() then
        return false
    end

    -- Validate
    if not STATE.anchorQueue or not STATE.anchorQueue.points or #STATE.anchorQueue.points < 3 then
        Log.warn("Cannot apply slowdown - need at least 3 queue points")
        return false
    end

    -- Ensure we have a queue path
    if not STATE.anchorQueue.queue then
        updateQueuePath()
    end

    -- Create and apply the slowdown
    local speedControls = AnchorTimeControl.createSlowdownAtPoints(
            STATE.anchorQueue.points,
            slowdownFactor,
            slowdownWidth,
            adaptiveWidth
    )

    -- Store these settings for persistence
    STATE.anchorQueue.speedControlSettings = speedControls

    -- Apply to the queue
    if STATE.anchorQueue.queue then
        STATE.anchorQueue.queue = AnchorTimeControl.applySpeedControl(
                STATE.anchorQueue.queue,
                speedControls
        )
    end

    Log.info(string.format("Applied slowdown at waypoints (factor: %.2f, %s width: %.2f)",
            slowdownFactor or 0.3,
            adaptiveWidth and "adaptive" or "fixed",
            slowdownWidth or 0.2))

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
        Log.info(string.format("Queue execution completed in %.2f seconds", totalTime))
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

            Log.trace(string.format("Queue progress: %d/%d (%.1f%%)",
                    STATE.anchorQueue.currentStep, #queue.steps,
                    overallProgress * 100))
        end
    end

    return STATE.anchorQueue.active
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

-- Add this to updateQueue to debug the actual execution
function CameraAnchorQueues.debugQueueExecution()
    if not STATE.anchorQueue or not STATE.anchorQueue.active then
        return
    end

    -- Log when transitioning between segments
    if STATE.anchorQueue.currentStep % 30 == 0 then
        -- Log every 30 steps
        local queue = STATE.anchorQueue.queue
        if not queue or not queue.steps then
            return
        end

        local currentStep = queue.steps[STATE.anchorQueue.currentStep]
        if not currentStep or not currentStep.state then
            return
        end

        -- Check for segment boundaries
        for i, point in ipairs(queue.points) do
            if point and point.state then
                local dist = math.sqrt(
                        (currentStep.state.px - point.state.px) ^ 2 +
                                (currentStep.state.py - point.state.py) ^ 2 +
                                (currentStep.state.pz - point.state.pz) ^ 2
                )

                if dist < 50 then
                    Log.warn(string.format("Approaching segment boundary at point %d (dist: %.2f)",
                            i, dist))

                    -- Check velocity safely
                    if STATE.anchorQueue.currentStep < #queue.steps then
                        local nextStep = queue.steps[STATE.anchorQueue.currentStep + 1]
                        local dt = queue.stepTimes[STATE.anchorQueue.currentStep] or 0.01

                        local vel = calculateStepVelocity(currentStep, nextStep, dt)

                        Log.warn(string.format("  Current velocity: %.3f units/sec", vel))

                        -- Check if this is a significant slowdown
                        if vel < 10 then
                            Log.warn("  WARNING: Camera is slowing down significantly at waypoint!")
                        end
                    end
                end
            end
        end
    end
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