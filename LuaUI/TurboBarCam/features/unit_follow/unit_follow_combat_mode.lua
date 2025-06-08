---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local Scheduler = ModuleManager.Scheduler(function(m) Scheduler = m end)
local TransitionManager = ModuleManager.TransitionManager(function(m) TransitionManager = m end)

-- Constants for attack state management
local ATTACK_STATE_DEBOUNCE_ID = "unit_follow_attack_state_debounce"
local ATTACK_STATE_COOLDOWN = 1.5

---@class UnitFollowCombatMode
local UnitFollowCombatMode = {}

--- Cycles through unit's weapons
function UnitFollowCombatMode.nextWeapon()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled('unit_follow') then
        return
    end
    if not STATE.mode.unitID or not Spring.ValidUnitID(STATE.mode.unitID) then
        Log:debug("No unit selected.")
        return
    end

    local unitID = STATE.mode.unitID
    local unitDefID = Spring.GetUnitDefID(unitID)
    local unitDef = UnitDefs[unitDefID]

    if not unitDef or not unitDef.weapons then
        Log:info("Unit has no weapons")
        return
    end

    -- Collect all valid weapon numbers in order
    local weaponNumbers = {}
    for weaponNum, weaponData in pairs(unitDef.weapons) do
        -- ignoring low range weapons because they probably aren't real weapons
        if type(weaponNum) == "number" and WeaponDefs[weaponData.weaponDef].range > 100 then
            table.insert(weaponNumbers, weaponNum)
        end
    end

    -- Sort them (since pairs() iteration order is not guaranteed)
    table.sort(weaponNumbers)

    if #weaponNumbers == 0 then
        Log:info("Unit has no usable weapons")
        return
    end

    local currentWeapon = STATE.mode.unit_follow.forcedWeaponNumber or weaponNumbers[1]

    -- Find the index of the current weapon in our ordered list
    local currentIndex = 1
    for i, num in ipairs(weaponNumbers) do
        if num == currentWeapon then
            currentIndex = i
            break
        end
    end

    -- Move to the next weapon or wrap around to the first
    local nextIndex = currentIndex % #weaponNumbers + 1
    STATE.mode.unit_follow.forcedWeaponNumber = weaponNumbers[nextIndex]

    -- Enable combat mode
    UnitFollowCombatMode.setCombatMode(true)

    -- Check if actively targeting something
    local targetPos = UnitFollowCombatMode.getWeaponTargetPosition(unitID, STATE.mode.unit_follow.forcedWeaponNumber)

    -- Set attacking state with debounce cancellation (if we're newly attacking)
    if targetPos then
        UnitFollowCombatMode.setAttackingState(true)
    else
        UnitFollowCombatMode.setAttackingState(false)
    end

    -- Use a smooth transition
    STATE.mode.isModeTransitionInProgress = true
    STATE.mode.transitionStartTime = Spring.GetTimer()

    Log:info("Current weapon: " .. tostring(STATE.mode.unit_follow.forcedWeaponNumber) .. " (" .. unitDef.wDefs[STATE.mode.unit_follow.forcedWeaponNumber].name .. ")")
end

--- Clear forced weapon
function UnitFollowCombatMode.clearWeaponSelection()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled('unit_follow') then
        return
    end

    STATE.mode.unit_follow.forcedWeaponNumber = nil

    if STATE.mode.unit_follow.combatModeEnabled then
        -- Update state but keep combat mode enabled
        local unitID = STATE.mode.unitID
        if unitID and Spring.ValidUnitID(unitID) then
            -- Check if any weapon is targeting something
            local unitDefID = Spring.GetUnitDefID(unitID)
            local unitDef = UnitDefs[unitDefID]

            if unitDef and unitDef.weapons then
                for weaponNum, weaponData in pairs(unitDef.weapons) do
                    if type(weaponNum) == "number" and WeaponDefs[weaponData.weaponDef].range > 100 then
                        local targetPos = UnitFollowCombatMode.getWeaponTargetPosition(unitID, weaponNum)
                        if targetPos then
                            -- Set attacking state with debounce cancellation
                            UnitFollowCombatMode.setAttackingState(true)
                            STATE.mode.unit_follow.activeWeaponNum = weaponNum
                            return
                        end
                    end
                end
            end
        end

        -- If we reach here, no active targeting was found - start debounce for disabling attack state
        UnitFollowCombatMode.scheduleAttackStateDisable()
    end

    Log:info("Cleared weapon selection.")
end

--- Sets the attacking state with debounce handling
--- @param isAttacking boolean Whether the unit is attacking
function UnitFollowCombatMode.setAttackingState(isAttacking)
    if isAttacking then
        -- If we're now attacking, cancel any scheduled disable
        Scheduler.cancel(ATTACK_STATE_DEBOUNCE_ID)

        -- Only update state if it's changing
        if not STATE.mode.unit_follow.isAttacking then
            STATE.mode.unit_follow.isAttacking = true
            Log:trace("Attack state enabled")
        end
    else
        -- If not attacking now, schedule disabling after cooldown
        UnitFollowCombatMode.scheduleAttackStateDisable()
    end
end

--- Schedules disabling of the attack state after a cooldown period
function UnitFollowCombatMode.scheduleAttackStateDisable()
    -- Only schedule if currently in attacking state and not already scheduled
    if STATE.mode.unit_follow.isAttacking and not Scheduler.isScheduled(ATTACK_STATE_DEBOUNCE_ID) then
        Scheduler.debounce(function()
            -- Only clear if we're still in combat mode
            if STATE.mode.unit_follow.combatModeEnabled then
                UnitFollowCombatMode.clearAttackingState()
                Log:trace("Attack state disabled after cooldown")
            end
        end, ATTACK_STATE_COOLDOWN, ATTACK_STATE_DEBOUNCE_ID)
    end
end

--- Clear attacking state immediately (no debounce)
function UnitFollowCombatMode.clearAttackingState()
    -- Cancel any pending attack state changes
    Scheduler.cancel(ATTACK_STATE_DEBOUNCE_ID)

    if not STATE.mode.unit_follow.isAttacking then
        return
    end

    Log:debug("clear attack state")
    STATE.mode.unit_follow.isAttacking = false
    STATE.mode.unit_follow.weaponPos = nil
    STATE.mode.unit_follow.weaponDir = nil
    STATE.mode.unit_follow.activeWeaponNum = nil
    STATE.mode.unit_follow.lastTargetPos = nil -- Clear the last target position
    STATE.mode.unit_follow.lastTargetUnitID = nil -- Clear the last target unit ID
    STATE.mode.unit_follow.lastTargetUnitName = nil -- Clear the last target unit name
    STATE.mode.unit_follow.lastTargetType = nil -- Clear the last target type
    STATE.mode.unit_follow.lastRotationRx = nil -- Clear last rotation values
    STATE.mode.unit_follow.lastRotationRy = nil
    STATE.mode.unit_follow.targetRotationHistory = {} -- Clear rotation history
end

--- Extracts target position from a weapon target and detects target switches.
---@param unitID number The unit ID
---@param weaponNum number The weapon number
---@return table|nil targetPos The target position or nil if no valid target
---@return number|nil targetUnitID The ID of the target unit, if applicable
---@return number|nil targetType The type of target (1=unit, 2=ground)
function UnitFollowCombatMode.getWeaponTargetPosition(unitID, weaponNum)
    -- Get weapon target info from Spring
    local targetType, targetUnitID, target = Spring.GetUnitWeaponTarget(unitID, weaponNum)

    -- Check if weapon has a proper target
    if not (targetType and targetType > 0 and target) then
        return nil, nil, nil -- No valid target for this weapon
    end
    local newTargetPos

    -- Determine position based on target type
    if targetType == 1 then
        -- Unit target
        targetUnitID = target -- The 'target' is the unitID itself
        if Spring.ValidUnitID(targetUnitID) then
            local x, y, z = Spring.GetUnitPosition(targetUnitID)
            newTargetPos = { x = x, y = y, z = z }
        else
            targetUnitID = nil -- Target unit is invalid
            targetType = nil
        end
    elseif targetType == 2 then
        -- Ground target
        newTargetPos = { x = target[1], y = target[2], z = target[3] }
        targetUnitID = nil -- Ground targets don't have a unit ID
    else
        targetType = nil -- Unknown target type
        targetUnitID = nil
    end

    -- If we couldn't determine a valid position or type, return nil
    if not newTargetPos or not targetType then
        return nil, nil, nil
    end

    local isNewTarget = UnitFollowCombatMode.isNewTarget(targetUnitID, newTargetPos, targetType)

    -- Update the globally tracked last target info *after* comparison and potential transition trigger
    STATE.mode.unit_follow.lastTargetPos = newTargetPos
    STATE.mode.unit_follow.lastTargetType = targetType
    STATE.mode.unit_follow.lastTargetUnitID = targetUnitID -- Can be nil for ground targets
    if targetUnitID then
        local unitDef = UnitDefs[Spring.GetUnitDefID(targetUnitID)]
        STATE.mode.unit_follow.lastTargetUnitName = unitDef and unitDef.name or "Unnamed unit"
    end

    -- Return the determined target position for the specific weapon
    return newTargetPos, isNewTarget, targetUnitID, targetType
end

function UnitFollowCombatMode.isNewTarget(targetUnitID, newTargetPos, targetType)
    local isNewTarget = false
    local oldTargetUnitID = STATE.mode.unit_follow.lastTargetUnitID
    local oldTargetPos = STATE.mode.unit_follow.lastTargetPos

    -- If no old target data, this is definitely a new target
    if not oldTargetPos then
        return true
    end

    if targetUnitID then
        -- Prioritize Unit ID for comparison (most accurate)
        if targetUnitID ~= oldTargetUnitID then
            isNewTarget = true
        end
    elseif newTargetPos and oldTargetPos then
        -- Compare position for non-unit or changed targets
        local distanceSquared = CameraCommons.distanceSquared(newTargetPos, oldTargetPos)

        -- Use a higher threshold to reduce sensitivity
        -- Now we use 200*200=40000 (significantly higher)
        if distanceSquared > (200 * 200) then
            -- Threshold: > 200 units moved significantly
            isNewTarget = true
            -- If switching to a ground target, clear the last unit ID state
            -- Check explicitly if the *old* target was a unit and the new one is ground
            if oldTargetUnitID and targetType == 2 then
                STATE.mode.unit_follow.lastTargetUnitID = nil
            end
        end
    elseif newTargetPos and not oldTargetPos then
        -- Gained a target when previously had none
        isNewTarget = true
    end

    -- If this is a new target, make sure we store it in previousTargetPos for the transition system
    if isNewTarget and not STATE.mode.unit_follow.previousTargetPos then
        STATE.mode.unit_follow.previousTargetPos = oldTargetPos
    end

    return isNewTarget
end

function UnitFollowCombatMode.chooseWeapon(unitID, unitDef)
    -- If we have a forced weapon number, only check that specific weapon
    if STATE.mode.unit_follow.forcedWeaponNumber then
        local weaponNum = STATE.mode.unit_follow.forcedWeaponNumber

        -- Verify that this weapon exists for the unit
        if unitDef.weapons[weaponNum] then
            -- Get target for forced weapon
            local targetPos, isNewTarget = UnitFollowCombatMode.getWeaponTargetPosition(unitID, weaponNum)

            if targetPos then
                return targetPos, weaponNum, isNewTarget
            end

            -- If we get here with a forced weapon but no target, we still return the forced weapon number
            -- This allows the camera to stay on the forced weapon even when not targeting
            return nil, weaponNum
        end
    end

    -- If no forced weapon, or forced weapon had no valid target, process all weapons
    for weaponNum, weaponData in pairs(unitDef.weapons) do
        -- ignoring low range weapons because they probably aren't real weapons
        if type(weaponNum) == "number" and WeaponDefs[weaponData.weaponDef].range > 100 then
            local targetPos, isNewTarget = UnitFollowCombatMode.getWeaponTargetPosition(unitID, weaponNum)
            if targetPos then
                return targetPos, weaponNum, isNewTarget
            end
        end
    end
end

--- Checks if unit is currently attacking a target (even without explicit command)
--- @param unitID number Unit ID to check
--- @return table|nil targetPos Position of the current attack target or nil
--- @return number|nil weaponNum The weapon number that is firing at the target
function UnitFollowCombatMode.getCurrentAttackTarget(unitID)
    if not Spring.ValidUnitID(unitID) then
        -- Schedule disabling attack state when unit is invalid
        UnitFollowCombatMode.scheduleAttackStateDisable()
        return nil, nil
    end

    local unitDefID = Spring.GetUnitDefID(unitID)
    local unitDef = UnitDefs[unitDefID]

    if not unitDef or not unitDef.weapons then
        -- Schedule disabling attack state when unit has no weapons
        UnitFollowCombatMode.scheduleAttackStateDisable()
        return nil, nil
    end

    local targetPos, weaponNum, isNewTarget = UnitFollowCombatMode.chooseWeapon(unitID, unitDef)

    -- If no target was found, but we have a last target position and we're in attacking state
    if not targetPos and STATE.mode.unit_follow.isAttacking and STATE.mode.unit_follow.lastTargetPos then
        Log:debug("Using last target position for " .. (STATE.mode.unit_follow.lastTargetUnitName or "unknown target"))
        UnitFollowCombatMode.scheduleAttackStateDisable()
        -- Return the last known target position and the active weapon number
        return STATE.mode.unit_follow.lastTargetPos, STATE.mode.unit_follow.activeWeaponNum
    end

    -- If no target was found at all, schedule disabling attack state
    if not targetPos then
        UnitFollowCombatMode.scheduleAttackStateDisable()
    else
        -- We found a target, cancel any pending disable and ensure attacking state is on
        Scheduler.cancel(ATTACK_STATE_DEBOUNCE_ID)
        STATE.mode.unit_follow.isAttacking = true

        -- Store the active weapon number for later use
        STATE.mode.unit_follow.activeWeaponNum = weaponNum

        -- Save the current target position for later use
        STATE.mode.unit_follow.lastTargetPos = targetPos
    end

    return targetPos, weaponNum, isNewTarget
end

--- Gets camera position for a unit, optionally using weapon position
--- @param unitID number Unit ID
--- @return table camPos Camera position with offsets applied
function UnitFollowCombatMode.getCameraPositionForActiveWeapon(unitID, applyOffsets)
    local x, y, z = Spring.GetUnitPosition(unitID)
    local front, up, right = Spring.GetUnitVectors(unitID)
    local unitPos = { x = x, y = y, z = z }
    local weaponNum = STATE.mode.unit_follow.activeWeaponNum

    if weaponNum then
        local posX, posY, posZ, destX, destY, destZ = Spring.GetUnitWeaponVectors(unitID, weaponNum)

        if posX and destX then
            -- Use weapon position instead of unit center
            unitPos = { x = posX, y = posY, z = posZ }

            -- Create normalized weapon direction vector
            local magnitude = math.sqrt(destX * destX + destY * destY + destZ * destZ)
            local normalizedDir
            if magnitude > 0 then
                normalizedDir = {
                    destX / magnitude,
                    destY / magnitude,
                    destZ / magnitude
                }
            else
                normalizedDir = { destX, destY, destZ }
            end

            -- Update state for tracking
            STATE.mode.unit_follow.weaponPos = unitPos
            STATE.mode.unit_follow.weaponDir = normalizedDir
            STATE.mode.unit_follow.activeWeaponNum = weaponNum
        end
    end

    -- Apply offsets to the position (applyOffsets will choose the right offset type)
    return applyOffsets(unitPos, front, up, right)
end

--- Toggles combat mode on/off
--- @return boolean success Whether the toggle was successful
function UnitFollowCombatMode.toggleCombatMode()
    if Utils.isTurboBarCamDisabled() then
        return false
    end
    if Utils.isModeDisabled('unit_follow') then
        return false
    end

    if STATE.mode.unit_follow.combatModeEnabled then
        UnitFollowCombatMode.setCombatMode(false)
    else
        UnitFollowCombatMode.setCombatMode(true)
    end

    return true
end

--- Switches between combat and normal modes
--- @param enable boolean Whether to enable combat mode
--- @param unitID number|nil The unit ID to use (defaults to STATE.mode.unitID)
--- @return boolean success Whether the switch was successful
function UnitFollowCombatMode.setCombatMode(enable, unitID)
    unitID = unitID or STATE.mode.unitID

    if not unitID or not Spring.ValidUnitID(unitID) then
        Log:trace("No valid unit for combat mode")
        return false
    end

    -- Set the combat mode flag
    STATE.mode.unit_follow.combatModeEnabled = enable

    if enable then
        -- Enable combat mode
        local unitDefID = Spring.GetUnitDefID(unitID)
        local unitDef = UnitDefs[unitDefID]

        -- Find a default weapon to use if not already set
        if not STATE.mode.unit_follow.forcedWeaponNumber and unitDef and unitDef.weapons then
            local weaponNumbers = {}
            for weaponNum, weaponData in pairs(unitDef.weapons) do
                if type(weaponNum) == "number" and WeaponDefs[weaponData.weaponDef].range > 100 then
                    table.insert(weaponNumbers, weaponNum)
                end
            end

            if #weaponNumbers > 0 then
                table.sort(weaponNumbers)
                STATE.mode.unit_follow.forcedWeaponNumber = weaponNumbers[1]
            end
        end

        -- Check if actively targeting something
        local weaponNum = STATE.mode.unit_follow.forcedWeaponNumber
        if weaponNum then
            local targetPos = UnitFollowCombatMode.getWeaponTargetPosition(unitID, weaponNum)

            -- Set attacking state with proper debounce handling
            if targetPos then
                -- Unit is attacking - enable immediately
                STATE.mode.unit_follow.isAttacking = true
                Scheduler.cancel(ATTACK_STATE_DEBOUNCE_ID)
            else
                -- Unit is not attacking - start with attacking false
                Log:debug("unit not attacking")
                STATE.mode.unit_follow.isAttacking = false
            end

            -- Get weapon position and direction
            local posX, posY, posZ, destX, destY, destZ = Spring.GetUnitWeaponVectors(unitID, weaponNum)
            if posX and destX then
                -- Use weapon position
                STATE.mode.unit_follow.weaponPos = { x = posX, y = posY, z = posZ }

                -- Create normalized vector
                local magnitude = math.sqrt(destX * destX + destY * destY + destZ * destZ)
                if magnitude > 0 then
                    STATE.mode.unit_follow.weaponDir = {
                        destX / magnitude,
                        destY / magnitude,
                        destZ / magnitude
                    }
                else
                    STATE.mode.unit_follow.weaponDir = { destX, destY, destZ }
                end

                STATE.mode.unit_follow.activeWeaponNum = weaponNum
            end
        end
        Log:info("Combat mode enabled")
    else
        -- Disable combat mode - immediately clear attacking state
        Scheduler.cancel(ATTACK_STATE_DEBOUNCE_ID)
        STATE.mode.unit_follow.isAttacking = false
        STATE.mode.unit_follow.weaponPos = nil
        STATE.mode.unit_follow.weaponDir = nil
        Log:info("Combat mode disabled")
    end

    -- Trigger a transition for smooth camera movement
    TransitionManager.start({
        id = "UnitFollowCombatMode.CombatToWeaponMode",
        easingFn = CameraCommons.easeOut,
        duration = 1.5,
        onUpdate = function(_, easedProgress, _)
            STATE.mode.unit_follow.transitionFactor = CameraCommons.lerp(0.001, CONFIG.CAMERA_MODES.UNIT_FOLLOW.SMOOTHING.COMBAT.ROTATION_FACTOR, easedProgress)
        end,
        onComplete = function()
            STATE.mode.unit_follow.transitionFactor = nil
        end
    })
    return true
end

return UnitFollowCombatMode