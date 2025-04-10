---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
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
    local lastRotation = STATE.tracking.lastRotation

    -- Skip if no previous position recorded
    if not STATE.tracking.fps.freeCam.lastMouseX or not STATE.tracking.fps.freeCam.lastMouseY then
        STATE.tracking.fps.freeCam.lastMouseX = mouseX
        STATE.tracking.fps.freeCam.lastMouseY = mouseY
        return lastRotation
    end

    -- Calculate delta movement
    local deltaX = mouseX - STATE.tracking.fps.freeCam.lastMouseX
    local deltaY = mouseY - STATE.tracking.fps.freeCam.lastMouseY

    -- Only update if mouse has moved
    if deltaX ~= 0 or deltaY ~= 0 then
        -- Update target rotations based on mouse movement
        STATE.tracking.fps.freeCam.targetRy = STATE.tracking.fps.freeCam.targetRy + deltaX * CONFIG.CAMERA_MODES.FPS.MOUSE_SENSITIVITY
        STATE.tracking.fps.freeCam.targetRx = STATE.tracking.fps.freeCam.targetRx - deltaY * CONFIG.CAMERA_MODES.FPS.MOUSE_SENSITIVITY

        -- Normalize yaw angle
        STATE.tracking.fps.freeCam.targetRy = CameraCommons.normalizeAngle(STATE.tracking.fps.freeCam.targetRy)

        -- Constrain pitch angle (prevent flipping over)
        STATE.tracking.fps.freeCam.targetRx = math.max(0.1, math.min(math.pi - 0.1, STATE.tracking.fps.freeCam.targetRx))

        -- Remember mouse position for next frame
        STATE.tracking.fps.freeCam.lastMouseX = mouseX
        STATE.tracking.fps.freeCam.lastMouseY = mouseY
    end

    -- Create smoothed camera rotation values
    local rx = CameraCommons.smoothStep(lastRotation.rx, STATE.tracking.fps.freeCam.targetRx, rotFactor)
    local ry = CameraCommons.smoothStepAngle(lastRotation.ry, STATE.tracking.fps.freeCam.targetRy, rotFactor)

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
    if not STATE.tracking.fps.freeCam.lastUnitHeading then
        STATE.tracking.fps.freeCam.lastUnitHeading = unitHeading
        return false
    end

    -- Calculate heading difference
    local headingDiff = unitHeading - STATE.tracking.fps.freeCam.lastUnitHeading

    -- Only adjust if the heading difference is significant
    if math.abs(headingDiff) > 0.01 then
        -- Calculate how much the unit has rotated
        headingDiff = CameraCommons.normalizeAngle(headingDiff)

        -- Invert the heading difference for correct rotation
        headingDiff = -headingDiff

        -- Adjust the target rotation to maintain relative orientation
        STATE.tracking.fps.freeCam.targetRy = CameraCommons.normalizeAngle(STATE.tracking.fps.freeCam.targetRy + headingDiff)

        -- Update the last heading for next frame
        STATE.tracking.fps.freeCam.lastUnitHeading = unitHeading
        return true
    end

    -- Update the last heading for next frame
    STATE.tracking.fps.freeCam.lastUnitHeading = unitHeading
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
        mode = 0,
        name = "fps",
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
    STATE.tracking.inFreeCameraMode = not STATE.tracking.inFreeCameraMode

    -- Initialize or clear free camera STATE.tracking
    if STATE.tracking.inFreeCameraMode then
        -- Initialize with current camera STATE.tracking
        local camState = CameraManager.getCameraState("GroupTrackingCamera.initializeCameraPosition")
        STATE.tracking.fps.freeCam = STATE.tracking.fps.freeCam or {}
        STATE.tracking.fps.freeCam.targetRx = camState.rx
        STATE.tracking.fps.freeCam.targetRy = camState.ry
        STATE.tracking.fps.freeCam.lastMouseX, STATE.tracking.fps.freeCam.lastMouseY = Spring.GetMouseState()

        -- Initialize unit heading tracking if we have a unit
        if STATE.tracking.unitID and Spring.ValidUnitID(STATE.tracking.unitID) then
            STATE.tracking.fps.freeCam.lastUnitHeading = Spring.GetUnitHeading(STATE.tracking.unitID, true)
        end

        Log.debug("Free camera mode enabled - use mouse to rotate view")
    else
        -- Clear tracking data when disabling
        STATE.tracking.fps.freeCam.lastMouseX = nil
        STATE.tracking.fps.freeCam.lastMouseY = nil
        STATE.tracking.fps.freeCam.targetRx = nil
        STATE.tracking.fps.freeCam.targetRy = nil
        STATE.tracking.fps.freeCam.lastUnitHeading = nil

        Log.debug("Free camera mode disabled - view follows unit orientation")
    end

    -- Start a transition for smooth change
    STATE.tracking.modeTransition = true
    STATE.tracking.transitionStartTime = Spring.GetTimer()

    return true
end

return {
    FreeCam = FreeCam
}