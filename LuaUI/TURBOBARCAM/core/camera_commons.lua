-- Camera Commons module for TURBOBARCAM
-- This module provides shared functionality used by all camera types
-- Load modules
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CommonModules
local TurboCommons = VFS.Include("LuaUI/TURBOBARCAM/common.lua")

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE
local Util = TurboCommons.Util

---@class CameraCommons
local CameraCommons = {}

--- Determines appropriate smoothing factors based on current state
---@param isTransitioning boolean Whether we're in a mode transition
---@param smoothType string Type of smoothing ('position', 'rotation', 'direction')
---@return number smoothingFactor The smoothing factor to use
function CameraCommons.getSmoothingFactor(isTransitioning, smoothType)
    if isTransitioning then
        return CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR
    end

    if smoothType == 'position' then
        return CONFIG.SMOOTHING.POSITION_FACTOR
    elseif smoothType == 'rotation' then
        return CONFIG.SMOOTHING.ROTATION_FACTOR
    elseif smoothType == 'direction' then
        return CONFIG.SMOOTHING.TRACKING_FACTOR
    elseif smoothType == 'free_camera' then
        return CONFIG.SMOOTHING.FREE_CAMERA_FACTOR
    elseif smoothType == 'fps' then
        return CONFIG.SMOOTHING.FPS_FACTOR
    end

    -- Default
    return CONFIG.SMOOTHING.POSITION_FACTOR
end

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
function CameraCommons.focusOnPoint(camPos, targetPos, lastCamDir, lastRotation, smoothFactor, rotFactor)
    -- Calculate look direction to the target point
    local lookDir = Util.calculateLookAtPoint(camPos, targetPos)

    -- Create camera direction state with smoothed values
    local cameraDirectionState = {
        -- Smooth direction vector
        dx = Util.smoothStep(lastCamDir.x, lookDir.dx, smoothFactor),
        dy = Util.smoothStep(lastCamDir.y, lookDir.dy, smoothFactor),
        dz = Util.smoothStep(lastCamDir.z, lookDir.dz, smoothFactor),

        -- Smooth rotations
        rx = Util.smoothStep(lastRotation.rx, lookDir.rx, rotFactor),
        ry = Util.smoothStepAngle(lastRotation.ry, lookDir.ry, rotFactor),
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

--- Handles the transition from one camera mode to another
---@param prevMode string Previous camera mode
---@param newMode string New camera mode to transition to
function CameraCommons.beginModeTransition(prevMode, newMode)
    -- Store the previous and current mode
    STATE.tracking.prevMode = prevMode
    STATE.tracking.mode = newMode

    -- Only start a transition if we're switching between different modes
    if prevMode ~= newMode then
        STATE.tracking.modeTransition = true
        STATE.tracking.transitionStartState = Spring.GetCameraState()
        STATE.tracking.transitionStartTime = Spring.GetTimer()

        -- Store current camera position as last position to smooth from
        local camState = Spring.GetCameraState()
        STATE.tracking.lastCamPos = { x = camState.px, y = camState.py, z = camState.pz }
        STATE.tracking.lastCamDir = { x = camState.dx, y = camState.dy, z = camState.dz }
        STATE.tracking.lastRotation = { rx = camState.rx, ry = camState.ry, rz = camState.rz }
    end
end

--- Checks if a unit exists and is valid
---@param unitID number Unit ID to check
---@param modeName string Camera mode name (for debug message)
---@return boolean isValid Whether the unit exists and is valid
function CameraCommons.validateUnit(unitID, modeName)
    if not Spring.ValidUnitID(unitID) then
        Util.debugEcho("Unit no longer exists, detaching " .. modeName .. " camera")
        return false
    end
    return true
end

--- Updates tracking state values after applying camera state
---@param camState table Camera state that was applied
function CameraCommons.updateTrackingState(camState)
    -- Update last camera position
    STATE.tracking.lastCamPos.x = camState.px
    STATE.tracking.lastCamPos.y = camState.py
    STATE.tracking.lastCamPos.z = camState.pz

    -- Update last camera direction
    STATE.tracking.lastCamDir.x = camState.dx
    STATE.tracking.lastCamDir.y = camState.dy
    STATE.tracking.lastCamDir.z = camState.dz

    -- Update last rotation
    STATE.tracking.lastRotation.rx = camState.rx
    STATE.tracking.lastRotation.ry = camState.ry
    STATE.tracking.lastRotation.rz = camState.rz
end

--- Ensures camera state is in FPS mode
---@param camState table Camera state to check and modify
---@return table fixedState Camera state with FPS mode set
function CameraCommons.ensureFPSMode(camState)
    if camState.mode ~= 0 then
        camState.mode = 0
        camState.name = "fps"
    end
    return camState
end

return {
    CameraCommons = CameraCommons
}