---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local Log = ModuleManager.Log(function(m) Log = m end, "MathUtils")

---@class MathUtils
local MathUtils = {}
MathUtils.vector = {}

--============================================================================--
--=                                Vector Math                               =--
--============================================================================--

function MathUtils.vector.add(v1, v2, out)
    out = out or {}
    local x, y, z = (v1.x or 0) + (v2.x or 0), (v1.y or 0) + (v2.y or 0), (v1.z or 0) + (v2.z or 0)
    out.x, out.y, out.z = x, y, z
    return out
end

function MathUtils.vector.subtract(v1, v2, out)
    out = out or {}
    local x, y, z = (v1.x or 0) - (v2.x or 0), (v1.y or 0) - (v2.y or 0), (v1.z or 0) - (v2.z or 0)
    out.x, out.y, out.z = x, y, z
    return out
end

function MathUtils.vector.multiply(v, scalar, out)
    out = out or {}
    local x, y, z = (v.x or 0) * scalar, (v.y or 0) * scalar, (v.z or 0) * scalar
    out.x, out.y, out.z = x, y, z
    return out
end

function MathUtils.vector.magnitudeSq(v)
    local x, y, z = v.x or 0, v.y or 0, v.z or 0
    return x * x + y * y + z * z
end

function MathUtils.vector.magnitude(v)
    return math.sqrt(MathUtils.vector.magnitudeSq(v))
end

function MathUtils.vector.normalize(v, out)
    local mag = MathUtils.vector.magnitude(v)
    out = out or {}
    if mag > 1e-5 then
        return MathUtils.vector.multiply(v, 1 / mag, out)
    end
    out.x, out.y, out.z = 0, 0, 0
    return out
end

function MathUtils.vector.dot(v1, v2)
    return (v1.x or 0) * (v2.x or 0) + (v1.y or 0) * (v2.y or 0) + (v1.z or 0) * (v2.z or 0)
end

function MathUtils.vector.cross(v1, v2, out)
    out = out or {}
    local x = (v1.y or 0) * (v2.z or 0) - (v1.z or 0) * (v2.y or 0)
    local y = (v1.z or 0) * (v2.x or 0) - (v1.x or 0) * (v2.z or 0)
    local z = (v1.x or 0) * (v2.y or 0) - (v1.y or 0) * (v2.x or 0)
    out.x, out.y, out.z = x, y, z
    return out
end

function MathUtils.vector.distanceSq(p1, p2)
    local dx = (p1.x or 0) - (p2.x or 0)
    local dy = (p1.y or 0) - (p2.y or 0)
    local dz = (p1.z or 0) - (p2.z or 0)
    return dx * dx + dy * dy + dz * dz
end


--============================================================================--
--=                                Damping                                   =--
--============================================================================--

function MathUtils.expApproximation(smoothTime, dt)
    -- Using 2/T for omega is standard for this critically-damped spring approximation.
    local omega = 6 / smoothTime
    local x = omega * dt
    return 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x), omega
end

--- Smoothly dampens a 3D vector towards a target value using a stable, framerate-independent
--- spring-damper model.
function MathUtils.vectorSmoothDamp(position, target, velocity, smoothTime, dt, outPos, outVel)
    dt = math.min(dt, 0.05) -- Prevent large steps during frame rate drops
    local maxSpeed = 100000 -- Set a high practical limit
    smoothTime = math.max(0.0001, smoothTime)

    local exp, omega = MathUtils.expApproximation(smoothTime, dt)

    -- 'change' is the offset from the target.
    local change = MathUtils.vector.subtract(position, target)

    -- Clamp the maximum change vector magnitude based on maxSpeed.
    local maxChange = maxSpeed * smoothTime
    if MathUtils.vector.magnitudeSq(change) > maxChange * maxChange then
        MathUtils.vector.normalize(change, change)
        MathUtils.vector.multiply(change, maxChange, change)
    end

    -- The effective target for this frame, after speed clamping.
    local frame_target = MathUtils.vector.subtract(position, change)

    -- Calculate the intermediate term for the velocity and position update.
    -- temp = (velocity + change * omega) * dt
    local temp = MathUtils.vector.multiply(change, omega)
    MathUtils.vector.add(velocity, temp, temp)
    MathUtils.vector.multiply(temp, dt, temp)

    -- Update velocity for the next frame.
    -- newVelocity = (velocity - temp * omega) * exp
    local newVelocity = outVel or {}
    local temp2 = MathUtils.vector.multiply(temp, omega)
    MathUtils.vector.subtract(velocity, temp2, newVelocity)
    MathUtils.vector.multiply(newVelocity, exp, newVelocity)

    -- Calculate the new position for this frame.
    -- newPosition = frame_target + (change + temp) * exp
    local newPosition = outPos or {}
    MathUtils.vector.add(change, temp, newPosition)
    MathUtils.vector.multiply(newPosition, exp, newPosition)
    MathUtils.vector.add(frame_target, newPosition, newPosition)

    return newPosition, newVelocity
end

return MathUtils
