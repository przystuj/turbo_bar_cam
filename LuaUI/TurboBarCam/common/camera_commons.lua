---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type TrackingManager
local TrackingManager = VFS.Include("LuaUI/TurboBarCam/common/tracking_manager.lua").TrackingManager
---@type Util
local Util = VFS.Include("LuaUI/TurboBarCam/common/utils.lua").Util

local STATE = WidgetContext.WidgetState.STATE

---@class CameraCommons
local CameraCommons = {}

--- Checks if a transition has completed
---@param startTime number Timer when transition started
---@return boolean hasCompleted True if transition is complete
function CameraCommons.isTransitionComplete(startTime)
    local now = Spring.GetTimer()
    local elapsed = Spring.DiffTimers(now, startTime)
    return elapsed > 1.0
end

--- Focuses camera on a point with appropriate smoothing
---@param camPos table Camera position {x, y, z}
---@param targetPos table Target position {x, y, z}
---@param lastCamDir table Last camera direction {x, y, z}
---@param lastRotation table Last camera rotation {rx, ry, rz}
---@param smoothFactor number Direction smoothing factor
---@param rotFactor number Rotation smoothing factor
---@return table cameraDirectionState Camera direction and rotation state
function CameraCommons.focusOnPoint(camPos, targetPos, smoothFactor, rotFactor)
    -- Calculate look direction to the target point
    local lookDir = Util.calculateLookAtPoint(camPos, targetPos)

    -- Create camera direction state with smoothed values
    local cameraDirectionState = {
        -- Smooth camera position
        px = Util.smoothStep(STATE.tracking.lastCamPos.x, camPos.x, smoothFactor),
        py = Util.smoothStep(STATE.tracking.lastCamPos.y, camPos.y, smoothFactor),
        pz = Util.smoothStep(STATE.tracking.lastCamPos.z, camPos.z, smoothFactor),

        -- Smooth direction vector
        dx = Util.smoothStep(STATE.tracking.lastCamDir.x, lookDir.dx, smoothFactor),
        dy = Util.smoothStep(STATE.tracking.lastCamDir.y, lookDir.dy, smoothFactor),
        dz = Util.smoothStep(STATE.tracking.lastCamDir.z, lookDir.dz, smoothFactor),

        -- Smooth rotations
        rx = Util.smoothStep(STATE.tracking.lastRotation.rx, lookDir.rx, rotFactor),
        ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, lookDir.ry, rotFactor),
        rz = 0
    }

    return cameraDirectionState
end

--- Applies camera offsets to a base position based on unit vectors
---@param unitPos table Unit position {x, y, z}
---@param front table Front vector {x, y, z}
---@param up table Up vector {x, y, z}
---@param right table Right vector {x, y, z}
---@param offsets table Offset values {height, forward, side}
---@return table adjustedPos Adjusted camera position
function CameraCommons.applyOffsets(unitPos, front, up, right, offsets)
    local x, y, z = unitPos.x, unitPos.y, unitPos.z

    -- Extract components from the vector tables
    local frontX, frontY, frontZ = front[1], front[2], front[3]
    local upX, upY, upZ = up[1], up[2], up[3]
    local rightX, rightY, rightZ = right[1], right[2], right[3]

    -- Apply height offset along the unit's up vector
    if offsets.height ~= 0 then
        x = x + upX * offsets.height
        y = y + upY * offsets.height
        z = z + upZ * offsets.height
    end

    -- Apply forward offset if needed
    if offsets.forward ~= 0 then
        x = x + frontX * offsets.forward
        y = y + frontY * offsets.forward
        z = z + frontZ * offsets.forward
    end

    -- Apply side offset if needed
    if offsets.side ~= 0 then
        x = x + rightX * offsets.side
        y = y + rightY * offsets.side
        z = z + rightZ * offsets.side
    end

    return { x = x, y = y, z = z }
end

--- Creates a basic camera state object with the specified position and direction
---@param position table Camera position {x, y, z}
---@param direction table Camera direction {dx, dy, dz, rx, ry, rz}
---@return table cameraState Complete camera state object
function CameraCommons.createCameraState(position, direction)
    return {
        mode = 0, -- FPS camera mode
        name = "fps",

        -- Position
        px = position.x,
        py = position.y,
        pz = position.z,

        -- Direction
        dx = direction.dx,
        dy = direction.dy,
        dz = direction.dz,

        -- Rotation
        rx = direction.rx,
        ry = direction.ry,
        rz = direction.rz
    }
end

--- Begins a transition between camera modes
---@param newMode string|nil New camera mode to transition to
function CameraCommons.beginModeTransition(newMode)
    -- Save the previous mode
    STATE.tracking.prevMode = STATE.tracking.mode
    STATE.tracking.mode = newMode

    -- Only start a transition if we're switching between different modes
    if STATE.tracking.prevMode ~= newMode then
        STATE.tracking.modeTransition = true
        STATE.tracking.transitionStartState = CameraManager.getCameraState("CameraCommons.beginModeTransition")
        STATE.tracking.transitionStartTime = Spring.GetTimer()

        -- Store current camera position as last position to smooth from
        local camState = CameraManager.getCameraState("CameraCommons.beginModeTransition")
        TrackingManager.updateTrackingState(camState)
    end
end

return {
    CameraCommons = CameraCommons
}