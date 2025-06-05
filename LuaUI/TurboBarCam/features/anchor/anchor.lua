---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CameraAnchorUtils = ModuleManager.CameraAnchorUtils(function(m) CameraAnchorUtils = m end)
local CameraAnchorPersistence = ModuleManager.CameraAnchorPersistence(function(m) CameraAnchorPersistence = m end)
local EasingFunctions = ModuleManager.EasingFunctions(function(m) EasingFunctions = m end)
local Util = ModuleManager.Util(function(m) Util = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)

---@class CameraAnchor
local CameraAnchor = {}

--- Sets a camera anchor
---@param index number Anchor index
---@return boolean success Always returns true for widget handler
function CameraAnchor.set(index)
    if Util.isTurboBarCamDisabled() then
        return
    end

    index = tonumber(index)
    if index and index >= 0 then
        STATE.anchor.points[index] = Spring.GetCameraState()
        Log:info("Saved camera anchor: " .. index)
    end
    return
end

--- Get the easing function based on type string
---@param easingType string|nil Easing type
---@return function easingFunc The easing function to use
function CameraAnchor.getEasingFunction(easingType)
    -- Use specified easing, or fall back to state easing, or default easing
    easingType = easingType or STATE.anchor.easing
    easingType = string.lower(easingType)

    local easingFunc = EasingFunctions[easingType]

    -- Fallback to default if not found
    if not easingFunc then
        Log:warn("Unknown easing type: " .. easingType .. ", falling back to none")
        easingFunc = EasingFunctions.none
    end

    return easingFunc
end

--- Focuses on a camera anchor with smooth transition
---@param index number Anchor index
---@param easingType string|nil Optional easing type
---@return boolean success Always returns true for widget handler
function CameraAnchor.focus(index, easingType)
    if Util.isTurboBarCamDisabled() then
        return true
    end

    index = tonumber(index)
    if not (index and index >= 0 and STATE.anchor.points[index]) then
        return true
    end

    -- Store the anchor we're moving to
    STATE.lastUsedAnchor = index

    if STATE.mode.name then
        ModeManager.disableMode()
    end

    -- Cancel transition if we click the same anchor we're currently moving to
    if STATE.transition.active and STATE.transition.currentAnchorIndex == index then
        STATE.transition.active = false
        STATE.transition.currentAnchorIndex = nil
        Log:trace("Transition canceled")
        return true
    end

    -- Cancel any in-progress transition when starting a new one
    if STATE.transition.active then
        STATE.transition.active = false
        Log:trace("Canceled previous transition")
    end

    -- Check if we should do an instant transition (duration = 0)
    if CONFIG.CAMERA_MODES.ANCHOR.DURATION <= 0 then
        -- Instant camera jump
        local targetState = Util.deepCopy(STATE.anchor.points[index])
        -- Ensure the target state is in FPS mode
        Spring.SetCameraState(targetState, 0)
        Log:trace("Instantly jumped to camera anchor: " .. index)
        return true
    end

    -- Get appropriate easing function
    local easingFunc = CameraAnchor.getEasingFunction(easingType)

    -- Start transition with selected easing
    CameraAnchorUtils.startTransitionToAnchor(
            STATE.anchor.points[index],
            CONFIG.CAMERA_MODES.ANCHOR.DURATION,
            easingFunc
    )

    STATE.transition.currentAnchorIndex = index
    Log:trace("Loading camera anchor: " .. index .. " with easing: " .. (easingType or STATE.anchor.easing))
    return true
end

--- Focuses on an anchor while tracking a unit
---@param index number Anchor index
---@param easingType string|nil Optional easing type
---@return boolean success Always returns true for widget handler
function CameraAnchor.focusAndTrack(index, easingType)
    if Util.isTurboBarCamDisabled() then
        return true
    end

    index = tonumber(index)
    if not (index and index >= 0 and STATE.anchor.points[index]) then
        Log:debug("Invalid or unset camera anchor: " .. (index or "nil"))
        return true
    end

    -- Store the anchor we're moving to
    STATE.lastUsedAnchor = index

    -- Check if current mode is compatible with tracking during anchor focus
    local isCompatibleMode = false
    for _, mode in ipairs(CONFIG.CAMERA_MODES.ANCHOR.COMPATIBLE_MODES) do
        if STATE.mode.name == mode then
            isCompatibleMode = true
            break
        end
    end

    -- If not in a compatible tracking mode or no unit is being tracked, do normal focus
    if not isCompatibleMode or not STATE.mode.unitID then
        Log:trace("No unit was tracked during focused anchor transition")
        -- Just do a normal anchor transition
        return CameraAnchor.focus(index, easingType)
    end

    local unitID = STATE.mode.unitID
    if not Spring.ValidUnitID(unitID) then
        Log:trace("Invalid unit for tracking during anchor transition")
        -- Just do a normal anchor transition
        return CameraAnchor.focus(index, easingType)
    end

    -- Cancel any in-progress transitions
    if STATE.transition.active then
        STATE.transition.active = false
        Log:trace("Canceled previous transition")
    end

    -- Disable any existing tracking modes to avoid conflicts
    if STATE.mode.name then
        ModeManager.disableMode()
    end

    -- Get appropriate easing function
    local easingFunc = CameraAnchor.getEasingFunction(easingType)

    -- Create a specialized transition that maintains focus on the unit
    local startState = Spring.GetCameraState()

    -- Enable tracking camera on the unit
    STATE.mode.name = 'unit_tracking'
    STATE.mode.unitID = unitID
    STATE.mode.lastCamDir = { x = 0, y = 0, z = 0 }
    STATE.mode.lastRotation = { rx = 0, ry = 0, rz = 0 }

    local unitX, unitY, unitZ = Spring.GetUnitPosition(unitID)
    local targetPos = { x = unitX, y = unitY, z = unitZ }

    -- Set up the transition
    STATE.transition.steps = CameraAnchorUtils.createPositionTransition(
            startState,
            STATE.anchor.points[index],
            CONFIG.CAMERA_MODES.ANCHOR.DURATION,
            targetPos,
            easingFunc
    )

    STATE.transition.currentStepIndex = 1
    STATE.transition.startTime = Spring.GetTimer()
    STATE.transition.active = true
    STATE.transition.currentAnchorIndex = index

    Log:trace("Moving to anchor " .. index .. " while tracking unit " .. unitID)
    return true
end

function CameraAnchor.update()
    if not STATE.transition.active then
        return
    end

    local now = Spring.GetTimer()

    -- Calculate current progress
    local elapsed = Spring.DiffTimers(now, STATE.transition.startTime)
    local targetProgress = math.min(elapsed / CONFIG.CAMERA_MODES.ANCHOR.DURATION, 1.0)

    -- Determine which step to use based on progress
    local totalSteps = #STATE.transition.steps
    local targetStep = math.max(1, math.min(totalSteps, math.ceil(targetProgress * totalSteps)))

    -- Only update if we need to move to a new step
    if targetStep > STATE.transition.currentStepIndex then
        STATE.transition.currentStepIndex = targetStep

        -- Apply the camera state for this step
        local camState = STATE.transition.steps[STATE.transition.currentStepIndex]

        -- Apply the base camera state (position)
        Spring.SetCameraState(camState, 0)

        -- Check if we've reached the end
        if STATE.transition.currentStepIndex >= totalSteps then
            STATE.transition.active = false
            STATE.transition.currentAnchorIndex = nil
            Log:trace("transition complete")
        end
    end
end

--- Action handler for setting anchor easing type
---@param easing string Parameters from the action command
---@return boolean success Always returns true
function CameraAnchor.setEasing(easing)
    if Util.isTurboBarCamDisabled() then
        return true
    end

    -- Set current easing type based on parameter
    if easing and EasingFunctions[easing] then
        STATE.anchor.easing = easing
        Log:info("Set anchor easing type to: " .. tostring(easing))
    else
        STATE.anchor.easing = "none"
        Log:info("Invalid easing: " .. tostring(easing) .. ". Valid values: none, in, out, inout")
    end

    return true
end

function CameraAnchor.save(id)
    if Util.isTurboBarCamDisabled() then
        return false
    end
    return CameraAnchorPersistence.saveToFile(id, false)
end

function CameraAnchor.load(id)
    if Util.isTurboBarCamDisabled() then
        return false
    end
    return CameraAnchorPersistence.loadFromFile(id)
end

---@see ModifiableParams
---@see Util#adjustParams
function CameraAnchor.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end

    Util.adjustParams(params, 'ANCHOR', function()
        CONFIG.CAMERA_MODES.ANCHOR.DURATION = 2
    end)
end

return CameraAnchor