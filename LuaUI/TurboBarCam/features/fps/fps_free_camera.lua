---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local Util = CommonModules.Util
local Log = CommonModules.Log
local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG

---@class FreeCam
local FreeCam = {}

--- Updates free camera rotation based on mouse movement
---@param rotFactor number Rotation smoothing factor
---@return table updated rotation values {rx, ry}
function FreeCam.updateMouseRotation(rotFactor)
    local mouseX, mouseY = Spring.GetMouseState()
    local state, lastRotation = STATE.tracking.freeCam, STATE.tracking.lastRotation
    
    -- Skip if no previous position recorded
    if not state.lastMouseX or not state.lastMouseY then
        state.lastMouseX = mouseX
        state.lastMouseY = mouseY
        return lastRotation
    end
    
    -- Calculate delta movement
    local deltaX = mouseX - state.lastMouseX
    local deltaY = mouseY - state.lastMouseY
    
    -- Only update if mouse has moved
    if deltaX ~= 0 or deltaY ~= 0 then
        -- Update target rotations based on mouse movement
        state.targetRy = state.targetRy + deltaX * CONFIG.CAMERA_MODES.FPS.MOUSE_SENSITIVITY
        state.targetRx = state.targetRx - deltaY * CONFIG.CAMERA_MODES.FPS.MOUSE_SENSITIVITY
        
        -- Normalize yaw angle
        state.targetRy = Util.normalizeAngle(state.targetRy)
        
        -- Constrain pitch angle (prevent flipping over)
        state.targetRx = math.max(0.1, math.min(math.pi - 0.1, state.targetRx))
        
        -- Remember mouse position for next frame
        state.lastMouseX = mouseX
        state.lastMouseY = mouseY
    end
    
    -- Create smoothed camera rotation values
    local rx = Util.smoothStep(lastRotation.rx, state.targetRx, rotFactor)
    local ry = Util.smoothStepAngle(lastRotation.ry, state.targetRy, rotFactor)
    
    return {
        rx = rx,
        ry = ry
    }
end

--- Updates rotation based on unit heading changes (for unit-following free cam)
---@param state table Free camera state
---@param unitID number Unit ID being followed
---@return boolean updated Whether heading was updated
function FreeCam.updateUnitHeadingTracking(state, unitID)
    if not Spring.ValidUnitID(unitID) then
        return false
    end
    
    -- Get the current unit heading
    local unitHeading = Spring.GetUnitHeading(unitID, true)
    
    -- Skip if no previous heading recorded
    if not state.lastUnitHeading then
        state.lastUnitHeading = unitHeading
        return false
    end
    
    -- Calculate heading difference
    local headingDiff = unitHeading - state.lastUnitHeading
    
    -- Only adjust if the heading difference is significant
    if math.abs(headingDiff) > 0.01 then
        -- Calculate how much the unit has rotated
        headingDiff = Util.normalizeAngle(headingDiff)
        
        -- Invert the heading difference for correct rotation
        headingDiff = -headingDiff
        
        -- Adjust the target rotation to maintain relative orientation
        state.targetRy = Util.normalizeAngle(state.targetRy + headingDiff)
        
        -- Update the last heading for next frame
        state.lastUnitHeading = unitHeading
        return true
    end
    
    -- Update the last heading for next frame
    state.lastUnitHeading = unitHeading
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
        dx = Util.smoothStep(lastCamDir.x, dx, rotFactor),
        dy = Util.smoothStep(lastCamDir.y, dy, rotFactor),
        dz = Util.smoothStep(lastCamDir.z, dz, rotFactor),
        -- Rotation (smoothed)
        rx = rotation.rx,
        ry = rotation.ry,
        rz = 0
    }
    
    return camState
end

--- Toggles free camera mode
---@param state table Current state
---@param modeType string Camera mode type
---@return boolean success Whether mode was toggled successfully
function FreeCam.toggle(state, modeType)
    if Util.isTurboBarCamDisabled() then
        return
    end
    
    -- Toggle free camera mode
    state.inFreeCameraMode = not state.inFreeCameraMode
    
    -- Initialize or clear free camera state
    if state.inFreeCameraMode then
        -- Initialize with current camera state
        local camState = CameraManager.getCameraState("GroupTrackingCamera.initializeCameraPosition")
        state.freeCam = state.freeCam or {}
        state.freeCam.targetRx = camState.rx
        state.freeCam.targetRy = camState.ry
        state.freeCam.lastMouseX, state.freeCam.lastMouseY = Spring.GetMouseState()
        
        -- Initialize unit heading tracking if we have a unit
        if state.unitID and Spring.ValidUnitID(state.unitID) then
            state.freeCam.lastUnitHeading = Spring.GetUnitHeading(state.unitID, true)
        end
        
        Log.debug("Free camera mode enabled - use mouse to rotate view")
    else
        -- Clear tracking data when disabling
        state.freeCam.lastMouseX = nil
        state.freeCam.lastMouseY = nil
        state.freeCam.targetRx = nil
        state.freeCam.targetRy = nil
        state.freeCam.lastUnitHeading = nil

        Log.debug("Free camera mode disabled - view follows " .. modeType .. " orientation")
    end
    
    -- Start a transition for smooth change
    state.modeTransition = true
    state.transitionStartTime = Spring.GetTimer()
    
    return true
end

return {
    FreeCam = FreeCam
}