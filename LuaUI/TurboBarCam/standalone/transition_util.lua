---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraCommons
local CameraCommons = VFS.Include("LuaUI/TurboBarCam/common/camera_commons.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua")
---@type VelocityTracker
local VelocityTracker = VFS.Include("LuaUI/TurboBarCam/standalone/velocity_tracker.lua")

local CONFIG = WidgetContext.CONFIG

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
    local DECAY_RATE_MIN = CONFIG.TRANSITION.DECELERATION.DECAY_RATE_MIN
    local POS_CONTROL_FACTOR_MIN = CONFIG.TRANSITION.DECELERATION.POS_CONTROL_FACTOR_MIN
    local ROT_CONTROL_FACTOR_MIN = CONFIG.TRANSITION.DECELERATION.ROT_CONTROL_FACTOR_MIN
    local MIN_VELOCITY_THRESHOLD = CONFIG.TRANSITION.DECELERATION.MIN_VELOCITY_THRESHOLD
    local MIN_ROT_VEL_THRESHOLD = CONFIG.TRANSITION.DECELERATION.MIN_ROT_VEL_THRESHOLD
    local MAX_POSITION_VELOCITY = CONFIG.TRANSITION.DECELERATION.MAX_POSITION_VELOCITY
    local MAX_ROTATION_VELOCITY = CONFIG.TRANSITION.DECELERATION.MAX_ROTATION_VELOCITY

    local clampedVelocity = velocity
    local clampedRotVelocity = rotVelocity
    local velMagnitude = CameraCommons.vectorMagnitude(velocity)
    local rotVelMagnitude = CameraCommons.vectorMagnitude(rotVelocity)

    if velMagnitude > MAX_POSITION_VELOCITY then
        clampedVelocity = CameraCommons.vectorMultiply(velocity, MAX_POSITION_VELOCITY / velMagnitude)
        Log.trace("Clamping high velocity: " .. velMagnitude .. " to " .. MAX_POSITION_VELOCITY)
        velMagnitude = MAX_POSITION_VELOCITY
    end
    if rotVelMagnitude > MAX_ROTATION_VELOCITY then
        clampedRotVelocity = CameraCommons.vectorMultiply(rotVelocity, MAX_ROTATION_VELOCITY / rotVelMagnitude)
        Log.trace("Clamping high rot velocity: " .. rotVelMagnitude .. " to " .. MAX_ROTATION_VELOCITY)
        rotVelMagnitude = MAX_ROTATION_VELOCITY
    end

    local initialBraking = profile.INITIAL_BRAKING or 8.0
    local pathAdherence = profile.PATH_ADHERENCE or 0.6

    local decayRate = CameraCommons.lerp(initialBraking, DECAY_RATE_MIN, easedProgress)
    local posControlFactor = CameraCommons.lerp(pathAdherence, POS_CONTROL_FACTOR_MIN, easedProgress)
    local rotControlFactor = CameraCommons.lerp(0.9, ROT_CONTROL_FACTOR_MIN, easedProgress)

    if (velMagnitude > MIN_VELOCITY_THRESHOLD or rotVelMagnitude > MIN_ROT_VEL_THRESHOLD) and easedProgress < 0.999 then

        local predictedState = VelocityTracker.predictState(currentState, clampedVelocity, clampedRotVelocity, dt, decayRate)

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
        return nil
    end
end

return TransitionUtil