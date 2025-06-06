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
local TransitionManager = ModuleManager.TransitionManager(function(m) TransitionManager = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)

---@class CameraAnchor
local CameraAnchor = {}

local ANCHOR_TRANSITION_BLENDING_ID = "CameraAnchor.ANCHOR_TRANSITION_BLENDING_ID"

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

    -- Blend into new transition
    if STATE.transition.active and STATE.transition.currentAnchorIndex ~= index then
        STATE.transition.active = false
        TransitionManager.force({
            id = ANCHOR_TRANSITION_BLENDING_ID,
            duration = CONFIG.CAMERA_MODES.ANCHOR.ANCHOR_TRANSITION_BLENDING_DURATION,
            easingFn = CameraCommons.easeInOut,
            onUpdate = function(raw_progress, eased_progress, dt)

            end,
            onComplete = function()
            end
        })
    end

    -- Check if we should do an instant transition (duration = 0 or used the same index)
    if CONFIG.CAMERA_MODES.ANCHOR.DURATION <= 0 or STATE.transition.currentAnchorIndex == index then
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