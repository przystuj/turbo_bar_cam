---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log

local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG

---@class CameraCommons
local CameraCommons = {}

-- Vector Helper Functions
function CameraCommons.vectorAdd(v1, v2) return { x = (v1.x or 0) + (v2.x or 0), y = (v1.y or 0) + (v2.y or 0), z = (v1.z or 0) + (v2.z or 0) } end
function CameraCommons.vectorSubtract(v1, v2) return { x = (v1.x or 0) - (v2.x or 0), y = (v1.y or 0) - (v2.y or 0), z = (v1.z or 0) - (v2.z or 0) } end
function CameraCommons.vectorMultiply(v, scalar) return { x = (v.x or 0) * scalar, y = (v.y or 0) * scalar, z = (v.z or 0) * scalar } end
function CameraCommons.vectorMagnitudeSq(v) local x,y,z = v.x or 0, v.y or 0, v.z or 0 return x*x+y*y+z*z end
function CameraCommons.vectorMagnitude(v) return math.sqrt(CameraCommons.vectorMagnitudeSq(v)) end
function CameraCommons.normalizeVector(v)
    local mag = CameraCommons.vectorMagnitude(v)
    if mag > 0.0001 then return CameraCommons.vectorMultiply(v, 1 / mag) end
    return { x = 0, y = 0, z = 0 }
end
function CameraCommons.dotProduct(v1, v2) return (v1.x or 0) * (v2.x or 0) + (v1.y or 0) * (v2.y or 0) + (v1.z or 0) * (v2.z or 0) end

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

function CameraCommons.getDefaultUnitView(x, z)
    local camState = {
        mode = 0, -- FPS camera mode
        name = "fps",
        fov = 45
    }

    local cameraHeight = 1280
    local offsetDistance = 1024
    local lookdownAngle = 2.4

    -- Set common camera properties
    camState.px = x
    camState.py = cameraHeight
    camState.rx = lookdownAngle
    camState.ry = 0

    -- Check if forward position would exceed map boundaries
    local forwardPosition = z + offsetDistance
    if forwardPosition >= Game.mapSizeZ * 0.95 then
        camState.pz = z - offsetDistance
        camState.ry = camState.ry + math.pi -- Rotate 180 degrees
        Log.trace("Boundary detected, positioning camera behind unit")
    else
        -- Normal positioning in front of unit
        camState.pz = forwardPosition
        Log.trace("Normal positioning in front of unit")
    end
    return camState
end

--- Performs Spherical Linear Interpolation between two 3D vectors (positions/offsets relative to a center)
--- Treats vectors as points on a sphere for interpolation path, lerps magnitude separately.
---@param vStart table Start vector {x, y, z}
---@param vEnd table End vector {x, y, z}
---@param t number Interpolation factor (0.0 to 1.0)
---@return table Interpolated vector {x, y, z}
function CameraCommons.slerpVectors(vStart, vEnd, t)
    local magStart = CameraCommons.vectorMagnitude(vStart)
    local magEnd = CameraCommons.vectorMagnitude(vEnd)

    -- Handle edge cases: zero vectors, identical vectors, or near-zero magnitude
    local startMagSq = CameraCommons.vectorMagnitudeSq(vStart)
    local endMagSq = CameraCommons.vectorMagnitudeSq(vEnd)
    local vectorsAreSame = (math.abs(vStart.x - vEnd.x) < 0.001 and math.abs(vStart.y - vEnd.y) < 0.001 and math.abs(vStart.z - vEnd.z) < 0.001)

    if startMagSq < 0.0001 or endMagSq < 0.0001 or vectorsAreSame then
        -- Fallback to LERP for position if vectors are too small, identical, or one is zero
        return {
            x = CameraCommons.lerp(vStart.x or 0, vEnd.x or 0, t),
            y = CameraCommons.lerp(vStart.y or 0, vEnd.y or 0, t),
            z = CameraCommons.lerp(vStart.z or 0, vEnd.z or 0, t)
        }
    end

    local vStartNorm = CameraCommons.normalizeVector(vStart)
    local vEndNorm = CameraCommons.normalizeVector(vEnd)

    -- Calculate the angle between the normalized vectors
    local dot = CameraCommons.dotProduct(vStartNorm, vEndNorm)
    dot = math.max(-1.0, math.min(1.0, dot)) -- Clamp for potential floating point inaccuracies
    local theta_0 = math.acos(dot) -- Total angle between vectors

    -- If angle is very small, linear interpolation is fine (and avoids division by zero in sin)
    if math.abs(theta_0) < 0.01 then
        return {
            x = CameraCommons.lerp(vStart.x or 0, vEnd.x or 0, t),
            y = CameraCommons.lerp(vStart.y or 0, vEnd.y or 0, t),
            z = CameraCommons.lerp(vStart.z or 0, vEnd.z or 0, t)
        }
    end

    local sin_theta_0 = math.sin(theta_0)
    local theta = theta_0 * t -- Angle for interpolation step

    -- Calculate scale factors using the SLERP formula
    local scaleStart = math.sin(theta_0 * (1.0 - t)) / sin_theta_0
    local scaleEnd = math.sin(theta) / sin_theta_0

    -- Calculate interpolated direction (normalized vectors scaled and added)
    local interpolatedDir = CameraCommons.vectorAdd(
            CameraCommons.vectorMultiply(vStartNorm, scaleStart),
            CameraCommons.vectorMultiply(vEndNorm, scaleEnd)
    )

    -- Interpolate magnitude linearly
    local interpolatedMag = CameraCommons.lerp(magStart, magEnd, t)

    -- Scale the interpolated direction by the interpolated magnitude
    return CameraCommons.vectorMultiply(interpolatedDir, interpolatedMag)
end

return {
    CameraCommons = CameraCommons
}