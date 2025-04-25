---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG
local Util = CommonModules.Util
local Log = CommonModules.Log

---@class FPSTargetingUtils
local FPSTargetingUtils = {}

-- Constants for air target handling
local AIR_HEIGHT_THRESHOLD = 80      -- Minimum height to consider a target as "air"
local ACTIVATION_ANGLE = 0.5         -- Minimum angle to activate air target adjustment
local DEACTIVATION_ANGLE = 0.4       -- Angle to deactivate adjustment (hysteresis)

-- Constants for target grouping (cloud targeting)
local TARGET_HISTORY_SIZE = 20       -- How many recent targets to track
local TARGET_HISTORY_DURATION = 3.0  -- How long targets remain in history (seconds)
local MIN_TARGETS_FOR_CLOUD = 3      -- Minimum targets needed to form a "cloud"
local CLOUD_RADIUS = 300             -- Maximum radius for targets to be considered in the same cloud
local CLOUD_BLEND_FACTOR = 0.7       -- How much to blend between actual target and cloud center (0-1)
local TARGET_SWITCH_THRESHOLD = 0.3  -- Time threshold (seconds) to detect rapid target switching

-- Initialize global state if needed
local function ensureGlobalState()
    if not STATE.tracking.fps.targetingGlobal then
        STATE.tracking.fps.targetingGlobal = {
            targetHistory = {}, -- Recent target positions
            cloudCenter = nil, -- Center of the target cloud
            cloudRadius = 0, -- Radius of the target cloud
            useCloudTargeting = false, -- Whether to use cloud targeting
            cloudStartTime = nil, -- When cloud targeting began
            lastCloudUpdateTime = Spring.GetTimer(),
            highActivityDetected = false,
            activityLevel = 0, -- Measure of targeting activity (0-1)
            lastTargetSwitchTime = Spring.GetTimer(),
            targetSwitchCount = 0, -- Number of target switches in short period
            lastStatusLogTime = Spring.GetTimer(),
            stateInitialized = true
        }
    end
end

-- Initialize target-specific tracking data
local function ensureTargetTracking(targetKey)
    if not STATE.tracking.fps.targetTracking then
        STATE.tracking.fps.targetTracking = {}
    end

    if not STATE.tracking.fps.targetTracking[targetKey] then
        STATE.tracking.fps.targetTracking[targetKey] = {
            lastUpdateTime = Spring.GetTimer(),
            lastRealPos = nil,
            positionHistory = {},
            isCachedTarget = false,
            cachedTargetDuration = 0,
            velocityX = 0,
            velocityY = 0,
            velocityZ = 0,
            speed = 0,
            ySpeed = 0,
            lastVelocityLogTime = Spring.GetTimer(),
            lastLogTime = Spring.GetTimer(),
            isMovingFast = false,
            isMovingUpFast = false,
            frameCounter = 0,
            airAdjustmentActive = false,
            lastAdjustmentStateTime = Spring.GetTimer()
        }

        -- Track target switch times
        local currentTime = Spring.GetTimer()
        local globalState = STATE.tracking.fps.targetingGlobal
        local timeSinceLastSwitch = Spring.DiffTimers(currentTime, globalState.lastTargetSwitchTime)

        if timeSinceLastSwitch < TARGET_SWITCH_THRESHOLD then
            globalState.targetSwitchCount = globalState.targetSwitchCount + 1

            -- If we're switching targets rapidly, this is a good indicator to use cloud targeting
            if globalState.targetSwitchCount >= 3 and not globalState.highActivityDetected then
                Log.info("Rapid target switching detected - enabling cloud targeting")
                globalState.highActivityDetected = true
                globalState.cloudStartTime = currentTime
            end
        else
            -- Reset counter if switches aren't happening rapidly
            globalState.targetSwitchCount = 1
        end

        globalState.lastTargetSwitchTime = currentTime
    end

    return STATE.tracking.fps.targetTracking[targetKey]
end

--- Gets or creates tracking data for a specific target
--- @param targetPos table The target position
--- @return table targetData The tracking data for this target
--- @return string targetKey The key for this target
local function getTargetTrackingData(targetPos)
    -- Create a target key based on position (rounded to avoid minor fluctuations)
    local targetKey = string.format("%.0f_%.0f_%.0f",
            math.floor(targetPos.x), math.floor(targetPos.y), math.floor(targetPos.z))

    -- Ensure global state exists
    ensureGlobalState()

    -- Ensure target-specific tracking exists
    local targetData = ensureTargetTracking(targetKey)

    return targetData, targetKey
end

--- Detects if a position is being cached (not updated in real time)
--- @param targetPos table The current target position
--- @param targetData table The target-specific tracking data
--- @return boolean isCached Whether the position is cached
local function detectCachedPosition(targetPos, targetData)
    -- Check if the position is exactly the same as the last real position
    if targetData.lastRealPos and
            targetPos.x == targetData.lastRealPos.x and
            targetPos.y == targetData.lastRealPos.y and
            targetPos.z == targetData.lastRealPos.z then
        targetData.cachedTargetDuration = targetData.cachedTargetDuration + 1
        return true
    else
        -- Not using a cached position, or first frame
        targetData.lastRealPos = {
            x = targetPos.x,
            y = targetPos.y,
            z = targetPos.z
        }
        targetData.cachedTargetDuration = 0
        return false
    end
end

--- Estimates velocity for a target based on position history or simulation
--- @param targetPos table The target position
--- @param unitPos table The unit position
--- @param horizontalDist number Horizontal distance to target
--- @param targetData table The target-specific tracking data
--- @param using_cached_target boolean Whether using a cached target
local function updateTargetVelocity(targetPos, unitPos, horizontalDist, targetData, using_cached_target)
    local currentTime = Spring.GetTimer()

    -- For high-speed target detection with cached positions, simulate target motion
    if using_cached_target and targetData.cachedTargetDuration > 30 then
        -- Air units typically move at 80-150 units/second
        -- For high-speed fighters, assume around 120 units/second
        local estimated_speed = 120.0

        -- Direction from our unit to the target (normalized)
        local dx = targetPos.x - unitPos.x
        local dz = targetPos.z - unitPos.z
        local dirX, dirZ

        if horizontalDist > 0.001 then
            dirX = dx / horizontalDist
            dirZ = dz / horizontalDist
        else
            dirX, dirZ = 0, 1  -- Default direction if target is directly above
        end

        -- Apply some randomness to make it feel natural
        local randomFactor = (math.random() * 0.4) + 0.8  -- 0.8 to 1.2

        -- Set estimated velocity components
        targetData.velocityX = dirX * estimated_speed * randomFactor
        targetData.velocityZ = dirZ * estimated_speed * randomFactor

        -- Assume slight vertical movement for fighters
        targetData.velocityY = (math.random() * 20) - 10  -- -10 to +10

        -- Calculate total speed
        targetData.speed = math.sqrt(
                targetData.velocityX * targetData.velocityX +
                        targetData.velocityY * targetData.velocityY +
                        targetData.velocityZ * targetData.velocityZ
        )

        -- Set vertical speed component
        targetData.ySpeed = targetData.velocityY

        -- For cached targets, we generally won't detect "fast upward movement"
        targetData.isMovingFast = targetData.speed > 150
        targetData.isMovingUpFast = false

        -- Log estimated velocity periodically
        if Spring.DiffTimers(currentTime, targetData.lastVelocityLogTime) > 1.0 then
            Log.trace(string.format("Estimated target velocity: %.1f units/s (x=%.1f, y=%.1f, z=%.1f)",
                    targetData.speed, targetData.velocityX, targetData.velocityY, targetData.velocityZ))
            targetData.lastVelocityLogTime = currentTime
        end
    else
        -- Normal velocity sampling (only useful for actively tracked targets)
        targetData.frameCounter = targetData.frameCounter + 1

        -- Only update velocity when we have a real position update
        if not using_cached_target and targetData.frameCounter % 3 == 0 then
            -- Update position history when we have real position data
            table.insert(targetData.positionHistory, {
                pos = { x = targetPos.x, y = targetPos.y, z = targetPos.z },
                time = currentTime
            })

            -- Keep only the last 5 position records
            if #targetData.positionHistory > 5 then
                table.remove(targetData.positionHistory, 1)
            end

            -- Calculate velocity if we have enough history (at least 2 points)
            if #targetData.positionHistory >= 2 then
                local newest = targetData.positionHistory[#targetData.positionHistory]
                local oldest = targetData.positionHistory[1]

                local timeDiff = Spring.DiffTimers(newest.time, oldest.time)

                -- Ensure we have a meaningful time difference
                if timeDiff > 0.05 then
                    -- Calculate velocity components
                    targetData.velocityX = (newest.pos.x - oldest.pos.x) / timeDiff
                    targetData.velocityY = (newest.pos.y - oldest.pos.y) / timeDiff
                    targetData.velocityZ = (newest.pos.z - oldest.pos.z) / timeDiff

                    -- Calculate speed magnitudes
                    targetData.speed = math.sqrt(
                            targetData.velocityX * targetData.velocityX +
                                    targetData.velocityY * targetData.velocityY +
                                    targetData.velocityZ * targetData.velocityZ
                    )
                    targetData.ySpeed = targetData.velocityY

                    -- Flag for fast-moving targets
                    local speedThreshold = 200  -- Units per second
                    local upSpeedThreshold = 150  -- Upward units per second

                    local prevIsMovingFast = targetData.isMovingFast
                    local prevIsMovingUpFast = targetData.isMovingUpFast

                    targetData.isMovingFast = targetData.speed > speedThreshold
                    targetData.isMovingUpFast = targetData.ySpeed > upSpeedThreshold

                    -- Log when movement state changes
                    if targetData.isMovingUpFast and not prevIsMovingUpFast then
                        Log.info(string.format("Fast upward movement detected: %.1f units/s (threshold: %.1f)",
                                targetData.ySpeed, upSpeedThreshold))
                    elseif not targetData.isMovingUpFast and prevIsMovingUpFast then
                        Log.info("Target no longer moving fast upward")
                    end

                    -- Log velocity periodically
                    if Spring.DiffTimers(currentTime, targetData.lastVelocityLogTime) > 1.0 then
                        Log.trace(string.format("Target velocity: %.1f units/s (x=%.1f, y=%.1f, z=%.1f)",
                                targetData.speed, targetData.velocityX, targetData.velocityY, targetData.velocityZ))
                        targetData.lastVelocityLogTime = currentTime
                    end
                end
            end
        end
    end
end

--- Updates the global target history for cloud targeting
--- @param targetPos table The current target position
--- @param targetKey string The target key
local function updateTargetHistory(targetPos, targetKey)
    local currentTime = Spring.GetTimer()
    local globalState = STATE.tracking.fps.targetingGlobal

    -- Add current target to history
    table.insert(globalState.targetHistory, {
        pos = { x = targetPos.x, y = targetPos.y, z = targetPos.z },
        key = targetKey,
        time = currentTime
    })

    -- Remove old targets
    local i = 1
    while i <= #globalState.targetHistory do
        local timeDiff = Spring.DiffTimers(currentTime, globalState.targetHistory[i].time)
        if timeDiff > TARGET_HISTORY_DURATION then
            table.remove(globalState.targetHistory, i)
        else
            i = i + 1
        end
    end

    -- Keep history size reasonable
    while #globalState.targetHistory > TARGET_HISTORY_SIZE do
        table.remove(globalState.targetHistory, 1)
    end

    -- Count unique targets in recent history
    local uniqueTargets = {}
    for _, target in ipairs(globalState.targetHistory) do
        uniqueTargets[target.key] = true
    end
    local uniqueTargetCount = 0
    for _ in pairs(uniqueTargets) do
        uniqueTargetCount = uniqueTargetCount + 1
    end

    -- Calculate activity level based on target history size and target switch count
    local historySizeFactor = math.min(uniqueTargetCount / MIN_TARGETS_FOR_CLOUD, 1.0)
    local switchFactor = math.min(globalState.targetSwitchCount / 3, 1.0)
    globalState.activityLevel = math.max(historySizeFactor, switchFactor)

    -- Update high activity flag
    if globalState.activityLevel >= 0.8 and not globalState.highActivityDetected then
        globalState.highActivityDetected = true
        Log.info("High targeting activity detected - enabling cloud targeting")
        globalState.cloudStartTime = currentTime
    elseif globalState.activityLevel < 0.4 and globalState.highActivityDetected then
        globalState.highActivityDetected = false
        Log.info("Targeting activity normalized - disabling cloud targeting")
        globalState.cloudStartTime = nil
    end

    -- Periodically log activity level
    if Spring.DiffTimers(currentTime, globalState.lastStatusLogTime) > 1.0 then
        if globalState.activityLevel > 0.5 then
            Log.trace(string.format("Targeting activity level: %.2f (%d unique targets in %d history, %d rapid switches)",
                    globalState.activityLevel, uniqueTargetCount, #globalState.targetHistory, globalState.targetSwitchCount))
        end
        globalState.lastStatusLogTime = currentTime
    end

    -- Decide whether to use cloud targeting
    globalState.useCloudTargeting = (globalState.highActivityDetected and
            (uniqueTargetCount >= MIN_TARGETS_FOR_CLOUD or globalState.targetSwitchCount >= 3))

    -- Calculate cloud center if needed
    if globalState.useCloudTargeting then
        FPSTargetingUtils.calculateCloudCenter()
    end
end

--- Gets the appropriate target position (actual target or cloud center)
--- @param targetPos table The current target position
--- @return table effectiveTarget The position to aim at
local function getEffectiveTargetPosition(targetPos)
    local globalState = STATE.tracking.fps.targetingGlobal

    -- If cloud targeting is active, use the cloud center instead of the current target
    if globalState.useCloudTargeting and globalState.cloudCenter then
        -- Apply some smoothing/interpolation between actual target and cloud center
        local blend = CLOUD_BLEND_FACTOR  -- 70% cloud, 30% actual target
        return {
            x = targetPos.x * (1 - blend) + globalState.cloudCenter.x * blend,
            y = targetPos.y * (1 - blend) + globalState.cloudCenter.y * blend,
            z = targetPos.z * (1 - blend) + globalState.cloudCenter.z * blend
        }
    end

    -- Default to actual target position
    return targetPos
end

--- Handles air target camera positioning adjustments
--- @param position table Camera position {x, y, z}
--- @param targetPos table Target position {x, y, z}
--- @param unitPos table Base unit position {x, y, z}
--- @return table adjustedPos Adjusted camera position {x, y, z}
function FPSTargetingUtils.handleAirTargetRepositioning(position, targetPos, unitPos)
    if not position or not targetPos then
        return position
    end

    -- Get target-specific tracking data
    local targetData, targetKey = getTargetTrackingData(targetPos)

    -- Store original position for reference
    local x, y, z = position.x, position.y, position.z

    -- Check if we're using a cached target position
    local using_cached_target = detectCachedPosition(targetPos, targetData)
    targetData.isCachedTarget = using_cached_target

    -- Log when the target position state changes
    local currentTime = Spring.GetTimer()
    if Spring.DiffTimers(currentTime, targetData.lastLogTime) > 1.0 then
        if using_cached_target then
            Log.trace(string.format("Using cached target position (duration: %d frames)",
                    targetData.cachedTargetDuration))
        else
            Log.trace("Using real-time target position")
        end
        targetData.lastLogTime = currentTime
    end

    -- Update target history for cloud targeting
    updateTargetHistory(targetPos, targetKey)

    -- Get the effective target position (actual target or cloud center)
    local effectiveTarget = getEffectiveTargetPosition(targetPos)

    -- Check if target is significantly above the unit (air unit)
    local heightDiff = effectiveTarget.y - unitPos.y

    -- Early exit if target isn't significantly above unit
    if heightDiff <= AIR_HEIGHT_THRESHOLD then
        targetData.airAdjustmentActive = false
        return position
    end

    -- Calculate angle to target in vertical plane
    local dx = effectiveTarget.x - unitPos.x
    local dy = heightDiff
    local dz = effectiveTarget.z - unitPos.z
    local horizontalDist = math.sqrt(dx * dx + dz * dz)
    local verticalAngle = math.atan2(dy, horizontalDist)

    -- Update target velocity
    updateTargetVelocity(effectiveTarget, unitPos, horizontalDist, targetData, using_cached_target)

    -- Determine if we need to activate air targeting adjustments (with hysteresis)
    local activationAngle = targetData.airAdjustmentActive
            and DEACTIVATION_ANGLE or ACTIVATION_ANGLE

    -- NEW: Check if we are in a stabilized camera state
    -- If we are, be more conservative with air adjustments to prevent jumps
    if STATE.tracking.fps.stableCamPos and STATE.tracking.fps.targetSmoothing and
            STATE.tracking.fps.targetSmoothing.activityLevel > 0.5 then
        -- Higher threshold during stabilization to prevent camera jumps
        activationAngle = activationAngle * 1.3

        -- If we were not previously in air adjustment mode,
        -- require a significantly steeper angle to activate during stabilization
        if not targetData.airAdjustmentActive then
            activationAngle = activationAngle * 1.5
        end

        -- Log this modified behavior
        if not targetData.lastStabilizedAdjustmentLog or
                Spring.DiffTimers(currentTime, targetData.lastStabilizedAdjustmentLog) > 2.0 then
            Log.debug("Using higher air adjustment threshold during stabilization")
            targetData.lastStabilizedAdjustmentLog = currentTime
        end
    end

    -- Skip adjustment if target is moving too fast upward and we're not already tracking it
    if targetData.isMovingUpFast and not targetData.airAdjustmentActive then
        Log.trace("Skipping adjustment for fast upward-moving target")
        return position
    end

    -- If angle is steep enough, adjust camera position
    if verticalAngle > activationAngle then
        -- Only log state changes, not every frame
        if not targetData.airAdjustmentActive then
            -- Only log the activation message once per second at most
            if Spring.DiffTimers(currentTime, targetData.lastAdjustmentStateTime) > 1.0 then
                Log.info(string.format("Activating air target adjustment mode (angle: %.2f, threshold: %.2f)",
                        verticalAngle, activationAngle))
                targetData.lastAdjustmentStateTime = currentTime
            end
        end

        targetData.airAdjustmentActive = true

        -- Calculate adjustment based on angle
        -- Higher angle = stronger adjustment
        local angleRatio = math.min((verticalAngle - ACTIVATION_ANGLE) / (math.pi / 2 - ACTIVATION_ANGLE), 1.0)
        local adjustmentFactor = 0.3 + (angleRatio * 0.4)  -- Range from 0.3 to 0.7

        -- NEW: Reduce adjustment factor during stabilization to avoid jarring movements
        if STATE.tracking.fps.stableCamPos then
            adjustmentFactor = adjustmentFactor * 0.7
        end

        -- Determine if we're very close to the target (directly underneath)
        local isCloseToTarget = horizontalDist < 300
        local isVeryCloseToTarget = horizontalDist < 200
        local isHighTargetMode = verticalAngle > 0.8  -- ~45 degrees

        -- Distance-based adjustment - more aggressive repositioning when close
        local distanceAdjustment = 1.0
        if isCloseToTarget then
            distanceAdjustment = 1.4  -- More aggressive when close
            if isVeryCloseToTarget then
                distanceAdjustment = 1.7  -- Even more aggressive when very close
            end
        end

        -- NEW: Reduce distance adjustment during stabilization
        if STATE.tracking.fps.stableCamPos then
            distanceAdjustment = distanceAdjustment * 0.8
        end

        -- For high targets, focus more on moving back to keep unit in view
        local upRatio, backRatio

        -- When directly underneath, move much more back and less up
        if isVeryCloseToTarget and verticalAngle > 1.3 then
            -- Almost overhead
            -- Closest and steepest case - much more backward
            upRatio = 0.15  -- Minimal upward movement
            backRatio = 1.5 * distanceAdjustment  -- Maximize backward movement
        elseif isHighTargetMode then
            -- High target mode: prioritize moving back to keep unit in view
            upRatio = math.min(verticalAngle * 0.25, 0.3) * (isCloseToTarget and 0.7 or 1.0)  -- Reduced upward when close
            backRatio = (0.9 + (angleRatio * 0.3)) * distanceAdjustment  -- Range from 0.9 to 1.2 * adjustment
        else
            -- Normal mode: still favor back movement
            upRatio = math.min(verticalAngle * 0.35, 0.4)  -- Reduced upward movement
            backRatio = (0.8 + (angleRatio * 0.3)) * distanceAdjustment  -- Range from 0.8 to 1.1 * adjustment
        end

        -- Apply the adjustment factor to both movements
        -- Calculate distance to move camera
        local moveUp = math.min(heightDiff * upRatio * adjustmentFactor, 90)  -- Reduced maximum height
        local moveBack = math.min(horizontalDist * backRatio * adjustmentFactor, 220)  -- Increased maximum back distance

        -- NEW: When using camera stabilization, apply changes more gradually
        if STATE.tracking.fps.stableCamPos and targetData.lastAdjustedPosition then
            -- Get last adjusted position
            local lastPos = targetData.lastAdjustedPosition

            -- Calculate gradual movement toward new adjustment (50% blend by default)
            local blendFactor = 0.2

            -- Calculate blended adjustments
            local lastMoveUp = y - position.y
            local newMoveUp = moveUp
            moveUp = lastMoveUp + (newMoveUp - lastMoveUp) * blendFactor

            -- Calculate horizontal movement components
            if horizontalDist > 0.001 then
                local horNormX = dx / horizontalDist
                local horNormZ = dz / horizontalDist

                -- Calculate new position without adjustments first
                local newX = x - horNormX * moveBack
                local newZ = z - horNormZ * moveBack

                -- Blend with previous position
                x = lastPos.x + (newX - lastPos.x) * blendFactor
                z = lastPos.z + (newZ - lastPos.z) * blendFactor
                y = y + moveUp
            end

            -- Store adjusted position for next frame
            targetData.lastAdjustedPosition = {x = x, y = y, z = z}

            return {x = x, y = y, z = z}
        end

        -- Apply vertical adjustment
        y = y + moveUp

        -- Apply backward movement along the horizontal vector to target
        if horizontalDist > 0.001 then
            local horNormX = dx / horizontalDist
            local horNormZ = dz / horizontalDist
            x = x - horNormX * moveBack
            z = z - horNormZ * moveBack
        end

        -- Store adjusted position for next frame
        targetData.lastAdjustedPosition = {x = x, y = y, z = z}

        -- Enhanced logging with more details - but only once per second
        if Spring.DiffTimers(currentTime, targetData.lastVelocityLogTime) > 1.0 then
            Log.trace(string.format(
                    "Air target adjustment: up=%.1f, back=%.1f, angle=%.2f, dist=%.1f, stabilized=%s",
                    moveUp, moveBack, verticalAngle, horizontalDist,
                    STATE.tracking.fps.stableCamPos and "true" or "false"))
        end

        return { x = x, y = y, z = z }
    else
        if targetData.airAdjustmentActive then
            -- Only log the deactivation message once per second at most
            if Spring.DiffTimers(currentTime, targetData.lastAdjustmentStateTime) > 1.0 then
                Log.info(string.format("Deactivating air target adjustment (angle: %.2f, threshold: %.2f)",
                        verticalAngle, activationAngle))
                targetData.lastAdjustmentStateTime = currentTime
            end
        end

        -- No longer meets criteria for adjustment
        targetData.airAdjustmentActive = false
        targetData.lastAdjustedPosition = nil
        return position
    end
end

-- Add to FPSTargetingUtils
function FPSTargetingUtils.detectCircularMotion(history)
    local directionChanges = 0
    local lastDx, lastDz = 0, 0

    for i = 2, #history do
        local dx = history[i].pos.x - history[i - 1].pos.x
        local dz = history[i].pos.z - history[i - 1].pos.z

        if lastDx ~= 0 and lastDz ~= 0 then
            -- Calculate cross product to detect direction change
            local cross = lastDx * dz - lastDz * dx
            if math.abs(cross) > 0.1 then
                directionChanges = directionChanges + 1
            end
        end

        lastDx, lastDz = dx, dz
    end

    -- If we have multiple direction changes, likely circular
    return directionChanges >= 4
end

--- Calculates the center of the target cloud
function FPSTargetingUtils.calculateCloudCenter()
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

        -- Add a maximum cloud radius to prevent large jumps
        local MAX_CLOUD_RADIUS = 150  -- Maximum allowed cloud radius
        state.cloudRadius = math.sqrt(maxDistSq)

        if state.cloudRadius > MAX_CLOUD_RADIUS then
            state.cloudRadius = MAX_CLOUD_RADIUS
            Log.trace(string.format("Cloud radius clamped to maximum (%d)", MAX_CLOUD_RADIUS))
        end

        state.cloudCenter = center

        -- Log cloud updates periodically
        if state.useCloudTargeting and state.lastCloudUpdateTime and
                Spring.DiffTimers(currentTime, state.lastCloudUpdateTime) > 1.0 then
            Log.debug(string.format("Target cloud: center=(%.1f, %.1f, %.1f), radius=%.1f",
                    center.x, center.y, center.z, state.cloudRadius))
            state.lastCloudUpdateTime = currentTime
        end
    end
end

return {
    FPSTargetingUtils = FPSTargetingUtils
}