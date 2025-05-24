---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
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

--- Toggles tracking camera mode
---@return boolean success Always returns true for widget handler
function UnitTrackingCamera.toggle()
    if Util.isTurboBarCamDisabled() then
        return
    end

    -- Get the selected unit
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits == 0 then
        -- If no unit is selected and tracking is currently on, turn it off
        if STATE.tracking.mode == 'unit_tracking' then
            TrackingManager.disableTracking()
            Log.trace("Tracking Camera disabled")
        else
            Log.trace("No unit selected for Tracking Camera")
        end
        return
    end

    local selectedUnitID = selectedUnits[1]

    -- If we're already tracking this exact unit in tracking camera mode, turn it off
    if STATE.tracking.mode == 'unit_tracking' and STATE.tracking.unitID == selectedUnitID then
        TrackingManager.disableTracking()
        Log.trace("Tracking Camera disabled")
        return
    end

    -- Initialize the tracking system
    -- Velocity tracking is handled automatically by CameraManager
    if TrackingManager.initializeTracking('unit_tracking', selectedUnitID) then
        Log.trace("Tracking Camera enabled. Camera will track unit " .. selectedUnitID)
    end
end

--- Updates tracking camera to point at the tracked unit
function UnitTrackingCamera.update(dt)
    if STATE.tracking.mode ~= 'unit_tracking' or not STATE.tracking.unitID then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Log.trace("Tracked unit no longer exists, disabling Tracking Camera")
        TrackingManager.disableTracking()
        return
    end

    local currentState = CameraManager.getCameraState("UnitTrackingCamera.update")

    -- Get unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)

    -- Apply the target height offset from config
    local targetPos = {
        x = unitX,
        y = unitY + CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT,
        z = unitZ
    }

    -- Get current camera position
    local camPos = { x = currentState.px, y = currentState.py, z = currentState.pz }

    -- Determine smoothing factor based on whether we're in a mode transition
    local dirFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.TRACKING_FACTOR
    local rotFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.ROTATION_FACTOR

    dirFactor, rotFactor = CameraCommons.handleModeTransition(dirFactor, rotFactor)

    -- Initialize last values if needed
    if STATE.tracking.lastCamDir.x == 0 and STATE.tracking.lastCamDir.y == 0 and STATE.tracking.lastCamDir.z == 0 then
        local initialLookDir = CameraCommons.calculateCameraDirectionToThePoint(camPos, targetPos)
        STATE.tracking.lastCamDir = { x = initialLookDir.dx, y = initialLookDir.dy, z = initialLookDir.dz }
        STATE.tracking.lastRotation = { rx = initialLookDir.rx, ry = initialLookDir.ry, rz = 0 }
    end

    -- Use the focusOnPoint method to get camera direction state
    local camStatePatch = CameraCommons.focusOnPoint(camPos, targetPos, dirFactor, rotFactor)

    -- Handle position control based on transition state
    if STATE.tracking.isModeTransitionInProgress then
        -- During transition, apply smooth deceleration using CameraManager's continuously tracked velocity
        local transitionProgress = CameraCommons.getTransitionProgress()

        -- Get current velocity from CameraManager (tracks automatically)
        local _, velMagnitude = CameraManager.getCurrentVelocity()

        if velMagnitude > 10.0 then  -- Only apply deceleration if we have significant velocity (increased threshold)
            -- Calculate deceleration parameters - more aggressive decay to prevent overshooting
            local decayRate = 5.0 + (transitionProgress * 15.0)  -- Range: 5-20 (increased from 2-10)

            -- Predict where camera should be based on decaying velocity
            local predictedPos = CameraManager.predictPosition(camPos, dt, decayRate)

            -- Calculate position control factor - more conservative
            local positionControlFactor = 0.9 - (0.1 * transitionProgress)

            -- Apply predicted position with decreasing influence
            camStatePatch.px = CameraCommons.smoothStep(camPos.x, predictedPos.x, positionControlFactor)
            camStatePatch.py = CameraCommons.smoothStep(camPos.y, predictedPos.y, positionControlFactor)
            camStatePatch.pz = CameraCommons.smoothStep(camPos.z, predictedPos.z, positionControlFactor)

            -- Log deceleration info occasionally for debugging
            if math.random() < 0.50 then  -- 2% chance per frame
                Log.debug(string.format("Unit tracking deceleration: progress=%.1f%%, vel=%.1f, decay=%.1f, control=%.3f",
                        transitionProgress * 100, velMagnitude, decayRate, positionControlFactor))
            end
        else
            -- Velocity is low, just gradually reduce position control to zero
            local positionControlFactor = (1.0 - transitionProgress) * 0.02  -- Even gentler final reduction

            -- Apply minimal position control to avoid sudden stops
            camStatePatch.px = CameraCommons.smoothStep(camPos.x, camPos.x, positionControlFactor)
            camStatePatch.py = CameraCommons.smoothStep(camPos.y, camPos.y, positionControlFactor)
            camStatePatch.pz = CameraCommons.smoothStep(camPos.z, camPos.z, positionControlFactor)
        end
    else
        -- After transition is complete, remove position updates to allow free camera movement
        camStatePatch.px, camStatePatch.py, camStatePatch.pz = nil, nil, nil

        -- Velocity tracking continues automatically in CameraManager
    end

    TrackingManager.updateTrackingState(camStatePatch)

    -- Apply camera state
    CameraManager.setCameraState(camStatePatch, 0, "UnitTrackingCamera.update")
end

---@see ModifiableParams
---@see Util#adjustParams
function UnitTrackingCamera.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("unit_tracking") then
        return
    end
    -- Make sure we have a unit to track
    if not STATE.tracking.unitID then
        Log.trace("No unit is tracked")
        return
    end

    Util.adjustParams(params, "UNIT_TRACKING", function() CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT = 0 end)
end

return {
    UnitTrackingCamera = UnitTrackingCamera
}