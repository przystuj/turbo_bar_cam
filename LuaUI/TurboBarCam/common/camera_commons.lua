---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local TransitionManager = ModuleManager.TransitionManager(function(m) TransitionManager = m end)

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
    if TransitionManager.isTransitioning() then
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

function CameraCommons.linear(t)
    return t
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

function CameraCommons.dipAndReturn(t, dipTarget)
    if t < 0.5 then
        -- Animate from 1.0 down to dipTarget
        -- Normalize t for the first half: [0, 0.5) -> [0, 1.0)
        local normalizedT = t * 2
        local easedT = CameraCommons.easeInOut(normalizedT)
        return 1.0 - (1.0 - dipTarget) * easedT
    else
        -- Animate from dipTarget back up to 1.0
        -- Normalize t for the second half: [0.5, 1.0] -> [0, 1.0]
        local normalizedT = (t - 0.5) * 2
        local easedT = CameraCommons.easeInOut(normalizedT)
        return dipTarget + (1.0 - dipTarget) * easedT
    end
end

--- @deprecated
--- Adjusts smoothing factors based on the current mode transition progress.
--- Reads progress from STATE.mode.transitionProgress.
---@param targetPosSmoothingFactor number The target position smoothing factor.
---@param targetRotSmoothingFactor number The target rotation smoothing factor.
---@return number posSmoothFactor Adjusted position smoothing factor.
---@return number rotSmoothFactor Adjusted rotation smoothing factor.
function CameraCommons.handleModeTransition(targetPosSmoothingFactor, targetRotSmoothingFactor)
    local progress = STATE.mode.transitionProgress

    if not progress then
        -- No transition in progress, or it's finished, return full factors.
        return targetPosSmoothingFactor, targetRotSmoothingFactor
    end

    -- A transition is active, interpolate the factors based on its progress.
    local posSmoothFactor = targetPosSmoothingFactor * progress
    local rotSmoothFactor = targetRotSmoothingFactor * progress

    return posSmoothFactor, rotSmoothFactor
end

--- Calculate the camera's actual position for this frame by interpolating from the last known position.
---@param camPos table The target/ideal camera position for this frame.
---@param smoothingFactor number Smoothing factor for camera position interpolation.
---@return table The new camera state {x,y,z}.
function CameraCommons.interpolateToPoint(camPos, smoothingFactor)
    -- Calculate the camera's actual position for this frame by interpolating from the last known position.
    local currentFrameActualPx = CameraCommons.lerp(STATE.mode.lastCamPos.x, camPos.x or camPos.px, smoothingFactor)
    local currentFrameActualPy = CameraCommons.lerp(STATE.mode.lastCamPos.y, camPos.y or camPos.py, smoothingFactor)
    local currentFrameActualPz = CameraCommons.lerp(STATE.mode.lastCamPos.z, camPos.z or camPos.pz, smoothingFactor)
    return { x = currentFrameActualPx, y = currentFrameActualPy, z = currentFrameActualPz }
end

--- Focuses camera on a point with appropriate smoothing.
--- The camera's actual position for the current frame is first calculated by lerping from its previous position.
--- Then, the look direction is determined from this new actual position towards the target point.
--- Finally, the camera's orientation is lerped towards this calculated look direction.
---@param camPos table The target/ideal camera position {x, y, z} for this frame (e.g., after rampUpFactor).
---@param targetPos table The target look-at position {x, y, z}.
---@param posFactor number Smoothing factor for camera position interpolation.
---@param rotFactor number Smoothing factor for camera orientation (direction and rotation) interpolation.
---@return table cameraDirectionState The new camera state {px,py,pz, dx,dy,dz, rx,ry,rz}.
function CameraCommons.focusOnPoint(camPos, targetPos, posFactor, rotFactor)
    -- Calculate the camera's actual position for this frame by interpolating from the last known position.
    local currentFrameActualPosition = CameraCommons.interpolateToPoint(camPos, posFactor)

    -- Calculate the ideal look direction and rotation from the camera's actual position for this frame to the target point.
    local lookDirFromActualPos = CameraCommons.calculateCameraDirectionToThePoint(currentFrameActualPosition, targetPos)

    -- Construct the new camera state.
    local cameraDirectionState = {
        -- Set the camera's actual position for this frame.
        px = currentFrameActualPosition.x,
        py = currentFrameActualPosition.y,
        pz = currentFrameActualPosition.z,

        -- Smooth the direction vector towards the look direction calculated from the actual current position.
        dx = CameraCommons.lerp(STATE.mode.lastCamDir.x, lookDirFromActualPos.dx, rotFactor),
        dy = CameraCommons.lerp(STATE.mode.lastCamDir.y, lookDirFromActualPos.dy, rotFactor),
        dz = CameraCommons.lerp(STATE.mode.lastCamDir.z, lookDirFromActualPos.dz, rotFactor),

        -- Smooth the rotation angles towards those derived from the look direction calculated from the actual current position.
        rx = CameraCommons.lerp(STATE.mode.lastRotation.rx, lookDirFromActualPos.rx, rotFactor),
        ry = CameraCommons.lerpAngle(STATE.mode.lastRotation.ry, lookDirFromActualPos.ry, rotFactor),
        rz = 0 -- Assuming roll is always 0 for this camera mode.
    }

    return cameraDirectionState
end

--- Calculates camera direction vector and rotation angles to look from camPos to targetPos.
--- Uses engine conventions for pitch and yaw.
---
---@param camPos table Camera position {x, y, z} or {px, py, pz}.
---@param targetPos table Target position {x, y, z}.
---@return table A table containing:
---             dx (number): X component of the normalized direction vector.
---             dy (number): Y component of the normalized direction vector.
---             dz (number): Z component of the normalized direction vector.
---             rx (number): Pitch angle in radians (angle from +Y axis, range [0, PI]).
---             ry (number): Yaw angle in radians (angle in XZ plane, 0 towards -Z, range [-PI, PI]).
---             rz (number): Roll angle in radians (always 0).
function CameraCommons.calculateCameraDirectionToThePoint(camPos, targetPos)
    local cX = camPos.x or camPos.px
    local cY = camPos.y or camPos.py
    local cZ = camPos.z or camPos.pz

    local dirX = targetPos.x - cX
    local dirY = targetPos.y - cY
    local dirZ = targetPos.z - cZ

    local length = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)

    if length < 0.00001 then
        -- Use a small epsilon for floating point comparison
        -- Camera is at the target, direction is undefined.
        -- Fallback to a default direction (looking along -Z axis in world space)
        -- and calculate consistent rotation for it based on engine math.
        -- For dir = {0,0,-1}:
        -- rx (pitch) = acos(dirY) = acos(0) = PI/2
        -- ry (yaw)   = atan2(dirX, -dirZ) = atan2(0, -(-1)) = atan2(0,1) = 0
        return {
            dx = 0,
            dy = 0,
            dz = -1, -- Default direction
            rx = math.pi / 2, -- Pitch for this direction
            ry = 0, -- Yaw for this direction
            rz = 0            -- Roll is typically 0
        }
    end

    -- Normalize the direction vector
    dirX = dirX / length
    dirY = dirY / length
    dirZ = dirZ / length

    -- Calculate rotation angles based on CCamera::GetRotFromDir(fwd)
    -- where fwd = {dirX, dirY, dirZ}:
    -- r.x = math::acos(fwd.y);          (Pitch)
    -- r.y = math::atan2(fwd.x, -fwd.z); (Yaw)

    local rx = math.acos(dirY) -- Pitch: angle from positive Y-axis. Range [0, PI].
    -- Clamping dirY to [-1, 1] for acos robustness if needed,
    -- but normalized dirY should already be in this range.
    -- rx = math.acos(math.max(-1.0, math.min(1.0, dirY)))


    local ry = math.atan2(dirX, -dirZ) -- Yaw: angle in XZ plane.
    -- 0 means horizontal component is along -Z.
    -- Range [-PI, PI].

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
function CameraCommons.lerp(current, target, factor)
    if current == nil or target == nil or factor == nil then
        return current or target
    end
    return current + (target - current) * factor
end

--- Smoothly interpolates between angles
---@param current number|nil Current angle (in radians)
---@param target number|nil Target angle (in radians)
---@param factor number Smoothing factor (0.0-1.0)
---@return number smoothed angle
function CameraCommons.lerpAngle(current, target, factor)
    if current == nil or target == nil or factor == nil then
        return current or target
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
        Log:trace("Boundary detected, positioning camera behind unit")
    else
        -- Normal positioning in front of unit
        camState.pz = forwardPosition
        Log:trace("Normal positioning in front of unit")
    end
    return camState
end

--- Converts rotation angles (pitch, yaw) into a normalized direction vector.
--- The engine's convention is used:
--- Pitch is the angle from the positive Y-axis.
--- Yaw is the angle in the XZ plane, measured from the -Z axis towards the +X axis.
--- Roll (rz) is ignored for calculating the forward direction vector.
---
---@param rx number Pitch angle in radians.
---                 0 looks along +Y (up), PI/2 is horizontal, PI looks along -Y (down).
---@param ry number Yaw angle in radians.
---                 0 means the horizontal component of direction is along -Z.
---                 PI/2 means the horizontal component of direction is along +X.
---@param rz number|nil Roll angle in radians (optional, ignored for the forward vector).
---@return table Direction vector {x, y, z}, normalized.
function CameraCommons.getDirectionFromRotation(rx, ry, rz)
    -- Default angles to 0 if nil, matching original behavior.
    rx = rx or 0
    ry = ry or 0
    -- rz is passed but not used in the C++ GetFwdFromRot for the forward vector calculation.

    local sin_rx = math.sin(rx)
    local cos_rx = math.cos(rx)
    local sin_ry = math.sin(ry)
    local cos_ry = math.cos(ry)

    -- This calculation matches CCamera::GetFwdFromRot(const float3& r)
    -- where r.x is pitch and r.y is yaw:
    -- fwd.x = std::sin(r.x) * std::sin(r.y);
    -- fwd.y = std::cos(r.x);
    -- fwd.z = std::sin(r.x) * (-std::cos(r.y));
    local dx = sin_rx * sin_ry
    local dy = cos_rx
    local dz = -sin_rx * cos_ry

    return CameraCommons.normalizeVector({ x = dx, y = dy, z = dz })
end

return CameraCommons