---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local Log = ModuleManager.Log(function(m) Log = m end, "QuaternionUtils")
local MathUtils = ModuleManager.MathUtils(function(m) MathUtils = m end)

--- A library of utility functions for working with quaternions.
---@class QuaternionUtils
local QuaternionUtils = {}

function QuaternionUtils.identity()
    return { x = 0, y = 0, z = 0, w = 1 }
end

function QuaternionUtils.dot(q1, q2)
    return q1.w * q2.w + q1.x * q2.x + q1.y * q2.y + q1.z * q2.z
end

function QuaternionUtils.multiply(q1, q2, out)
    out = out or {}
    local w1, x1, y1, z1 = q1.w, q1.x, q1.y, q1.z
    local w2, x2, y2, z2 = q2.w, q2.x, q2.y, q2.z
    out.w = w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2
    out.x = w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2
    out.y = w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2
    out.z = w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2
    return out
end

function QuaternionUtils.fromEuler(rx, ry, out)
    local standardPitch = rx - (math.pi / 2)
    local halfPitch = standardPitch * 0.5
    local halfYaw = ry * 0.5
    local cosPitch, sinPitch = math.cos(halfPitch), math.sin(halfPitch)
    local cosYaw, sinYaw = math.cos(halfYaw), math.sin(halfYaw)
    local qx = { x = sinPitch, y = 0, z = 0, w = cosPitch }
    local qy = { x = 0, y = sinYaw, z = 0, w = cosYaw }
    return QuaternionUtils.multiply(qy, qx, out)
end

function QuaternionUtils.toEuler(orientation)
    local standardPitch, ry
    local sinP = 2 * (orientation.w * orientation.x - orientation.y * orientation.z)

    if math.abs(sinP) >= 0.99999 then
        standardPitch = (math.pi / 2) * (sinP > 0 and 1 or -1)
        ry = 2 * math.atan2(orientation.y, orientation.w)
    else
        standardPitch = math.asin(sinP)
        local sinY = 2 * (orientation.w * orientation.y + orientation.x * orientation.z)
        local cosY = 1 - 2 * (orientation.x * orientation.x + orientation.y * orientation.y)
        ry = math.atan2(sinY, cosY)
    end

    local rx = standardPitch + (math.pi / 2)
    return rx, ry
end

function QuaternionUtils.inverse(q, out)
    out = out or {}
    local x, y, z, w = -q.x, -q.y, -q.z, q.w
    out.x, out.y, out.z, out.w = x, y, z, w
    return out
end

function QuaternionUtils.normalize(q, out)
    local mag = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    out = out or {}
    if mag < 0.00001 then
        out.x, out.y, out.z, out.w = 0, 0, 0, 1
        return out
    end
    local x, y, z, w = q.x / mag, q.y / mag, q.z / mag, q.w / mag
    out.x, out.y, out.z, out.w = x, y, z, w
    return out
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

function QuaternionUtils.log(q, out)
    local vMagSq = q.x * q.x + q.y * q.y + q.z * q.z
    out = out or {}
    if vMagSq < 1e-12 then
        out.w, out.x, out.y, out.z = 0, 0, 0, 0
        return out
    end
    local vMag = math.sqrt(vMagSq)
    local halfAngle = math.atan2(vMag, q.w)
    local scale = halfAngle / vMag
    local x, y, z = q.x * scale, q.y * scale, q.z * scale
    out.w, out.x, out.y, out.z = 0, x, y, z
    return out
end

function QuaternionUtils.expMap(q, out)
    local halfAngle = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z)
    out = out or {}
    if halfAngle < 1e-5 then
        out.x, out.y, out.z, out.w = 0, 0, 0, 1
        return out
    end
    local w = math.cos(halfAngle)
    local s = math.sin(halfAngle) / halfAngle
    local x, y, z = q.x * s, q.y * s, q.z * s
    out.w, out.x, out.y, out.z = w, x, y, z
    return out
end

function QuaternionUtils.toAxisAngle(q)
    -- Ensure quaternion is normalized to prevent math errors
    local nq = QuaternionUtils.normalize(q)
    local angle = 2 * math.acos(nq.w)
    local s = math.sqrt(1 - nq.w * nq.w)
    local axis

    if s < 0.0001 then
        -- If s is close to zero, angle is close to zero, axis is irrelevant
        axis = { x = 1, y = 0, z = 0 }
    else
        axis = { x = nq.x / s, y = nq.y / s, z = nq.z / s }
    end

    -- Normalize angle to be in [-PI, PI] range
    if angle > math.pi then
        angle = angle - (2 * math.pi)
    end
    return axis, angle
end


--- Smoothly dampens a quaternion towards a target value.
function QuaternionUtils.quaternionSmoothDamp(orientation, target, angularVelocity, smoothTime, dt, outQ, outAV)
    dt = math.min(dt, 0.05)
    smoothTime = math.max(0.0001, smoothTime)
    local vec = MathUtils.vector

    -- Ensure we take the shortest path
    local target_q = target
    if QuaternionUtils.dot(orientation, target) < 0.0 then
        target_q = { w = -target.w, x = -target.x, y = -target.y, z = -target.z }
    end

    local exp, omega = MathUtils.expApproximation(smoothTime, dt)

    -- Calculate change vector from current to target
    local inv_target = QuaternionUtils.inverse(target_q)
    local delta_to_target = QuaternionUtils.multiply(orientation, inv_target)
    local change_v = QuaternionUtils.log(delta_to_target)

    --Add stability clamp, mirroring vectorSmoothDamp's maxSpeed
    local maxAngularSpeed = 100 -- Radians per second
    local maxAngleChange = maxAngularSpeed * smoothTime
    if vec.magnitudeSq(change_v) > maxAngleChange * maxAngleChange then
        vec.normalize(change_v, change_v)
        vec.multiply(change_v, maxAngleChange, change_v)
    end

    -- The rest of the logic mirrors vectorSmoothDamp
    -- temp_v = (angularVelocity + change_v * omega) * dt
    local temp_v = vec.multiply(change_v, omega)
    vec.add(angularVelocity, temp_v, temp_v)
    vec.multiply(temp_v, dt, temp_v)

    -- newAngularVelocity = (angularVelocity - temp_v * omega) * exp
    local newAngularVelocity = outAV or {}
    local temp2 = vec.multiply(temp_v, omega)
    vec.subtract(angularVelocity, temp2, newAngularVelocity)
    vec.multiply(newAngularVelocity, exp, newAngularVelocity)

    -- Convert displacement vector to a quaternion and apply it to the target
    -- output_disp_v = (change_v + temp_v) * exp
    local output_disp_v = vec.add(change_v, temp_v)
    vec.multiply(output_disp_v, exp, output_disp_v)

    local output_disp_q = QuaternionUtils.expMap(output_disp_v)
    local output_q = outQ or {}
    QuaternionUtils.multiply(output_disp_q, target_q, output_q)

    return QuaternionUtils.normalize(output_q, output_q), newAngularVelocity
end

return QuaternionUtils
