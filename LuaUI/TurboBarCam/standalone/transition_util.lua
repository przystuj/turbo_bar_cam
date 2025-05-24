---@type CameraCommons
local CameraCommons = VFS.Include("LuaUI/TurboBarCam/common/camera_commons.lua").CameraCommons
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua")

---@class TransitionUtil
local TransitionUtil = {}

--- Handles smooth positional deceleration for camera transitions.
---@param currentPos table Current camera position {x, y, z}
---@param dt number Delta time
---@param transitionProgress number Progress of the transition (0.0 to 1.0)
---@param velocity table Current camera velocity {x,y,z} (e.g., from CameraManager or stored initial velocity)
---@param config table Configuration for deceleration { DECAY_RATE_MIN, DECAY_RATE_MAX, POS_CONTROL_FACTOR_MIN, POS_CONTROL_FACTOR_MAX, MIN_VELOCITY_THRESHOLD, PREDICT_DT_SCALE }
---@return table|nil newCamPos Smoothed camera position {px, py, pz} or nil if no position update needed
function TransitionUtil.smoothDecelerationTransition(currentPos, dt, transitionProgress, velocity, config)
    local velMagnitude = CameraCommons.vectorMagnitude(velocity)

    -- Ensure config defaults if some values are missing
    local minVelocityThreshold = config.MIN_VELOCITY_THRESHOLD or 1.0
    local decayRateMax = config.DECAY_RATE_MAX or 10.0
    local decayRateMin = config.DECAY_RATE_MIN or 2.0
    local posControlFactorMax = config.POS_CONTROL_FACTOR_MAX or 0.1
    local posControlFactorMin = config.POS_CONTROL_FACTOR_MIN or 0.02
    local predictDtScale = config.PREDICT_DT_SCALE or 1.0

    if velMagnitude > minVelocityThreshold then
        -- Calculate dynamic decay rate and position control factor based on progress
        local decayRate = CameraCommons.lerp(decayRateMax, decayRateMin, transitionProgress) -- Starts high, ends low
        local posControlFactor = CameraCommons.lerp(posControlFactorMax, posControlFactorMin, transitionProgress) -- Starts high, ends low

        -- Predict where camera should be based on decaying velocity
        local predictDt = dt * predictDtScale
        -- Ensure CameraManager.predictPosition is available and correctly referenced
        local predictedPos = CameraManager.predictPosition(currentPos, velocity, predictDt, decayRate)

        return {
            px = CameraCommons.smoothStep(currentPos.x, predictedPos.x, posControlFactor),
            py = CameraCommons.smoothStep(currentPos.y, predictedPos.y, posControlFactor),
            pz = CameraCommons.smoothStep(currentPos.z, predictedPos.z, posControlFactor)
        }
    else
        -- Velocity is low. We might want to gently bring it to a halt or let the calling mode handle it.
        -- Lerp the position control factor down to 0 as progress completes.
        local finalPosControlFactor = CameraCommons.lerp(posControlFactorMin, 0.0, transitionProgress)
        if finalPosControlFactor > 0.001 then
            return {
                px = CameraCommons.smoothStep(currentPos.x, currentPos.x, finalPosControlFactor), -- Smooth towards current position (effectively stopping)
                py = CameraCommons.smoothStep(currentPos.y, currentPos.y, finalPosControlFactor),
                pz = CameraCommons.smoothStep(currentPos.z, currentPos.z, finalPosControlFactor)
            }
        end
        return nil -- No position override, let the mode's regular smoothing/logic take over or fix position
    end
end

return TransitionUtil