---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local Util = ModuleManager.Util(function(m) Util = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local SettingsManager = ModuleManager.SettingsManager(function(m) SettingsManager = m end)
local FPSCombatMode = ModuleManager.FPSCombatMode(function(m) FPSCombatMode = m end)
local FPSTargetingUtils = ModuleManager.FPSTargetingUtils(function(m) FPSTargetingUtils = m end)
local FPSTargetingSmoothing = ModuleManager.FPSTargetingSmoothing(function(m) FPSTargetingSmoothing = m end)
local FPSPersistence = ModuleManager.FPSPersistence(function(m) FPSPersistence = m end)

---@class FPSCameraUtils
local FPSCameraUtils = {}

--- Checks if FPS camera should be updated
---@return boolean shouldUpdate Whether FPS camera should be updated
function FPSCameraUtils.shouldUpdateFPSCamera()
    if STATE.mode.name ~= 'fps' or not STATE.mode.unitID then
        return false
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.mode.unitID) then
        Log:trace("Unit no longer exists")
        ModeManager.disableMode()
        return false
    end

    return true
end

--- Calculate the height if it's not set
function FPSCameraUtils.ensureHeightIsSet()
    -- Set PEACE mode height if not set
    if not CONFIG.CAMERA_MODES.FPS.OFFSETS.PEACE.HEIGHT then
        local unitHeight = math.max(Util.getUnitHeight(STATE.mode.unitID), 100) + 30
        CONFIG.CAMERA_MODES.FPS.OFFSETS.PEACE.HEIGHT = unitHeight
    end

    -- Ensure COMBAT mode height is set (though it should have a default)
    if not CONFIG.CAMERA_MODES.FPS.OFFSETS.COMBAT.HEIGHT then
        CONFIG.CAMERA_MODES.FPS.OFFSETS.COMBAT.HEIGHT = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.COMBAT.HEIGHT
    end

    -- Ensure WEAPON mode height is set (though it should have a default)
    if not CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON.HEIGHT then
        CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON.HEIGHT = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.WEAPON.HEIGHT
    end
end

--- Gets appropriate offsets based on current mode
---@return table offsets The offsets to apply
function FPSCameraUtils.getAppropriateOffsets()
    -- In combat mode - check if actively attacking
    if STATE.mode.fps.combatModeEnabled then
        if STATE.mode.fps.isAttacking then
            -- Weapon offsets - when actively targeting something
            return CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON
        else
            -- Combat offsets - when in combat mode but not targeting
            return CONFIG.CAMERA_MODES.FPS.OFFSETS.COMBAT
        end
    else
        -- Peace mode - normal offsets
        return CONFIG.CAMERA_MODES.FPS.OFFSETS.PEACE
    end
end

--- Creates a basic camera state object with the specified position and direction
---@param position table Camera position {x, y, z}
---@param direction table Camera direction {dx, dy, dz, rx, ry, rz}
---@return table cameraState Complete camera state object
function FPSCameraUtils.createCameraState(position, direction)
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
--- @param rotFactor number Rotation smoothing factor
--- @return table directionState Camera direction state
function FPSCameraUtils.createHullDirectionState(unitID, offsets, rotFactor)
    local front, _, _ = Spring.GetUnitVectors(unitID)
    local frontX, frontY, frontZ = front[1], front[2], front[3]

    local targetRy = -(Spring.GetUnitHeading(unitID, true) + math.pi) + offsets.ROTATION
    local targetRx = 1.8
    local targetRz = 0

    -- Create camera direction state with smoothed values
    return {
        dx = CameraCommons.lerp(STATE.mode.lastCamDir.x, frontX, rotFactor),
        dy = CameraCommons.lerp(STATE.mode.lastCamDir.y, frontY, rotFactor),
        dz = CameraCommons.lerp(STATE.mode.lastCamDir.z, frontZ, rotFactor),
        rx = CameraCommons.lerp(STATE.mode.lastRotation.rx, targetRx, rotFactor),
        ry = CameraCommons.lerpAngle(STATE.mode.lastRotation.ry, targetRy, rotFactor),
        rz = CameraCommons.lerp(STATE.mode.lastRotation.rz, targetRz, rotFactor),
    }
end

--- Creates direction state when actively firing at a target
--- @param unitID number Unit ID
--- @param targetPos table Target position
--- @param weaponNum number|nil Weapon number
--- @param rotFactor number Rotation smoothing factor
--- @return table|nil directionState Camera direction state or nil if it fails
function FPSCameraUtils.createTargetingDirectionState(unitID, targetPos, weaponNum, rotFactor)
    if not targetPos or not weaponNum then
        return nil
    end

    -- Get the weapon position if available
    local posX, posY, posZ, destX, destY, destZ = Spring.GetUnitWeaponVectors(unitID, weaponNum)
    if not posX or not destX then
        return nil
    end

    -- We have valid weapon vectors
    local weaponPos = { x = posX, y = posY, z = posZ }

    -- Apply target smoothing here - this is the key addition!
    -- Process the target through all smoothing systems (cloud targeting, rotation constraints)
    local processedTarget = FPSTargetingSmoothing.processTarget(targetPos, STATE.mode.fps.lastTargetUnitID)

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
    STATE.mode.fps.weaponPos = weaponPos
    STATE.mode.fps.weaponDir = { dx, dy, dz }
    STATE.mode.fps.activeWeaponNum = weaponNum

    -- Get camera position with weapon offsets
    local camPos = FPSCombatMode.getCameraPositionForActiveWeapon(unitID, FPSCameraUtils.applyFPSOffsets)

    -- Create focusing direction to look at target
    local directionState = CameraCommons.focusOnPoint(camPos, targetPos, rotFactor, rotFactor)

    -- Apply rotation constraints to prevent too rapid rotation
    if directionState and STATE.mode.fps.isAttacking then
        -- Get the constrained rotation values
        local constrainedYaw, constrainedPitch = FPSTargetingSmoothing.constrainRotationRate(
                directionState.ry, directionState.rx)

        -- Apply the constrained values
        directionState.ry = constrainedYaw
        directionState.rx = constrainedPitch
    end

    return directionState
end

--- Handles normal FPS mode camera orientation
--- @param unitID number Unit ID
--- @param rotFactor number Rotation smoothing factor
--- @return table directionState Camera direction and rotation state
function FPSCameraUtils.handleNormalFPSMode(unitID, rotFactor)
    -- Check if combat mode is enabled
    if STATE.mode.fps.combatModeEnabled then
        -- Check if the unit is actively targeting something
        local targetPos, firingWeaponNum, isNewTarget = FPSCombatMode.getCurrentAttackTarget(unitID)
        if isNewTarget and not STATE.mode.fps.isTargetSwitchTransition then
            FPSCameraUtils.handleNewTarget()
        end

        if STATE.mode.fps.isAttacking then
            -- Try to create direction state based on targeting data
            local targetingState = FPSCameraUtils.createTargetingDirectionState(
                    unitID, targetPos, firingWeaponNum or STATE.mode.fps.activeWeaponNum, rotFactor)

            if targetingState then
                -- Successfully created targeting state
                return targetingState
            end
        end

        -- If we get here, we're in combat mode but not attacking (or couldn't create targeting state)
        -- Use combat offset mode
        return FPSCameraUtils.createHullDirectionState(unitID, CONFIG.CAMERA_MODES.FPS.OFFSETS.COMBAT, rotFactor)
    else
        -- Normal mode - always ensure isAttacking is false
        STATE.mode.fps.isAttacking = false
        return FPSCameraUtils.createHullDirectionState(unitID, CONFIG.CAMERA_MODES.FPS.OFFSETS.PEACE, rotFactor)
    end
end

function FPSCameraUtils.handleNewTarget()
    local trackedUnitID = STATE.mode.unitID
    if not trackedUnitID or not Spring.ValidUnitID(trackedUnitID) then
        return
    end

    -- Initialize state fields if needed
    if not STATE.mode.fps.previousTargetPos then
        if STATE.mode.fps.lastTargetPos then
            STATE.mode.fps.previousTargetPos = {
                x = STATE.mode.fps.lastTargetPos.x,
                y = STATE.mode.fps.lastTargetPos.y,
                z = STATE.mode.fps.lastTargetPos.z
            }
        end
    end

    if not STATE.mode.fps.lastTargetSwitchTime then
        STATE.mode.fps.lastTargetSwitchTime = Spring.GetTimer()
    end

    -- Check for target suitability
    local newTargetPos = STATE.mode.fps.lastTargetPos
    local previousTargetPos = STATE.mode.fps.previousTargetPos

    -- Skip if we don't have proper target data
    if not newTargetPos then
        return
    end

    -- First acquisition just store it
    if not previousTargetPos then
        STATE.mode.fps.previousTargetPos = {
            x = newTargetPos.x,
            y = newTargetPos.y,
            z = newTargetPos.z
        }
        return
    end

    -- Get current time
    local currentTime = Spring.GetTimer()

    -- Rate limiting criteria
    local timeSinceLastTransition = Spring.DiffTimers(currentTime, STATE.mode.fps.lastTargetSwitchTime)
    local minTimeBetweenTransitions = STATE.mode.fps.isTargetSwitchTransition and 0.5 or 1.0  -- Shorter if already in transition

    -- Enhanced decision criteria:
    local isInTransition = STATE.mode.fps.isTargetSwitchTransition
    local isTimeSufficientForNewTransition = timeSinceLastTransition > minTimeBetweenTransitions

    -- Skip transition if:
    -- 1. Already in transition, OR
    -- 2. Distance too small, OR
    -- 3. Last transition was too recent
    if isInTransition or (not isTimeSufficientForNewTransition) then
        -- Just update the previous target position without starting a new transition
        STATE.mode.fps.previousTargetPos = {
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
    STATE.mode.fps.previousCamPosWorld = {
        x = currentCameraState.px,
        y = currentCameraState.py,
        z = currentCameraState.pz
    }

    -- Store previous direction vector (used for calculating target camera position)
    if STATE.mode.fps.weaponDir then
        STATE.mode.fps.previousWeaponDir = {
            STATE.mode.fps.weaponDir[1],
            STATE.mode.fps.weaponDir[2],
            STATE.mode.fps.weaponDir[3]
        }
    else
        local _, frontVec, _, _ = Spring.GetUnitVectors(trackedUnitID)
        if frontVec then
            STATE.mode.fps.previousWeaponDir = { frontVec[1], frontVec[2], frontVec[3] }
        else
            STATE.mode.fps.previousWeaponDir = { 0, 0, 1 }  -- Fallback
        end
    end

    -- Start transition
    STATE.mode.fps.isTargetSwitchTransition = true
    STATE.mode.fps.targetSwitchStartTime = currentTime
    STATE.mode.fps.lastTargetSwitchTime = currentTime
    STATE.mode.fps.transitionCounter = (STATE.mode.fps.transitionCounter or 0) + 1

    -- Signal rotation constraints to reset
    if STATE.mode.fps.targetSmoothing and STATE.mode.fps.targetSmoothing.rotationConstraint then
        STATE.mode.fps.targetSmoothing.rotationConstraint.resetForSwitch = true
        Log:debug("Signaling rotation constraint reset.")
    end

    -- Store this target position for future comparisons
    STATE.mode.fps.previousTargetPos = {
        x = newTargetPos.x,
        y = newTargetPos.y,
        z = newTargetPos.z
    }
end

--- Sets a fixed look point for the camera
---@param fixedPoint table Point to look at {x, y, z}
---@param targetUnitID number|nil Optional unit ID to track
---@return boolean success Whether fixed point was set successfully
function FPSCameraUtils.setFixedLookPoint(fixedPoint, targetUnitID)
    if Util.isTurboBarCamDisabled() then
        return false
    end
    if Util.isModeDisabled("fps") then
        return false
    end
    if not STATE.mode.unitID then
        Log:trace("No unit being tracked for fixed point camera")
        return false
    end

    -- Set the fixed point
    STATE.mode.fps.fixedPoint = fixedPoint
    STATE.mode.fps.targetUnitID = targetUnitID
    STATE.mode.fps.isFixedPointActive = true

    -- We're no longer in target selection mode
    STATE.mode.fps.inTargetSelectionMode = false
    STATE.mode.fps.prevFixedPoint = nil -- Clear saved previous fixed point

    -- Use the previous free camera state for normal operation
    STATE.mode.fps.isFreeCameraActive = STATE.mode.fps.prevFreeCamState or false

    -- If not in free camera mode, enable a transition to the fixed point
    if not STATE.mode.fps.isFreeCameraActive then
        -- Trigger a transition to smoothly move to the new view
        STATE.mode.isModeTransitionInProgress = true
        STATE.mode.transitionStartTime = Spring.GetTimer()
    end

    if not STATE.mode.fps.targetUnitID then
        Log:trace("Camera will follow unit but look at fixed point")
    else
        local unitDef = UnitDefs[Spring.GetUnitDefID(STATE.mode.fps.targetUnitID)]
        local targetName = unitDef and unitDef.name or "Unnamed unit"
        Log:trace("Camera will follow unit but look at unit " .. STATE.mode.fps.targetUnitID ..
                " (" .. targetName .. ")")
    end

    return true
end

--- Clears fixed point tracking
function FPSCameraUtils.clearFixedLookPoint()
    if Util.isTurboBarCamDisabled() then
        return
    end

    if STATE.mode.fps.isFixedPointActive and STATE.mode.unitID then
        -- Disable fixed point tracking
        STATE.mode.fps.isFixedPointActive = false
        STATE.mode.fps.fixedPoint = nil
        STATE.mode.fps.targetUnitID = nil  -- Clear the target unit ID
        STATE.mode.fps.inTargetSelectionMode = false
        STATE.mode.fps.prevFixedPoint = nil -- Clear saved previous fixed point

        -- Start a transition when changing modes
        STATE.mode.isModeTransitionInProgress = true
        STATE.mode.transitionStartTime = Spring.GetTimer()

        if STATE.mode.fps.isFreeCameraActive then
            Log:trace("Fixed point tracking disabled, maintaining free camera mode")
        else
            Log:trace("Fixed point tracking disabled, returning to FPS mode")
        end
    end
end

--- Updates the fixed point if tracking a unit
---@return table|nil fixedPoint The updated fixed point or nil if not tracking a unit
function FPSCameraUtils.updateFixedPointTarget()
    if not STATE.mode.fps.targetUnitID or not Spring.ValidUnitID(STATE.mode.fps.targetUnitID) then
        return STATE.mode.fps.fixedPoint
    end

    -- Get the current position of the target unit
    local targetX, targetY, targetZ = Spring.GetUnitPosition(STATE.mode.fps.targetUnitID)
    STATE.mode.fps.fixedPoint = {
        x = targetX,
        y = targetY,
        z = targetZ
    }
    return STATE.mode.fps.fixedPoint
end

--- Determines appropriate smoothing factors based on current state
---@param smoothType string Type of smoothing ('position', 'rotation', 'direction')
---@return number smoothingFactor The smoothing factor to use
function FPSCameraUtils.getSmoothingFactor(smoothType, additionalFactor)
    -- Determine which mode we're in
    local smoothingMode
    if STATE.mode.fps.combatModeEnabled then
        if STATE.mode.fps.isAttacking then
            smoothingMode = "WEAPON"
        else
            smoothingMode = "COMBAT"
        end
    else
        smoothingMode = "PEACE"
    end

    local result = CONFIG.CAMERA_MODES.FPS.SMOOTHING.PEACE.POSITION_FACTOR

    additionalFactor = additionalFactor or 1
    -- Get the appropriate smoothing factor based on mode and type
    if smoothType == 'position' then
        result = CONFIG.CAMERA_MODES.FPS.SMOOTHING[smoothingMode].POSITION_FACTOR
    elseif smoothType == 'rotation' then
        result = CONFIG.CAMERA_MODES.FPS.SMOOTHING[smoothingMode].ROTATION_FACTOR
    end

    return STATE.mode.fps.transitionFactor or (result * additionalFactor)
end

local function getFPSParamPrefixes()
    return {
        PEACE = "PEACE.",
        COMBAT = "COMBAT.",
        WEAPON = "WEAPON."
    }
end

--- Update adjustParams to handle the new offset structure
function FPSCameraUtils.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("fps") then
        return
    end

    -- Make sure we have a unit to track
    if not STATE.mode.unitID then
        Log:trace("No unit being tracked")
        return
    end

    -- Handle reset directly
    if params == "reset" then
        FPSCameraUtils.resetOffsets()
        FPSPersistence.saveUnitSettings("fps", STATE.mode.unitID)
        return
    end

    -- Determine current FPS submode
    local currentFPSMode
    if STATE.mode.fps.combatModeEnabled then
        if STATE.mode.fps.isAttacking then
            currentFPSMode = "WEAPON"
        else
            currentFPSMode = "COMBAT"
        end
    else
        currentFPSMode = "PEACE"
    end

    Log:trace("Adjusting FPS parameters for submode: " .. currentFPSMode)

    -- Call the generic adjustParams function
    Util.adjustParams(params, "FPS", function()
        FPSCameraUtils.resetOffsets()
    end, currentFPSMode, getFPSParamPrefixes)

    FPSPersistence.saveUnitSettings("fps", STATE.mode.unitID)
end

--- Resets camera offsets to default values
function FPSCameraUtils.resetOffsets()
    local function reset(mode)
        CONFIG.CAMERA_MODES.FPS.OFFSETS[mode].HEIGHT = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS[mode].HEIGHT
        CONFIG.CAMERA_MODES.FPS.OFFSETS[mode].FORWARD = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS[mode].FORWARD
        CONFIG.CAMERA_MODES.FPS.OFFSETS[mode].SIDE = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS[mode].SIDE
        CONFIG.CAMERA_MODES.FPS.OFFSETS[mode].ROTATION = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS[mode].ROTATION
    end

    reset("PEACE")
    reset("COMBAT")
    reset("WEAPON")

    FPSCameraUtils.ensureHeightIsSet()
    Log:trace("Restored fps camera settings to defaults")
    return true
end

--- Applies FPS camera offsets to unit position, handling target switch transitions
---@param position table Unit position {x, y, z}
---@param front table Unit Front vector
---@param up table Unit Up vector
---@param right table Unit Right vector
---@return table camPos Final Camera position with offsets and transitions applied
function FPSCameraUtils.applyFPSOffsets(position, front, up, right)
    FPSCameraUtils.ensureHeightIsSet()
    local offsets = FPSCameraUtils.getAppropriateOffsets()
    local unitPos = { x = position.x, y = position.y, z = position.z } -- Store original unit center

    -- Determine which vectors to use based on state
    local frontVec, upVec, rightVec
    local weaponBasePos = unitPos

    if STATE.mode.fps.isAttacking and STATE.mode.fps.weaponDir then
        -- Use weapon position when attacking if available
        if STATE.mode.fps.weaponPos then
            weaponBasePos = STATE.mode.fps.weaponPos
            position = STATE.mode.fps.weaponPos
        end
        -- Use weapon direction when attacking
        frontVec = STATE.mode.fps.weaponDir
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
    targetCamPosWorld = FPSCameraUtils.enforceMinimumHeight(targetCamPosWorld, STATE.mode.unitID)

    -- IMPORTANT: First apply the stabilization for jittery camera
    local finalCamPosWorld = targetCamPosWorld

    -- Handle transition if active
    if STATE.mode.fps.isTargetSwitchTransition then
        local transitionPos = FPSCameraUtils.handleTransition(targetCamPosWorld)
        if transitionPos then
            finalCamPosWorld = transitionPos
        end
    else
        -- Apply stabilization when not in transition
        local stabilizedPos = FPSCameraUtils.applyStabilization(targetCamPosWorld)
        if stabilizedPos then
            finalCamPosWorld = stabilizedPos
        end
    end

    -- IMPORTANT: Apply air target repositioning AFTER stabilization
    -- This ensures the air adjustment respects the stabilized camera state
    if STATE.mode.fps.isAttacking and STATE.mode.fps.lastTargetPos then
        finalCamPosWorld = FPSTargetingUtils.handleAirTargetRepositioning(
                finalCamPosWorld,
                STATE.mode.fps.lastTargetPos,
                unitPos  -- Pass original unit position for reference
        )
    end

    return finalCamPosWorld
end

-- New separated function to handle either transition or stabilization
-- This follows the guideline to avoid large conditional blocks
function FPSCameraUtils.applyStabilizationOrTransition(targetCamPosWorld)
    -- Check if we are in a target switch transition
    if STATE.mode.fps.isTargetSwitchTransition then
        return FPSCameraUtils.handleTransition(targetCamPosWorld)
    end

    -- Not in transition, check if we need stabilization
    return FPSCameraUtils.applyStabilization(targetCamPosWorld)
end

-- Separate function to handle camera transition
-- This follows the guideline to split large conditionals into functions
function FPSCameraUtils.handleTransition(targetCamPosWorld)
    local now = Spring.GetTimer()
    local elapsed = Spring.DiffTimers(now, STATE.mode.fps.targetSwitchStartTime or now)
    local transitionDuration = STATE.mode.fps.targetSwitchDuration or 0.4

    -- Calculate the progress with ease-in-out curve for smoother acceleration/deceleration
    local rawProgress = math.min(1.0, elapsed / transitionDuration)
    -- Ease-in-out: smoother at start and end of transition
    local progress = rawProgress * rawProgress * (3 - 2 * rawProgress)

    if progress < 1.0 then
        -- Use current actual camera position for transition
        if STATE.mode.fps.previousCamPosWorld then
            local startPos = STATE.mode.fps.previousCamPosWorld
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
        STATE.mode.fps.isTargetSwitchTransition = false
        STATE.mode.fps.previousCamPosWorld = nil
        Log:info("Target switch transition finished.")
    end

    return nil
end

-- Separate function to handle camera stabilization for jittery situations
-- This follows the guideline to split large conditionals into functions
function FPSCameraUtils.applyStabilization(targetCamPosWorld)
    -- Get targeting information from smoothing system
    local targetSmoothing = STATE.mode.fps.targetSmoothing

    -- Only apply stabilization during active targeting with high target switching activity
    if not STATE.mode.fps.isAttacking or not targetSmoothing or
            not targetSmoothing.activityLevel or targetSmoothing.activityLevel <= 0.5 then
        -- Reset stabilization when not in a high-activity targeting situation
        STATE.mode.fps.stableCamPos = nil
        return nil
    end

    -- Initialize stable camera position history if needed
    if not STATE.mode.fps.stableCamPos then
        STATE.mode.fps.stableCamPos = targetCamPosWorld
        STATE.mode.fps.cameraStabilityFactor = 0.05 -- Default slow response
    end

    -- Calculate stabilization factors
    local factor = FPSCameraUtils.calculateStabilityFactor(targetSmoothing)

    -- Apply very gradual interpolation towards the target position
    local stableCamPos = STATE.mode.fps.stableCamPos

    local smoothedCamPos = {
        x = stableCamPos.x + (targetCamPosWorld.x - stableCamPos.x) * factor,
        y = stableCamPos.y + (targetCamPosWorld.y - stableCamPos.y) * factor,
        z = stableCamPos.z + (targetCamPosWorld.z - stableCamPos.z) * factor
    }

    -- Update stable camera position for next frame
    STATE.mode.fps.stableCamPos = smoothedCamPos

    -- Log stabilization info periodically
    FPSCameraUtils.logStabilizationInfo(factor, targetSmoothing)

    return smoothedCamPos
end

-- Calculate stability factor based on activity level
-- Following the guideline to avoid code duplication
function FPSCameraUtils.calculateStabilityFactor(targetSmoothing)
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
    STATE.mode.fps.cameraStabilityFactor = factor

    return factor
end

-- Log stabilization info periodically to avoid spam
function FPSCameraUtils.logStabilizationInfo(factor, targetSmoothing)
    local currentTime = Spring.GetTimer()
    if not STATE.mode.fps.lastStabilizationLog or
            Spring.DiffTimers(currentTime, STATE.mode.fps.lastStabilizationLog) > 1.0 then
        Log:debug(string.format("Camera stabilization active: factor=%.3f, activity=%.2f, switches=%d",
                factor, targetSmoothing.activityLevel, targetSmoothing.targetSwitchCount or 0))
        STATE.mode.fps.lastStabilizationLog = currentTime
    end
end

--- Ensures camera doesn't go below minimum height
--- @param position table Camera position {x, y, z}
--- @param unitID number The unit ID
--- @return table adjustedPos Position with height constraint applied
function FPSCameraUtils.enforceMinimumHeight(position, unitID)
    if not position then
        return position
    end

    local minHeight = FPSCameraUtils.getMinimumCameraHeight(unitID)
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
function FPSCameraUtils.getMinimumCameraHeight(unitID)
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

return FPSCameraUtils