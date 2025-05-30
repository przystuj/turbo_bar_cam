---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua")
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
local ROT_SMOOTH_FACTOR_DURING_TRANSITION = 0.08

--- Internal: Starts the standard deceleration entry transition.
---@param unitID number
---@param initialCamState table Captured camera state from ModeManager at mode entry.
local function startStandardDecelTransition(unitID, initialCamState)
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.warn("UnitTrackingCamera: Invalid unitID for startStandardDecelTransition.")
        return
    end
    if TransitionManager.isTransitioning(STANDARD_DECEL_TRANSITION_ID) then return end

    Log.trace("UnitTrackingCamera: Starting standard deceleration entry for unit " .. unitID)
    local currentActualVelocity, _, currentActualRotVelocity, _ = CameraManager.getCurrentVelocity()
    local profile = CONFIG.CAMERA_MODES.UNIT_TRACKING.DECELERATION_PROFILE
    local _, gameSpeed = Spring.GetGameSpeed()
    local duration = profile.DURATION
    if gameSpeed > 0 then duration = profile.DURATION / math.max(0.1, gameSpeed) end

    TransitionManager.force({
        id = STANDARD_DECEL_TRANSITION_ID,
        duration = duration,
        easingFn = CameraCommons.easeOut,
        onUpdate = function(progress, easedProgress, dt)
            local currentUpdateState = CameraManager.getCameraState("UnitTrackingCamera.DecelUpdate")
            local MM = ModeManager or WidgetContext.ModeManager -- How ModeManager is accessed
            if not Spring.ValidUnitID(unitID) then
                TransitionManager.cancel(STANDARD_DECEL_TRANSITION_ID)
                if MM and MM.disableMode then MM.disableMode() end; return
            end
            local uX, uY, uZ = Spring.GetUnitPosition(unitID)
            if not uX then
                TransitionManager.cancel(STANDARD_DECEL_TRANSITION_ID)
                if MM and MM.disableMode then MM.disableMode() end; return
            end
            local targetLookPos = { x = uX, y = uY + CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT, z = uZ }
            local deceleratedState = TransitionUtil.smoothDecelerationTransition(currentUpdateState, dt, easedProgress, currentActualVelocity, currentActualRotVelocity, profile)
            local camStatePatch = {}
            if deceleratedState then
                camStatePatch.px, camStatePatch.py, camStatePatch.pz = deceleratedState.px, deceleratedState.py, deceleratedState.pz
                local targetLookDir = CameraCommons.calculateCameraDirectionToThePoint(deceleratedState, targetLookPos)
                camStatePatch.rx = CameraCommons.smoothStepAngle(deceleratedState.rx, targetLookDir.rx, ROT_SMOOTH_FACTOR_DURING_TRANSITION)
                camStatePatch.ry = CameraCommons.smoothStepAngle(deceleratedState.ry, targetLookDir.ry, ROT_SMOOTH_FACTOR_DURING_TRANSITION)
            else
                camStatePatch.px, camStatePatch.py, camStatePatch.pz = currentUpdateState.px, currentUpdateState.py, currentUpdateState.pz
                local targetLookDir = CameraCommons.calculateCameraDirectionToThePoint(currentUpdateState, targetLookPos)
                camStatePatch.rx = CameraCommons.smoothStepAngle(currentUpdateState.rx, targetLookDir.rx, ROT_SMOOTH_FACTOR_DURING_TRANSITION)
                camStatePatch.ry = CameraCommons.smoothStepAngle(currentUpdateState.ry, targetLookDir.ry, ROT_SMOOTH_FACTOR_DURING_TRANSITION)
            end
            camStatePatch.fov = currentUpdateState.fov
            local finalDir = CameraCommons.getDirectionFromRotation(camStatePatch.rx, camStatePatch.ry, 0)
            camStatePatch.dx, camStatePatch.dy, camStatePatch.dz = finalDir.x, finalDir.y, finalDir.z
            camStatePatch.rz = 0
            if MM and MM.updateTrackingState then MM.updateTrackingState(camStatePatch) end
            CameraManager.setCameraState(camStatePatch, 0, "UnitTrackingCamera.DecelUpdate.Set")
        end,
        onComplete = function()
            Log.trace("UnitTrackingCamera: Standard deceleration entry finished for unit " .. unitID)
        end
    })
end

--- Internal: Starts a transition to a specific target camera state (LERP position/FOV, focus unit).
---@param unitID number
---@param initialCamState table Captured camera state from ModeManager at mode entry.
---@param targetCamState table The target camera state (px,py,pz,fov) from ModeManager.
local function startTargetedEntryTransition(unitID, initialCamState, targetCamState)
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.warn("UnitTrackingCamera: Invalid unitID for startTargetedEntryTransition.")
        return
    end
    if TransitionManager.isTransitioning(TARGETED_LERP_TRANSITION_ID) then return end

    Log.trace("UnitTrackingCamera: Starting targeted LERP entry for unit " .. unitID)
    local duration = CONFIG.TRANSITION.MODE_TRANSITION_DURATION -- Use general mode transition duration

    TransitionManager.force({
        id = TARGETED_LERP_TRANSITION_ID,
        duration = duration,
        easingFn = CameraCommons.easeInOut,
        onUpdate = function(progress, easedProgress, dt)
            local currentUpdateState = CameraManager.getCameraState("UnitTrackingCamera.LerpUpdate")
            local MM = ModeManager or WidgetContext.ModeManager
            if not Spring.ValidUnitID(unitID) then
                TransitionManager.cancel(TARGETED_LERP_TRANSITION_ID)
                if MM and MM.disableMode then MM.disableMode() end; return
            end
            local uX, uY, uZ = Spring.GetUnitPosition(unitID)
            if not uX then
                TransitionManager.cancel(TARGETED_LERP_TRANSITION_ID)
                if MM and MM.disableMode then MM.disableMode() end; return
            end
            local targetLookPos = { x = uX, y = uY + CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT, z = uZ }
            local camStatePatch = {}
            camStatePatch.px = CameraCommons.lerp(initialCamState.px, targetCamState.px, easedProgress)
            camStatePatch.py = CameraCommons.lerp(initialCamState.py, targetCamState.py, easedProgress)
            camStatePatch.pz = CameraCommons.lerp(initialCamState.pz, targetCamState.pz, easedProgress)
            camStatePatch.fov = CameraCommons.lerp(initialCamState.fov or 45, targetCamState.fov or 45, easedProgress)
            local currentLerpedPos = { x = camStatePatch.px, y = camStatePatch.py, z = camStatePatch.pz }
            local targetLookDir = CameraCommons.calculateCameraDirectionToThePoint(currentLerpedPos, targetLookPos)
            camStatePatch.rx = CameraCommons.smoothStepAngle(currentUpdateState.rx, targetLookDir.rx, ROT_SMOOTH_FACTOR_DURING_TRANSITION)
            camStatePatch.ry = CameraCommons.smoothStepAngle(currentUpdateState.ry, targetLookDir.ry, ROT_SMOOTH_FACTOR_DURING_TRANSITION)
            local finalDir = CameraCommons.getDirectionFromRotation(camStatePatch.rx, camStatePatch.ry, 0)
            camStatePatch.dx, camStatePatch.dy, camStatePatch.dz = finalDir.x, finalDir.y, finalDir.z
            camStatePatch.rz = 0
            if MM and MM.updateTrackingState then MM.updateTrackingState(camStatePatch) end
            CameraManager.setCameraState(camStatePatch, 0, "UnitTrackingCamera.LerpUpdate.Set")
        end,
        onComplete = function()
            Log.trace("UnitTrackingCamera: Targeted LERP entry finished for unit " .. unitID)
        end
    })
end

-- Renamed from startStandardEntryTransition_internal as per user request
-- This is the primary function a feature module would call to initiate its standard view settling.
UnitTrackingCamera.startModeTransition = startStandardDecelTransition -- Public alias if needed, or keep internal

function UnitTrackingCamera.toggle()
    if Util.isTurboBarCamDisabled() then return end
    local selectedUnits = Spring.GetSelectedUnits()
    local MM = ModeManager or WidgetContext.ModeManager

    if #selectedUnits == 0 then
        if STATE.mode.name == 'unit_tracking' then
            if MM and MM.disableMode then MM.disableMode() end
        end; return
    end
    local selectedUnitID = selectedUnits[1]

    if STATE.mode.name == 'unit_tracking' and
            STATE.mode.unitID == selectedUnitID and
            not STATE.mode.optionalTargetCameraStateForModeEntry then -- If not in a LERP to a specific state
        if MM and MM.disableMode then MM.disableMode() end
        return
    end

    if MM and MM.initializeMode then
        MM.initializeMode('unit_tracking', selectedUnitID, STATE.TARGET_TYPES.UNIT)
    end
end

function UnitTrackingCamera.update(dt)
    local MM = ModeManager or WidgetContext.ModeManager

    if STATE.mode.name ~= 'unit_tracking' then
        if STATE.mode.unit_tracking then STATE.mode.unit_tracking.isModeInitialized = false end
        return
    end

    local unitID = STATE.mode.unitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        if STATE.mode.name == 'unit_tracking' and MM and MM.disableMode then MM.disableMode() end
        return
    end

    -- Initialize mode if not already done for this activation
    if STATE.mode.unit_tracking and not STATE.mode.unit_tracking.isModeInitialized then
        STATE.mode.unit_tracking.isModeInitialized = true -- Set true once we process this block
        local initialCamState = STATE.mode.initialCameraStateForModeEntry
        local optionalTargetCamState = STATE.mode.optionalTargetCameraStateForModeEntry
        if optionalTargetCamState then
            startTargetedEntryTransition(unitID, initialCamState, optionalTargetCamState)
        else
            -- User requested this to be called startModeTransition.
            -- This refers to the local function startStandardDecelTransition
            startStandardDecelTransition(unitID, initialCamState)
        end
    end

    -- If any of our specific transitions are running, they handle the camera
    if TransitionManager.isTransitioning(STANDARD_DECEL_TRANSITION_ID) or
            TransitionManager.isTransitioning(TARGETED_LERP_TRANSITION_ID) then
        return
    end

    -- Steady-state: Hold current camera position and focus on the unit
    local currentState = CameraManager.getCameraState("UnitTrackingCamera.SteadyState")
    local uX, uY, uZ = Spring.GetUnitPosition(unitID)
    if not uX then
        if MM and MM.disableMode then MM.disableMode() end; return
    end
    local targetFocusPos = { x = uX, y = uY + CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT, z = uZ }

    -- Use non-transitioned smoothing factors for steady state
    local dirFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.TRACKING_FACTOR
    local rotFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.ROTATION_FACTOR

    local idealState = CameraCommons.focusOnPoint(currentState, targetFocusPos, dirFactor, rotFactor)
    local camStatePatch = {
        px = currentState.px, py = currentState.py, pz = currentState.pz, -- Hold position
        rx = idealState.rx, ry = idealState.ry, rz = 0,
        dx = idealState.dx, dy = idealState.dy, dz = idealState.dz,
        fov = currentState.fov
    }
    if MM and MM.updateTrackingState then MM.updateTrackingState(camStatePatch) end
    CameraManager.setCameraState(camStatePatch, 0, "UnitTrackingCamera.SteadyState.Set")
end

function UnitTrackingCamera.adjustParams(params)
    if Util.isTurboBarCamDisabled() then return end
    if STATE.mode.name ~= 'unit_tracking' then return end
    if not STATE.mode.unitID then return end
    Util.adjustParams(params, "UNIT_TRACKING", function()
        CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT = 0
    end)
end

return {
    UnitTrackingCamera = UnitTrackingCamera,
}