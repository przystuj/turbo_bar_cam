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
            TrackingManager.disableMode()
            Log.trace("Tracking Camera disabled")
        else
            Log.trace("No unit selected for Tracking Camera")
        end
        return
    end

    local selectedUnitID = selectedUnits[1]

    -- If already tracking this unit AND not currently transitioning to a target, disable.
    if STATE.tracking.mode == 'unit_tracking' and STATE.tracking.unitID == selectedUnitID and not STATE.tracking.transitionTarget then
        TrackingManager.disableMode()
        Log.trace("Tracking Camera disabled")
        return
    end

    if TrackingManager.initializeMode('unit_tracking', selectedUnitID) then
        Log.trace("Tracking Camera enabled. Camera will track unit " .. selectedUnitID)
    end
end

function UnitTrackingCamera.update(dt)
    if STATE.tracking.mode ~= 'unit_tracking' or not STATE.tracking.unitID then
        return
    end

    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Log.trace("Tracked unit no longer exists, disabling Tracking Camera")
        TrackingManager.disableMode()
        return
    end

    local currentState = CameraManager.getCameraState("UnitTrackingCamera.update")
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)
    local targetPos = {
        x = unitX,
        y = unitY + CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT,
        z = unitZ
    }

    local baseDirFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.TRACKING_FACTOR
    local baseRotFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.ROTATION_FACTOR
    local dirFactor, rotFactor = CameraCommons.handleModeTransition(baseDirFactor, baseRotFactor)

    local camStatePatch = {}
    local transitionTarget = STATE.tracking.transitionTarget -- Get the generic target

    if STATE.tracking.isModeTransitionInProgress then

        if transitionTarget then
            local progress = CameraCommons.getTransitionProgress()
            -- *** Transition to a specific Point X ***
            local startState = STATE.tracking.transitionStartState
            camStatePatch.px = CameraCommons.lerp(startState.px, transitionTarget.px, progress)
            camStatePatch.py = CameraCommons.lerp(startState.py, transitionTarget.py, progress)
            camStatePatch.pz = CameraCommons.lerp(startState.pz, transitionTarget.pz, progress)
            camStatePatch.fov = CameraCommons.lerp(startState.fov or 45, transitionTarget.fov or 45, progress)

            local currentPos = { x = camStatePatch.px, y = camStatePatch.py, z = camStatePatch.pz }
            local targetLookDir = CameraCommons.calculateCameraDirectionToThePoint(currentPos, targetPos)

            camStatePatch.rx = CameraCommons.smoothStepAngle(currentState.rx, targetLookDir.rx, rotFactor)
            camStatePatch.ry = CameraCommons.smoothStepAngle(currentState.ry, targetLookDir.ry, rotFactor)

            if progress >= 1 then
                STATE.tracking.transitionTarget = nil -- Clear target
                STATE.tracking.isModeTransitionInProgress = false
            end
        else
            local _, gameSpeed = Spring.GetGameSpeed()
            local profile = CONFIG.CAMERA_MODES.UNIT_TRACKING.DECELERATION_PROFILE
            local progress = CameraCommons.getTransitionProgress(profile.DURATION / gameSpeed) -- shorten the transition if gameSpeed is higher
            local initialVelocity, _, initialRotVelocity = CameraManager.getCurrentVelocity()
            local deceleratedState = TransitionUtil.smoothDecelerationTransition(currentState, dt, progress, initialVelocity, initialRotVelocity, profile)

            if deceleratedState then
                camStatePatch.px = deceleratedState.px
                camStatePatch.py = deceleratedState.py
                camStatePatch.pz = deceleratedState.pz
                local targetLookDir = CameraCommons.calculateCameraDirectionToThePoint(deceleratedState, targetPos)
                camStatePatch.rx = CameraCommons.smoothStepAngle(deceleratedState.rx, targetLookDir.rx, rotFactor)
                camStatePatch.ry = CameraCommons.smoothStepAngle(deceleratedState.ry, targetLookDir.ry, rotFactor)
            else
                -- Deceleration finished. Hold position and focus.
                local idealState = CameraCommons.focusOnPoint(currentState, targetPos, dirFactor, rotFactor)
                camStatePatch.px = currentState.px -- Hold
                camStatePatch.py = currentState.py -- Hold
                camStatePatch.pz = currentState.pz -- Hold
                camStatePatch.rx = idealState.rx
                camStatePatch.ry = idealState.ry
                STATE.tracking.transitionTarget = nil -- Clear just in case
                STATE.tracking.isModeTransitionInProgress = false
            end
        end
    else
        -- Not in transition. Hold position and focus.
        local idealState = CameraCommons.focusOnPoint(currentState, targetPos, dirFactor, rotFactor)
        camStatePatch.px = currentState.px -- Hold
        camStatePatch.py = currentState.py -- Hold
        camStatePatch.pz = currentState.pz -- Hold
        camStatePatch.rx = idealState.rx
        camStatePatch.ry = idealState.ry
    end

    -- Ensure dx/dy/dz and rz are set based on the final rotation.
    local finalDir = CameraCommons.getDirectionFromRotation(camStatePatch.rx, camStatePatch.ry, 0)
    camStatePatch.dx = finalDir.x
    camStatePatch.dy = finalDir.y
    camStatePatch.dz = finalDir.z
    camStatePatch.rz = 0

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
