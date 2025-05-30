---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons
local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG

---@class FreeCam
local FreeCam = {}

--- Updates free camera rotation based on mouse movement
---@param rotFactor number Rotation smoothing factor
---@return table updated rotation values {rx, ry}
function FreeCam.updateMouseRotation(rotFactor)
    local mouseX, mouseY = Spring.GetMouseState()
    local lastRotation = STATE.mode.lastRotation

    -- Skip if no previous position recorded
    if not STATE.mode.fps.freeCam.lastMouseX or not STATE.mode.fps.freeCam.lastMouseY then
        STATE.mode.fps.freeCam.lastMouseX = mouseX
        STATE.mode.fps.freeCam.lastMouseY = mouseY
        return lastRotation
    end

    -- Calculate delta movement
    local deltaX = mouseX - STATE.mode.fps.freeCam.lastMouseX
    local deltaY = mouseY - STATE.mode.fps.freeCam.lastMouseY

    -- Only update if mouse has moved
    if deltaX ~= 0 or deltaY ~= 0 then
        -- Update target rotations based on mouse movement
        STATE.mode.fps.freeCam.targetRy = STATE.mode.fps.freeCam.targetRy + deltaX * CONFIG.CAMERA_MODES.FPS.MOUSE_SENSITIVITY
        STATE.mode.fps.freeCam.targetRx = STATE.mode.fps.freeCam.targetRx - deltaY * CONFIG.CAMERA_MODES.FPS.MOUSE_SENSITIVITY

        -- Normalize yaw angle
        STATE.mode.fps.freeCam.targetRy = CameraCommons.normalizeAngle(STATE.mode.fps.freeCam.targetRy)

        -- Constrain pitch angle (prevent flipping over)
        STATE.mode.fps.freeCam.targetRx = math.max(0.1, math.min(math.pi - 0.1, STATE.mode.fps.freeCam.targetRx))

        -- Remember mouse position for next frame
        STATE.mode.fps.freeCam.lastMouseX = mouseX
        STATE.mode.fps.freeCam.lastMouseY = mouseY
    end

    -- Create smoothed camera rotation values
    local rx = CameraCommons.smoothStep(lastRotation.rx, STATE.mode.fps.freeCam.targetRx, rotFactor)
    local ry = CameraCommons.smoothStepAngle(lastRotation.ry, STATE.mode.fps.freeCam.targetRy, rotFactor)

    return {
        rx = rx,
        ry = ry
    }
end

--- Updates rotation based on unit heading changes (for unit-following free cam)
---@param unitID number Unit ID being followed
---@return boolean updated Whether heading was updated
function FreeCam.updateUnitHeadingTracking(unitID)
    if not Spring.ValidUnitID(unitID) then
        return false
    end

    -- Get the current unit heading
    local unitHeading = Spring.GetUnitHeading(unitID, true)

    -- Skip if no previous heading recorded
    if not STATE.mode.fps.freeCam.lastUnitHeading then
        STATE.mode.fps.freeCam.lastUnitHeading = unitHeading
        return false
    end

    -- Calculate heading difference
    local headingDiff = unitHeading - STATE.mode.fps.freeCam.lastUnitHeading

    -- Only adjust if the heading difference is significant
    if math.abs(headingDiff) > 0.01 then
        -- Calculate how much the unit has rotated
        headingDiff = CameraCommons.normalizeAngle(headingDiff)

        -- Invert the heading difference for correct rotation
        headingDiff = -headingDiff

        -- Adjust the target rotation to maintain relative orientation
        STATE.mode.fps.freeCam.targetRy = CameraCommons.normalizeAngle(STATE.mode.fps.freeCam.targetRy + headingDiff)

        -- Update the last heading for next frame
        STATE.mode.fps.freeCam.lastUnitHeading = unitHeading
        return true
    end

    -- Update the last heading for next frame
    STATE.mode.fps.freeCam.lastUnitHeading = unitHeading
    return false
end

--- Creates a complete camera state for free camera mode
---@param position table Camera position {x, y, z}
---@param rotation table Camera rotation {rx, ry}
---@param lastCamDir table Last camera direction {x, y, z}
---@param lastRotation table Last camera rotation {rx, ry, rz}
---@param rotFactor number Rotation smoothing factor
---@return table cameraState Complete camera state
function FreeCam.createCameraState(position, rotation, lastCamDir, lastRotation, rotFactor)
    -- Calculate direction vector from rotation angles
    local cosRx = math.cos(rotation.rx)
    local dx = math.sin(rotation.ry) * cosRx
    local dz = math.cos(rotation.ry) * cosRx
    local dy = math.sin(rotation.rx)

    -- Create camera state with smoothed directions
    local camState = {
        -- Position
        px = position.x,
        py = position.y,
        pz = position.z,
        -- Direction (smoothed)
        dx = CameraCommons.smoothStep(lastCamDir.x, dx, rotFactor),
        dy = CameraCommons.smoothStep(lastCamDir.y, dy, rotFactor),
        dz = CameraCommons.smoothStep(lastCamDir.z, dz, rotFactor),
        -- Rotation (smoothed)
        rx = rotation.rx,
        ry = rotation.ry,
        rz = 0
    }

    return camState
end

--- Toggles free camera mode
---@return boolean success Whether mode was toggled successfully
function FreeCam.toggle()
    if Util.isTurboBarCamDisabled() then
        return
    end

    -- Toggle free camera mode
    STATE.mode.inFreeCameraMode = not STATE.mode.inFreeCameraMode

    -- Initialize or clear free camera STATE.mode
    if STATE.mode.inFreeCameraMode then
        -- Initialize with current camera STATE.mode
        local camState = CameraManager.getCameraState("GroupTrackingCamera.initializeCameraPosition")
        STATE.mode.fps.freeCam = STATE.mode.fps.freeCam or {}
        STATE.mode.fps.freeCam.targetRx = camState.rx
        STATE.mode.fps.freeCam.targetRy = camState.ry
        STATE.mode.fps.freeCam.lastMouseX, STATE.mode.fps.freeCam.lastMouseY = Spring.GetMouseState()

        -- Initialize unit heading tracking if we have a unit
        if STATE.mode.unitID and Spring.ValidUnitID(STATE.mode.unitID) then
            STATE.mode.fps.freeCam.lastUnitHeading = Spring.GetUnitHeading(STATE.mode.unitID, true)
        end

        Log.debug("Free camera mode enabled - use mouse to rotate view")
    else
        -- Clear tracking data when disabling
        STATE.mode.fps.freeCam.lastMouseX = nil
        STATE.mode.fps.freeCam.lastMouseY = nil
        STATE.mode.fps.freeCam.targetRx = nil
        STATE.mode.fps.freeCam.targetRy = nil
        STATE.mode.fps.freeCam.lastUnitHeading = nil

        Log.trace("Free camera mode disabled - view follows unit orientation")
    end

    -- Start a transition for smooth change
    STATE.mode.modeTransition = true
    STATE.mode.transitionStartTime = Spring.GetTimer()

    return true
end

return {
    FreeCam = FreeCam
}