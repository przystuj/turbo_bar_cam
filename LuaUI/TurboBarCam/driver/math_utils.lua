---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local Log = ModuleManager.Log(function(m) Log = m end, "MathUtils")

---@class MathUtils
local MathUtils = {}

--- Smoothly dampens a 3D vector towards a target value using a stable, framerate-independent
--- spring-damper model.
--- Modifies the velocity_ref table in place.
---@param position table The current vector position {x, y, z}.
---@param target table The target vector position {x, y, z}.
---@param velocity table A table holding the current velocity {x, y, z}, passed by reference.
---@param smoothTime number The approximate time to reach the target. A smaller value will reach the target faster.
---@param dt number The delta time for this frame.
---@return table The new smoothed vector for this frame.
function MathUtils.vectorSmoothDamp(position, target, velocity, smoothTime, dt)
    dt = math.min(dt, 0.05) -- Prevent large steps during frame rate drops
    local maxSpeed = 10000
    smoothTime = math.max(0.0001, smoothTime)

    -- This calculation is based on a critical-damped spring model.
    -- The omega value influences how stiff the spring is.
    local omega = 6 / smoothTime
    local x = omega * dt
    -- A Taylor series approximation for exp(-x) that is stable.
    local exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)

    -- In the formula, 'change' is the offset from the target we want to achieve this frame.
    -- We start with the full offset from the current position to the overall target.
    local change_x = position.x - target.x
    local change_y = position.y - target.y
    local change_z = position.z - target.z

    -- Clamp the maximum change vector magnitude based on maxSpeed.
    -- This ensures the camera doesn't move faster than the specified limit.
    local maxChange = maxSpeed * smoothTime
    local changeMagSq = change_x * change_x + change_y * change_y + change_z * change_z

    if changeMagSq > maxChange * maxChange then
        local changeMag = math.sqrt(changeMagSq)
        local scale = maxChange / changeMag
        change_x = change_x * scale
        change_y = change_y * scale
        change_z = change_z * scale
    end

    -- The effective target for this frame, after speed clamping.
    local frame_target_x = position.x - change_x
    local frame_target_y = position.y - change_y
    local frame_target_z = position.z - change_z

    -- Calculate the intermediate term for the velocity and position update.
    local temp_x = (velocity.x + omega * change_x) * dt
    local temp_y = (velocity.y + omega * change_y) * dt
    local temp_z = (velocity.z + omega * change_z) * dt

    -- Update velocity for the next frame. This is the 'damping' part.
    local newVelocity = {}
    newVelocity.x = (velocity.x - omega * temp_x) * exp
    newVelocity.y = (velocity.y - omega * temp_y) * exp
    newVelocity.z = (velocity.z - omega * temp_z) * exp

    -- Calculate the new position for this frame.
    local newPosition = {}
    newPosition.x = frame_target_x + (change_x + temp_x) * exp
    newPosition.y = frame_target_y + (change_y + temp_y) * exp
    newPosition.z = frame_target_z + (change_z + temp_z) * exp

    return newPosition, newVelocity
end

return MathUtils