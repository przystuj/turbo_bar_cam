--- A library of utility functions for working with quaternions.
--- Upgraded with Log, Exp, and Squad for velocity-aware transitions.
---@class QuaternionUtils
local QuaternionUtils = {}

-- ##################################################################
-- ## Local Vector Math Utilities
-- ##################################################################

local function normalizeVector(v)
    local mag = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if mag > 0.0001 then
        return { x = v.x / mag, y = v.y / mag, z = v.z / mag }
    end
    return { x = 0, y = 0, z = 0 }
end

--- This is the engine's convention for converting its (rx,ry) angles to a direction vector.
local function getDirectionFromRotation(rx, ry)
    local sin_rx = math.sin(rx)
    local cos_rx = math.cos(rx)
    local sin_ry = math.sin(ry)
    local cos_ry = math.cos(ry)
    return normalizeVector({
        x = sin_rx * sin_ry,
        y = cos_rx,
        z = -sin_rx * cos_ry
    })
end

-- Helper to scale the vector part of a pure quaternion by a scalar.
function QuaternionUtils.scalePureQuaternion(q, s)
    return { w = 0, x = q.x * s, y = q.y * s, z = q.z * s }
end

-- ##################################################################
-- ## Quaternion Functions
-- ##################################################################

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
    -- Convert engine's inclination 'rx' to a standard pitch angle (0=horizontal, -pi/2=up).
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
        local result = {
            w = q1.w + t * (q2_temp.w - q1.w),
            x = q1.x + t * (q2_temp.x - q1.x),
            y = q1.y + t * (q2_temp.y - q1.y),
            z = q1.z + t * (q2_temp.z - q1.z),
        }
        local mag = math.sqrt(result.x^2 + result.y^2 + result.z^2 + result.w^2)
        if mag > 0.00001 then
            result.x, result.y, result.z, result.w = result.x/mag, result.y/mag, result.z/mag, result.w/mag
        else
            return QuaternionUtils.identity()
        end
        return result
    end

    local halfTheta = math.acos(cosHalfTheta)
    local sinHalfTheta = math.sqrt(1.0 - cosHalfTheta * cosHalfTheta)

    if math.abs(sinHalfTheta) < 0.001 then
        return q1 -- Should not happen due to the lerp case above, but as a safe fallback
    end

    local ratioA = math.sin((1 - t) * halfTheta) / sinHalfTheta
    local ratioB = math.sin(t * halfTheta) / sinHalfTheta

    return {
        w = (q1.w * ratioA + q2_temp.w * ratioB),
        x = (q1.x * ratioA + q2_temp.x * ratioB),
        y = (q1.y * ratioA + q2_temp.y * ratioB),
        z = (q1.z * ratioA + q2_temp.z * ratioB),
    }
end

--- Calculates the exponential of a pure quaternion. Result is a unit quaternion.
function QuaternionUtils.exp(q) -- Assumes pure quaternion input {w=0, x, y, z}
    local v_mag = math.sqrt(q.x*q.x + q.y*q.y + q.z*q.z)

    if v_mag < 0.00001 then return QuaternionUtils.identity() end

    local w = math.cos(v_mag)
    local s = math.sin(v_mag) / v_mag

    return { w = w, x = q.x * s, y = q.y * s, z = q.z * s }
end

--- Performs Spherical and Quadrangle (Squad) interpolation for C1 continuous transitions.
function QuaternionUtils.squad(q0, q1, a0, b1, t)
    local slerp1 = QuaternionUtils.slerp(q0, q1, t)
    local slerp2 = QuaternionUtils.slerp(a0, b1, t)
    return QuaternionUtils.slerp(slerp1, slerp2, 2 * t * (1 - t))
end

return QuaternionUtils