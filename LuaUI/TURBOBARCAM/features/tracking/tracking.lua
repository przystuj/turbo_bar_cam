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

---@class TrackingCamera
local TrackingCamera = {}

--- Toggles tracking camera mode
---@return boolean success Always returns true for widget handler
function TrackingCamera.toggle()
    if not STATE.enabled then
        Util.debugEcho("TURBOBARCAM must be enabled first")
        return true
    end

    -- Get the selected unit
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits == 0 then
        -- If no unit is selected and tracking is currently on, turn it off
        if STATE.tracking.mode == 'tracking_camera' then
            Util.disableTracking()
            Util.debugEcho("Tracking Camera disabled")
        else
            Util.debugEcho("No unit selected for Tracking Camera")
        end
        return true
    end

    local selectedUnitID = selectedUnits[1]

    -- If we're already tracking this exact unit in tracking camera mode, turn it off
    if STATE.tracking.mode == 'tracking_camera' and STATE.tracking.unitID == selectedUnitID then
        Util.disableTracking()
        Util.debugEcho("Tracking Camera disabled")
        return true
    end


    -- Initialize the tracking system
    if TrackingManager.initializeTracking('tracking_camera', selectedUnitID) then
        Util.debugEcho("Tracking Camera enabled. Camera will track unit " .. selectedUnitID)

    end

    return true
end

--- Updates tracking camera to point at the tracked unit
function TrackingCamera.update()
    if STATE.tracking.mode ~= 'tracking_camera' or not STATE.tracking.unitID then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Util.debugEcho("Tracked unit no longer exists, disabling Tracking Camera")
        Util.disableTracking()
        return
    end

    -- Check if we're still in FPS mode
    local currentState = Spring.GetCameraState()
    if currentState.mode ~= 0 then
        -- Force back to FPS mode
        currentState.mode = 0
        currentState.name = "fps"
        Spring.SetCameraState(currentState, 0)
    end


    -- Get unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)
    local targetPos = { x = unitX, y = unitY, z = unitZ }

    -- Get current camera position
    local camPos = { x = currentState.px, y = currentState.py, z = currentState.pz }

    -- Calculate look direction to the unit
    local lookDir = Util.calculateLookAtPoint(camPos, targetPos)

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
        STATE.tracking.lastCamDir = { x = lookDir.dx, y = lookDir.dy, z = lookDir.dz }
        STATE.tracking.lastRotation = { rx = lookDir.rx, ry = lookDir.ry, rz = 0 }
    end


    -- Create camera state patch - only update direction, not position
    local camStatePatch = {
        mode = 0,
        name = "fps",

        -- Smooth direction vector
        dx = Util.smoothStep(STATE.tracking.lastCamDir.x, lookDir.dx, dirFactor),
        dy = Util.smoothStep(STATE.tracking.lastCamDir.y, lookDir.dy, dirFactor),
        dz = Util.smoothStep(STATE.tracking.lastCamDir.z, lookDir.dz, dirFactor),

        -- Smooth rotations
        rx = Util.smoothStep(STATE.tracking.lastRotation.rx, lookDir.rx, rotFactor),
        ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, lookDir.ry, rotFactor),
        rz = 0
    }

    -- Update last values
    STATE.tracking.lastCamDir.x = camStatePatch.dx
    STATE.tracking.lastCamDir.y = camStatePatch.dy
    STATE.tracking.lastCamDir.z = camStatePatch.dz
    STATE.tracking.lastRotation.rx = camStatePatch.rx
    STATE.tracking.lastRotation.ry = camStatePatch.ry

    -- Apply camera state - only updating direction and rotation
    Spring.SetCameraState(camStatePatch, 0)
end

return {
    TrackingCamera = TrackingCamera
}