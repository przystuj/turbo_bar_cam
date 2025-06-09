---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager

---@class MathUtils
local MathUtils = {}

--- Smoothly dampens a 3D vector towards a target value using a stable, framerate-independent
--- spring-damper model.
--- Modifies the velocity_ref table in place.
---@param current table The current vector position {x, y, z}.
---@param target table The target vector position {x, y, z}.
---@param velocity_ref table A table holding the current velocity {x, y, z}, passed by reference.
---@param smoothTime number The approximate time to reach the target. A smaller value will reach the target faster.
---@param dt number The delta time for this frame.
---@return table The new smoothed vector for this frame.
function MathUtils.vectorSmoothDamp(current, target, velocity_ref, smoothTime, dt)
    local maxSpeed = 10000
    smoothTime = math.max(0.0001, smoothTime)

    -- This calculation is based on a critical-damped spring model.
    -- The omega value influences how stiff the spring is.
    local omega = 10 / smoothTime
    local x = omega * dt
    -- A Taylor series approximation for exp(-x) that is stable.
    local exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)

    -- In the formula, 'change' is the offset from the target we want to achieve this frame.
    -- We start with the full offset from the current position to the overall target.
    local change_x = current.x - target.x
    local change_y = current.y - target.y
    local change_z = current.z - target.z

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
    local frame_target_x = current.x - change_x
    local frame_target_y = current.y - change_y
    local frame_target_z = current.z - change_z

    -- Calculate the intermediate term for the velocity and position update.
    local temp_x = (velocity_ref.x + omega * change_x) * dt
    local temp_y = (velocity_ref.y + omega * change_y) * dt
    local temp_z = (velocity_ref.z + omega * change_z) * dt

    -- Update velocity for the next frame. This is the 'damping' part.
    velocity_ref.x = (velocity_ref.x - omega * temp_x) * exp
    velocity_ref.y = (velocity_ref.y - omega * temp_y) * exp
    velocity_ref.z = (velocity_ref.z - omega * temp_z) * exp

    -- Calculate the new position for this frame.
    local output_x = frame_target_x + (change_x + temp_x) * exp
    local output_y = frame_target_y + (change_y + temp_y) * exp
    local output_z = frame_target_z + (change_z + temp_z) * exp

    -- Prevent overshooting the target.
    -- We do this by checking if the new position has 'crossed' the plane defined by the target position
    -- with a normal pointing back to the original position. A dot product is perfect for this.
    local vec_orig_to_target_x = target.x - current.x
    local vec_orig_to_target_y = target.y - current.y
    local vec_orig_to_target_z = target.z - current.z

    local vec_new_to_target_x = target.x - output_x
    local vec_new_to_target_y = target.y - output_y
    local vec_new_to_target_z = target.z - output_z

    local dot = vec_orig_to_target_x * vec_new_to_target_x + vec_orig_to_target_y * vec_new_to_target_y + vec_orig_to_target_z * vec_new_to_target_z

    if dot < 0.0 then
        output_x = target.x
        output_y = target.y
        output_z = target.z

        -- If we've snapped to the target, the velocity should be zero.
        velocity_ref.x = 0
        velocity_ref.y = 0
        velocity_ref.z = 0
    end

    return { x = output_x, y = output_y, z = output_z }
end

return MathUtils