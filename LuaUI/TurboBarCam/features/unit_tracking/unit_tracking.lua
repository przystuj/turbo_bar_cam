---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type VelocityTracker
local VelocityTracker = VFS.Include("LuaUI/TurboBarCam/standalone/velocity_tracker.lua")
---@type TransitionUtil
local TransitionUtil = VFS.Include("LuaUI/TurboBarCam/standalone/transition_util.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type TransitionManager
local TransitionManager = VFS.Include("LuaUI/TurboBarCam/standalone/transition_manager.lua").TransitionManager

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons
local ModeManager = CommonModules.ModeManager

---@class UnitTrackingCamera
local UnitTrackingCamera = {}

local STANDARD_DECEL_TRANSITION_ID = "UnitTrackingCamera.StandardDecelTransition"
local TARGETED_LERP_TRANSITION_ID = "UnitTrackingCamera.TargetedLerpTransition"
local INITIAL_ROT_SMOOTH_FACTOR_DURING_TRANSITION = 0.001

---@param unitID number
---@param initialCamStateAtModeEntry table Captured camera state from ModeManager at mode entry.
local function startModeTransition(unitID, initialCamStateAtModeEntry)
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.warn("UnitTrackingCamera: Invalid unitID for startModeTransition (decel).")
        if STATE.mode.unit_tracking then
            STATE.mode.unit_tracking.isModeInitialized = true
        end
        return
    end

    local currentActualVelocity, _, currentActualRotVelocity, _ = VelocityTracker.getCurrentVelocity()
    local profile = CONFIG.CAMERA_MODES.UNIT_TRACKING.DECELERATION_PROFILE
    local _, gameSpeed = Spring.GetGameSpeed()
    local duration = profile.DURATION
    if gameSpeed > 0 then
        duration = profile.DURATION / math.max(0.1, gameSpeed)
    end

    TransitionManager.force({
        id = STANDARD_DECEL_TRANSITION_ID,
        duration = duration,
        easingFn = CameraCommons.easeOut,
        respectGameSpeed = true, -- Assuming deceleration should respect game speed
        onUpdate = function(progress, easedProgress, effectiveDt)
            local currentUpdateState = Spring.GetCameraState()
            if not Spring.ValidUnitID(unitID) then
                TransitionManager.cancel(STANDARD_DECEL_TRANSITION_ID)
                ModeManager.disableMode()
                return
            end
            local uX, uY, uZ = Spring.GetUnitPosition(unitID)
            if not uX then
                TransitionManager.cancel(STANDARD_DECEL_TRANSITION_ID)
                ModeManager.disableMode()
                return
            end
            local targetLookPos = { x = uX, y = uY + CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT, z = uZ }
            local deceleratedState = TransitionUtil.smoothDecelerationTransition(currentUpdateState, effectiveDt, easedProgress, currentActualVelocity, currentActualRotVelocity, profile)

            local camStatePatch = {}
            local posStateToUseForRotation = currentUpdateState -- Default to current if deceleratedState is nil
            if deceleratedState then
                camStatePatch.px, camStatePatch.py, camStatePatch.pz = deceleratedState.px, deceleratedState.py, deceleratedState.pz
                posStateToUseForRotation = deceleratedState
            else
                camStatePatch.px, camStatePatch.py, camStatePatch.pz = currentUpdateState.px, currentUpdateState.py, currentUpdateState.pz
            end

            local targetLookDir = CameraCommons.calculateCameraDirectionToThePoint(posStateToUseForRotation, targetLookPos)

            -- Gradual ramp-up for rotation factor
            local steadyStateRotFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.ROTATION_FACTOR
            local currentFrameRotFactor = CameraCommons.lerp(INITIAL_ROT_SMOOTH_FACTOR_DURING_TRANSITION, steadyStateRotFactor, easedProgress)

            camStatePatch.rx = CameraCommons.smoothStepAngle(posStateToUseForRotation.rx, targetLookDir.rx, currentFrameRotFactor)
            camStatePatch.ry = CameraCommons.smoothStepAngle(posStateToUseForRotation.ry, targetLookDir.ry, currentFrameRotFactor)

            camStatePatch.fov = currentUpdateState.fov
            local finalDir = CameraCommons.getDirectionFromRotation(camStatePatch.rx, camStatePatch.ry, 0)
            camStatePatch.dx, camStatePatch.dy, camStatePatch.dz = finalDir.x, finalDir.y, finalDir.z
            camStatePatch.rz = 0
            ModeManager.updateTrackingState(camStatePatch)
            Spring.SetCameraState(camStatePatch, 0)
        end,
        onComplete = function()
            Log.trace("UnitTrackingCamera: Standard deceleration entry finished for unit " .. unitID)
        end
    })
end

--- Internal: Starts a transition to a specific target camera state (LERP position/FOV, focus unit).
---@param unitID number
---@param initialCamStateAtModeEntry table Captured camera state from ModeManager at mode entry.
---@param targetCamState table The target camera state (px,py,pz,fov) from ModeManager.
local function startTargetedEntryTransition(unitID, initialCamStateAtModeEntry, targetCamState)
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.warn("UnitTrackingCamera: Invalid unitID for startTargetedEntryTransition.")
        STATE.mode.unit_tracking.isModeInitialized = true
        return
    end
    -- No need for: if TransitionManager.isTransitioning(TARGETED_LERP_TRANSITION_ID) then return end
    if not initialCamStateAtModeEntry then
        Log.warn("UnitTrackingCamera: initialCamStateAtModeEntry missing for startTargetedEntryTransition.")
        STATE.mode.unit_tracking.isModeInitialized = true
        return
    end
    if not targetCamState then
        Log.warn("UnitTrackingCamera: targetCamState missing for startTargetedEntryTransition.")
        STATE.mode.unit_tracking.isModeInitialized = true
        return
    end

    Log.trace("UnitTrackingCamera: Starting targeted LERP entry for unit " .. unitID)
    local duration = CONFIG.TRANSITION.MODE_TRANSITION_DURATION

    TransitionManager.force({
        id = TARGETED_LERP_TRANSITION_ID,
        duration = duration,
        easingFn = CameraCommons.easeInOut,
        respectGameSpeed = false,
        onUpdate = function(progress, easedProgress, effectiveDt)
            local currentUpdateState = Spring.GetCameraState()
            if not Spring.ValidUnitID(unitID) then
                TransitionManager.cancel(TARGETED_LERP_TRANSITION_ID)
                ModeManager.disableMode()
                return
            end
            local uX, uY, uZ = Spring.GetUnitPosition(unitID)
            if not uX then
                TransitionManager.cancel(TARGETED_LERP_TRANSITION_ID)
                ModeManager.disableMode()
                return
            end
            local targetLookPos = { x = uX, y = uY + CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT, z = uZ }

            local camStatePatch = {}
            camStatePatch.px = CameraCommons.lerp(initialCamStateAtModeEntry.px, targetCamState.px, easedProgress)
            camStatePatch.py = CameraCommons.lerp(initialCamStateAtModeEntry.py, targetCamState.py, easedProgress)
            camStatePatch.pz = CameraCommons.lerp(initialCamStateAtModeEntry.pz, targetCamState.pz, easedProgress)
            camStatePatch.fov = CameraCommons.lerp(initialCamStateAtModeEntry.fov or 45, targetCamState.fov or 45, easedProgress)

            local currentLerpedPos = { x = camStatePatch.px, y = camStatePatch.py, z = camStatePatch.pz }
            local targetLookDir = CameraCommons.calculateCameraDirectionToThePoint(currentLerpedPos, targetLookPos)

            -- Gradual ramp-up for rotation factor
            local steadyStateRotFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.ROTATION_FACTOR
            local currentFrameRotFactor = CameraCommons.lerp(INITIAL_ROT_SMOOTH_FACTOR_DURING_TRANSITION, steadyStateRotFactor, easedProgress)

            camStatePatch.rx = CameraCommons.smoothStepAngle(currentUpdateState.rx, targetLookDir.rx, currentFrameRotFactor)
            camStatePatch.ry = CameraCommons.smoothStepAngle(currentUpdateState.ry, targetLookDir.ry, currentFrameRotFactor)

            local finalDir = CameraCommons.getDirectionFromRotation(camStatePatch.rx, camStatePatch.ry, 0)
            camStatePatch.dx, camStatePatch.dy, camStatePatch.dz = finalDir.x, finalDir.y, finalDir.z
            camStatePatch.rz = 0
            ModeManager.updateTrackingState(camStatePatch)
            Spring.SetCameraState(camStatePatch, 0)
        end,
        onComplete = function()
            Log.trace("UnitTrackingCamera: Targeted LERP entry finished for unit " .. unitID)
        end
    })
end

function UnitTrackingCamera.toggle()
    if Util.isTurboBarCamDisabled() then
        return
    end
    local selectedUnits = Spring.GetSelectedUnits()

    if #selectedUnits == 0 then
        if STATE.mode.name == 'unit_tracking' then
            ModeManager.disableMode()
            Log.trace("UnitTrackingCamera: Disabled (no units selected).")
        else
            Log.trace("UnitTrackingCamera: No unit selected.")
        end
        return
    end
    local selectedUnitID = selectedUnits[1]

    if STATE.mode.name == 'unit_tracking' and
            STATE.mode.unitID == selectedUnitID and
            not STATE.mode.optionalTargetCameraStateForModeEntry then
        ModeManager.disableMode()
        Log.trace("UnitTrackingCamera: Disabled for unit " .. selectedUnitID)
        return
    end

    if ModeManager.initializeMode('unit_tracking', selectedUnitID, STATE.TARGET_TYPES.UNIT, false, nil) then
        Log.trace("UnitTrackingCamera: Enabled for unit " .. selectedUnitID)
    else
        Log.warn("UnitTrackingCamera: Failed to initializeMode for unit_tracking.")
    end
end

function UnitTrackingCamera.update(dt)
    if STATE.mode.name ~= 'unit_tracking' then
        STATE.mode.unit_tracking.isModeInitialized = false
        return
    end

    local unitID = STATE.mode.unitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.trace("UnitTrackingCamera: Tracked unit " .. tostring(unitID) .. " no longer exists, disabling.")
        if STATE.mode.name == 'unit_tracking' then
            ModeManager.disableMode()
        end
        return
    end

    if STATE.mode.unit_tracking and not STATE.mode.unit_tracking.isModeInitialized then
        STATE.mode.unit_tracking.isModeInitialized = true

        local initialCamState = STATE.mode.initialCameraStateForModeEntry
        local optionalTargetCamState = STATE.mode.optionalTargetCameraStateForModeEntry

        if not initialCamState then
            Log.warn("UnitTrackingCamera: initialCameraStateForModeEntry is nil. Cannot start entry transition properly.")
            -- Allow steady state to take over, or consider disabling
        else
            if optionalTargetCamState then
                startTargetedEntryTransition(unitID, initialCamState, optionalTargetCamState)
            else
                startModeTransition(unitID, initialCamState) -- This is the renamed standard decel starter
            end
        end
    end

    if TransitionManager.isTransitioning(STANDARD_DECEL_TRANSITION_ID) or
            TransitionManager.isTransitioning(TARGETED_LERP_TRANSITION_ID) then
        return
    end

    local currentState = Spring.GetCameraState()
    local uX, uY, uZ = Spring.GetUnitPosition(unitID)
    if not uX then
        Log.trace("UnitTrackingCamera: Could not get position for unit " .. unitID .. " in steady state. Disabling.")
        ModeManager.disableMode()
        return
    end
    local targetFocusPos = { x = uX, y = uY + CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT, z = uZ }

    local dirFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.TRACKING_FACTOR
    local rotFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.ROTATION_FACTOR

    local idealState = CameraCommons.focusOnPoint(currentState, targetFocusPos, dirFactor, rotFactor)
    local camStatePatch = {
        px = currentState.px, py = currentState.py, pz = currentState.pz,
        rx = idealState.rx, ry = idealState.ry, rz = 0,
        dx = idealState.dx, dy = idealState.dy, dz = idealState.dz,
        fov = currentState.fov
    }
    ModeManager.updateTrackingState(camStatePatch)
    Spring.SetCameraState(camStatePatch, 0)
end

function UnitTrackingCamera.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if STATE.mode.name ~= 'unit_tracking' then
        return
    end
    if not STATE.mode.unitID then
        Log.trace("UnitTrackingCamera: No unit is tracked for adjustParams.")
        return
    end
    Util.adjustParams(params, "UNIT_TRACKING", function()
        CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT = 0
    end)
end

return {
    UnitTrackingCamera = UnitTrackingCamera
}