---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager

--- A library of utility functions for working with quaternions.
---@class QuaternionUtils
local QuaternionUtils = {}

-- Helper to scale the vector part of a pure quaternion by a scalar.
local function scalePureQuaternion(q, s)
    return { w = 0, x = q.x * s, y = q.y * s, z = q.z * s }
end

function QuaternionUtils.identity()
    return { x = 0, y = 0, z = 0, w = 1 }
end

function QuaternionUtils.dot(q1, q2)
    return q1.w * q2.w + q1.x * q2.x + q1.y * q2.y + q1.z * q2.z
end

function QuaternionUtils.multiply(q1, q2)
    return {
        w = q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z,
        x = q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
        y = q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
        z = q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w
    }
end

function QuaternionUtils.fromEuler(rx, ry)
    local standardPitch = rx - (math.pi / 2)
    local halfPitch = standardPitch * 0.5
    local halfYaw = ry * 0.5
    local cosPitch, sinPitch = math.cos(halfPitch), math.sin(halfPitch)
    local cosYaw, sinYaw = math.cos(halfYaw), math.sin(halfYaw)
    local qx = { x = sinPitch, y = 0, z = 0, w = cosPitch }
    local qy = { x = 0, y = sinYaw, z = 0, w = cosYaw }
    return QuaternionUtils.multiply(qy, qx)
end

function QuaternionUtils.toEuler(q)
    local standardPitch, yaw
    local sinP = 2 * (q.w * q.x - q.y * q.z)

    if math.abs(sinP) >= 0.99999 then
        standardPitch = (math.pi / 2) * (sinP > 0 and 1 or -1)
        yaw = 2 * math.atan2(q.y, q.w)
    else
        standardPitch = math.asin(sinP)
        local sinY = 2 * (q.w * q.y + q.x * q.z)
        local cosY = 1 - 2 * (q.x * q.x + q.y * q.y)
        yaw = math.atan2(sinY, cosY)
    end

    local engineRx = standardPitch + (math.pi / 2)
    return engineRx, yaw
end

function QuaternionUtils.inverse(q)
    return { x = -q.x, y = -q.y, z = -q.z, w = q.w }
end

function QuaternionUtils.normalize(q)
    local mag = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    if mag < 0.00001 then
        return QuaternionUtils.identity()
    end
    return { x = q.x / mag, y = q.y / mag, z = q.z / mag, w = q.w / mag }
end

function QuaternionUtils.slerp(q1, q2, t)
    if t <= 0 then return q1 end
    if t >= 1 then return q2 end

    local cosHalfTheta = QuaternionUtils.dot(q1, q2)
    local q2_temp = q2

    if cosHalfTheta < 0 then
        q2_temp = { x = -q2.x, y = -q2.y, z = -q2.z, w = -q2.w }
        cosHalfTheta = -cosHalfTheta
    end

    if cosHalfTheta > 0.9999 then
        return QuaternionUtils.normalize({
            w = q1.w + t * (q2_temp.w - q1.w),
            x = q1.x + t * (q2_temp.x - q1.x),
            y = q1.y + t * (q2_temp.y - q1.y),
            z = q1.z + t * (q2_temp.z - q1.z),
        })
    end

    local halfTheta = math.acos(cosHalfTheta)
    local sinHalfTheta = math.sqrt(1.0 - cosHalfTheta * cosHalfTheta)

    if math.abs(sinHalfTheta) < 0.001 then return q1 end

    local ratioA = math.sin((1 - t) * halfTheta) / sinHalfTheta
    local ratioB = math.sin(t * halfTheta) / sinHalfTheta

    return QuaternionUtils.normalize({
        w = (q1.w * ratioA + q2_temp.w * ratioB),
        x = (q1.x * ratioA + q2_temp.x * ratioB),
        y = (q1.y * ratioA + q2_temp.y * ratioB),
        z = (q1.z * ratioA + q2_temp.z * ratioB),
    })
end

function QuaternionUtils.log(q)
    local w = q.w
    if w > 0.99999 then
        return { w = 0, x = 0, y = 0, z = 0 }
    end

    local vMagSq = q.x*q.x + q.y*q.y + q.z*q.z
    local vMag = math.sqrt(vMagSq)

    if vMag < 0.00001 then
        return { w = 0, x = 0, y = 0, z = 0 }
    end

    local halfAngle = math.atan2(vMag, w)

    return scalePureQuaternion({w=0, x=q.x, y=q.y, z=q.z}, halfAngle / vMag)
end

function QuaternionUtils.exp(q)
    local halfAngle = math.sqrt(q.x*q.x + q.y*q.y + q.z*q.z)

    if halfAngle < 0.00001 then return QuaternionUtils.identity() end

    local w = math.cos(halfAngle)
    local s = math.sin(halfAngle) / halfAngle

    return { w = w, x = q.x * s, y = q.y * s, z = q.z * s }
end

--- Smoothly dampens a quaternion towards a target orientation using a stable, framerate-independent
--- spring-damper model.
--- Modifies the angular_velocity_ref table in place.
---@param current table The current quaternion {x, y, z, w}.
---@param target table The target quaternion {x, y, z, w}.
---@param angularVelocityRef table A table holding the current angular velocity {x, y, z}, passed by reference.
---@param smoothTime number The approximate time to reach the target. A smaller value will reach the target faster.
---@param dt number The delta time for this frame.
---@return table The new smoothed quaternion for this frame.
function QuaternionUtils.quaternionSmoothDamp(current, target, angularVelocityRef, smoothTime, dt)
    -- 1. Ensure we are rotating along the shortest path.
    -- Quaternions q and -q represent the same rotation, but the interpolation path will differ.
    local target_aligned = target
    if QuaternionUtils.dot(current, target) < 0.0 then
        target_aligned = { w = -target.w, x = -target.x, y = -target.y, z = -target.z }
    end

    -- 2. Convert the rotation difference to a rotation vector (in axis-angle format).
    -- This vector represents the "change" we need to make.
    local error_q = QuaternionUtils.multiply(target_aligned, QuaternionUtils.inverse(current))
    local change_vec = QuaternionUtils.log(error_q)

    -- 3. Use the same stable, critically damped spring math from MathUtils.vectorSmoothDamp.
    -- We are damping the angular velocity towards zero to correct for the `change_vec` error.
    local omega = 2.0 / smoothTime
    local x = omega * dt
    local exp = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)

    -- 4. Calculate the damped velocity and the new offset for this frame.
    local temp_x = (angularVelocityRef.x + omega * change_vec.x) * dt
    local temp_y = (angularVelocityRef.y + omega * change_vec.y) * dt
    local temp_z = (angularVelocityRef.z + omega * change_vec.z) * dt

    -- Update angular velocity for next frame (the "in place" modification)
    angularVelocityRef.x = (angularVelocityRef.x - omega * temp_x) * exp
    angularVelocityRef.y = (angularVelocityRef.y - omega * temp_y) * exp
    angularVelocityRef.z = (angularVelocityRef.z - omega * temp_z) * exp

    -- Calculate the rotation to apply this frame to move towards the target
    local offset_vec = {
        x = (change_vec.x + temp_x) * exp,
        y = (change_vec.y + temp_y) * exp,
        z = (change_vec.z + temp_z) * exp,
    }

    -- 5. Convert the resulting rotation vector back to a quaternion and apply it to the current orientation.
    local delta_rot = QuaternionUtils.exp(offset_vec)
    return QuaternionUtils.multiply(delta_rot, current)
end


return QuaternionUtils