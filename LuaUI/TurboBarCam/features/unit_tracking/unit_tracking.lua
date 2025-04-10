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
            Log.debug("Tracking Camera disabled")
        else
            Log.debug("No unit selected for Tracking Camera")
        end
        return
    end

    local selectedUnitID = selectedUnits[1]

    -- If we're already tracking this exact unit in tracking camera mode, turn it off
    if STATE.tracking.mode == 'unit_tracking' and STATE.tracking.unitID == selectedUnitID then
        TrackingManager.disableTracking()
        Log.debug("Tracking Camera disabled")
        return
    end

    -- Initialize the tracking system
    if TrackingManager.initializeTracking('unit_tracking', selectedUnitID) then
        Log.debug("Tracking Camera enabled. Camera will track unit " .. selectedUnitID)
    end
end

--- Updates tracking camera to point at the tracked unit
function UnitTrackingCamera.update()
    if STATE.tracking.mode ~= 'unit_tracking' or not STATE.tracking.unitID then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Log.debug("Tracked unit no longer exists, disabling Tracking Camera")
        TrackingManager.disableTracking()
        return
    end

    -- Check if we're still in FPS mode
    local currentState = CameraManager.getCameraState("UnitTrackingCamera.update")
    if currentState.mode ~= 0 then
        -- Force back to FPS mode
        currentState.mode = 0
        currentState.name = "fps"
        CameraManager.setCameraState(currentState, 0, "UnitTrackingCamera.update")
    end

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

    if STATE.tracking.isModeTransitionInProgress then
        -- Use a special transition factor during mode changes
        dirFactor = CONFIG.MODE_TRANSITION_SMOOTHING
        rotFactor = CONFIG.MODE_TRANSITION_SMOOTHING

        -- Check if we should end the transition
        if CameraCommons.isTransitionComplete() then
            STATE.tracking.isModeTransitionInProgress = false
        end
    end

    -- Initialize last values if needed
    if STATE.tracking.lastCamDir.x == 0 and STATE.tracking.lastCamDir.y == 0 and STATE.tracking.lastCamDir.z == 0 then
        local initialLookDir = CameraCommons.calculateCameraDirectionToThePoint(camPos, targetPos)
        STATE.tracking.lastCamDir = { x = initialLookDir.dx, y = initialLookDir.dy, z = initialLookDir.dz }
        STATE.tracking.lastRotation = { rx = initialLookDir.rx, ry = initialLookDir.ry, rz = 0 }
    end

    -- Use the focusOnPoint method to get camera direction state
    local camStatePatch = CameraCommons.focusOnPoint(camPos, targetPos, dirFactor, rotFactor)
    -- Remove position updates to allow free camera movement
    camStatePatch.px, camStatePatch.py, camStatePatch.pz = nil, nil, nil
    TrackingManager.updateTrackingState(camStatePatch)

    -- Apply camera state - only updating direction and rotation
    CameraManager.setCameraState(camStatePatch, 1, "UnitTrackingCamera.update")
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
        Log.debug("No unit is tracked")
        return
    end

    Util.adjustParams(params, "UNIT_TRACKING", function() CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT = 0 end)
end

return {
    UnitTrackingCamera = UnitTrackingCamera
}