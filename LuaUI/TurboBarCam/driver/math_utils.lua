---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local Log = ModuleManager.Log(function(m) Log = m end, "MathUtils")

---@class MathUtils
local MathUtils = {}
MathUtils.vector = {}

--============================================================================--
--=                                Vector Math                               =--
--============================================================================--

function MathUtils.vector.add(v1, v2)
    return { x = (v1.x or 0) + (v2.x or 0), y = (v1.y or 0) + (v2.y or 0), z = (v1.z or 0) + (v2.z or 0) }
end

function MathUtils.vector.subtract(v1, v2)
    return { x = (v1.x or 0) - (v2.x or 0), y = (v1.y or 0) - (v2.y or 0), z = (v1.z or 0) - (v2.z or 0) }
end

function MathUtils.vector.multiply(v, scalar)
    return { x = (v.x or 0) * scalar, y = (v.y or 0) * scalar, z = (v.z or 0) * scalar }
end

function MathUtils.vector.magnitudeSq(v)
    local x, y, z = v.x or 0, v.y or 0, v.z or 0
    return x * x + y * y + z * z
end

function MathUtils.vector.magnitude(v)
    return math.sqrt(MathUtils.vector.magnitudeSq(v))
end

function MathUtils.vector.normalize(v)
    local mag = MathUtils.vector.magnitude(v)
    if mag > 1e-5 then
        return MathUtils.vector.multiply(v, 1 / mag)
    end
    return { x = 0, y = 0, z = 0 }
end

function MathUtils.vector.dot(v1, v2)
    return (v1.x or 0) * (v2.x or 0) + (v1.y or 0) * (v2.y or 0) + (v1.z or 0) * (v2.z or 0)
end

function MathUtils.vector.cross(v1, v2)
    return {
        x = (v1.y or 0) * (v2.z or 0) - (v1.z or 0) * (v2.y or 0),
        y = (v1.z or 0) * (v2.x or 0) - (v1.x or 0) * (v2.z or 0),
        z = (v1.x or 0) * (v2.y or 0) - (v1.y or 0) * (v2.x or 0)
    }
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
function MathUtils.vectorSmoothDamp(position, target, velocity, smoothTime, dt)
    dt = math.min(dt, 0.05) -- Prevent large steps during frame rate drops
    local maxSpeed = 100000 -- Set a high practical limit
    smoothTime = math.max(0.0001, smoothTime)

    local exp, omega = MathUtils.expApproximation(smoothTime, dt)

    -- 'change' is the offset from the target.
    local change = MathUtils.vector.subtract(position, target)

    -- Clamp the maximum change vector magnitude based on maxSpeed.
    local maxChange = maxSpeed * smoothTime
    if MathUtils.vector.magnitudeSq(change) > maxChange * maxChange then
        change = MathUtils.vector.multiply(MathUtils.vector.normalize(change), maxChange)
    end

    -- The effective target for this frame, after speed clamping.
    local frame_target = MathUtils.vector.subtract(position, change)

    -- Calculate the intermediate term for the velocity and position update.
    local temp = MathUtils.vector.multiply(MathUtils.vector.add(velocity, MathUtils.vector.multiply(change, omega)), dt)

    -- Update velocity for the next frame.
    local newVelocity = MathUtils.vector.multiply(MathUtils.vector.subtract(velocity, MathUtils.vector.multiply(temp, omega)), exp)

    -- Calculate the new position for this frame.
    local newPosition = MathUtils.vector.add(frame_target, MathUtils.vector.multiply(MathUtils.vector.add(change, temp), exp))

    return newPosition, newVelocity
end

return MathUtils