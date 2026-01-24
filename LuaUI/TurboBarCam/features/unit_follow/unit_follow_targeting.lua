---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "UnitFollowTargeting")

---@class UnitFollowTargeting
local UnitFollowTargeting = {}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

-- Target History & Cloud constants
local TARGET_HISTORY_SIZE = 20       -- Maximum number of recent targets to track
local TARGET_HISTORY_DURATION = 3.0  -- How long targets remain in history (seconds)
local MIN_TARGETS_FOR_CLOUD = 3      -- Minimum targets needed to form a "cloud"
local CLOUD_BLEND_FACTOR = 0.7       -- How much to blend between actual target and cloud center (0-1)
local TARGET_SWITCH_THRESHOLD = 0.3  -- Time threshold (seconds) to detect rapid target switching

-- Air Target Adjustment constants
local AIR_HEIGHT_THRESHOLD = 80      -- Minimum height to consider a target as "air"
local ACTIVATION_ANGLE = 0.5         -- Minimum angle to activate air target adjustment
local DEACTIVATION_ANGLE = 0.4       -- Angle to deactivate adjustment (hysteresis)

-- ============================================================================
-- UTILITIES
-- ============================================================================

--- Creates a unique key for a target position
local function createTargetKey(targetPos)
    return string.format("%.0f_%.0f_%.0f",
            math.floor(targetPos.x / 10) * 10,
            math.floor(targetPos.y / 10) * 10,
            math.floor(targetPos.z / 10) * 10)
end

--- Detects if target is moving in a circular pattern
local function detectCircularMotion(history)
    local directionChanges = 0
    local lastDx, lastDz = 0, 0

    for i = 2, #history do
        local dx = history[i].pos.x - history[i - 1].pos.x
        local dz = history[i].pos.z - history[i - 1].pos.z

        if lastDx ~= 0 and lastDz ~= 0 then
            local cross = lastDx * dz - lastDz * dx
            if math.abs(cross) > 0.1 then
                directionChanges = directionChanges + 1
            end
        end
        lastDx, lastDz = dx, dz
    end
    return directionChanges >= 4
end

--- Detects if a position is being cached (not updated in real time)
local function detectCachedPosition(targetPos, targetData)
    if targetData.lastRealPos and
            targetPos.x == targetData.lastRealPos.x and
            targetPos.y == targetData.lastRealPos.y and
            targetPos.z == targetData.lastRealPos.z then
        targetData.cachedTargetDuration = targetData.cachedTargetDuration + 1
        return true
    else
        targetData.lastRealPos = { x = targetPos.x, y = targetPos.y, z = targetPos.z }
        targetData.cachedTargetDuration = 0
        return false
    end
end

-- ============================================================================
-- CORE LOGIC: HISTORY & CLOUD
-- ============================================================================

--- Calculates the center of the target cloud
local function calculateCloudCenter()
    local state = STATE.active.mode.unit_follow.targeting
    if #state.targetHistory < MIN_TARGETS_FOR_CLOUD then return end

    local sumX, sumY, sumZ, count = 0, 0, 0, 0
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
        local center = { x = sumX / count, y = sumY / count, z = sumZ / count }

        -- Calculate cloud radius
        local maxDistSq = 0
        for _, target in ipairs(state.targetHistory) do
            local dx, dy, dz = target.pos.x - center.x, target.pos.y - center.y, target.pos.z - center.z
            local distSq = dx * dx + dy * dy + dz * dz
            if distSq > maxDistSq then maxDistSq = distSq end
        end

        state.cloudCenter = center
    end
end

--- Updates the target history with the current target
local function updateTargetHistory(targetPos)
    if not targetPos then return end

    local state = STATE.active.mode.unit_follow.targeting
    local currentTime = Spring.GetTimer()

    -- Prevent double updates in same frame
    if state.lastHistoryUpdateFrame == Spring.GetGameFrame() then return end
    state.lastHistoryUpdateFrame = Spring.GetGameFrame()

    if not state.lastTargetSwitchTime then state.lastTargetSwitchTime = currentTime end

    -- Create a key for this target
    local targetKey = createTargetKey(targetPos)

    -- Check if target has changed
    if targetKey ~= state.currentTargetKey then
        state.currentTargetKey = targetKey
        local timeSinceLastSwitch = Spring.DiffTimers(currentTime, state.lastTargetSwitchTime)

        if timeSinceLastSwitch < TARGET_SWITCH_THRESHOLD then
            state.targetSwitchCount = state.targetSwitchCount + 1
            if state.targetSwitchCount >= 3 and not state.highActivityDetected then
                state.highActivityDetected = true
                state.cloudStartTime = currentTime
                state.minCloudDuration = currentTime
            end
        else
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

    -- Maintenance: Remove old targets
    local i = 1
    while i <= #state.targetHistory do
        if Spring.DiffTimers(currentTime, state.targetHistory[i].time) > TARGET_HISTORY_DURATION then
            table.remove(state.targetHistory, i)
        else
            i = i + 1
        end
    end
    while #state.targetHistory > TARGET_HISTORY_SIZE do table.remove(state.targetHistory, 1) end

    -- Calculate Activity Level
    local uniqueTargets = {}
    for _, target in ipairs(state.targetHistory) do uniqueTargets[target.key] = true end
    local uniqueTargetCount = 0
    for _ in pairs(uniqueTargets) do uniqueTargetCount = uniqueTargetCount + 1 end

    local historySizeFactor = math.min(uniqueTargetCount / MIN_TARGETS_FOR_CLOUD, 1.0)
    local switchFactor = math.min(state.targetSwitchCount / 3, 1.0)
    state.activityLevel = math.max(historySizeFactor, switchFactor)

    -- Manage High Activity State
    if state.activityLevel >= 0.7 and not state.highActivityDetected then
        state.highActivityDetected = true
        state.cloudStartTime = currentTime
        state.minCloudDuration = currentTime


        -- fixme state.cloudStartTime is not used
    elseif state.activityLevel < 0.3 and state.highActivityDetected then
        local hasMinDurationPassed = not state.minCloudDuration or
                Spring.DiffTimers(currentTime, state.minCloudDuration) > 3.0
        if hasMinDurationPassed then
            state.highActivityDetected = false
            state.cloudStartTime = nil
        end
    end

    -- Decide usage and calculate
    state.useCloudTargeting = (state.highActivityDetected and
            (uniqueTargetCount >= MIN_TARGETS_FOR_CLOUD or state.targetSwitchCount >= 3))

    if state.useCloudTargeting then
        calculateCloudCenter()
    end
end

-- ============================================================================
-- PREDICTION & SMOOTHING
-- ============================================================================

--- Predicts target position based on velocity
local function predictTargetPosition(targetPos, targetUnitID)
    if not targetPos then return nil end
    local state = STATE.active.mode.unit_follow.targeting

    if not state.prediction.enabled then return targetPos end

    local currentTime = Spring.GetTimer()
    local timeDiff = 0
    if state.prediction.lastUpdateTime then
        timeDiff = Spring.DiffTimers(currentTime, state.prediction.lastUpdateTime)
    end

    if targetUnitID and Spring.ValidUnitID(targetUnitID) and timeDiff > 0.1 then
        local vx, vy, vz = Spring.GetUnitVelocity(targetUnitID)
        if vx then
            state.prediction.velocityX = vx
            state.prediction.velocityY = vy
            state.prediction.velocityZ = vz
            state.prediction.lastUpdateTime = currentTime
        end
    end

    local lookAheadTime = 0.3
    return {
        x = targetPos.x + (state.prediction.velocityX * lookAheadTime),
        y = targetPos.y + (state.prediction.velocityY * lookAheadTime),
        z = targetPos.z + (state.prediction.velocityZ * lookAheadTime)
    }
end

local function processAerialTarget(targetPos, unitPos, targetData)
    local state = STATE.active.mode.unit_follow.targeting

    -- Initialize aerial tracking in main state if needed
    if not state.aerialTracking then
        state.aerialTracking = {
            smoothedPosition = { x = targetPos.x, y = targetPos.y, z = targetPos.z },
            lastUpdateTime = Spring.GetTimer(),
            trajectoryPredictionEnabled = true,
            positionHistory = {}
        }
    end
    local aerial = state.aerialTracking

    -- Update History
    table.insert(aerial.positionHistory, {
        pos = { x = targetPos.x, y = targetPos.y, z = targetPos.z },
        time = Spring.GetTimer()
    })
    while #aerial.positionHistory > 30 do table.remove(aerial.positionHistory, 1) end

    -- Analysis
    local speed = targetData.speed or 0
    local heightDiff = targetPos.y - unitPos.y
    local dx, dz = targetPos.x - unitPos.x, targetPos.z - unitPos.z
    local horizontalDist = math.sqrt(dx * dx + dz * dz)
    local verticalAngle = math.atan2(heightDiff, horizontalDist)
    local isCircular = #aerial.positionHistory >= 10 and detectCircularMotion(aerial.positionHistory)

    -- Smoothing Logic
    local smoothFactor = 0.08
    if isCircular then smoothFactor = 0.03
    elseif targetData.isMovingFast then smoothFactor = 0.06 end
    if verticalAngle > 0.8 then smoothFactor = smoothFactor * 0.7 end
    if horizontalDist < 200 and heightDiff > 200 then smoothFactor = smoothFactor * 0.6 end

    -- Trajectory Prediction
    local predictedPos = targetPos
    if aerial.trajectoryPredictionEnabled and speed > 50 then
        local lookAheadTime = math.min(0.4, speed / 600)
        if isCircular and verticalAngle > 0.7 then lookAheadTime = lookAheadTime * 0.5 end

        predictedPos = {
            x = targetPos.x + (targetData.velocityX or 0) * lookAheadTime,
            y = targetPos.y + (targetData.velocityY or 0) * lookAheadTime,
            z = targetPos.z + (targetData.velocityZ or 0) * lookAheadTime
        }
    end

    -- Apply
    aerial.smoothedPosition = {
        x = aerial.smoothedPosition.x + (predictedPos.x - aerial.smoothedPosition.x) * smoothFactor,
        y = aerial.smoothedPosition.y + (predictedPos.y - aerial.smoothedPosition.y) * smoothFactor,
        z = aerial.smoothedPosition.z + (predictedPos.z - aerial.smoothedPosition.z) * smoothFactor
    }
    return aerial.smoothedPosition
end

--- Gets the effective target position (actual target or cloud center)
local function getEffectiveTargetPosition(targetPos)
    if not targetPos then return nil end
    local state = STATE.active.mode.unit_follow.targeting

    -- Get unit position for aerial checks
    local unitPos
    if STATE.active.mode.unitID and Spring.ValidUnitID(STATE.active.mode.unitID) then
        local x, y, z = Spring.GetUnitPosition(STATE.active.mode.unitID)
        unitPos = { x = x, y = y, z = z }
    end

    -- Aerial Target Logic
    local isAerialTarget = unitPos and targetPos.y > (unitPos.y + 80)
    if isAerialTarget then
        local targetKey = createTargetKey(targetPos)
        local targetData = state.targetTracking[targetKey]

        if targetData then
            local smoothedAerialPos = processAerialTarget(targetPos, unitPos, targetData)

            if state.useCloudTargeting and state.cloudCenter then
                local blend = CLOUD_BLEND_FACTOR * 0.8
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

    -- Normal Cloud Logic
    if state.useCloudTargeting and state.cloudCenter then
        local blend = CLOUD_BLEND_FACTOR
        -- Smooth cloud center transition
        if not state.previousCloudCenter then
            state.previousCloudCenter = { x = state.cloudCenter.x, y = state.cloudCenter.y, z = state.cloudCenter.z }
        end
        local cloudSmoothFactor = 0.05
        local smoothedCloudX = state.previousCloudCenter.x + (state.cloudCenter.x - state.previousCloudCenter.x) * cloudSmoothFactor
        local smoothedCloudY = state.previousCloudCenter.y + (state.cloudCenter.y - state.previousCloudCenter.y) * cloudSmoothFactor
        local smoothedCloudZ = state.previousCloudCenter.z + (state.cloudCenter.z - state.previousCloudCenter.z) * cloudSmoothFactor

        state.previousCloudCenter.x = smoothedCloudX
        state.previousCloudCenter.y = smoothedCloudY
        state.previousCloudCenter.z = smoothedCloudZ

        return {
            x = targetPos.x * (1 - blend) + smoothedCloudX * blend,
            y = targetPos.y * (1 - blend) + smoothedCloudY * blend,
            z = targetPos.z * (1 - blend) + smoothedCloudZ * blend
        }
    end

    return targetPos
end

-- ============================================================================
-- VELOCITY TRACKING FOR AERIAL ADJUSTMENT
-- ============================================================================

local function updateTargetVelocity(targetPos, unitPos, horizontalDist, targetData, using_cached_target)
    local currentTime = Spring.GetTimer()

    if using_cached_target and targetData.cachedTargetDuration > 30 then
        -- Simulating high speed target for cached positions
        local estimated_speed = 120.0
        local dx, dz = targetPos.x - unitPos.x, targetPos.z - unitPos.z
        local dirX, dirZ
        if horizontalDist > 0.001 then dirX, dirZ = dx / horizontalDist, dz / horizontalDist
        else dirX, dirZ = 0, 1 end

        local randomFactor = (math.random() * 0.4) + 0.8
        targetData.velocityX = dirX * estimated_speed * randomFactor
        targetData.velocityZ = dirZ * estimated_speed * randomFactor
        targetData.velocityY = (math.random() * 20) - 10

        targetData.speed = math.sqrt(targetData.velocityX ^ 2 + targetData.velocityY ^ 2 + targetData.velocityZ ^ 2)
        targetData.ySpeed = targetData.velocityY
        targetData.isMovingFast = targetData.speed > 150
        targetData.isMovingUpFast = false
    else
        targetData.frameCounter = targetData.frameCounter + 1
        if not using_cached_target and targetData.frameCounter % 3 == 0 then
            table.insert(targetData.positionHistory, {
                pos = { x = targetPos.x, y = targetPos.y, z = targetPos.z },
                time = currentTime
            })
            if #targetData.positionHistory > 5 then table.remove(targetData.positionHistory, 1) end

            if #targetData.positionHistory >= 2 then
                local newest = targetData.positionHistory[#targetData.positionHistory]
                local oldest = targetData.positionHistory[1]
                local timeDiff = Spring.DiffTimers(newest.time, oldest.time)

                if timeDiff > 0.05 then
                    targetData.velocityX = (newest.pos.x - oldest.pos.x) / timeDiff
                    targetData.velocityY = (newest.pos.y - oldest.pos.y) / timeDiff
                    targetData.velocityZ = (newest.pos.z - oldest.pos.z) / timeDiff
                    targetData.speed = math.sqrt(targetData.velocityX ^ 2 + targetData.velocityY ^ 2 + targetData.velocityZ ^ 2)
                    targetData.ySpeed = targetData.velocityY
                    targetData.isMovingFast = targetData.speed > 200
                    targetData.isMovingUpFast = targetData.ySpeed > 150
                end
            end
        end
    end
end

-- ============================================================================
-- PUBLIC INTERFACE
-- ============================================================================

--- Process a target for camera orientation (The main entry point for target processing)
--- @param targetPos table Raw target position {x, y, z}
--- @param targetUnitID number|nil Target unit ID if targeting a unit
--- @return table processedTarget Processed target position for camera orientation
function UnitFollowTargeting.processTarget(targetPos, targetUnitID)
    if not targetPos then return nil end
    updateTargetHistory(targetPos)
    local effectiveTarget = getEffectiveTargetPosition(targetPos)
    local predictedTarget = predictTargetPosition(effectiveTarget, targetUnitID)
    return predictedTarget
end

--- Handles air target camera positioning adjustments (The main entry point for camera placement)
--- @param position table Camera position {x, y, z}
--- @param targetPos table Target position {x, y, z}
--- @param unitPos table Base unit position {x, y, z}
--- @return table adjustedPos Adjusted camera position {x, y, z}
function UnitFollowTargeting.handleAirTargetRepositioning(position, targetPos, unitPos)
    if not position or not targetPos then return position end
    local state = STATE.active.mode.unit_follow.targeting
    local targetKey = createTargetKey(targetPos)

    ---@type UnitFollowCombatModeTarget
    local targetData = {
        lastUpdateTime = Spring.GetTimer(),
        lastRealPos = nil,
        positionHistory = {},
        isCachedTarget = false,
        cachedTargetDuration = 0,
        velocityX = 0, velocityY = 0, velocityZ = 0,
        speed = 0, ySpeed = 0,
        isMovingFast = false,
        isMovingUpFast = false,
        frameCounter = 0,
        airAdjustmentActive = false,
        lastAdjustmentStateTime = Spring.GetTimer(),
        lastLogTime = Spring.GetTimer()
    }

    state.targetTracking[targetKey] = targetData
    local currentTime = Spring.GetTimer()

    -- Ensure History is updated (in case processTarget wasn't called this frame)
    updateTargetHistory(targetPos)

    -- Cache Detection
    local using_cached_target = detectCachedPosition(targetPos, targetData)
    targetData.isCachedTarget = using_cached_target

    -- Log
    if Spring.DiffTimers(currentTime, targetData.lastLogTime) > 1.0 then
        targetData.lastLogTime = currentTime
    end

    local effectiveTarget = getEffectiveTargetPosition(targetPos)
    local heightDiff = effectiveTarget.y - unitPos.y

    -- Early exit: Not air
    if heightDiff <= AIR_HEIGHT_THRESHOLD then
        targetData.airAdjustmentActive = false
        return position
    end

    -- Math
    local dx, dy, dz = effectiveTarget.x - unitPos.x, heightDiff, effectiveTarget.z - unitPos.z
    local horizontalDist = math.sqrt(dx * dx + dz * dz)
    local verticalAngle = math.atan2(dy, horizontalDist)

    updateTargetVelocity(effectiveTarget, unitPos, horizontalDist, targetData, using_cached_target)

    local activationAngle = targetData.airAdjustmentActive and DEACTIVATION_ANGLE or ACTIVATION_ANGLE

    -- Stability check
    if STATE.active.mode.unit_follow.stableCamPos and state.activityLevel > 0.5 then
        activationAngle = activationAngle * 1.3
        if not targetData.airAdjustmentActive then activationAngle = activationAngle * 1.5 end
    end

    -- Fast upward check
    if targetData.isMovingUpFast and not targetData.airAdjustmentActive then
        return position
    end

    -- Adjustment Logic
    if verticalAngle > activationAngle then
        if not targetData.airAdjustmentActive and Spring.DiffTimers(currentTime, targetData.lastAdjustmentStateTime) > 1.0 then
            targetData.lastAdjustmentStateTime = currentTime
        end
        targetData.airAdjustmentActive = true

        local angleRatio = math.min((verticalAngle - ACTIVATION_ANGLE) / (math.pi / 2 - ACTIVATION_ANGLE), 1.0)
        local adjustmentFactor = 0.3 + (angleRatio * 0.4)
        if STATE.active.mode.unit_follow.stableCamPos then adjustmentFactor = adjustmentFactor * 0.7 end

        local isCloseToTarget = horizontalDist < 300
        local isVeryCloseToTarget = horizontalDist < 200
        local isHighTargetMode = verticalAngle > 0.8

        local distanceAdjustment = 1.0
        if isCloseToTarget then distanceAdjustment = 1.4 end
        if isVeryCloseToTarget then distanceAdjustment = 1.7 end
        if STATE.active.mode.unit_follow.stableCamPos then distanceAdjustment = distanceAdjustment * 0.8 end

        local upRatio, backRatio
        if isVeryCloseToTarget and verticalAngle > 1.3 then
            upRatio = 0.15
            backRatio = 1.5 * distanceAdjustment
        elseif isHighTargetMode then
            upRatio = math.min(verticalAngle * 0.25, 0.3) * (isCloseToTarget and 0.7 or 1.0)
            backRatio = (0.9 + (angleRatio * 0.3)) * distanceAdjustment
        else
            upRatio = math.min(verticalAngle * 0.35, 0.4)
            backRatio = (0.8 + (angleRatio * 0.3)) * distanceAdjustment
        end

        local moveUp = math.min(heightDiff * upRatio * adjustmentFactor, 90)
        local moveBack = math.min(horizontalDist * backRatio * adjustmentFactor, 220)
        local x, y, z = position.x, position.y, position.z

        -- Gradual application (if stabilized)
        if STATE.active.mode.unit_follow.stableCamPos and targetData.lastAdjustedPosition then
            local lastPos = targetData.lastAdjustedPosition
            local blendFactor = 0.2

            local lastMoveUp = y - position.y
            moveUp = lastMoveUp + (moveUp - lastMoveUp) * blendFactor

            if horizontalDist > 0.001 then
                local horNormX, horNormZ = dx / horizontalDist, dz / horizontalDist
                local newX = x - horNormX * moveBack
                local newZ = z - horNormZ * moveBack
                x = lastPos.x + (newX - lastPos.x) * blendFactor
                z = lastPos.z + (newZ - lastPos.z) * blendFactor
                y = y + moveUp
            end
            targetData.lastAdjustedPosition = { x = x, y = y, z = z }
            return { x = x, y = y, z = z }
        end

        -- Standard application
        y = y + moveUp
        if horizontalDist > 0.001 then
            local horNormX, horNormZ = dx / horizontalDist, dz / horizontalDist
            x = x - horNormX * moveBack
            z = z - horNormZ * moveBack
        end

        targetData.lastAdjustedPosition = { x = x, y = y, z = z }
        return targetData.lastAdjustedPosition
    else
        targetData.airAdjustmentActive = false
        targetData.lastAdjustedPosition = nil
        return position
    end
end

return UnitFollowTargeting
