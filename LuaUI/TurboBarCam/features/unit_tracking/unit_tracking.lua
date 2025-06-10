---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local VelocityTracker = ModuleManager.VelocityTracker(function(m) VelocityTracker = m end)
local TransitionUtil = ModuleManager.TransitionUtil(function(m) TransitionUtil = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "UnitTrackingCamera")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local TransitionManager = ModuleManager.TransitionManager(function(m) TransitionManager = m end)
local CameraTracker = ModuleManager.CameraTracker(function(m) CameraTracker = m end)
local ParamUtils = ModuleManager.ParamUtils(function(m) ParamUtils = m end)

---@class UnitTrackingCamera
local UnitTrackingCamera = {}

local ENTRY_TRANSITION_ID = "UnitTrackingCamera.ENTRY_TRANSITION_ID"

---
--- Helper function to apply common camera rotation logic.
--- Updates rx, ry, dx, dy, dz, rz in camStatePatch.
---
---@param camStatePatch table The camera state patch to populate.
---@param posForRotation {x: number, y: number, z: number} The camera's current position coordinates for calculating look direction.
---@param targetLookPos {x: number, y: number, z: number} The world coordinates the camera should be looking at.
---@param currentActualRx number The camera's current actual rotation X (e.g., from Spring.GetCameraState().rx).
---@param currentActualRy number The camera's current actual rotation Y (e.g., from Spring.GetCameraState().ry).
---@param easedProgressForRotFactor number The eased progress (0-1) of the transition, used for LERPing rotation factor.
local function applySharedCameraRotationLogic(camStatePatch, posForRotation, targetLookPos, currentActualRx, currentActualRy, easedProgressForRotFactor)
    local targetLookDir = CameraCommons.calculateCameraDirectionToThePoint(posForRotation, targetLookPos)

    local steadyStateRotFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.ROTATION_FACTOR
    local currentFrameRotFactor = CameraCommons.lerp(CONFIG.CAMERA_MODES.UNIT_TRACKING.INITIAL_TRANSITION_FACTOR, steadyStateRotFactor, easedProgressForRotFactor)

    camStatePatch.rx = CameraCommons.lerpAngle(currentActualRx, targetLookDir.rx, currentFrameRotFactor)
    camStatePatch.ry = CameraCommons.lerpAngle(currentActualRy, targetLookDir.ry, currentFrameRotFactor)

    local finalDir = CameraCommons.getDirectionFromRotation(camStatePatch.rx, camStatePatch.ry, 0)
    camStatePatch.dx, camStatePatch.dy, camStatePatch.dz = finalDir.x, finalDir.y, finalDir.z
    camStatePatch.rz = 0 -- Explicitly set roll to 0
end

---
--- Unified function to start a camera transition for unit tracking.
--- Behaves as a deceleration transition if targetCamState is nil.
--- Behaves as a targeted LERP transition if targetCamState is provided.
---
---@param unitID number The ID of the unit to track.
---@param initialCamStateAtModeEntry table? Captured camera state from ModeManager at mode entry. Required if targetCamState is provided. Ignored otherwise.
---@param targetCamState table? The target camera state (px,py,pz,fov) for a targeted transition.If nil, a standard deceleration transition is performed.
local function startUnitTrackingTransition(unitID, initialCamStateAtModeEntry, targetCamState)
    STATE.active.mode.unit_tracking.isModeInitialized = true

    -- Initial validation for unitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        local context = targetCamState and "targeted" or "deceleration"
        Log:warn("UnitTrackingCamera: Invalid unitID for startUnitTrackingTransition (" .. context .. ").")
        return
    end

    local isTargetedTransition = targetCamState ~= nil

    -- Validation specific to targeted transition
    if isTargetedTransition then
        if not initialCamStateAtModeEntry then
            Log:warn("UnitTrackingCamera: initialCamStateAtModeEntry missing for targeted transition. Aborting.")
            return
        end
        -- targetCamState is already confirmed not nil by isTargetedTransition check
    end

    -- Transition-specific parameters
    local duration
    if isTargetedTransition then
        duration = CONFIG.CAMERA_MODES.UNIT_TRACKING.INITIAL_TRANSITION_DURATION
    else
        duration = CONFIG.CAMERA_MODES.UNIT_TRACKING.DECELERATION_PROFILE.DURATION
    end

    local currentActualVelocity, _, currentActualRotVelocity, _ = VelocityTracker.getCurrentVelocity()

    TransitionManager.force({
        id = ENTRY_TRANSITION_ID,
        duration = duration,
        easingFn = CameraCommons.easeOut,
        respectGameSpeed = false,
        onUpdate = function(progress, easedProgress, effectiveDt)
            local currentSpringCamState = Spring.GetCameraState()

            if not Spring.ValidUnitID(unitID) then
                TransitionManager.cancel(ENTRY_TRANSITION_ID)
                ModeManager.disableMode()
                return
            end
            local uX, uY, uZ = Spring.GetUnitPosition(unitID)
            if not uX then
                -- Unit likely died or was removed
                TransitionManager.cancel(ENTRY_TRANSITION_ID)
                ModeManager.disableMode()
                return
            end

            local targetLookPos = { x = uX, y = uY + CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT, z = uZ }
            local camStatePatch = {}
            local posStateForRotation

            if isTargetedTransition then
                local factor = CameraCommons.lerp(CONFIG.CAMERA_MODES.UNIT_TRACKING.INITIAL_TRANSITION_FACTOR, CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.POSITION_FACTOR, CameraCommons.easeInOut(progress))
                posStateForRotation = CameraCommons.interpolateToPoint(targetCamState, factor)
                camStatePatch.px = posStateForRotation.x
                camStatePatch.py = posStateForRotation.y
                camStatePatch.pz = posStateForRotation.z
            else
                -- Deceleration transition
                local deceleratedPosState = TransitionUtil.smoothDecelerationTransition(currentSpringCamState, effectiveDt, easedProgress,
                        currentActualVelocity, currentActualRotVelocity, CONFIG.CAMERA_MODES.UNIT_TRACKING.DECELERATION_PROFILE)

                if deceleratedPosState then
                    camStatePatch.px, camStatePatch.py, camStatePatch.pz = deceleratedPosState.px, deceleratedPosState.py, deceleratedPosState.pz
                    posStateForRotation = { x = deceleratedPosState.px, y = deceleratedPosState.py, z = deceleratedPosState.pz }
                else
                    -- Fallback to current Spring camera state position if deceleration logic returns nil
                    camStatePatch.px, camStatePatch.py, camStatePatch.pz = currentSpringCamState.px, currentSpringCamState.py, currentSpringCamState.pz
                    posStateForRotation = { x = currentSpringCamState.px, y = currentSpringCamState.py, z = currentSpringCamState.pz }
                end
            end

            -- Apply common rotation logic using the determined position and current actual rotations
            applySharedCameraRotationLogic(camStatePatch, posStateForRotation, targetLookPos, currentSpringCamState.rx, currentSpringCamState.ry, easedProgress)

            -- Update systems
            CameraTracker.updateLastKnownCameraState(camStatePatch)
            Spring.SetCameraState(camStatePatch, 0)
        end
    })
end

function UnitTrackingCamera.toggle()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    local selectedUnits = Spring.GetSelectedUnits()

    if #selectedUnits == 0 then
        if STATE.active.mode.name == 'unit_tracking' then
            ModeManager.disableMode()
            Log:trace("UnitTrackingCamera: Disabled (no units selected).")
        else
            Log:trace("UnitTrackingCamera: No unit selected.")
        end
        return
    end
    local selectedUnitID = selectedUnits[1]

    if STATE.active.mode.name == 'unit_tracking' and
            STATE.active.mode.unitID == selectedUnitID and
            not STATE.active.mode.optionalTargetCameraStateForModeEntry then
        ModeManager.disableMode()
        Log:trace("UnitTrackingCamera: Disabled for unit " .. selectedUnitID)
        return
    end

    if ModeManager.initializeMode('unit_tracking', selectedUnitID, STATE.TARGET_TYPES.UNIT, false, nil) then
        Log:trace("UnitTrackingCamera: Enabled for unit " .. selectedUnitID)
    else
        Log:warn("UnitTrackingCamera: Failed to initializeMode for unit_tracking.")
    end
end

function UnitTrackingCamera.update(dt)
    if STATE.active.mode.name ~= 'unit_tracking' then
        STATE.active.mode.unit_tracking.isModeInitialized = false
        return
    end

    local unitID = STATE.active.mode.unitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log:trace("UnitTrackingCamera: Tracked unit " .. tostring(unitID) .. " no longer exists, disabling.")
        if STATE.active.mode.name == 'unit_tracking' then
            ModeManager.disableMode()
        end
        return
    end

    if STATE.active.mode.unit_tracking and not STATE.active.mode.unit_tracking.isModeInitialized then
        STATE.active.mode.unit_tracking.isModeInitialized = true

        local initialCamState = STATE.active.mode.initialCameraStateForModeEntry
        local optionalTargetCamState = STATE.active.mode.optionalTargetCameraStateForModeEntry

        if not initialCamState then
            Log:warn("UnitTrackingCamera: initialCameraStateForModeEntry is nil. Cannot start entry transition properly.")
            -- Allow steady state to take over, or consider disabling
        else
            startUnitTrackingTransition(unitID, initialCamState, optionalTargetCamState)
        end
    end

    if TransitionManager.isTransitioning(ENTRY_TRANSITION_ID) then
        return
    end

    local currentState = Spring.GetCameraState()
    local uX, uY, uZ = Spring.GetUnitPosition(unitID)
    if not uX then
        Log:trace("UnitTrackingCamera: Could not get position for unit " .. unitID .. " in steady state. Disabling.")
        ModeManager.disableMode()
        return
    end
    local targetFocusPos = { x = uX, y = uY + CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT, z = uZ }

    local posFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.POSITION_FACTOR
    local rotFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.ROTATION_FACTOR

    local idealState = CameraCommons.focusOnPoint(currentState, targetFocusPos, posFactor, rotFactor)
    local camStatePatch = {
        px = currentState.px, py = currentState.py, pz = currentState.pz,
        rx = idealState.rx, ry = idealState.ry, rz = 0,
        dx = idealState.dx, dy = idealState.dy, dz = idealState.dz,
        fov = currentState.fov
    }
    CameraTracker.updateLastKnownCameraState(camStatePatch)
    Spring.SetCameraState(camStatePatch, 0)
end

function UnitTrackingCamera.adjustParams(params)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if STATE.active.mode.name ~= 'unit_tracking' then
        return
    end
    if not STATE.active.mode.unitID then
        Log:trace("UnitTrackingCamera: No unit is tracked for adjustParams.")
        return
    end
    ParamUtils.adjustParams(params, "UNIT_TRACKING", function()
        CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT = 0
    end)
end

return UnitTrackingCamera