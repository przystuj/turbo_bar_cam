---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "UnitFollowTargetingSmoothing")
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local UnitFollowTargetingUtils = ModuleManager.UnitFollowTargetingUtils(function(m) UnitFollowTargetingUtils = m end)

---@class UnitFollowTargetingSmoothing
local UnitFollowTargetingSmoothing = {}

-- Constants for target smoothing
local TARGET_HISTORY_SIZE = 20       -- Maximum number of recent targets to track
local TARGET_HISTORY_DURATION = 3.0  -- How long targets remain in history (seconds)
local MIN_TARGETS_FOR_CLOUD = 3      -- Minimum targets needed to form a "cloud"
local CLOUD_BLEND_FACTOR = 0.7       -- How much to blend between actual target and cloud center (0-1)
local TARGET_SWITCH_THRESHOLD = 0.3  -- Time threshold (seconds) to detect rapid target switching

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
function UnitFollowTargetingSmoothing.updateTargetHistory(targetPos)
    if not targetPos then
        return
    end

    local state = STATE.active.mode.unit_follow.targetSmoothing
    local currentTime = Spring.GetTimer()

    -- Ensure all timer values are initialized
    if not state.lastTargetSwitchTime then
        state.lastTargetSwitchTime = currentTime
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
                Log:info("Rapid target switching detected - enabling cloud targeting")
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
        pos = { x = targetPos.x, y = targetPos.y, z = targetPos.z },
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
        Log:info("High targeting activity detected - enabling cloud targeting")
        state.cloudStartTime = currentTime

        -- Add a minimum duration for cloud targeting (3 seconds)
        state.minCloudDuration = Spring.GetTimer()
    elseif state.activityLevel < 0.3 and state.highActivityDetected then
        -- Only disable if minimum duration has passed
        local hasMinDurationPassed = not state.minCloudDuration or
                Spring.DiffTimers(currentTime, state.minCloudDuration) > 3.0

        if hasMinDurationPassed then
            state.highActivityDetected = false
            Log:info("Targeting activity normalized - disabling cloud targeting")
            state.cloudStartTime = nil
        end
    end

    -- Decide whether to use cloud targeting
    state.useCloudTargeting = (state.highActivityDetected and
            (uniqueTargetCount >= MIN_TARGETS_FOR_CLOUD or state.targetSwitchCount >= 3))

    -- Calculate cloud center if needed
    if state.useCloudTargeting then
        UnitFollowTargetingUtils.calculateCloudCenter()
    end
end

--- Gets the effective target position (actual target or cloud center)
--- @param targetPos table The current target position
--- @return table effectiveTarget The position to aim at
function UnitFollowTargetingSmoothing.getEffectiveTargetPosition(targetPos)
    if not targetPos then
        return nil
    end

    local state = STATE.active.mode.unit_follow.targetSmoothing

    -- Get unit position
    local unitPos = nil
    if STATE.active.mode.unitID and Spring.ValidUnitID(STATE.active.mode.unitID) then
        local x, y, z = Spring.GetUnitPosition(STATE.active.mode.unitID)
        unitPos = { x = x, y = y, z = z }
    end

    -- For aerial targets, check if we have tracking data from UnitFollowTargetingUtils
    local isAerialTarget = unitPos and targetPos.y > (unitPos.y + 80)
    local targetData = nil

    if isAerialTarget then
        -- Get the target tracking data from your existing system
        local targetKey = string.format("%.0f_%.0f_%.0f",
                math.floor(targetPos.x), math.floor(targetPos.y), math.floor(targetPos.z))

        if STATE.active.mode.unit_follow.targetTracking and STATE.active.mode.unit_follow.targetTracking[targetKey] then
            targetData = STATE.active.mode.unit_follow.targetTracking[targetKey]

            -- Process aerial target using your velocity data
            local smoothedAerialPos = UnitFollowTargetingSmoothing.processAerialTarget(
                    targetPos, unitPos, targetData)

            -- If cloud targeting is also active, blend between cloud and aerial tracking
            if state.useCloudTargeting and state.cloudCenter then
                local blend = CLOUD_BLEND_FACTOR * 0.8  -- Reduced cloud influence for aerial targets
                return {
                    x = smoothedAerialPos.x * (1 - blend) + state.cloudCenter.x * blend,
                    y = smoothedAerialPos.y * (1 - blend) + state.cloudCenter.y * blend,
                    z = smoothedAerialPos.z * (1 - blend) + state.cloudCenter.z * blend
                }
            else
                return smoothedAerialPos
            end
        end
    end
    -- Regular cloud targeting for non-aerial targets
    if state.useCloudTargeting and state.cloudCenter then
        -- Apply smoothing/interpolation between actual target and cloud center
        local blend = CLOUD_BLEND_FACTOR

        -- Store previous cloud center for smoothing
        if not state.previousCloudCenter then
            state.previousCloudCenter = {
                x = state.cloudCenter.x,
                y = state.cloudCenter.y,
                z = state.cloudCenter.z
            }
        end
        -- Apply smooth transitioning for cloud center
        local cloudSmoothFactor = 0.05  -- Base smoothing factor (slower)
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
            x = targetPos.x * (1 - blend) + smoothedCloudX * blend,
            y = targetPos.y * (1 - blend) + smoothedCloudY * blend,
            z = targetPos.z * (1 - blend) + smoothedCloudZ * blend
        }
    end

    -- Default to actual target position
    return targetPos
end

--- Predicts target position based on velocity
--- @param targetPos table Current target position {x, y, z}
--- @param targetUnitID number|nil Target unit ID if targeting a unit
--- @return table predictedPos Predicted target position
function UnitFollowTargetingSmoothing.predictTargetPosition(targetPos, targetUnitID)
    if not targetPos then
        return nil
    end

    local state = STATE.active.mode.unit_follow.targetSmoothing

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
function UnitFollowTargetingSmoothing.constrainRotationRate(desiredYaw, desiredPitch)
    local state = STATE.active.mode.unit_follow.targetSmoothing

    -- *** Reset constraints state on target switch signal ***
    if state.rotationConstraint.resetForSwitch then
        Log:debug("Resetting rotation constraints state now.")
        state.rotationConstraint.lastYaw = nil -- Force reinitialization on next valid run
        state.rotationConstraint.lastPitch = nil
        state.rotationConstraint.yawVelocity = 0
        state.rotationConstraint.pitchVelocity = 0
        state.rotationConstraint.lastYawDiff = 0
        state.rotationConstraint.lastPitchDiff = 0
        state.rotationConstraint.consecutiveChanges = 0
        state.rotationConstraint.resetForSwitch = false -- Consume the signal
    end

    -- Skip constraint if not enabled
    if not state.rotationConstraint.enabled then
        return desiredYaw, desiredPitch
    end

    -- Initialize last values if needed
    if not state.rotationConstraint.lastYaw then
        -- Don't initialize if a reset just happened and we haven't processed a frame yet
        if state.rotationConstraint.resetForSwitch == false then
            state.rotationConstraint.lastYaw = desiredYaw
            state.rotationConstraint.lastPitch = desiredPitch
            return desiredYaw, desiredPitch
        else
            -- Still waiting for first valid frame after reset
            return desiredYaw, desiredPitch -- Return desired angles directly during reset frame
        end
    end

    -- Calculate angle differences
    local yawDiff = CameraCommons.normalizeAngle(desiredYaw - state.rotationConstraint.lastYaw)
    local pitchDiff = desiredPitch - state.rotationConstraint.lastPitch

    -- Apply adaptive constraints based on rate of change
    local baseMaxRate = state.rotationConstraint.maxRotationRate
    local baseDampingFactor = state.rotationConstraint.damping
    local maxRate = baseMaxRate
    local dampingFactor = baseDampingFactor

    -- Track rotation velocity for adaptive constraint
    if not state.rotationConstraint.yawVelocity then
        state.rotationConstraint.yawVelocity = 0
        state.rotationConstraint.pitchVelocity = 0
        state.rotationConstraint.lastYawDiff = 0
        state.rotationConstraint.lastPitchDiff = 0
        state.rotationConstraint.consecutiveChanges = 0
    end

    -- Update rotation velocity estimate
    local yawAcceleration = math.abs(yawDiff) - math.abs(state.rotationConstraint.lastYawDiff)
    state.rotationConstraint.lastYawDiff = yawDiff

    -- If rotation is accelerating, apply stronger constraints
    if yawAcceleration > 0.01 then
        state.rotationConstraint.consecutiveChanges = state.rotationConstraint.consecutiveChanges + 1
        if state.rotationConstraint.consecutiveChanges > 5 then
            -- Apply stronger constraints when consistent rotation acceleration is detected
            maxRate = baseMaxRate * 0.7
            dampingFactor = baseDampingFactor * 1.2
        end
    else
        state.rotationConstraint.consecutiveChanges = math.max(0, state.rotationConstraint.consecutiveChanges - 1)
    end

    -- Apply constraints with damping
    if math.abs(yawDiff) > maxRate then
        yawDiff = (yawDiff > 0) and maxRate or -maxRate
        yawDiff = yawDiff * dampingFactor
    end

    if math.abs(pitchDiff) > maxRate then
        pitchDiff = (pitchDiff > 0) and maxRate or -maxRate
        pitchDiff = pitchDiff * dampingFactor
    end

    -- Calculate new constrained values with additional inertia
    local inertiaDamping = 0.85 -- How much previous motion affects current motion
    state.rotationConstraint.yawVelocity = state.rotationConstraint.yawVelocity * inertiaDamping + yawDiff * (1 - inertiaDamping)
    state.rotationConstraint.pitchVelocity = state.rotationConstraint.pitchVelocity * inertiaDamping + pitchDiff * (1 - inertiaDamping)

    local constrainedYaw = state.rotationConstraint.lastYaw + state.rotationConstraint.yawVelocity
    local constrainedPitch = state.rotationConstraint.lastPitch + state.rotationConstraint.pitchVelocity

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
function UnitFollowTargetingSmoothing.processTarget(targetPos, targetUnitID)
    if not targetPos then
        return nil
    end

    -- Update target history for cloud targeting
    UnitFollowTargetingSmoothing.updateTargetHistory(targetPos)

    -- Get the effective target (cloud center or actual target)
    local effectiveTarget = UnitFollowTargetingSmoothing.getEffectiveTargetPosition(targetPos)

    -- Apply target prediction if enabled
    local predictedTarget = UnitFollowTargetingSmoothing.predictTargetPosition(effectiveTarget, targetUnitID)

    -- Return the processed target
    return predictedTarget
end

--- Configures target smoothing settings
--- @param settings table Settings to apply
function UnitFollowTargetingSmoothing.configure(settings)
    if settings.cloudBlendFactor then
        CLOUD_BLEND_FACTOR = math.max(0, math.min(1, settings.cloudBlendFactor))
    end

    if settings.targetPrediction ~= nil then
        STATE.active.mode.unit_follow.targetSmoothing.targetPrediction.enabled = settings.targetPrediction
    end

    if settings.rotationConstraint ~= nil then
        STATE.active.mode.unit_follow.targetSmoothing.rotationConstraint.enabled = settings.rotationConstraint
    end

    if settings.maxRotationRate then
        STATE.active.mode.unit_follow.targetSmoothing.rotationConstraint.maxRotationRate = settings.maxRotationRate
    end

    if settings.rotationDamping then
        STATE.active.mode.unit_follow.targetSmoothing.rotationConstraint.damping = settings.rotationDamping
    end

    Log:info("Target smoothing settings updated")
end

function UnitFollowTargetingSmoothing.processAerialTarget(targetPos, unitPos, targetData)
    -- Use the existing velocity data that's already being tracked
    local velocityX = targetData.velocityX or 0
    local velocityY = targetData.velocityY or 0
    local velocityZ = targetData.velocityZ or 0
    local speed = targetData.speed or 0

    -- Initialize aerial tracking data in targetSmoothing if not already present
    if not STATE.active.mode.unit_follow.targetSmoothing.aerialTracking then
        STATE.active.mode.unit_follow.targetSmoothing.aerialTracking = {
            smoothedPosition = {x = targetPos.x, y = targetPos.y, z = targetPos.z},
            lastUpdateTime = Spring.GetTimer(),
            trajectoryPredictionEnabled = true,
            positionHistory = {}
        }
    end

    local aerial = STATE.active.mode.unit_follow.targetSmoothing.aerialTracking

    -- Add to position history
    table.insert(aerial.positionHistory, {
        pos = {x = targetPos.x, y = targetPos.y, z = targetPos.z},
        time = Spring.GetTimer()
    })

    -- Keep history at reasonable size
    while #aerial.positionHistory > 30 do
        table.remove(aerial.positionHistory, 1)
    end

    -- Calculate relative position to unit
    local heightDiff = targetPos.y - unitPos.y
    local dx = targetPos.x - unitPos.x
    local dz = targetPos.z - unitPos.z
    local horizontalDist = math.sqrt(dx*dx + dz*dz)
    local verticalAngle = math.atan2(heightDiff, horizontalDist)

    -- Detect if target is moving in a circular pattern
    local isCircular = #aerial.positionHistory >= 10 and
            UnitFollowTargetingUtils.detectCircularMotion(aerial.positionHistory)

    -- Adjust smoothing based on movement pattern and position relative to unit
    local smoothFactor = 0.08 -- Default

    if isCircular then
        -- Much stronger smoothing for circular patterns
        smoothFactor = 0.03
        Log:trace("Circular aerial motion detected - using stronger smoothing")
    elseif targetData.isMovingFast then
        -- Fast-moving targets need stronger prediction but not too much smoothing
        smoothFactor = 0.06
        Log:trace("Fast aerial motion detected - using prediction")
    end

    -- Further adjust smoothing based on target's position relative to unit
    if verticalAngle > 0.8 then  -- Target is nearly overhead
        smoothFactor = smoothFactor * 0.7  -- Even stronger smoothing for overhead targets
        Log:trace("Overhead target - applying stronger smoothing")
    end

    -- For targets that are very close and high above, increase smoothing even more
    if horizontalDist < 200 and heightDiff > 200 then
        smoothFactor = smoothFactor * 0.6
        Log:trace("Close overhead target - applying maximum smoothing")
    end

    -- Apply trajectory prediction for fast-moving targets
    local predictedPos = targetPos
    if aerial.trajectoryPredictionEnabled and speed > 50 then
        -- Look ahead time depends on speed and position
        local lookAheadTime = math.min(0.4, speed / 600)

        -- For targets circling directly overhead, reduce prediction
        if isCircular and verticalAngle > 0.7 then
            lookAheadTime = lookAheadTime * 0.5
        end

        predictedPos = {
            x = targetPos.x + velocityX * lookAheadTime,
            y = targetPos.y + velocityY * lookAheadTime,
            z = targetPos.z + velocityZ * lookAheadTime
        }
    end

    -- Smooth the position
    aerial.smoothedPosition = {
        x = aerial.smoothedPosition.x + (predictedPos.x - aerial.smoothedPosition.x) * smoothFactor,
        y = aerial.smoothedPosition.y + (predictedPos.y - aerial.smoothedPosition.y) * smoothFactor,
        z = aerial.smoothedPosition.z + (predictedPos.z - aerial.smoothedPosition.z) * smoothFactor
    }

    aerial.lastUpdateTime = Spring.GetTimer()
    return aerial.smoothedPosition
end

return UnitFollowTargetingSmoothing