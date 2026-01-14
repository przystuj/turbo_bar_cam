---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "UnitFollowCombatMode")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local Scheduler = ModuleManager.Scheduler(function(m) Scheduler = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)

-- Constants for attack state management
local ATTACK_STATE_DEBOUNCE_ID = "unit_follow_attack_state_debounce"
local ATTACK_STATE_FREEZE_ID = "attack_state_freeze_id"
local ACQUISITION_DEBOUNCE_ID = "unit_follow_target_acquisition"

local isAir = {}
for unitDefID, unitDef in pairs(UnitDefs) do
    if unitDef.isAirUnit then
        isAir[unitDefID] = true
    end
end

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
    if not STATE.active.mode.unitID or not Spring.ValidUnitID(STATE.active.mode.unitID) then
        Log:debug("No unit selected.")
        return
    end

    local unitID = STATE.active.mode.unitID
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

    table.sort(weaponNumbers)

    if #weaponNumbers == 0 then
        Log:info("Unit has no usable weapons")
        return
    end

    local currentWeapon = STATE.active.mode.unit_follow.forcedWeaponNumber or weaponNumbers[1]

    local currentIndex = 1
    for i, num in ipairs(weaponNumbers) do
        if num == currentWeapon then
            currentIndex = i
            break
        end
    end

    -- Move to the next weapon or wrap around to the first
    local nextIndex = currentIndex % #weaponNumbers + 1
    STATE.active.mode.unit_follow.forcedWeaponNumber = weaponNumbers[nextIndex]

    -- Enable combat mode
    UnitFollowCombatMode.setCombatMode(true)

    -- Check if actively targeting something
    local targetPos = UnitFollowCombatMode.getWeaponTargetPosition(unitID, STATE.active.mode.unit_follow.forcedWeaponNumber)

    -- Set attacking state with debounce cancellation (if we're newly attacking)
    if targetPos then
        UnitFollowCombatMode.setAttackingState(true)
    else
        UnitFollowCombatMode.setAttackingState(false)
    end

    -- Use a smooth transition
    STATE.active.mode.isModeTransitionInProgress = true
    STATE.active.mode.transitionStartTime = Spring.GetTimer()

    Log:info("Current weapon: " .. tostring(STATE.active.mode.unit_follow.forcedWeaponNumber) .. " (" .. unitDef.wDefs[STATE.active.mode.unit_follow.forcedWeaponNumber].name .. ")")
end

--- Clear forced weapon
function UnitFollowCombatMode.clearWeaponSelection()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled('unit_follow') then
        return
    end

    STATE.active.mode.unit_follow.forcedWeaponNumber = nil
    Log:info("Cleared weapon selection.")
end

function UnitFollowCombatMode.resetAttackState(delay)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled('unit_follow') then
        return
    end
    STATE.active.mode.unit_follow.freezeAttackState = true
    UnitFollowCombatMode.clearAttackingState()
    Scheduler.debounce(function()
        STATE.active.mode.unit_follow.freezeAttackState = false
    end, tonumber(delay), ATTACK_STATE_FREEZE_ID)
end

--- Sets the attacking state with debounce handling
--- @param isAttacking boolean Whether the unit is attacking
function UnitFollowCombatMode.setAttackingState(isAttacking)
    if isAttacking and not STATE.active.mode.unit_follow.freezeAttackState then
        -- If we're now attacking, cancel any scheduled disable
        Scheduler.cancel(ATTACK_STATE_DEBOUNCE_ID)

        -- Only update state if it's changing
        if not STATE.active.mode.unit_follow.isAttacking then
            STATE.active.mode.unit_follow.isAttacking = true
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
    if STATE.active.mode.unit_follow.isAttacking and not Scheduler.isScheduled(ATTACK_STATE_DEBOUNCE_ID) then
        Scheduler.debounce(function()
            -- Only clear if we're still in combat mode
            if STATE.active.mode.unit_follow.combatModeEnabled then
                UnitFollowCombatMode.clearAttackingState()
                Log:trace("Attack state disabled after cooldown")
            end
        end, CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.ATTACK_STATE_COOLDOWN, ATTACK_STATE_DEBOUNCE_ID)
    end
end

--- Clear attacking state immediately (no debounce)
function UnitFollowCombatMode.clearAttackingState()
    -- Cancel any pending attack state changes
    Scheduler.cancel(ATTACK_STATE_DEBOUNCE_ID)
    Scheduler.cancel(ACQUISITION_DEBOUNCE_ID)

    if not STATE.active.mode.unit_follow.isAttacking then
        return
    end

    STATE.active.mode.unit_follow.isAttacking = false
    STATE.active.mode.unit_follow.weaponPos = nil
    STATE.active.mode.unit_follow.weaponDir = nil
    STATE.active.mode.unit_follow.activeWeaponNum = nil
    STATE.active.mode.unit_follow.lastTargetPos = nil -- Clear the last target position
    STATE.active.mode.unit_follow.lastTargetUnitID = nil -- Clear the last target unit ID
    STATE.active.mode.unit_follow.pendingTarget = nil
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
            if CONFIG.CAMERA_MODES.UNIT_FOLLOW.IGNORE_AIR_TARGETS and isAir[Spring.GetUnitDefID(targetUnitID)] then
                return nil, nil, nil
            end

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

    -- Return the determined target position for the specific weapon
    return newTargetPos, targetUnitID, targetType
end

function UnitFollowCombatMode.isNewTarget(targetUnitID, newTargetPos, targetType)
    local isNewTarget = false
    local oldTargetUnitID = STATE.active.mode.unit_follow.lastTargetUnitID
    local oldTargetPos = STATE.active.mode.unit_follow.lastTargetPos

    -- If no old target data, this is definitely a new target
    if not oldTargetPos then
        return true
    end

    if targetUnitID then
        if targetUnitID ~= oldTargetUnitID then
            isNewTarget = true
        end
    elseif newTargetPos and oldTargetPos then
        -- Compare position for non-unit or changed targets
        local distanceSquared = MathUtils.vector.distanceSq(newTargetPos, oldTargetPos)

        if distanceSquared > (400 * 400) then
            isNewTarget = true
            -- If switching to a ground target, clear the last unit ID state
            if oldTargetUnitID and targetType == 2 then
                STATE.active.mode.unit_follow.lastTargetUnitID = nil
            end
        end
    elseif newTargetPos and not oldTargetPos then
        isNewTarget = true
    end

    -- If this is a new target, make sure we store it in previousTargetPos for the transition system
    if isNewTarget and not STATE.active.mode.unit_follow.previousTargetPos then
        STATE.active.mode.unit_follow.previousTargetPos = oldTargetPos
    end

    return isNewTarget
end

function UnitFollowCombatMode.getCurrentTarget(unitID, unitDef)
    -- If we have a forced weapon number, only check that specific weapon
    if STATE.active.mode.unit_follow.forcedWeaponNumber then
        local weaponNum = STATE.active.mode.unit_follow.forcedWeaponNumber

        -- Verify that this weapon exists for the unit
        if unitDef.weapons[weaponNum] then
            -- Get target for forced weapon
            local targetPos, targetUnitID, targetType = UnitFollowCombatMode.getWeaponTargetPosition(unitID, weaponNum)

            if targetPos then
                return targetPos, weaponNum, targetUnitID, targetType
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
            local targetPos, targetUnitID, targetType = UnitFollowCombatMode.getWeaponTargetPosition(unitID, weaponNum)
            if targetPos then
                return targetPos, weaponNum, targetUnitID, targetType
            end
        end
    end
end

--- Helper to check if two targets are effectively the same
local function areTargetsEqual(pos1, id1, pos2, id2)
    if not pos1 or not pos2 then return false end
    if id1 and id2 then return id1 == id2 end
    if (id1 and not id2) or (not id1 and id2) then return false end
    local dx = pos1.x - pos2.x
    local dy = pos1.y - pos2.y
    local dz = pos1.z - pos2.z
    return (dx*dx + dy*dy + dz*dz) < 100
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

    local rawTargetPos, weaponNum, rawUnitID, rawType = UnitFollowCombatMode.getCurrentTarget(unitID, unitDef)

    local state = STATE.active.mode.unit_follow
    local confirmedPos = state.lastTargetPos
    local confirmedUnitID = state.lastTargetUnitID
    local pending = state.pendingTarget

    if rawTargetPos then
        if areTargetsEqual(rawTargetPos, rawUnitID, confirmedPos, confirmedUnitID) then
            if pending then
                Scheduler.cancel(ACQUISITION_DEBOUNCE_ID)
                state.pendingTarget = nil
            end
            Scheduler.cancel(ATTACK_STATE_DEBOUNCE_ID)
            state.isAttacking = true and not state.freezeAttackState
            state.activeWeaponNum = weaponNum
        else
            if not (pending and areTargetsEqual(rawTargetPos, rawUnitID, pending.pos, pending.unitID)) then
                state.pendingTarget = {
                    pos = rawTargetPos,
                    unitID = rawUnitID,
                    type = rawType,
                    weaponNum = weaponNum
                }

                Scheduler.debounce(function()
                    local s = STATE.active.mode.unit_follow
                    if s.pendingTarget then
                        s.lastTargetPos = s.pendingTarget.pos
                        s.lastTargetUnitID = s.pendingTarget.unitID
                        s.activeWeaponNum = s.pendingTarget.weaponNum
                        s.isAttacking = true
                        s.justConfirmedNewTarget = true

                        s.pendingTarget = nil
                        Log:trace("Target confirmed via debounce")
                    end
                end, CONFIG.CAMERA_MODES.UNIT_FOLLOW.TARGET_ACQUISITION_DELAY, ACQUISITION_DEBOUNCE_ID)
            end
        end
    else
        Scheduler.cancel(ACQUISITION_DEBOUNCE_ID)
        state.pendingTarget = nil
        UnitFollowCombatMode.scheduleAttackStateDisable()
    end

    local isNewTarget = state.justConfirmedNewTarget or false
    state.justConfirmedNewTarget = false -- Consume the flag

    if state.lastTargetPos and state.isAttacking then
        return state.lastTargetPos, state.activeWeaponNum, isNewTarget
    end

    return nil, nil
end

--- Gets camera position for a unit, optionally using weapon position
--- @param unitID number Unit ID
--- @return table camPos Camera position with offsets applied
function UnitFollowCombatMode.getCameraPositionForActiveWeapon(unitID, applyOffsets)
    local x, y, z = Spring.GetUnitPosition(unitID)
    local front, up, right = Spring.GetUnitVectors(unitID)
    local unitPos = { x = x, y = y, z = z }
    local weaponNum = STATE.active.mode.unit_follow.activeWeaponNum
    local attachToWeapon = CONFIG.CAMERA_MODES.UNIT_FOLLOW.ATTACH_TO_WEAPON

    if weaponNum and attachToWeapon then
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
            STATE.active.mode.unit_follow.weaponPos = unitPos
            STATE.active.mode.unit_follow.weaponDir = normalizedDir
            STATE.active.mode.unit_follow.activeWeaponNum = weaponNum
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

    if STATE.active.mode.unit_follow.combatModeEnabled then
        UnitFollowCombatMode.setCombatMode(false)
    else
        UnitFollowCombatMode.setCombatMode(true)
    end

    return true
end

--- Switches between combat and normal modes
--- @param enable boolean Whether to enable combat mode
--- @param unitID number|nil The unit ID to use (defaults to STATE.active.mode.unitID)
--- @return boolean success Whether the switch was successful
function UnitFollowCombatMode.setCombatMode(enable, unitID)
    unitID = unitID or STATE.active.mode.unitID

    if not unitID or not Spring.ValidUnitID(unitID) then
        Log:trace("No valid unit for combat mode")
        return false
    end

    -- Set the combat mode flag
    STATE.active.mode.unit_follow.combatModeEnabled = enable
    local attachToWeapon = CONFIG.CAMERA_MODES.UNIT_FOLLOW.ATTACH_TO_WEAPON

    if enable then
        -- Enable combat mode
        local unitDefID = Spring.GetUnitDefID(unitID)
        local unitDef = UnitDefs[unitDefID]

        -- Find a default weapon to use if not already set
        if not STATE.active.mode.unit_follow.forcedWeaponNumber and unitDef and unitDef.weapons then
            local weaponNumbers = {}
            for weaponNum, weaponData in pairs(unitDef.weapons) do
                if type(weaponNum) == "number" and WeaponDefs[weaponData.weaponDef].range > 100 then
                    table.insert(weaponNumbers, weaponNum)
                end
            end

            if #weaponNumbers > 0 then
                table.sort(weaponNumbers)
                STATE.active.mode.unit_follow.forcedWeaponNumber = weaponNumbers[1]
            end
        end

        -- Check if actively targeting something
        local weaponNum = STATE.active.mode.unit_follow.forcedWeaponNumber
        if weaponNum then
            local targetPos = UnitFollowCombatMode.getWeaponTargetPosition(unitID, weaponNum)

            -- Set attacking state with proper debounce handling
            if targetPos then
                -- Unit is attacking - enable immediately
                STATE.active.mode.unit_follow.isAttacking = true and not STATE.active.mode.unit_follow.freezeAttackState
                Scheduler.cancel(ATTACK_STATE_DEBOUNCE_ID)
            else
                -- Unit is not attacking - start with attacking false
                STATE.active.mode.unit_follow.isAttacking = false
            end

            -- Get weapon position and direction
            local posX, posY, posZ, destX, destY, destZ = Spring.GetUnitWeaponVectors(unitID, weaponNum)
            if posX and destX then
                local originX, originY, originZ = posX, posY, posZ

                if attachToWeapon then
                    STATE.active.mode.unit_follow.weaponPos = { x = posX, y = posY, z = posZ }
                else
                    STATE.active.mode.unit_follow.weaponPos = nil
                    originX, originY, originZ = Spring.GetUnitPosition(unitID)
                    originY = originY
                end

                local dx, dy, dz
                if targetPos then
                    dx = targetPos.x - originX
                    dy = targetPos.y - originY
                    dz = targetPos.z - originZ
                else
                    dx, dy, dz = destX, destY, destZ
                end

                local magnitude = math.sqrt(dx * dx + dy * dy + dz * dz)
                if magnitude > 0 then
                    STATE.active.mode.unit_follow.weaponDir = {
                        dx / magnitude,
                        dy / magnitude,
                        dz / magnitude
                    }
                else
                    STATE.active.mode.unit_follow.weaponDir = { destX, destY, destZ }
                end

                STATE.active.mode.unit_follow.activeWeaponNum = weaponNum
            end
        end
        Log:info("Combat mode enabled")
    else
        -- Disable combat mode - immediately clear attacking state
        Scheduler.cancel(ATTACK_STATE_DEBOUNCE_ID)
        STATE.active.mode.unit_follow.isAttacking = false
        STATE.active.mode.unit_follow.weaponPos = nil
        STATE.active.mode.unit_follow.weaponDir = nil
        Log:info("Combat mode disabled")
    end
    return true
end

return UnitFollowCombatMode
