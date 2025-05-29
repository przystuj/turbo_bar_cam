---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log

local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG

---@class CameraCommons
local CameraCommons = {}

-- Vector Helper Functions
function CameraCommons.vectorAdd(v1, v2)
    return { x = (v1.x or 0) + (v2.x or 0), y = (v1.y or 0) + (v2.y or 0), z = (v1.z or 0) + (v2.z or 0) }
end
function CameraCommons.vectorSubtract(v1, v2)
    return { x = (v1.x or 0) - (v2.x or 0), y = (v1.y or 0) - (v2.y or 0), z = (v1.z or 0) - (v2.z or 0) }
end
function CameraCommons.vectorMultiply(v, scalar)
    return { x = (v.x or 0) * scalar, y = (v.y or 0) * scalar, z = (v.z or 0) * scalar }
end
function CameraCommons.vectorMagnitudeSq(v)
    local x, y, z = v.x or 0, v.y or 0, v.z or 0
    return x * x + y * y + z * z
end
function CameraCommons.vectorMagnitude(v)
    return math.sqrt(CameraCommons.vectorMagnitudeSq(v))
end
function CameraCommons.normalizeVector(v)
    local mag = CameraCommons.vectorMagnitude(v)
    if mag > 0.0001 then
        return CameraCommons.vectorMultiply(v, 1 / mag)
    end
    return { x = 0, y = 0, z = 0 }
end
function CameraCommons.dotProduct(v1, v2)
    return (v1.x or 0) * (v2.x or 0) + (v1.y or 0) * (v2.y or 0) + (v1.z or 0) * (v2.z or 0)
end
--- Calculates the cross product of two vectors
---@param v1 table Vector {x, y, z}
---@param v2 table Vector {x, y, z}
---@return table Cross product vector {x, y, z}
function CameraCommons.crossProduct(v1, v2)
    return {
        x = (v1.y or 0) * (v2.z or 0) - (v1.z or 0) * (v2.y or 0),
        y = (v1.z or 0) * (v2.x or 0) - (v1.x or 0) * (v2.z or 0),
        z = (v1.x or 0) * (v2.y or 0) - (v1.y or 0) * (v2.x or 0)
    }
end

--- Linear interpolation between two values
---@param a number Start value
---@param b number End value
---@param t number Interpolation factor (0.0-1.0)
---@return number interpolated value
function CameraCommons.lerp(a, b, t)
    return a + (b - a) * t
end

function CameraCommons.sphericalInterpolate(center, startPos, endPos, factor, preserveHeight)
    -- If preserveHeight is true, we'll maintain the Y component's relative position
    local preserveY = preserveHeight or false

    -- Calculate vectors from center
    local startVec = CameraCommons.vectorSubtract(startPos, center)
    local endVec = CameraCommons.vectorSubtract(endPos, center)

    -- Save initial heights if preserving
    local startRelativeY = startVec.y
    local endRelativeY = endVec.y

    -- For height preservation, use XZ plane for spherical calculation
    if preserveY then
        -- Zero out Y components for direction calculation
        startVec.y = 0
        endVec.y = 0
    end

    -- Get the distances (in XZ plane if preserving height)
    local startDist = CameraCommons.vectorMagnitude(startVec)
    local endDist = CameraCommons.vectorMagnitude(endVec)

    -- Normalize vectors
    local startDir = CameraCommons.normalizeVector(startVec)
    local endDir = CameraCommons.normalizeVector(endVec)

    -- Calculate dot product
    local dot = CameraCommons.dotProduct(startDir, endDir)
    dot = math.max(-0.99, math.min(0.99, dot)) -- Clamp to avoid numerical issues

    -- If vectors are nearly identical or factor is 1, use linear interpolation
    if dot > 0.99 or factor >= 1 then
        return {
            x = startPos.x + (endPos.x - startPos.x) * factor,
            y = startPos.y + (endPos.y - startPos.y) * factor,
            z = startPos.z + (endPos.z - startPos.z) * factor
        }
    end

    -- Calculate angle and slerp weights
    local angle = math.acos(dot)
    local sinAngle = math.sin(angle)

    local w1 = math.sin((1 - factor) * angle) / sinAngle
    local w2 = math.sin(factor * angle) / sinAngle

    -- Interpolate direction
    local resultDir = {
        x = startDir.x * w1 + endDir.x * w2,
        y = startDir.y * w1 + endDir.y * w2,
        z = startDir.z * w1 + endDir.z * w2
    }
    resultDir = CameraCommons.normalizeVector(resultDir)

    -- Interpolate distance
    local resultDist = startDist * (1 - factor) + endDist * factor

    -- Calculate interpolated position
    local result = {
        x = center.x + resultDir.x * resultDist,
        y = 0, -- Will be set below
        z = center.z + resultDir.z * resultDist
    }

    -- Handle Y component based on preserveHeight option
    if preserveY then
        -- Linearly interpolate the relative height
        local relativeY = startRelativeY * (1 - factor) + endRelativeY * factor
        result.y = center.y + relativeY
    else
        -- Use spherical interpolation for Y as well
        result.y = center.y + resultDir.y * resultDist
    end

    return result
end

function CameraCommons.shouldUseSphericalInterpolation(currentPos, targetPos, center)
    if STATE.tracking.isModeTransitionInProgress then
        return false
    end

    -- Calculate direction vectors from center (in XZ plane)
    local currentVec = {
        x = currentPos.x - center.x,
        z = currentPos.z - center.z
    }
    local newVec = {
        x = targetPos.x - center.x,
        z = targetPos.z - center.z
    }

    -- Normalize 2D vectors
    local currentLength = math.sqrt(currentVec.x * currentVec.x + currentVec.z * currentVec.z)
    local newLength = math.sqrt(newVec.x * newVec.x + newVec.z * newVec.z)

    if currentLength > 0.001 and newLength > 0.001 then
        currentVec.x = currentVec.x / currentLength
        currentVec.z = currentVec.z / currentLength

        newVec.x = newVec.x / newLength
        newVec.z = newVec.z / newLength

        -- Calculate dot product
        local dot = currentVec.x * newVec.x + currentVec.z * newVec.z

        -- Return true if angle is significant (dot < 0.7 is roughly > 45 degrees)
        return dot < 0.7
    end

    return false
end

--- Checks if a transition has completed
---@return boolean hasCompleted True if transition is complete
function CameraCommons.isTransitionComplete()
    return CameraCommons.getTransitionProgress() == 1
end

function CameraCommons.easeIn(t)
    return t * t * t
end

function CameraCommons.easeOut(t)
    local t2 = t - 1
    return t2 * t2 * t2 + 1
end

function CameraCommons.easeInOut(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local p = -2 * t + 2
        return 1 - (p * p * p) / 2
    end
end

--- Adjusts smoothing factors based on the current mode transition progress.
--- Reads progress from STATE.tracking.transitionProgress.
---@param targetPosSmoothingFactor number The target position smoothing factor.
---@param targetRotSmoothingFactor number The target rotation smoothing factor.
---@return number posSmoothFactor Adjusted position smoothing factor.
---@return number rotSmoothFactor Adjusted rotation smoothing factor.
function CameraCommons.handleModeTransition(targetPosSmoothingFactor, targetRotSmoothingFactor)
    local progress = STATE.tracking.transitionProgress

    if not progress then
        -- No transition in progress, or it's finished, return full factors.
        return targetPosSmoothingFactor, targetRotSmoothingFactor
    end

    -- A transition is active, interpolate the factors based on its progress.
    local posSmoothFactor = targetPosSmoothingFactor * progress
    local rotSmoothFactor = targetRotSmoothingFactor * progress

    return posSmoothFactor, rotSmoothFactor
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
    while fpsState.ry > math.pi do
        fpsState.ry = fpsState.ry - 2 * math.pi
    end
    while fpsState.ry < -math.pi do
        fpsState.ry = fpsState.ry + 2 * math.pi
    end

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

--- Converts rotation angles (pitch, yaw) into a normalized direction vector.
--- Assumes FPS-style camera where roll (rz) is ignored for direction.
---@param rx number Pitch angle (rotation around X-axis) in radians.
---@param ry number Yaw angle (rotation around Y-axis) in radians.
---@param rz number|nil Roll angle (optional, currently ignored).
---@return table Direction vector {x, y, z}.
function CameraCommons.getDirectionFromRotation(rx, ry, rz)
    -- Ensure we have valid angles, default to 0 if nil
    rx = rx or 0
    ry = ry or 0
    -- rz = rz or 0 -- We ignore roll (rz) for the direction vector itself.

    local cos_rx = math.cos(rx)
    local sin_rx = math.sin(rx)
    local cos_ry = math.cos(ry)
    local sin_ry = math.sin(ry)

    -- Calculate direction based on standard Euler-to-Vector conversion (Y-up)
    -- Note: The exact formula can depend on the engine's coordinate system
    -- and how ry=0 and rx=0 is defined. This assumes ry=0 looks down -Z.
    -- If your camera looks down +Z or +X at ry=0, these might need swapping/negating.
    -- This matches the 'dx = sin(ry)*cos(rx)', 'dy = -sin(rx)', 'dz = -cos(ry)*cos(rx)' pattern
    local dx = cos_rx * sin_ry
    local dy = -sin_rx
    local dz = -cos_rx * cos_ry

    -- The result should inherently be normalized if rx/ry are standard,
    -- but normalizing here ensures it.
    return CameraCommons.normalizeVector({ x = dx, y = dy, z = dz })
end

return {
    CameraCommons = CameraCommons
}