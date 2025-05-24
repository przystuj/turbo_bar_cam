---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua")
---@type TransitionUtil
local TransitionUtil = VFS.Include("LuaUI/TurboBarCam/standalone/transition_util.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons
local TrackingManager = CommonModules.TrackingManager

---@class UnitTrackingCamera
local UnitTrackingCamera = {}

function UnitTrackingCamera.toggle()
    if Util.isTurboBarCamDisabled() then
        return
    end

    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits == 0 then
        if STATE.tracking.mode == 'unit_tracking' then
            TrackingManager.disableTracking()
            Log.trace("Tracking Camera disabled")
        else
            Log.trace("No unit selected for Tracking Camera")
        end
        return
    end

    local selectedUnitID = selectedUnits[1]

    if STATE.tracking.mode == 'unit_tracking' and STATE.tracking.unitID == selectedUnitID then
        TrackingManager.disableTracking()
        Log.trace("Tracking Camera disabled")
        return
    end

    if TrackingManager.initializeTracking('unit_tracking', selectedUnitID) then
        Log.trace("Tracking Camera enabled. Camera will track unit " .. selectedUnitID)
    end
end

function UnitTrackingCamera.update(dt)
    if STATE.tracking.mode ~= 'unit_tracking' or not STATE.tracking.unitID then
        return
    end

    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Log.trace("Tracked unit no longer exists, disabling Tracking Camera")
        TrackingManager.disableTracking()
        return
    end

    local currentState = CameraManager.getCameraState("UnitTrackingCamera.update")
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)
    local targetPos = {
        x = unitX,
        y = unitY + CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT,
        z = unitZ
    }
    local camPos = { x = currentState.px, y = currentState.py, z = currentState.pz }

    -- Get base smoothing factors for direction/rotation
    local baseDirFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.TRACKING_FACTOR
    local baseRotFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.ROTATION_FACTOR

    -- Handle mode transition for direction/rotation smoothing and manage isModeTransitionInProgress flag
    local dirFactor, rotFactor = CameraCommons.handleModeTransition(baseDirFactor, baseRotFactor)

    -- Initialize last values if needed (for direction/rotation smoothing)
    if STATE.tracking.lastCamDir.x == 0 and STATE.tracking.lastCamDir.y == 0 and STATE.tracking.lastCamDir.z == 0 then
        local initialLookDir = CameraCommons.calculateCameraDirectionToThePoint(camPos, targetPos)
        STATE.tracking.lastCamDir = { x = initialLookDir.dx, y = initialLookDir.dy, z = initialLookDir.dz }
        STATE.tracking.lastRotation = { rx = initialLookDir.rx, ry = initialLookDir.ry, rz = 0 }
    end

    -- Use focusOnPoint for camera direction and rotation state
    local camStatePatch = CameraCommons.focusOnPoint(camPos, targetPos, dirFactor, rotFactor)

    -- Handle position control based on transition state using the new generic deceleration
    if STATE.tracking.isModeTransitionInProgress then
        -- This flag is managed by handleModeTransition
        local transitionProgress = CameraCommons.getTransitionProgress() -- Progress over MODE_TRANSITION_DURATION
        local currentVelocity, _ = CameraManager.getCurrentVelocity() -- Get live camera velocity
        local profile = CONFIG.DECELERATION_PROFILES.UNIT_TRACKING_ENTER

        local newPos = TransitionUtil.smoothDecelerationTransition(camPos, dt, transitionProgress, currentVelocity, profile)

        if newPos then
            camStatePatch.px = newPos.px
            camStatePatch.py = newPos.py
            camStatePatch.pz = newPos.pz
        else
            -- Velocity is low or transition is nearing end.
            -- Gently bring to a stop or allow free movement if transition is almost over.
            if transitionProgress < 0.95 then
                -- Still actively transitioning
                local gentleStopFactor = CameraCommons.lerp(profile.POS_CONTROL_FACTOR_MIN or 0.02, 0.0, transitionProgress)
                if gentleStopFactor > 0.001 then
                    camStatePatch.px = CameraCommons.smoothStep(camPos.x, camPos.x, gentleStopFactor)
                    camStatePatch.py = CameraCommons.smoothStep(camPos.y, camPos.y, gentleStopFactor)
                    camStatePatch.pz = CameraCommons.smoothStep(camPos.z, camPos.z, gentleStopFactor)
                else
                    -- Position control has faded out, allow free movement by not setting px,py,pz
                    camStatePatch.px, camStatePatch.py, camStatePatch.pz = nil, nil, nil
                end
            else
                -- Transition virtually complete, ensure no positional override
                camStatePatch.px, camStatePatch.py, camStatePatch.pz = nil, nil, nil
            end
        end
    else
        -- After transition is complete, remove position updates to allow free camera movement
        camStatePatch.px, camStatePatch.py, camStatePatch.pz = nil, nil, nil
    end

    TrackingManager.updateTrackingState(camStatePatch)
    CameraManager.setCameraState(camStatePatch, 0, "UnitTrackingCamera.update")
end

function UnitTrackingCamera.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("unit_tracking") then
        return
    end
    if not STATE.tracking.unitID then
        Log.trace("No unit is tracked")
        return
    end

    Util.adjustParams(params, "UNIT_TRACKING", function()
        CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT = 0
    end)
end

return {
    UnitTrackingCamera = UnitTrackingCamera
}
