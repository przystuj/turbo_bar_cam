---@type CameraCommons
local CameraCommons = VFS.Include("LuaUI/TurboBarCam/common/camera_commons.lua").CameraCommons
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log
---@type Util
local Util = VFS.Include("LuaUI/TurboBarCam/common/utils.lua").Util
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua")

---@class TransitionUtil
local TransitionUtil = {}

--- Performs a smooth deceleration transition for both position and rotation.
---@param currentState table Current camera state {px, py, pz, rx, ry, rz, ...}
---@param dt number Delta time
---@param easedProgress number Progress of the transition (0.0 to 1.0), already eased!
---@param velocity table Current camera velocity {x, y, z}
---@param rotVelocity table Current camera rotational velocity {rx, ry, rz}
---@param profile table Configuration { DURATION, INITIAL_BRAKING, PATH_ADHERENCE }
---@return table|nil newCamState Full smoothed camera state {px, py, pz, rx, ry, rz} or nil
function TransitionUtil.smoothDecelerationTransition(currentState, dt, easedProgress, velocity, rotVelocity, profile)
    local DECAY_RATE_MIN = 0.5
    local POS_CONTROL_FACTOR_MIN = 0.05
    local ROT_CONTROL_FACTOR_MIN = 0.01
    local MIN_VELOCITY_THRESHOLD = 1.0
    local MIN_ROT_VEL_THRESHOLD = 0.1

    local initialBraking = profile.INITIAL_BRAKING or 8.0
    local pathAdherence = profile.PATH_ADHERENCE or 0.6

    local decayRate = CameraCommons.lerp(initialBraking, DECAY_RATE_MIN, easedProgress)
    local posControlFactor = CameraCommons.lerp(pathAdherence, POS_CONTROL_FACTOR_MIN, easedProgress)
    local rotControlFactor = CameraCommons.lerp(0.9, ROT_CONTROL_FACTOR_MIN, easedProgress)

    local velMagnitude = CameraCommons.vectorMagnitude(velocity)
    local rotVelMagnitude = CameraCommons.vectorMagnitude(rotVelocity)

    -- Check if either position OR rotation needs deceleration
    if (velMagnitude > MIN_VELOCITY_THRESHOLD or rotVelMagnitude > MIN_ROT_VEL_THRESHOLD) and easedProgress < 0.999 then

        -- Predict the full next state
        local predictedState = CameraManager.predictState(currentState, velocity, rotVelocity, dt, decayRate)

        local newState = {
            px = CameraCommons.smoothStep(currentState.px, predictedState.px, posControlFactor),
            py = CameraCommons.smoothStep(currentState.py, predictedState.py, posControlFactor),
            pz = CameraCommons.smoothStep(currentState.pz, predictedState.pz, posControlFactor),
            rx = CameraCommons.smoothStepAngle(currentState.rx, predictedState.rx, rotControlFactor),
            ry = CameraCommons.smoothStepAngle(currentState.ry, predictedState.ry, rotControlFactor),
            rz = CameraCommons.smoothStepAngle(currentState.rz, predictedState.rz, rotControlFactor),
            fov = currentState.fov
        }
        return newState
    else
        -- Nothing to decelerate, return nil to signal holding position/rotation
        return nil
    end
end

return TransitionUtil