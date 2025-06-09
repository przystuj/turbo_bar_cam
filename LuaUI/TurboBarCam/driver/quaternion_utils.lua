---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local MathUtils = ModuleManager.MathUtils(function(m) MathUtils = m end)

--- A library of utility functions for working with quaternions.
---@class QuaternionUtils
local QuaternionUtils = {}

-- ... (All other functions like identity, multiply, slerp, etc., remain exactly the same) ...
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

---@diagnostic disable-next-line: unused-local
local function scalePureQuaternion(q, s)
    return { w = 0, x = q.x * s, y = q.y * s, z = q.z * s }
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

--- Smoothly dampens a quaternion towards a target value using a stable, framerate-independent
--- spring-damper model analogous to vectorSmoothDamp.
--- Modifies the angularVelocityRef table in place.
---@param current table The current quaternion orientation.
---@param target table The target quaternion orientation.
---@param angularVelocityRef table A table holding the current angular velocity {x, y, z}, passed by reference.
---@param smoothTime number The approximate time to reach the target.
---@param dt number The delta time for this frame.
---@return table The new smoothed quaternion for this frame.
function QuaternionUtils.quaternionSmoothDamp(current, target, angularVelocityRef, smoothTime, dt)
    dt = math.min(dt, 0.05)
    smoothTime = math.max(0.0001, smoothTime)

    -- Local vector helpers to avoid external dependencies
    local function vec_add(v1, v2) return { x = (v1.x or 0) + (v2.x or 0), y = (v1.y or 0) + (v2.y or 0), z = (v1.z or 0) + (v2.z or 0) } end
    local function vec_sub(v1, v2) return { x = (v1.x or 0) - (v2.x or 0), y = (v1.y or 0) - (v2.y or 0), z = (v1.z or 0) - (v2.z or 0) } end
    local function vec_mul_scalar(v, s) return { x = (v.x or 0) * s, y = (v.y or 0) * s, z = (v.z or 0) * s } end
    local function vec_dot(v1, v2) return (v1.x or 0) * (v2.x or 0) + (v1.y or 0) * (v2.y or 0) + (v1.z or 0) * (v2.z or 0) end
    local function vec_mag_sq(v) return (v.x or 0)^2 + (v.y or 0)^2 + (v.z or 0)^2 end

    -- Ensure we take the shortest path by avoiding the long way around the sphere
    local target_q = target
    if QuaternionUtils.dot(current, target) < 0.0 then
        target_q = { w = -target.w, x = -target.x, y = -target.y, z = -target.z }
    end

    -- Same spring physics constants as vectorSmoothDamp for synchronization
    local omega = 2 / smoothTime
    local x = omega * dt
    local exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)

    -- Calculate change vector from current to target, analogous to `current - target`
    local delta_to_target = QuaternionUtils.multiply(current, QuaternionUtils.inverse(target_q))
    local log_delta = QuaternionUtils.log(delta_to_target)
    local change_v = { x = log_delta.x, y = log_delta.y, z = log_delta.z }

    -- Add stability clamp, mirroring vectorSmoothDamp's maxSpeed
    local maxAngularSpeed = 100 -- Radians per second, a very high but safe limit
    local maxAngleChange = maxAngularSpeed * smoothTime
    if vec_mag_sq(change_v) > maxAngleChange * maxAngleChange then
        local change_mag = math.sqrt(vec_mag_sq(change_v))
        change_v = vec_mul_scalar(change_v, maxAngleChange / change_mag)
    end

    -- The rest of the logic mirrors vectorSmoothDamp
    local temp_v = vec_mul_scalar(vec_add(angularVelocityRef, vec_mul_scalar(change_v, omega)), dt)

    local new_vel = vec_mul_scalar(vec_sub(angularVelocityRef, vec_mul_scalar(temp_v, omega)), exp)
    angularVelocityRef.x = new_vel.x
    angularVelocityRef.y = new_vel.y
    angularVelocityRef.z = new_vel.z

    -- This vector represents the remaining rotation offset from the target
    local output_disp_v = vec_mul_scalar(vec_add(change_v, temp_v), exp)

    -- Convert displacement vector to a quaternion and apply it to the target
    local output_disp_q = QuaternionUtils.exp({ w = 0, x = output_disp_v.x, y = output_disp_v.y, z = output_disp_v.z })
    local output_q = QuaternionUtils.multiply(output_disp_q, target_q)

    -- Prevent overshooting
    local orig_to_target_q = QuaternionUtils.multiply(target_q, QuaternionUtils.inverse(current))
    local new_to_target_q = QuaternionUtils.multiply(target_q, QuaternionUtils.inverse(output_q))
    local v_orig = QuaternionUtils.log(orig_to_target_q)
    local v_new = QuaternionUtils.log(new_to_target_q)
    if vec_dot(v_orig, v_new) < 0.0 then
        output_q = target_q
        angularVelocityRef.x, angularVelocityRef.y, angularVelocityRef.z = 0, 0, 0
    end

    return QuaternionUtils.normalize(output_q)
end

return QuaternionUtils