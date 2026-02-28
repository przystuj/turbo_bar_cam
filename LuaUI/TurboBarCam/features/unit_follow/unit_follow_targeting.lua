---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "UnitFollowTargeting")

---@class UnitFollowTargeting
local UnitFollowTargeting = {}

local TARGET_SWITCH_THRESHOLD = 2.0
local PENALTY_DECAY_RATE = 1.0
local PENALTY_ADD = 3.0
local MAX_PENALTY = 10.0
local AIR_HEIGHT_THRESHOLD = 80
local ACTIVATION_ANGLE = 0.5
local DEACTIVATION_ANGLE = 0.4

-- Pre-allocated output table to avoid GC pressure per frame
local airAdjustedOut = { x = 0, y = 0, z = 0 }

local function getStabilizedTarget(targetPos, targetUnitID)
    local state = STATE.active.mode.unit_follow.targeting

    -- Prevent ID wiping by falling back to the globally known last target
    local fallbackID = STATE.active.mode.unit_follow.lastTargetUnitID
    targetUnitID = targetUnitID or fallbackID

    local currentTime = Spring.GetTimer()

    if not state.stabilization then
        --Log:debug("Initializing target stabilization state")
        state.stabilization = {
            lastTargetUnitID = targetUnitID,
            lastTargetPos = { x = targetPos.x, y = targetPos.y, z = targetPos.z },
            lastSwitchTime = currentTime,
            penaltyStack = 0,
            smoothedTargetPos = { x = targetPos.x, y = targetPos.y, z = targetPos.z },
            lastUpdateTime = currentTime
        }
    end

    local stab = state.stabilization
    local dt = Spring.DiffTimers(currentTime, stab.lastUpdateTime)

    -- FATAL BUG FIX: Prevent double-processing if called multiple times in the same frame.
    -- This prevents the dt=0 bug that caused Alpha to snap to 1.0
    if dt < 0.001 then
        return stab.smoothedTargetPos
    end

    stab.lastUpdateTime = currentTime

    if dt < 1.0 then
        stab.penaltyStack = math.max(0, stab.penaltyStack - (PENALTY_DECAY_RATE * dt))
    end

    -- Detect target switch without string allocations
    local isNewTarget = false
    if targetUnitID and targetUnitID > 0 then
        if targetUnitID ~= stab.lastTargetUnitID then
--            Log:debug("New target UNIT detected. Old ID:", stab.lastTargetUnitID, "New ID:", targetUnitID)
            isNewTarget = true
            stab.lastTargetUnitID = targetUnitID
        end
    else
        -- Ground target fallback: check distance squared
        local dx = targetPos.x - stab.lastTargetPos.x
        local dy = targetPos.y - stab.lastTargetPos.y
        local dz = targetPos.z - stab.lastTargetPos.z
        if (dx * dx + dy * dy + dz * dz) > 100 then
--            Log:debug("New GROUND target detected.")
            isNewTarget = true
        end
        stab.lastTargetUnitID = nil
    end

    if isNewTarget then
        local timeSinceSwitch = Spring.DiffTimers(currentTime, stab.lastSwitchTime)
        if timeSinceSwitch < TARGET_SWITCH_THRESHOLD then
            local oldPenalty = stab.penaltyStack
            stab.penaltyStack = math.min(MAX_PENALTY, stab.penaltyStack + PENALTY_ADD)
--            Log:debug("Rapid switch detected! Penalty increased from", oldPenalty, "to", stab.penaltyStack)
        end
        stab.lastSwitchTime = currentTime
        stab.lastTargetPos.x = targetPos.x
        stab.lastTargetPos.y = targetPos.y
        stab.lastTargetPos.z = targetPos.z
    end

    state.activityLevel = stab.penaltyStack / MAX_PENALTY
    state.targetSwitchCount = stab.penaltyStack

    -- High penalty = low lerpSpeed (sluggish, heavily damped tracking)
    local lerpSpeed = 10.0 / (1.0 + stab.penaltyStack * 2.0)
    local alpha = 1.0 - math.exp(-lerpSpeed * dt)

    if stab.penaltyStack > 0.1 then
        Log:trace("Target Tracking - Penalty:", stab.penaltyStack, "Alpha:", alpha)
    end

    -- Mutate in-place to avoid GC
    stab.smoothedTargetPos.x = stab.smoothedTargetPos.x + (targetPos.x - stab.smoothedTargetPos.x) * alpha
    stab.smoothedTargetPos.y = stab.smoothedTargetPos.y + (targetPos.y - stab.smoothedTargetPos.y) * alpha
    stab.smoothedTargetPos.z = stab.smoothedTargetPos.z + (targetPos.z - stab.smoothedTargetPos.z) * alpha

    return stab.smoothedTargetPos
end

function UnitFollowTargeting.processTarget(targetPos, targetUnitID)
    if not targetPos then return nil end
    return getStabilizedTarget(targetPos, targetUnitID)
end

function UnitFollowTargeting.handleAirTargetRepositioning(position, targetPos, unitPos)
    if not position or not targetPos then return position end
    local state = STATE.active.mode.unit_follow.targeting

    local effectiveTarget = getStabilizedTarget(targetPos, nil)
    local heightDiff = effectiveTarget.y - unitPos.y

    if heightDiff <= AIR_HEIGHT_THRESHOLD then
        state.airAdjustmentActive = false
        return position
    end

    local dx, dy, dz = effectiveTarget.x - unitPos.x, heightDiff, effectiveTarget.z - unitPos.z
    local horizontalDist = math.sqrt(dx * dx + dz * dz)
    local verticalAngle = math.atan2(dy, horizontalDist)

    local activationAngle = state.airAdjustmentActive and DEACTIVATION_ANGLE or ACTIVATION_ANGLE

    if STATE.active.mode.unit_follow.stableCamPos and (state.activityLevel or 0) > 0.3 then
        activationAngle = activationAngle * 1.3
        if not state.airAdjustmentActive then activationAngle = activationAngle * 1.5 end
    end

    if verticalAngle > activationAngle then
        state.airAdjustmentActive = true
        local angleRatio = math.min((verticalAngle - ACTIVATION_ANGLE) / (math.pi / 2 - ACTIVATION_ANGLE), 1.0)
        local adjustmentFactor = 0.3 + (angleRatio * 0.4)
        if STATE.active.mode.unit_follow.stableCamPos then adjustmentFactor = adjustmentFactor * 0.7 end

        local isCloseToTarget = horizontalDist < 300
        local isVeryCloseToTarget = horizontalDist < 200
        local distanceAdjustment = 1.0
        if isCloseToTarget then distanceAdjustment = 1.4 end
        if isVeryCloseToTarget then distanceAdjustment = 1.7 end
        if STATE.active.mode.unit_follow.stableCamPos then distanceAdjustment = distanceAdjustment * 0.8 end

        local upRatio = math.min(verticalAngle * 0.35, 0.4)
        local backRatio = (0.8 + (angleRatio * 0.3)) * distanceAdjustment

        local moveUp = math.min(math.max(heightDiff * upRatio * adjustmentFactor, 0), 90)
        local moveBack = math.min(math.max(horizontalDist * backRatio * adjustmentFactor, 0), 220)

        local x, y, z = position.x, position.y + moveUp, position.z
        if horizontalDist > 0.001 then
            local horNormX, horNormZ = dx / horizontalDist, dz / horizontalDist
            x = x - horNormX * moveBack
            z = z - horNormZ * moveBack
        end

        if STATE.active.mode.unit_follow.stableCamPos and state.lastAirAdjustedPosition then
            local blendFactor = 0.2
            x = state.lastAirAdjustedPosition.x + (x - state.lastAirAdjustedPosition.x) * blendFactor
            y = state.lastAirAdjustedPosition.y + (y - state.lastAirAdjustedPosition.y) * blendFactor
            z = state.lastAirAdjustedPosition.z + (z - state.lastAirAdjustedPosition.z) * blendFactor
        end

        if not state.lastAirAdjustedPosition then
            state.lastAirAdjustedPosition = { x = x, y = y, z = z }
        else
            state.lastAirAdjustedPosition.x = x
            state.lastAirAdjustedPosition.y = y
            state.lastAirAdjustedPosition.z = z
        end

        -- Populate pre-allocated output table to avoid GC
        airAdjustedOut.x = state.lastAirAdjustedPosition.x
        airAdjustedOut.y = state.lastAirAdjustedPosition.y
        airAdjustedOut.z = state.lastAirAdjustedPosition.z

        return airAdjustedOut
    else
        state.airAdjustmentActive = false
        return position
    end
end

return UnitFollowTargeting
