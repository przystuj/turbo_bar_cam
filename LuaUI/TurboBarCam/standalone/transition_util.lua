---@type CameraCommons
local CameraCommons = VFS.Include("LuaUI/TurboBarCam/common/camera_commons.lua").CameraCommons
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua")

---@class TransitionUtil
local TransitionUtil = {}

---@param currentPos table Current camera position {x, y, z}
---@param dt number Delta time
---@param easedProgress number Progress of the transition (0.0 to 1.0), already eased!
---@param velocity table Current camera velocity {x,y,z}
---@param profile table Simplified configuration { DURATION, INITIAL_BRAKING, PATH_ADHERENCE }
---@return table|nil newCamPos Smoothed camera position {px, py, pz} or nil if no position update needed
function TransitionUtil.decelerationTransition(currentPos, dt, easedProgress, velocity, profile)
    -- Fixed internal values for simplification
    local DECAY_RATE_MIN = 0.5
    local POS_CONTROL_FACTOR_MIN = 0.05
    local MIN_VELOCITY_THRESHOLD = 1.0
    local PREDICT_DT_SCALE = 1.0

    -- Use profile values as MAX
    local initialBraking = profile.INITIAL_BRAKING or 8.0
    local pathAdherence = profile.PATH_ADHERENCE or 0.6

    -- Lerp using the *already eased* progress
    local decayRate = CameraCommons.lerp(initialBraking, DECAY_RATE_MIN, easedProgress)
    local posControlFactor = CameraCommons.lerp(pathAdherence, POS_CONTROL_FACTOR_MIN, easedProgress)

    local velMagnitude = CameraCommons.vectorMagnitude(velocity)

    -- Use a low threshold; mostly rely on progress reaching 1.0
    if velMagnitude > MIN_VELOCITY_THRESHOLD and easedProgress < 0.999 then
        -- Predict using the calculated decay rate
        local predictedPos = CameraManager.predictPosition(currentPos, velocity, dt * PREDICT_DT_SCALE, decayRate)

        -- Smooth towards the predicted position using the calculated control factor
        return {
            px = CameraCommons.smoothStep(currentPos.x, predictedPos.x, posControlFactor),
            py = CameraCommons.smoothStep(currentPos.y, predictedPos.y, posControlFactor),
            pz = CameraCommons.smoothStep(currentPos.z, predictedPos.z, posControlFactor)
        }
    else
        -- Velocity is very low or progress is complete, signal to hold position
        return nil
    end
end

return TransitionUtil