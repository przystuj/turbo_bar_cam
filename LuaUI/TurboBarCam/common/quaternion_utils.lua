---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local Util = ModuleManager.Util(function(m) Util = m end)

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

    local v_mag_sq = q.x*q.x + q.y*q.y + q.z*q.z
    local v_mag = math.sqrt(v_mag_sq)

    if v_mag < 0.00001 then
        return { w = 0, x = 0, y = 0, z = 0 }
    end

    local half_angle = math.atan2(v_mag, w)

    return scalePureQuaternion({w=0, x=q.x, y=q.y, z=q.z}, half_angle / v_mag)
end

function QuaternionUtils.exp(q)
    local half_angle = math.sqrt(q.x*q.x + q.y*q.y + q.z*q.z)

    if half_angle < 0.00001 then return QuaternionUtils.identity() end

    local w = math.cos(half_angle)
    local s = math.sin(half_angle) / half_angle

    return { w = w, x = q.x * s, y = q.y * s, z = q.z * s }
end

--- Smoothly dampens a quaternion towards a target orientation.
--- Modifies the angular_velocity_ref table in place.
function QuaternionUtils.quaternionSmoothDamp(current, target, angular_velocity_ref, smoothTime, maxSpeed, dt)
    local error_q = QuaternionUtils.multiply(target, QuaternionUtils.inverse(current))
    local error_vec = QuaternionUtils.log(error_q)

    local target_vec = {x = 0, y = 0, z = 0}

    -- We want to smoothly dampen the error vector to zero.
    -- The velocity we are damping is the angular velocity.
    local damped_error_vec = Util.vectorSmoothDamp(error_vec, target_vec, angular_velocity_ref, smoothTime, maxSpeed, dt)

    -- The result of the damping is a new, smaller error vector for this frame.
    -- We convert this back into a quaternion representing the rotation to apply for this frame.
    local delta_rot_q = QuaternionUtils.exp(damped_error_vec)

    -- To get the new camera orientation, we apply this frame's rotation to the current orientation.
    return QuaternionUtils.multiply(delta_rot_q, current)
end

return QuaternionUtils