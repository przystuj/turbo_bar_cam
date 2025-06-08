---@class MathUtils
local MathUtils = {}

--- Core single-value smooth damp function.
--- This is a stable, framerate-independent implementation.
---@param current number The current value.
---@param target number The target value.
---@param velocity_ref table A table holding the current velocity {val = number}, passed by reference.
---@param smoothTime number The approximate time to reach the target.
---@param maxSpeed number The maximum speed.
---@param dt number The delta time for this frame.
---@return number The new smoothed value for this frame.
local function smoothDamp(current, target, velocity_ref, smoothTime, maxSpeed, dt)
    smoothTime = math.max(0.0001, smoothTime)
    local omega = 10 / smoothTime
    local x = omega * dt
    -- This is a Taylor series approximation for exp(-x) that is stable
    local exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)

    local change = current - target

    local maxChange = maxSpeed * smoothTime
    change = math.max(-maxChange, math.min(maxChange, change))

    local new_target = current - change
    local temp = (velocity_ref.val + omega * change) * dt

    velocity_ref.val = (velocity_ref.val - omega * temp) * exp

    local output = new_target + (change + temp) * exp

    -- Prevent overshooting
    if (target - current > 0.0) == (output > target) then
        output = target
        velocity_ref.val = (output - target) / dt
    end

    return output
end

--- Smoothly dampens a 3D vector towards a target value.
--- Modifies the velocity_ref table in place.
function MathUtils.vectorSmoothDamp(current, target, velocity_ref, smoothTime, maxSpeed, dt)
    maxSpeed = maxSpeed or 100000

    -- We need to pass velocity by reference since the function modifies it.
    local vx_ref = { val = velocity_ref.x }
    local vy_ref = { val = velocity_ref.y }
    local vz_ref = { val = velocity_ref.z }

    local out_x = smoothDamp(current.x, target.x, vx_ref, smoothTime, maxSpeed, dt)
    local out_y = smoothDamp(current.y, target.y, vy_ref, smoothTime, maxSpeed, dt)
    local out_z = smoothDamp(current.z, target.z, vz_ref, smoothTime, maxSpeed, dt)

    velocity_ref.x = vx_ref.val
    velocity_ref.y = vy_ref.val
    velocity_ref.z = vz_ref.val

    return { x = out_x, y = out_y, z = out_z }
end

return MathUtils