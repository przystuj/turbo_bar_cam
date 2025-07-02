---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CONSTANTS = ModuleManager.CONSTANTS(function(m) CONSTANTS = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "UnitFollowUtils")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local UnitFollowCombatMode = ModuleManager.UnitFollowCombatMode(function(m) UnitFollowCombatMode = m end)
local UnitFollowTargetingUtils = ModuleManager.UnitFollowTargetingUtils(function(m) UnitFollowTargetingUtils = m end)
local UnitFollowTargetingSmoothing = ModuleManager.UnitFollowTargetingSmoothing(function(m) UnitFollowTargetingSmoothing = m end)
local UnitFollowPersistence = ModuleManager.UnitFollowPersistence(function(m) UnitFollowPersistence = m end)
local ParamUtils = ModuleManager.ParamUtils(function(m) ParamUtils = m end)
local WorldUtils = ModuleManager.WorldUtils(function(m) WorldUtils = m end)

---@class UnitFollowUtils
local UnitFollowUtils = {}

--- Checks if unit_follow camera should be updated
---@return boolean shouldUpdate Whether unit_follow camera should be updated
function UnitFollowUtils.shouldUpdateCamera()
    if STATE.active.mode.name ~= 'unit_follow' or not STATE.active.mode.unitID then
        return false
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.active.mode.unitID) then
        Log:trace("Unit no longer exists")
        ModeManager.disableMode()
        return false
    end

    return true
end

--- Calculate the height if it's not set
function UnitFollowUtils.ensureHeightIsSet()
    -- Set DEFAULT mode height if not set
    if not CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.DEFAULT.HEIGHT then
        local unitHeight = math.max(WorldUtils.getUnitHeight(STATE.active.mode.unitID), 100) + 30
        CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.DEFAULT.HEIGHT = unitHeight
    end

    -- Ensure COMBAT mode height is set (though it should have a default)
    if not CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.COMBAT.HEIGHT then
        CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.COMBAT.HEIGHT = CONFIG.CAMERA_MODES.UNIT_FOLLOW.DEFAULT_OFFSETS.COMBAT.HEIGHT
    end

    -- Ensure WEAPON mode height is set (though it should have a default)
    if not CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.WEAPON.HEIGHT then
        CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.WEAPON.HEIGHT = CONFIG.CAMERA_MODES.UNIT_FOLLOW.DEFAULT_OFFSETS.WEAPON.HEIGHT
    end
end

--- Gets appropriate offsets based on current mode
---@return table offsets The offsets to apply
function UnitFollowUtils.getAppropriateOffsets()
    -- In combat mode - check if actively attacking
    if STATE.active.mode.unit_follow.combatModeEnabled then
        if STATE.active.mode.unit_follow.isAttacking then
            -- Weapon offsets - when actively targeting something
            return CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.WEAPON
        else
            -- Combat offsets - when in combat mode but not targeting
            return CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.COMBAT
        end
    else
        -- Peace mode - normal offsets
        return CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.DEFAULT
    end
end

--- Creates a basic camera state object with the specified position and direction
---@param position table Camera position {x, y, z}
---@param direction table Camera direction {dx, dy, dz, rx, ry, rz}
---@return table cameraState Complete camera state object
function UnitFollowUtils.createCameraState(position, direction)
    return {
        -- Position
        px = position.x,
        py = position.y,
        pz = position.z,

        -- Direction
        dx = direction.dx,
        dy = direction.dy,
        dz = direction.dz,

        -- Rotation
        rx = direction.rx,
        ry = direction.ry,
        rz = direction.rz
    }
end

--- Creates direction state based on unit's hull direction
--- @param unitID number Unit ID
--- @param offsets table Offsets to use
--- @return table directionState Camera direction state
function UnitFollowUtils.createHullDirectionState(unitID, offsets)
    local targetRy = -(Spring.GetUnitHeading(unitID, true) + math.pi) + offsets.ROTATION
    local targetRx = 1.8

    return { rx = targetRx, ry = targetRy, }, CONSTANTS.TARGET_TYPE.EULER
end

--- Creates direction state when actively firing at a target
--- @param unitID number Unit ID
--- @param targetPos table Target position
--- @param weaponNum number|nil Weapon number
--- @param rotFactor number Rotation smoothing factor
--- @return table|nil directionState Camera direction state or nil if it fails
function UnitFollowUtils.createTargetingDirectionState(unitID, targetPos, weaponNum)
    if not targetPos or not weaponNum then
        return nil
    end

    -- Get the weapon position if available
    local posX, posY, posZ, destX = Spring.GetUnitWeaponVectors(unitID, weaponNum)
    if not posX or not destX then
        return nil
    end

    -- We have valid weapon vectors
    local weaponPos = { x = posX, y = posY, z = posZ }

    -- Apply target smoothing here - this is the key addition!
    -- Process the target through all smoothing systems (cloud targeting, rotation constraints)
    local processedTarget = UnitFollowTargetingSmoothing.processTarget(targetPos, STATE.active.mode.unit_follow.lastTargetUnitID)

    if processedTarget then
        targetPos = processedTarget
    end

    -- Calculate direction to target (not weapon direction)
    local dx = targetPos.x - posX
    local dy = targetPos.y - posY
    local dz = targetPos.z - posZ
    local magnitude = math.sqrt(dx * dx + dy * dy + dz * dz)

    if magnitude < 0.001 then
        return nil
    end

    -- Normalize direction vector
    dx, dy, dz = dx / magnitude, dy / magnitude, dz / magnitude

    -- Store position and direction for other functions
    STATE.active.mode.unit_follow.weaponPos = weaponPos
    STATE.active.mode.unit_follow.weaponDir = { dx, dy, dz }
    STATE.active.mode.unit_follow.activeWeaponNum = weaponNum

    return targetPos
end

--- Handles normal unit_follow mode camera orientation
--- @param unitID number Unit ID
--- @return table directionState Camera direction and rotation state
function UnitFollowUtils.handleNormalFollowMode(unitID)
    -- Check if combat mode is enabled
    if STATE.active.mode.unit_follow.combatModeEnabled then
        -- Check if the unit is actively targeting something
        local targetPos, firingWeaponNum, isNewTarget = UnitFollowCombatMode.getCurrentAttackTarget(unitID)
        if isNewTarget and not STATE.active.mode.unit_follow.isTargetSwitchTransition then
            UnitFollowUtils.handleNewTarget()
        end

        if STATE.active.mode.unit_follow.isAttacking then
            -- Try to create direction state based on targeting data
            local targetingState = UnitFollowUtils.createTargetingDirectionState(unitID, targetPos, firingWeaponNum or STATE.active.mode.unit_follow.activeWeaponNum)

            if targetingState then
                -- Successfully created targeting state
                return targetingState, CONSTANTS.TARGET_TYPE.POINT
            end
        end

        -- If we get here, we're in combat mode but not attacking (or couldn't create targeting state)
        -- Use combat offset mode
        return UnitFollowUtils.createHullDirectionState(unitID, CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.COMBAT)
    else
        -- Normal mode - always ensure isAttacking is false
        STATE.active.mode.unit_follow.isAttacking = false
        return UnitFollowUtils.createHullDirectionState(unitID, CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.DEFAULT)
    end
end

function UnitFollowUtils.handleNewTarget()
    local trackedUnitID = STATE.active.mode.unitID
    if not trackedUnitID or not Spring.ValidUnitID(trackedUnitID) then
        return
    end

    -- Initialize state fields if needed
    if not STATE.active.mode.unit_follow.previousTargetPos then
        if STATE.active.mode.unit_follow.lastTargetPos then
            STATE.active.mode.unit_follow.previousTargetPos = {
                x = STATE.active.mode.unit_follow.lastTargetPos.x,
                y = STATE.active.mode.unit_follow.lastTargetPos.y,
                z = STATE.active.mode.unit_follow.lastTargetPos.z
            }
        end
    end

    if not STATE.active.mode.unit_follow.lastTargetSwitchTime then
        STATE.active.mode.unit_follow.lastTargetSwitchTime = Spring.GetTimer()
    end

    -- Check for target suitability
    local newTargetPos = STATE.active.mode.unit_follow.lastTargetPos
    local previousTargetPos = STATE.active.mode.unit_follow.previousTargetPos

    -- Skip if we don't have proper target data
    if not newTargetPos then
        return
    end

    -- First acquisition just store it
    if not previousTargetPos then
        STATE.active.mode.unit_follow.previousTargetPos = {
            x = newTargetPos.x,
            y = newTargetPos.y,
            z = newTargetPos.z
        }
        return
    end

    -- Get current time
    local currentTime = Spring.GetTimer()

    -- Rate limiting criteria
    local timeSinceLastTransition = Spring.DiffTimers(currentTime, STATE.active.mode.unit_follow.lastTargetSwitchTime)
    local minTimeBetweenTransitions = STATE.active.mode.unit_follow.isTargetSwitchTransition and 0.5 or 1.0  -- Shorter if already in transition

    -- Enhanced decision criteria:
    local isInTransition = STATE.active.mode.unit_follow.isTargetSwitchTransition
    local isTimeSufficientForNewTransition = timeSinceLastTransition > minTimeBetweenTransitions

    -- Skip transition if:
    -- 1. Already in transition, OR
    -- 2. Distance too small, OR
    -- 3. Last transition was too recent
    if isInTransition or (not isTimeSufficientForNewTransition) then
        -- Just update the previous target position without starting a new transition
        STATE.active.mode.unit_follow.previousTargetPos = {
            x = newTargetPos.x,
            y = newTargetPos.y,
            z = newTargetPos.z
        }

        -- Log why we're skipping (only if distance significant or debugging enabled)
        if CONFIG.DEBUG.LOG_LEVEL == "DEBUG" then
            local reason = ""
            if isInTransition then
                reason = "already in transition"
            else
                reason = "too soon after last transition"
            end
        end
        return
    end

    -- If we get here, we're starting a new transition

    -- CRITICAL FIX: Capture the CURRENT camera state for transition origin point
    -- This ensures we start from where the camera actually is
    local currentCameraState = Spring.GetCameraState()
    STATE.active.mode.unit_follow.previousCamPosWorld = {
        x = currentCameraState.px,
        y = currentCameraState.py,
        z = currentCameraState.pz
    }

    -- Store previous direction vector (used for calculating target camera position)
    if STATE.active.mode.unit_follow.weaponDir then
        STATE.active.mode.unit_follow.previousWeaponDir = {
            STATE.active.mode.unit_follow.weaponDir[1],
            STATE.active.mode.unit_follow.weaponDir[2],
            STATE.active.mode.unit_follow.weaponDir[3]
        }
    else
        local _, frontVec, _, _ = Spring.GetUnitVectors(trackedUnitID)
        if frontVec then
            STATE.active.mode.unit_follow.previousWeaponDir = { frontVec[1], frontVec[2], frontVec[3] }
        else
            STATE.active.mode.unit_follow.previousWeaponDir = { 0, 0, 1 }  -- Fallback
        end
    end

    -- Start transition
    STATE.active.mode.unit_follow.isTargetSwitchTransition = true
    STATE.active.mode.unit_follow.targetSwitchStartTime = currentTime
    STATE.active.mode.unit_follow.lastTargetSwitchTime = currentTime
    STATE.active.mode.unit_follow.transitionCounter = (STATE.active.mode.unit_follow.transitionCounter or 0) + 1

    -- Signal rotation constraints to reset
    if STATE.active.mode.unit_follow.targetSmoothing and STATE.active.mode.unit_follow.targetSmoothing.rotationConstraint then
        STATE.active.mode.unit_follow.targetSmoothing.rotationConstraint.resetForSwitch = true
        Log:debug("Signaling rotation constraint reset.")
    end

    -- Store this target position for future comparisons
    STATE.active.mode.unit_follow.previousTargetPos = {
        x = newTargetPos.x,
        y = newTargetPos.y,
        z = newTargetPos.z
    }
end

--- Sets a fixed look point for the camera
---@param fixedPoint table Point to look at {x, y, z}
---@param targetUnitID number|nil Optional unit ID to track
---@return boolean success Whether fixed point was set successfully
function UnitFollowUtils.setFixedLookPoint(fixedPoint, targetUnitID)
    if Utils.isTurboBarCamDisabled() then
        return false
    end
    if Utils.isModeDisabled("unit_follow") then
        return false
    end
    if not STATE.active.mode.unitID then
        Log:trace("No unit being tracked for fixed point camera")
        return false
    end

    -- Set the fixed point
    STATE.active.mode.unit_follow.fixedPoint = fixedPoint
    STATE.active.mode.unit_follow.targetUnitID = targetUnitID
    STATE.active.mode.unit_follow.isFixedPointActive = true

    -- We're no longer in target selection mode
    STATE.active.mode.unit_follow.inTargetSelectionMode = false
    STATE.active.mode.unit_follow.prevFixedPoint = nil -- Clear saved previous fixed point

    -- Use the previous free camera state for normal operation
    STATE.active.mode.unit_follow.isFreeCameraActive = STATE.active.mode.unit_follow.prevFreeCamState or false

    -- If not in free camera mode, enable a transition to the fixed point
    if not STATE.active.mode.unit_follow.isFreeCameraActive then
        -- Trigger a transition to smoothly move to the new view
        STATE.active.mode.isModeTransitionInProgress = true
        STATE.active.mode.transitionStartTime = Spring.GetTimer()
    end

    if not STATE.active.mode.unit_follow.targetUnitID then
        Log:trace("Camera will follow unit but look at fixed point")
    else
        local unitDef = UnitDefs[Spring.GetUnitDefID(STATE.active.mode.unit_follow.targetUnitID)]
        local targetName = unitDef and unitDef.name or "Unnamed unit"
        Log:trace("Camera will follow unit but look at unit " .. STATE.active.mode.unit_follow.targetUnitID ..
                " (" .. targetName .. ")")
    end

    return true
end

--- Clears fixed point tracking
function UnitFollowUtils.clearFixedLookPoint()
    if Utils.isTurboBarCamDisabled() then
        return
    end

    if STATE.active.mode.unit_follow.isFixedPointActive and STATE.active.mode.unitID then
        -- Disable fixed point tracking
        STATE.active.mode.unit_follow.isFixedPointActive = false
        STATE.active.mode.unit_follow.fixedPoint = nil
        STATE.active.mode.unit_follow.targetUnitID = nil  -- Clear the target unit ID
        STATE.active.mode.unit_follow.inTargetSelectionMode = false
        STATE.active.mode.unit_follow.prevFixedPoint = nil -- Clear saved previous fixed point

        -- Start a transition when changing modes
        STATE.active.mode.isModeTransitionInProgress = true
        STATE.active.mode.transitionStartTime = Spring.GetTimer()

        if STATE.active.mode.unit_follow.isFreeCameraActive then
            Log:trace("Fixed point tracking disabled, maintaining free camera mode")
        else
            Log:trace("Fixed point tracking disabled, returning to unit_follow mode")
        end
    end
end

--- Updates the fixed point if tracking a unit
---@return table|nil fixedPoint The updated fixed point or nil if not tracking a unit
function UnitFollowUtils.updateFixedPointTarget()
    if not STATE.active.mode.unit_follow.targetUnitID or not Spring.ValidUnitID(STATE.active.mode.unit_follow.targetUnitID) then
        return STATE.active.mode.unit_follow.fixedPoint, CONSTANTS.TARGET_TYPE.POINT
    end
    return STATE.active.mode.unit_follow.targetUnitID, CONSTANTS.TARGET_TYPE.UNIT
end

--- Determines appropriate smoothing factors based on current state
---@param smoothType string Type of smoothing ('position', 'rotation')
---@return number smoothingFactor The smoothing factor to use
function UnitFollowUtils.getSmoothingFactor(smoothType)
    -- Determine which mode we're in
    local smoothingMode
    if STATE.active.mode.unit_follow.combatModeEnabled then
        if STATE.active.mode.unit_follow.isAttacking then
            smoothingMode = "WEAPON"
        else
            smoothingMode = "COMBAT"
        end
    else
        smoothingMode = "DEFAULT"
    end

    -- Get the appropriate smoothing factor based on mode and type
    if smoothType == 'position' then
        return CONFIG.CAMERA_MODES.UNIT_FOLLOW.SMOOTHING[smoothingMode].POSITION_FACTOR
    elseif smoothType == 'rotation' then
        return CONFIG.CAMERA_MODES.UNIT_FOLLOW.SMOOTHING[smoothingMode].ROTATION_FACTOR
    end
end

local function getParamPrefixes()
    return {
        DEFAULT = "DEFAULT.",
        COMBAT = "COMBAT.",
        WEAPON = "WEAPON."
    }
end

--- Update adjustParams to handle the new offset structure
function UnitFollowUtils.adjustParams(params)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled("unit_follow") then
        return
    end

    -- Make sure we have a unit to track
    if not STATE.active.mode.unitID then
        Log:trace("No unit being tracked")
        return
    end

    -- Handle reset directly
    if params == "reset" then
        UnitFollowUtils.resetOffsets()
        UnitFollowPersistence.saveUnitSettings("unit_follow", STATE.active.mode.unitID)
        return
    end

    -- Determine current submode
    local currentSubMode
    if STATE.active.mode.unit_follow.combatModeEnabled then
        if STATE.active.mode.unit_follow.isAttacking then
            currentSubMode = "WEAPON"
        else
            currentSubMode = "COMBAT"
        end
    else
        currentSubMode = "DEFAULT"
    end

    Log:trace("Adjusting unit_follow parameters for submode: " .. currentSubMode)

    ParamUtils.adjustParams(params, "UNIT_FOLLOW", function()
        UnitFollowUtils.resetOffsets()
    end, currentSubMode, getParamPrefixes)

    UnitFollowPersistence.saveUnitSettings("unit_follow", STATE.active.mode.unitID)
end

--- Resets camera offsets to default values
function UnitFollowUtils.resetOffsets()
    local function reset(mode)
        TableUtils.patchTable(CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS[mode], CONFIG.CAMERA_MODES.UNIT_FOLLOW.DEFAULT_OFFSETS[mode])
    end

    reset("DEFAULT")
    reset("COMBAT")
    reset("WEAPON")

    UnitFollowUtils.ensureHeightIsSet()
    Log:trace("Restored unit_follow camera settings to defaults")
    return true
end

--- Applies unit_follow camera offsets to unit position, handling target switch transitions
---@param position table Unit position {x, y, z}
---@param front table Unit Front vector
---@param up table Unit Up vector
---@param right table Unit Right vector
---@return table camPos Final Camera position with offsets and transitions applied
function UnitFollowUtils.applyOffsets(position, front, up, right)
    UnitFollowUtils.ensureHeightIsSet()
    local offsets = UnitFollowUtils.getAppropriateOffsets()
    local unitPos = { x = position.x, y = position.y, z = position.z } -- Store original unit center

    -- Determine which vectors to use based on state
    local frontVec, upVec, rightVec
    local weaponBasePos = unitPos

    if STATE.active.mode.unit_follow.isAttacking and STATE.active.mode.unit_follow.weaponDir then
        -- Use weapon position when attacking if available
        if STATE.active.mode.unit_follow.weaponPos then
            weaponBasePos = STATE.active.mode.unit_follow.weaponPos
            position = STATE.active.mode.unit_follow.weaponPos
        end
        -- Use weapon direction when attacking
        frontVec = STATE.active.mode.unit_follow.weaponDir
        upVec = up
        -- Calculate right vector from front and up vectors
        rightVec = {
            frontVec[2] * upVec[3] - frontVec[3] * upVec[2],
            frontVec[3] * upVec[1] - frontVec[1] * upVec[3],
            frontVec[1] * upVec[2] - frontVec[2] * upVec[1]
        }
    else
        -- Use standard vectors otherwise
        frontVec = front
        upVec = up
        rightVec = right
    end

    -- Extract components from the vector tables
    local x, y, z = position.x, position.y, position.z
    local frontX, frontY, frontZ = frontVec[1], frontVec[2], frontVec[3]
    local upX, upY, upZ = upVec[1], upVec[2], upVec[3]
    local rightX, rightY, rightZ = rightVec[1], rightVec[2], rightVec[3]

    -- Calculate the TARGET relative camera position based on offsets
    local targetCamPosRelative = { x = 0, y = 0, z = 0 }

    -- Apply offsets directly to position components
    if offsets.HEIGHT ~= 0 then
        x = x + upX * offsets.HEIGHT
        y = y + upY * offsets.HEIGHT
        z = z + upZ * offsets.HEIGHT

        -- Also update the relative offset vector for transitions
        targetCamPosRelative.x = targetCamPosRelative.x + upX * offsets.HEIGHT
        targetCamPosRelative.y = targetCamPosRelative.y + upY * offsets.HEIGHT
        targetCamPosRelative.z = targetCamPosRelative.z + upZ * offsets.HEIGHT
    end

    if offsets.FORWARD ~= 0 then
        x = x + frontX * offsets.FORWARD
        y = y + frontY * offsets.FORWARD
        z = z + frontZ * offsets.FORWARD

        targetCamPosRelative.x = targetCamPosRelative.x + frontX * offsets.FORWARD
        targetCamPosRelative.y = targetCamPosRelative.y + frontY * offsets.FORWARD
        targetCamPosRelative.z = targetCamPosRelative.z + frontZ * offsets.FORWARD
    end

    if offsets.SIDE ~= 0 then
        x = x + rightX * offsets.SIDE
        y = y + rightY * offsets.SIDE
        z = z + rightZ * offsets.SIDE

        targetCamPosRelative.x = targetCamPosRelative.x + rightX * offsets.SIDE
        targetCamPosRelative.y = targetCamPosRelative.y + rightY * offsets.SIDE
        targetCamPosRelative.z = targetCamPosRelative.z + rightZ * offsets.SIDE
    end

    -- Calculate the target world position (with offsets applied)
    local targetCamPosWorld = { x = x, y = y, z = z }

    -- Apply minimum height constraint to target position
    targetCamPosWorld = UnitFollowUtils.enforceMinimumHeight(targetCamPosWorld, STATE.active.mode.unitID)

    -- IMPORTANT: First apply the stabilization for jittery camera
    local finalCamPosWorld = targetCamPosWorld

    -- Handle transition if active
    if STATE.active.mode.unit_follow.isTargetSwitchTransition then
        local transitionPos = UnitFollowUtils.handleTransition(targetCamPosWorld)
        if transitionPos then
            finalCamPosWorld = transitionPos
        end
    else
        -- Apply stabilization when not in transition
        local stabilizedPos = UnitFollowUtils.applyStabilization(targetCamPosWorld)
        if stabilizedPos then
            finalCamPosWorld = stabilizedPos
        end
    end

    -- IMPORTANT: Apply air target repositioning AFTER stabilization
    -- This ensures the air adjustment respects the stabilized camera state
    if STATE.active.mode.unit_follow.isAttacking and STATE.active.mode.unit_follow.lastTargetPos then
        finalCamPosWorld = UnitFollowTargetingUtils.handleAirTargetRepositioning(
                finalCamPosWorld,
                STATE.active.mode.unit_follow.lastTargetPos,
                unitPos  -- Pass original unit position for reference
        )
    end

    return finalCamPosWorld
end

-- New separated function to handle either transition or stabilization
-- This follows the guideline to avoid large conditional blocks
function UnitFollowUtils.applyStabilizationOrTransition(targetCamPosWorld)
    -- Check if we are in a target switch transition
    if STATE.active.mode.unit_follow.isTargetSwitchTransition then
        return UnitFollowUtils.handleTransition(targetCamPosWorld)
    end

    -- Not in transition, check if we need stabilization
    return UnitFollowUtils.applyStabilization(targetCamPosWorld)
end

-- Separate function to handle camera transition
-- This follows the guideline to split large conditionals into functions
function UnitFollowUtils.handleTransition(targetCamPosWorld)
    local now = Spring.GetTimer()
    local elapsed = Spring.DiffTimers(now, STATE.active.mode.unit_follow.targetSwitchStartTime or now)
    local transitionDuration = STATE.active.mode.unit_follow.targetSwitchDuration or 0.4

    -- Calculate the progress with ease-in-out curve for smoother acceleration/deceleration
    local rawProgress = math.min(1.0, elapsed / transitionDuration)
    -- Ease-in-out: smoother at start and end of transition
    local progress = rawProgress * rawProgress * (3 - 2 * rawProgress)

    if progress < 1.0 then
        -- Use current actual camera position for transition
        if STATE.active.mode.unit_follow.previousCamPosWorld then
            local startPos = STATE.active.mode.unit_follow.previousCamPosWorld
            local endPos = targetCamPosWorld

            -- Simple direct linear interpolation between current and target position
            local finalCamPosWorld = {
                x = startPos.x + (endPos.x - startPos.x) * progress,
                y = startPos.y + (endPos.y - startPos.y) * progress,
                z = startPos.z + (endPos.z - startPos.z) * progress
            }

            -- Return the interpolated position
            return finalCamPosWorld
        end
    else
        -- Transition finished this frame
        STATE.active.mode.unit_follow.isTargetSwitchTransition = false
        STATE.active.mode.unit_follow.previousCamPosWorld = nil
        Log:info("Target switch transition finished.")
    end

    return nil
end

-- Separate function to handle camera stabilization for jittery situations
-- This follows the guideline to split large conditionals into functions
function UnitFollowUtils.applyStabilization(targetCamPosWorld)
    -- Get targeting information from smoothing system
    local targetSmoothing = STATE.active.mode.unit_follow.targetSmoothing

    -- Only apply stabilization during active targeting with high target switching activity
    if not STATE.active.mode.unit_follow.isAttacking or not targetSmoothing or
            not targetSmoothing.activityLevel or targetSmoothing.activityLevel <= 0.5 then
        -- Reset stabilization when not in a high-activity targeting situation
        STATE.active.mode.unit_follow.stableCamPos = nil
        return nil
    end

    -- Initialize stable camera position history if needed
    if not STATE.active.mode.unit_follow.stableCamPos then
        STATE.active.mode.unit_follow.stableCamPos = targetCamPosWorld
        STATE.active.mode.unit_follow.cameraStabilityFactor = 0.05 -- Default slow response
    end

    -- Calculate stabilization factors
    local factor = UnitFollowUtils.calculateStabilityFactor(targetSmoothing)

    -- Apply very gradual interpolation towards the target position
    local stableCamPos = STATE.active.mode.unit_follow.stableCamPos

    local smoothedCamPos = {
        x = stableCamPos.x + (targetCamPosWorld.x - stableCamPos.x) * factor,
        y = stableCamPos.y + (targetCamPosWorld.y - stableCamPos.y) * factor,
        z = stableCamPos.z + (targetCamPosWorld.z - stableCamPos.z) * factor
    }

    -- Update stable camera position for next frame
    STATE.active.mode.unit_follow.stableCamPos = smoothedCamPos

    -- Log stabilization info periodically
    UnitFollowUtils.logStabilizationInfo(factor, targetSmoothing)

    return smoothedCamPos
end

-- Calculate stability factor based on activity level
-- Following the guideline to avoid code duplication
function UnitFollowUtils.calculateStabilityFactor(targetSmoothing)
    local stabilityBase = 0.05 -- Base smoothing factor for minimal stabilization
    local maxStability = 0.02 -- Maximum smoothing factor (smaller = more stable)

    -- Scale stability factor inversely with activity level
    local activityScaling = math.min(targetSmoothing.activityLevel * 1.5, 1.0)
    local factor = stabilityBase - (activityScaling * (stabilityBase - maxStability))

    -- Add rapid switch counter to increase stabilization for very rapid switching
    if targetSmoothing.targetSwitchCount > 100 then
        -- Further decrease factor for extremely high switching rates
        factor = factor * 0.8
    end

    -- Store the factor for reference
    STATE.active.mode.unit_follow.cameraStabilityFactor = factor

    return factor
end

-- Log stabilization info periodically to avoid spam
function UnitFollowUtils.logStabilizationInfo(factor, targetSmoothing)
    local currentTime = Spring.GetTimer()
    if not STATE.active.mode.unit_follow.lastStabilizationLog or
            Spring.DiffTimers(currentTime, STATE.active.mode.unit_follow.lastStabilizationLog) > 1.0 then
        Log:debug(string.format("Camera stabilization active: factor=%.3f, activity=%.2f, switches=%d",
                factor, targetSmoothing.activityLevel, targetSmoothing.targetSwitchCount or 0))
        STATE.active.mode.unit_follow.lastStabilizationLog = currentTime
    end
end

--- Ensures camera doesn't go below minimum height
--- @param position table Camera position {x, y, z}
--- @param unitID number The unit ID
--- @return table adjustedPos Position with height constraint applied
function UnitFollowUtils.enforceMinimumHeight(position, unitID)
    if not position then
        return position
    end

    local minHeight = UnitFollowUtils.getMinimumCameraHeight(unitID)
    local x, y, z = position.x, position.y, position.z

    -- Get ground height at the position
    local groundHeight = Spring.GetGroundHeight(x, z)

    -- Ensure camera is at least minHeight above ground
    if y < (groundHeight + minHeight) then
        y = groundHeight + minHeight
    end

    return { x = x, y = y, z = z }
end

--- Gets minimum height for camera position
--- @param unitID number The unit ID
--- @return number minHeight Minimum height above ground
function UnitFollowUtils.getMinimumCameraHeight(unitID)
    if not Spring.ValidUnitID(unitID) then
        return 50 -- Default fallback
    end

    -- Get unit height
    local unitDefID = Spring.GetUnitDefID(unitID)
    local unitDef = UnitDefs[unitDefID]
    if not unitDef then
        return 50
    end

    -- Use half of the unit height as minimum (or a fixed value if that's too small)
    local baseUnitHeight = unitDef.height or 0
    return math.max(baseUnitHeight * 0.5, 50) -- At least half unit height or 50 units
end

return UnitFollowUtils