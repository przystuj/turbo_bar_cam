---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")

local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG

---@class CameraCommons
local CameraCommons = {}

--- Checks if a transition has completed
---@return boolean hasCompleted True if transition is complete
function CameraCommons.isTransitionComplete()
    local now = Spring.GetTimer()
    local elapsed = Spring.DiffTimers(now, STATE.tracking.transitionStartTime)
    return elapsed > CONFIG.TRANSITION.MODE_TRANSITION_DURATION
end

--- Focuses camera on a point with appropriate smoothing
---@param camPos table Camera position {x, y, z}
---@param targetPos table Target position {x, y, z}
---@param smoothFactor number Direction smoothing factor
---@param rotFactor number Rotation smoothing factor
---@return table cameraDirectionState Camera direction and rotation state
function CameraCommons.focusOnPoint(camPos, targetPos, smoothFactor, rotFactor, pitchModifier)
    -- Calculate look direction to the target point
    local lookDir = CameraCommons.calculateCameraDirectionToThePoint(camPos, targetPos, pitchModifier)

    -- Create camera direction state with smoothed values
    local cameraDirectionState = {
        -- Smooth camera position
        px = CameraCommons.smoothStep(STATE.tracking.lastCamPos.x, camPos.x, smoothFactor),
        py = CameraCommons.smoothStep(STATE.tracking.lastCamPos.y, camPos.y, smoothFactor),
        pz = CameraCommons.smoothStep(STATE.tracking.lastCamPos.z, camPos.z, smoothFactor),

        -- Smooth direction vector
        dx = CameraCommons.smoothStep(STATE.tracking.lastCamDir.x, lookDir.dx, smoothFactor),
        dy = CameraCommons.smoothStep(STATE.tracking.lastCamDir.y, lookDir.dy, smoothFactor),
        dz = CameraCommons.smoothStep(STATE.tracking.lastCamDir.z, lookDir.dz, smoothFactor),

        -- Smooth rotations
        rx = CameraCommons.smoothStep(STATE.tracking.lastRotation.rx, lookDir.rx, rotFactor),
        ry = CameraCommons.smoothStepAngle(STATE.tracking.lastRotation.ry, lookDir.ry, rotFactor),
        rz = 0
    }

    return cameraDirectionState
end

--- Calculates camera direction and rotation to look at a point
---@param camPos table Camera position {x, y, z}
---@param targetPos table Target position {x, y, z}
---@return table direction and rotation values
function CameraCommons.calculateCameraDirectionToThePoint(camPos, targetPos, pitchModifier)
    -- 1.65 looks at target. 1.8 above target
    pitchModifier = pitchModifier or 1.65

    -- Calculate direction vector from camera to target
    local dirX = targetPos.x - (camPos.x or camPos.px)
    local dirY = targetPos.y - (camPos.y or camPos.py)
    local dirZ = targetPos.z - (camPos.z or camPos.pz)

    -- Normalize the direction vector
    local length = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)
    if length > 0 then
        dirX = dirX / length
        dirY = dirY / length
        dirZ = dirZ / length
    end

    -- Calculate appropriate rotation for FPS camera
    local ry = -math.atan2(dirX, dirZ) - math.pi

    -- Calculate pitch (rx)
    local horizontalLength = math.sqrt(dirX * dirX + dirZ * dirZ)
    local rx = -((math.atan2(dirY, horizontalLength) - math.pi) / pitchModifier)

    return {
        dx = dirX,
        dy = dirY,
        dz = dirZ,
        rx = rx,
        ry = ry,
        rz = 0
    }
end

--- Smoothly interpolates between current and target values
---@param current number|nil Current value
---@param target number|nil Target value
---@param factor number Smoothing factor (0.0-1.0)
---@return number smoothed value
function CameraCommons.smoothStep(current, target, factor)
    if current == nil or target == nil or factor == nil then
        return current or target or 0
    end
    return current + (target - current) * factor
end

--- Smoothly interpolates between angles
---@param current number|nil Current angle (in radians)
---@param target number|nil Target angle (in radians)
---@param factor number Smoothing factor (0.0-1.0)
---@return number smoothed angle
function CameraCommons.smoothStepAngle(current, target, factor)
    if current == nil or target == nil or factor == nil then
        return current or target or 0 -- Return whichever is not nil, or 0 if both are nil
    end

    -- Normalize both angles to -pi to pi range
    current = CameraCommons.normalizeAngle(current)
    target = CameraCommons.normalizeAngle(target)

    -- Find the shortest path
    local diff = target - current

    -- If the difference is greater than pi, we need to go the other way around
    if diff > math.pi then
        diff = diff - 2 * math.pi
    elseif diff < -math.pi then
        diff = diff + 2 * math.pi
    end

    return current + diff * factor
end

--- Normalizes an angle to be within -pi to pi range
---@param angle number|nil Angle to normalize (in radians)
---@return number normalized angle
function CameraCommons.normalizeAngle(angle)
    if angle == nil then
        return 0 -- Default to 0 if angle is nil
    end

    local twoPi = 2 * math.pi
    angle = angle % twoPi
    if angle > math.pi then
        angle = angle - twoPi
    end
    return angle
end

function CameraCommons.convertSpringToFPSCameraState(camState)
    if camState.mode ~= 2 then
        return camState
    end

    local fpsState = {}

    -- Copy basic properties
    fpsState.mode = 0  -- FPS mode
    fpsState.name = "fps"
    fpsState.fov = camState.fov or 45

    -- Get direction vector
    local dirX = camState.dx or 0
    local dirY = camState.dy or 0
    local dirZ = camState.dz or 0

    -- Normalize direction
    local dirLen = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)
    if dirLen > 0 then
        dirX, dirY, dirZ = dirX / dirLen, dirY / dirLen, dirZ / dirLen
    end

    -- Calculate the actual camera position using the same logic as CSpringController::GetPos()
    local dist = camState.dist or 0
    local actualX = camState.px - (dirX * dist)
    local actualY = camState.py - (dirY * dist)
    local actualZ = camState.pz - (dirZ * dist)

    -- Use this actual position for the FPS camera
    fpsState.px = actualX
    fpsState.py = actualY
    fpsState.pz = actualZ

    -- Fix rotation calculation - we need to either invert the direction
    -- or adjust the angles to account for camera direction conventions
    -- Try adding pi (180 degrees) to the y-rotation to flip the camera direction
    fpsState.rx = math.atan2(math.sqrt(dirX * dirX + dirZ * dirZ), dirY)
    fpsState.ry = math.atan2(dirX, dirZ) + math.pi
    fpsState.rz = 0

    -- Normalize ry to keep it in the range [-π, π]
    while fpsState.ry > math.pi do fpsState.ry = fpsState.ry - 2 * math.pi end
    while fpsState.ry < -math.pi do fpsState.ry = fpsState.ry + 2 * math.pi end

    -- Copy any additional properties that might be needed
    fpsState.vx = camState.vx or 0
    fpsState.vy = camState.vy or 0
    fpsState.vz = camState.vz or 0

    return fpsState
end

return {
    CameraCommons = CameraCommons
}