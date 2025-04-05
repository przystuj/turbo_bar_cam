-- Tracking Camera module for TURBOBARCAM
-- Load modules
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CoreModules
local TurboCore = VFS.Include("LuaUI/TURBOBARCAM/core.lua")
---@type CommonModules
local TurboCommons = VFS.Include("LuaUI/TURBOBARCAM/common.lua")

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE
local Util = TurboCommons.Util
local CameraCommons = TurboCore.CameraCommons
local TrackingManager = TurboCommons.Tracking

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
            Util.debugEcho("Tracking Camera disabled")
        else
            Util.debugEcho("No unit selected for Tracking Camera")
        end
        return
    end

    local selectedUnitID = selectedUnits[1]

    -- If we're already tracking this exact unit in tracking camera mode, turn it off
    if STATE.tracking.mode == 'unit_tracking' and STATE.tracking.unitID == selectedUnitID then
        TrackingManager.disableTracking()
        Util.debugEcho("Tracking Camera disabled")
        return
    end

    -- Initialize the tracking system
    if TrackingManager.initializeTracking('unit_tracking', selectedUnitID) then
        Util.debugEcho("Tracking Camera enabled. Camera will track unit " .. selectedUnitID)
    end
end

--- Updates tracking camera to point at the tracked unit
function UnitTrackingCamera.update()
    if STATE.tracking.mode ~= 'unit_tracking' or not STATE.tracking.unitID then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Util.debugEcho("Tracked unit no longer exists, disabling Tracking Camera")
        TrackingManager.disableTracking()
        return
    end

    -- Check if we're still in FPS mode
    local currentState = Spring.GetCameraState()
    if currentState.mode ~= 0 then
        -- Force back to FPS mode
        currentState.mode = 0
        currentState.name = "fps"
        Util.setCameraState(currentState, false, "UnitTrackingCamera.update")
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
    local dirFactor = CONFIG.SMOOTHING.TRACKING_FACTOR
    local rotFactor = CONFIG.SMOOTHING.ROTATION_FACTOR

    if STATE.tracking.modeTransition then
        -- Use a special transition factor during mode changes
        dirFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR
        rotFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR

        -- Check if we should end the transition
        if CameraCommons.isTransitionComplete(STATE.tracking.transitionStartTime) then
            STATE.tracking.modeTransition = false
        end
    end

    -- Initialize last values if needed
    if STATE.tracking.lastCamDir.x == 0 and STATE.tracking.lastCamDir.y == 0 and STATE.tracking.lastCamDir.z == 0 then
        local initialLookDir = Util.calculateLookAtPoint(camPos, targetPos)
        STATE.tracking.lastCamDir = { x = initialLookDir.dx, y = initialLookDir.dy, z = initialLookDir.dz }
        STATE.tracking.lastRotation = { rx = initialLookDir.rx, ry = initialLookDir.ry, rz = 0 }
    end

    -- Use the focusOnPoint method to get camera direction state
    local camStatePatch = CameraCommons.focusOnPoint(camPos, targetPos, dirFactor, rotFactor)
    -- Remove position updates to allow free camera movement
    camStatePatch.px, camStatePatch.py, camStatePatch.pz = nil, nil, nil
    TrackingManager.updateTrackingState(camStatePatch)

    -- Apply camera state - only updating direction and rotation
    Util.setCameraState(camStatePatch, true, "UnitTrackingCamera.update")
end

---@see ModifiableParams
---@see UtilsModule#adjustParams
function UnitTrackingCamera.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("unit_tracking") then
        return
    end
    -- Make sure we have a unit to track
    if not STATE.tracking.unitID then
        Util.debugEcho("No unit is tracked")
        return
    end

    Util.adjustParams(params, "UNIT_TRACKING", function() CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT = 0 end)
end

return {
    UnitTrackingCamera = UnitTrackingCamera
}