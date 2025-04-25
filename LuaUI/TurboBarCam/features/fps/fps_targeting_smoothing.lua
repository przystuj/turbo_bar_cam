---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons

---@class FPSTargetingSmoothing
local FPSTargetingSmoothing = {}

-- Constants for target smoothing
local TARGET_HISTORY_SIZE = 20       -- Maximum number of recent targets to track
local TARGET_HISTORY_DURATION = 3.0  -- How long targets remain in history (seconds)
local MIN_TARGETS_FOR_CLOUD = 3      -- Minimum targets needed to form a "cloud"
local CLOUD_RADIUS = 300             -- Maximum radius for targets to be considered in the same cloud
local CLOUD_BLEND_FACTOR = 0.7       -- How much to blend between actual target and cloud center (0-1)
local TARGET_SWITCH_THRESHOLD = 0.3  -- Time threshold (seconds) to detect rapid target switching

-- Initialize state if needed
local function ensureTargetSmoothingState()
    if not STATE.tracking.fps.targetSmoothing then
        local currentTime = Spring.GetTimer()
        STATE.tracking.fps.targetSmoothing = {
            targetHistory = {},
            cloudCenter = nil,
            cloudRadius = 0,
            useCloudTargeting = false,
            cloudStartTime = nil,
            lastCloudUpdateTime = currentTime,
            highActivityDetected = false,
            activityLevel = 0,
            lastTargetSwitchTime = currentTime,
            targetSwitchCount = 0,
            lastStatusLogTime = currentTime,
            currentTargetKey = nil,
            targetAimOffset = {x=0, y=0, z=0},
            targetPrediction = {
                enabled = false,
                velocityX = 0,
                velocityY = 0,
                velocityZ = 0,
                lastUpdateTime = currentTime
            },
            rotationConstraint = {
                enabled = true,
                maxRotationRate = 0.07,
                lastYaw = nil,
                lastPitch = nil,
                damping = 0.8
            }
        }
    end
end

--- Creates a unique key for a target position
--- @param targetPos table Target position {x, y, z}
--- @return string targetKey Unique key for this target
local function createTargetKey(targetPos)
    -- Round position to reduce minor fluctuations
    return string.format("%.0f_%.0f_%.0f",
            math.floor(targetPos.x / 10) * 10,
            math.floor(targetPos.y / 10) * 10,
            math.floor(targetPos.z / 10) * 10)
end

--- Updates the target history with the current target
--- @param targetPos table Target position {x, y, z}
function FPSTargetingSmoothing.updateTargetHistory(targetPos)
    if not targetPos then return end

    ensureTargetSmoothingState()
    local state = STATE.tracking.fps.targetSmoothing
    local currentTime = Spring.GetTimer()

    -- Ensure all timer values are initialized
    if not state.lastTargetSwitchTime then
        state.lastTargetSwitchTime = currentTime
    end
    if not state.lastStatusLogTime then
        state.lastStatusLogTime = currentTime
    end
    if not state.lastCloudUpdateTime then
        state.lastCloudUpdateTime = currentTime
    end

    -- Create a key for this target
    local targetKey = createTargetKey(targetPos)

    -- Check if target has changed
    local targetChanged = (targetKey ~= state.currentTargetKey)
    if targetChanged then
        state.currentTargetKey = targetKey

        -- Track time between target switches
        local timeSinceLastSwitch = 0
        if state.lastTargetSwitchTime then
            timeSinceLastSwitch = Spring.DiffTimers(currentTime, state.lastTargetSwitchTime)
        end

        -- Increment switch count if this was a rapid switch
        if timeSinceLastSwitch < TARGET_SWITCH_THRESHOLD then
            state.targetSwitchCount = state.targetSwitchCount + 1

            -- If we're switching targets rapidly, enable cloud targeting
            if state.targetSwitchCount >= 3 and not state.highActivityDetected then
                Log.info("Rapid target switching detected - enabling cloud targeting")
                state.highActivityDetected = true
                state.cloudStartTime = currentTime
            end
        else
            -- Reset counter if switches aren't happening rapidly
            state.targetSwitchCount = 1
        end

        state.lastTargetSwitchTime = currentTime
    end

    -- Add current target to history
    table.insert(state.targetHistory, {
        pos = {x = targetPos.x, y = targetPos.y, z = targetPos.z},
        key = targetKey,
        time = currentTime
    })

    -- Remove old targets
    local i = 1
    while i <= #state.targetHistory do
        local timeDiff = 0
        if state.targetHistory[i].time then
            timeDiff = Spring.DiffTimers(currentTime, state.targetHistory[i].time)
        end

        if timeDiff > TARGET_HISTORY_DURATION then
            table.remove(state.targetHistory, i)
        else
            i = i + 1
        end
    end

    -- Keep history size reasonable
    while #state.targetHistory > TARGET_HISTORY_SIZE do
        table.remove(state.targetHistory, 1)
    end

    -- Count unique targets in recent history
    local uniqueTargets = {}
    for _, target in ipairs(state.targetHistory) do
        uniqueTargets[target.key] = true
    end
    local uniqueTargetCount = 0
    for _ in pairs(uniqueTargets) do
        uniqueTargetCount = uniqueTargetCount + 1
    end

    -- Calculate activity level based on unique targets and switch count
    local historySizeFactor = math.min(uniqueTargetCount / MIN_TARGETS_FOR_CLOUD, 1.0)
    local switchFactor = math.min(state.targetSwitchCount / 3, 1.0)
    state.activityLevel = math.max(historySizeFactor, switchFactor)

    -- Update high activity flag
    if state.activityLevel >= 0.7 and not state.highActivityDetected then
        state.highActivityDetected = true
        Log.info("High targeting activity detected - enabling cloud targeting")
        state.cloudStartTime = currentTime

        -- Add a minimum duration for cloud targeting (3 seconds)
        state.minCloudDuration = Spring.GetTimer()
    elseif state.activityLevel < 0.3 and state.highActivityDetected then
        -- Only disable if minimum duration has passed
        local hasMinDurationPassed = not state.minCloudDuration or
                Spring.DiffTimers(currentTime, state.minCloudDuration) > 3.0

        if hasMinDurationPassed then
            state.highActivityDetected = false
            Log.info("Targeting activity normalized - disabling cloud targeting")
            state.cloudStartTime = nil
        end
    end

    -- Periodically log status
    if Spring.DiffTimers(currentTime, state.lastStatusLogTime) > 1.0 then
        if state.activityLevel > 0.5 then
            Log.debug(string.format("Targeting activity: %.2f (%d unique targets, %d rapid switches)",
                    state.activityLevel, uniqueTargetCount, state.targetSwitchCount))
        end
        state.lastStatusLogTime = currentTime
    end

    -- Decide whether to use cloud targeting
    state.useCloudTargeting = (state.highActivityDetected and
            (uniqueTargetCount >= MIN_TARGETS_FOR_CLOUD or state.targetSwitchCount >= 3))

    -- Calculate cloud center if needed
    if state.useCloudTargeting then
        FPSTargetingSmoothing.calculateCloudCenter()
    end
end

--- Calculates the center of the target cloud
function FPSTargetingSmoothing.calculateCloudCenter()
    ensureTargetSmoothingState()
    local state = STATE.tracking.fps.targetSmoothing

    if #state.targetHistory < MIN_TARGETS_FOR_CLOUD then
        return
    end

    -- Calculate the centroid of all recent targets with time weighting
    local sumX, sumY, sumZ = 0, 0, 0
    local count = 0
    local currentTime = Spring.GetTimer()

    for _, target in ipairs(state.targetHistory) do
        local timeDiff = Spring.DiffTimers(currentTime, target.time)
        local weight = 1.0 - (timeDiff / TARGET_HISTORY_DURATION)
        weight = weight * weight  -- Square for stronger recency bias

        sumX = sumX + target.pos.x * weight
        sumY = sumY + target.pos.y * weight
        sumZ = sumZ + target.pos.z * weight
        count = count + weight
    end

    if count > 0 then
        local center = {
            x = sumX / count,
            y = sumY / count,
            z = sumZ / count
        }

        -- Calculate cloud radius (distance to furthest target)
        local maxDistSq = 0
        for _, target in ipairs(state.targetHistory) do
            local dx = target.pos.x - center.x
            local dy = target.pos.y - center.y
            local dz = target.pos.z - center.z
            local distSq = dx * dx + dy * dy + dz * dz
            if distSq > maxDistSq then
                maxDistSq = distSq
            end
        end

        state.cloudRadius = math.sqrt(maxDistSq)
        state.cloudCenter = center

        -- Log cloud updates periodically
        if state.useCloudTargeting and Spring.DiffTimers(currentTime, state.lastCloudUpdateTime) > 1.0 then
            Log.debug(string.format("Target cloud: center=(%.1f, %.1f, %.1f), radius=%.1f",
                    center.x, center.y, center.z, state.cloudRadius))
            state.lastCloudUpdateTime = currentTime
        end
    end
end

--- Gets the effective target position (actual target or cloud center)
--- @param targetPos table The current target position
--- @return table effectiveTarget The position to aim at
function FPSTargetingSmoothing.getEffectiveTargetPosition(targetPos)
    if not targetPos then
        return nil
    end

    ensureTargetSmoothingState()
    local state = STATE.tracking.fps.targetSmoothing

    -- If cloud targeting is active, blend between actual target and cloud center
    if state.useCloudTargeting and state.cloudCenter then
        local blend = CLOUD_BLEND_FACTOR  -- 85% cloud, 15% actual target

        -- Store previous cloud center for smoothing
        if not state.previousCloudCenter then
            state.previousCloudCenter = {
                x = state.cloudCenter.x,
                y = state.cloudCenter.y,
                z = state.cloudCenter.z
            }
        end

        -- Smooth the cloud center (temporal smoothing)
        local cloudSmoothFactor = 0.1  -- How quickly cloud center can move
        local smoothedCloudX = state.previousCloudCenter.x +
                (state.cloudCenter.x - state.previousCloudCenter.x) * cloudSmoothFactor
        local smoothedCloudY = state.previousCloudCenter.y +
                (state.cloudCenter.y - state.previousCloudCenter.y) * cloudSmoothFactor
        local smoothedCloudZ = state.previousCloudCenter.z +
                (state.cloudCenter.z - state.previousCloudCenter.z) * cloudSmoothFactor

        -- Update previous cloud center for next frame
        state.previousCloudCenter.x = smoothedCloudX
        state.previousCloudCenter.y = smoothedCloudY
        state.previousCloudCenter.z = smoothedCloudZ

        -- Blend between actual target and smoothed cloud center
        return {
            x = targetPos.x * (1-blend) + smoothedCloudX * blend,
            y = targetPos.y * (1-blend) + smoothedCloudY * blend,
            z = targetPos.z * (1-blend) + smoothedCloudZ * blend
        }
    end

    -- Default to actual target position
    return targetPos
end

--- Predicts target position based on velocity
--- @param targetPos table Current target position {x, y, z}
--- @param targetUnitID number|nil Target unit ID if targeting a unit
--- @return table predictedPos Predicted target position
function FPSTargetingSmoothing.predictTargetPosition(targetPos, targetUnitID)
    if not targetPos then
        return nil
    end

    ensureTargetSmoothingState()
    local state = STATE.tracking.fps.targetSmoothing

    -- Skip prediction if not enabled
    if not state.targetPrediction.enabled then
        return targetPos
    end

    local currentTime = Spring.GetTimer()
    local timeDiff = 0
    if state.targetPrediction.lastUpdateTime then
        timeDiff = Spring.DiffTimers(currentTime, state.targetPrediction.lastUpdateTime)
    end

    -- Only update velocity every ~0.1 seconds
    if targetUnitID and Spring.ValidUnitID(targetUnitID) and timeDiff > 0.1 then
        -- Get unit velocity directly if possible
        local vx, vy, vz = Spring.GetUnitVelocity(targetUnitID)
        if vx then
            state.targetPrediction.velocityX = vx
            state.targetPrediction.velocityY = vy
            state.targetPrediction.velocityZ = vz
            state.targetPrediction.lastUpdateTime = currentTime
        end
    end

    -- Apply velocity-based prediction (looking ahead 0.3 seconds)
    local lookAheadTime = 0.3
    local predictedPos = {
        x = targetPos.x + (state.targetPrediction.velocityX * lookAheadTime),
        y = targetPos.y + (state.targetPrediction.velocityY * lookAheadTime),
        z = targetPos.z + (state.targetPrediction.velocityZ * lookAheadTime)
    }

    return predictedPos
end

--- Constrains camera rotation rate to reduce disorientation
--- @param desiredYaw number Desired yaw angle
--- @param desiredPitch number Desired pitch angle
--- @return number constrainedYaw Constrained yaw angle
--- @return number constrainedPitch Constrained pitch angle
function FPSTargetingSmoothing.constrainRotationRate(desiredYaw, desiredPitch)
    ensureTargetSmoothingState()
    local state = STATE.tracking.fps.targetSmoothing

    -- Skip constraint if not enabled
    if not state.rotationConstraint.enabled then
        return desiredYaw, desiredPitch
    end

    -- Initialize last values if needed
    if not state.rotationConstraint.lastYaw then
        state.rotationConstraint.lastYaw = desiredYaw
        state.rotationConstraint.lastPitch = desiredPitch
        return desiredYaw, desiredPitch
    end

    -- Calculate angle differences
    local yawDiff = CameraCommons.normalizeAngle(desiredYaw - state.rotationConstraint.lastYaw)
    local pitchDiff = desiredPitch - state.rotationConstraint.lastPitch

    -- Constrain to maximum rotation rate
    local maxRate = state.rotationConstraint.maxRotationRate
    local dampingFactor = state.rotationConstraint.damping

    -- Apply constraints with damping
    if math.abs(yawDiff) > maxRate then
        yawDiff = (yawDiff > 0) and maxRate or -maxRate
        yawDiff = yawDiff * dampingFactor
    end

    if math.abs(pitchDiff) > maxRate then
        pitchDiff = (pitchDiff > 0) and maxRate or -maxRate
        pitchDiff = pitchDiff * dampingFactor
    end

    -- Calculate new constrained values
    local constrainedYaw = state.rotationConstraint.lastYaw + yawDiff
    local constrainedPitch = state.rotationConstraint.lastPitch + pitchDiff

    -- Update last values for next frame
    state.rotationConstraint.lastYaw = constrainedYaw
    state.rotationConstraint.lastPitch = constrainedPitch

    -- Normalize yaw to stay in proper range
    constrainedYaw = CameraCommons.normalizeAngle(constrainedYaw)

    return constrainedYaw, constrainedPitch
end

--- Process a target for camera orientation, applying all smoothing techniques
--- @param targetPos table Raw target position {x, y, z}
--- @param targetUnitID number|nil Target unit ID if targeting a unit
--- @return table processedTarget Processed target position for camera orientation
function FPSTargetingSmoothing.processTarget(targetPos, targetUnitID)
    if not targetPos then
        return nil
    end

    -- Update target history for cloud targeting
    FPSTargetingSmoothing.updateTargetHistory(targetPos)

    -- Get the effective target (cloud center or actual target)
    local effectiveTarget = FPSTargetingSmoothing.getEffectiveTargetPosition(targetPos)

    -- Apply target prediction if enabled
    local predictedTarget = FPSTargetingSmoothing.predictTargetPosition(effectiveTarget, targetUnitID)

    -- Return the processed target
    return predictedTarget
end

--- Configures target smoothing settings
--- @param settings table Settings to apply
function FPSTargetingSmoothing.configure(settings)
    ensureTargetSmoothingState()
    local state = STATE.tracking.fps.targetSmoothing

    if settings.cloudBlendFactor then
        CLOUD_BLEND_FACTOR = math.max(0, math.min(1, settings.cloudBlendFactor))
    end

    if settings.targetPrediction ~= nil then
        state.targetPrediction.enabled = settings.targetPrediction
    end

    if settings.rotationConstraint ~= nil then
        state.rotationConstraint.enabled = settings.rotationConstraint
    end

    if settings.maxRotationRate then
        state.rotationConstraint.maxRotationRate = settings.maxRotationRate
    end

    if settings.rotationDamping then
        state.rotationConstraint.damping = settings.rotationDamping
    end

    Log.info("Target smoothing settings updated")
end

return {
    FPSTargetingSmoothing = FPSTargetingSmoothing
}