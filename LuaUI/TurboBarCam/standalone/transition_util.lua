---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "TransitionUtil")
local VelocityTracker = ModuleManager.VelocityTracker(function(m) VelocityTracker = m end)
local MathUtils = ModuleManager.MathUtils(function(m) MathUtils = m end)

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
    local velMagnitude = MathUtils.vector.magnitude(velocity)
    local rotVelMagnitude = MathUtils.vector.magnitude(rotVelocity)

    if velMagnitude > MAX_POSITION_VELOCITY then
        clampedVelocity = MathUtils.vector.multiply(velocity, MAX_POSITION_VELOCITY / velMagnitude)
        Log:trace("Clamping high velocity: " .. velMagnitude .. " to " .. MAX_POSITION_VELOCITY)
        velMagnitude = MAX_POSITION_VELOCITY
    end
    if rotVelMagnitude > MAX_ROTATION_VELOCITY then
        clampedRotVelocity = MathUtils.vector.multiply(rotVelocity, MAX_ROTATION_VELOCITY / rotVelMagnitude)
        Log:trace("Clamping high rot velocity: " .. rotVelMagnitude .. " to " .. MAX_ROTATION_VELOCITY)
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
            px = CameraCommons.lerp(currentState.px, predictedState.px, posControlFactor),
            py = CameraCommons.lerp(currentState.py, predictedState.py, posControlFactor),
            pz = CameraCommons.lerp(currentState.pz, predictedState.pz, posControlFactor),
            rx = CameraCommons.lerpAngle(currentState.rx, predictedState.rx, rotControlFactor),
            ry = CameraCommons.lerpAngle(currentState.ry, predictedState.ry, rotControlFactor),
            rz = CameraCommons.lerpAngle(currentState.rz, predictedState.rz, rotControlFactor),
            fov = currentState.fov
        }
        return newState
    else
        return nil
    end
end

return TransitionUtil