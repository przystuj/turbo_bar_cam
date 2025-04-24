---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type Scheduler
local Scheduler = VFS.Include("LuaUI/TurboBarCam/standalone/scheduler.lua").Scheduler

local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG
local Util = CommonModules.Util
local Log = CommonModules.Log

-- Constants for attack state management
local ATTACK_STATE_DEBOUNCE_ID = "fps_attack_state_debounce"
local ATTACK_STATE_COOLDOWN = 1.5

---@class FPSCombatMode
local FPSCombatMode = {}

--- Gets the name of a unit from its unitDefID
--- @param unitID number The unit ID
--- @return string name The unit name or "Unknown"
function FPSCombatMode.getUnitName(unitID)
    if not Spring.ValidUnitID(unitID) then
        return "Invalid unit"
    end

    local unitDefID = Spring.GetUnitDefID(unitID)
    if not unitDefID then
        return "Unknown unit"
    end

    local unitDef = UnitDefs[unitDefID]
    if not unitDef then
        return "Unknown unit type"
    end

    -- Return the unit's human-readable name
    return unitDef.name or "Unnamed unit"
end

--- Calculates the angle difference between two rotations
--- @param oldRy number Old rotation Y (yaw)
--- @param newRy number New rotation Y (yaw)
--- @return number diff Angle difference in radians
function FPSCombatMode.getRotationDifference(oldRy, newRy)
    if not oldRy or not newRy then
        return 0
    end

    -- Normalize both angles to 0-2π range
    local normalizeAngle = function(angle)
        angle = angle % (2 * math.pi)
        if angle < 0 then
            angle = angle + 2 * math.pi
        end
        return angle
    end

    oldRy = normalizeAngle(oldRy)
    newRy = normalizeAngle(newRy)

    -- Find the shortest angle between the two directions
    local diff = math.abs(newRy - oldRy)
    if diff > math.pi then
        diff = 2 * math.pi - diff
    end

    return diff
end

--- Logs target acquisition with detailed information
--- @param targetPos table The target position
--- @param targetUnitID number|nil The target unit ID if targeting a unit
--- @param targetType number The target type (1 = unit, 2 = ground)
--- @param weaponNum number The weapon number used for targeting
function FPSCombatMode.logTargetAcquisition(targetPos, targetUnitID, targetType, weaponNum)
    if CONFIG.DEBUG.LOG_LEVEL == "INFO" then
        return
    end

    if not targetPos then
        return
    end

    -- Check if this is a new target
    local isNewTarget = true
    local isNewPosition = true

    if STATE.tracking.fps.lastTargetPos then
        -- Check if position is significantly different (more than 5 units away)
        local dx = targetPos.x - STATE.tracking.fps.lastTargetPos.x
        local dy = targetPos.y - STATE.tracking.fps.lastTargetPos.y
        local dz = targetPos.z - STATE.tracking.fps.lastTargetPos.z
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

        if distance < 5 then
            isNewPosition = false
        end

        -- Also check if unit ID is the same (for unit targets)
        if targetUnitID and targetUnitID == STATE.tracking.fps.lastTargetUnitID then
            isNewTarget = false
        end
    end

    -- Only log if it's a new target or position
    if isNewTarget or isNewPosition then
        local targetInfo = ""

        -- Add unit information if it's a unit target
        if targetType == 1 and targetUnitID then
            local unitName = FPSCombatMode.getUnitName(targetUnitID)
            targetInfo = " (Unit: " .. unitName .. ", ID: " .. targetUnitID .. ")"
            STATE.tracking.fps.lastTargetUnitName = unitName
            STATE.tracking.fps.lastTargetUnitID = targetUnitID
        else
            targetInfo = " (Ground target)"
        end

        -- Format position
        local posStr = string.format("x=%.1f, y=%.1f, z=%.1f",
                targetPos.x, targetPos.y, targetPos.z)

        -- Log the target acquisition
        if isNewTarget then
            Log.info("New target acquired" .. targetInfo .. " at " .. posStr ..
                    " using weapon #" .. weaponNum)

            -- Reset target history for new target
            STATE.tracking.fps.initialTargetAcquisitionTime = Spring.GetGameSeconds()
            STATE.tracking.fps.targetRotationHistory = {}
        elseif isNewPosition then
            Log.trace("Target moved to " .. posStr)
        end
    end

    -- Always update the last target position
    STATE.tracking.fps.lastTargetPos = targetPos
    STATE.tracking.fps.lastTargetType = targetType
end

--- Logs camera rotation changes when targeting
--- @param rx number New rotation X (pitch)
--- @param ry number New rotation Y (yaw)
--- @param rz number New rotation Z (roll)
function FPSCombatMode.logRotationChange(rx, ry, rz)
    if CONFIG.DEBUG.LOG_LEVEL == "INFO" then
        return
    end
    -- Skip if we're not in attacking mode
    if not STATE.tracking.fps.isAttacking then
        return
    end

    -- Calculate rotation change from last recorded values
    local rotationDiff = FPSCombatMode.getRotationDifference(
            STATE.tracking.fps.lastRotationRy, ry)

    -- Only log significant changes
    if rotationDiff > STATE.tracking.fps.rotationChangeThreshold then
        -- Format angle in degrees for readability
        local rotationDiffDeg = math.floor(rotationDiff * 180 / math.pi)

        -- Add entry to rotation history
        table.insert(STATE.tracking.fps.targetRotationHistory, {
            time = Spring.GetGameSeconds(),
            diff = rotationDiff,
            rx = rx,
            ry = ry
        })

        -- Check if this is a very large sudden change (potential jump)
        if rotationDiff > 0.5 then
            -- ~28 degrees
            Log.info("LARGE camera rotation: " .. rotationDiffDeg ..
                    "° while tracking " ..
                    (STATE.tracking.fps.lastTargetUnitName or "target"))
        else
            Log.debug("Camera rotation: " .. rotationDiffDeg .. "°")
        end
    end

    -- Update last rotation values
    STATE.tracking.fps.lastRotationRx = rx
    STATE.tracking.fps.lastRotationRy = ry
end

--- Cycles through unit's weapons
function FPSCombatMode.nextWeapon()
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled('fps') then
        return
    end
    if not STATE.tracking.unitID or not Spring.ValidUnitID(STATE.tracking.unitID) then
        Log.debug("No unit selected.")
        return
    end

    local unitID = STATE.tracking.unitID
    local unitDefID = Spring.GetUnitDefID(unitID)
    local unitDef = UnitDefs[unitDefID]

    if not unitDef or not unitDef.weapons then
        Log.info("Unit has no weapons")
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
        Log.info("Unit has no usable weapons")
        return
    end

    local currentWeapon = STATE.tracking.fps.forcedWeaponNumber or weaponNumbers[1]

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
    STATE.tracking.fps.forcedWeaponNumber = weaponNumbers[nextIndex]

    -- Enable combat mode
    FPSCombatMode.setCombatMode(true)

    -- Check if actively targeting something
    local targetPos = FPSCombatMode.getWeaponTargetPosition(unitID, STATE.tracking.fps.forcedWeaponNumber)

    -- Set attacking state with debounce cancellation (if we're newly attacking)
    if targetPos then
        FPSCombatMode.setAttackingState(true)
    else
        FPSCombatMode.setAttackingState(false)
    end

    -- Use a smooth transition
    STATE.tracking.isModeTransitionInProgress = true
    STATE.tracking.transitionStartTime = Spring.GetTimer()

    Log.info("Current weapon: " .. tostring(STATE.tracking.fps.forcedWeaponNumber) .. " (" .. unitDef.wDefs[STATE.tracking.fps.forcedWeaponNumber].name .. ")")
end

--- Clear forced weapon
function FPSCombatMode.clearWeaponSelection()
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled('fps') then
        return
    end

    STATE.tracking.fps.forcedWeaponNumber = nil

    if STATE.tracking.fps.combatModeEnabled then
        -- Update state but keep combat mode enabled
        local unitID = STATE.tracking.unitID
        if unitID and Spring.ValidUnitID(unitID) then
            -- Check if any weapon is targeting something
            local unitDefID = Spring.GetUnitDefID(unitID)
            local unitDef = UnitDefs[unitDefID]

            if unitDef and unitDef.weapons then
                for weaponNum, weaponData in pairs(unitDef.weapons) do
                    if type(weaponNum) == "number" and WeaponDefs[weaponData.weaponDef].range > 100 then
                        local targetPos = FPSCombatMode.getWeaponTargetPosition(unitID, weaponNum)
                        if targetPos then
                            -- Set attacking state with debounce cancellation
                            FPSCombatMode.setAttackingState(true)
                            STATE.tracking.fps.activeWeaponNum = weaponNum
                            return
                        end
                    end
                end
            end
        end

        -- If we reach here, no active targeting was found - start debounce for disabling attack state
        FPSCombatMode.scheduleAttackStateDisable()
    end

    Log.info("Cleared weapon selection.")
end

--- Sets the attacking state with debounce handling
--- @param isAttacking boolean Whether the unit is attacking
function FPSCombatMode.setAttackingState(isAttacking)
    if isAttacking then
        -- If we're now attacking, cancel any scheduled disable
        Scheduler.cancel(ATTACK_STATE_DEBOUNCE_ID)

        -- Only update state if it's changing
        if not STATE.tracking.fps.isAttacking then
            STATE.tracking.fps.isAttacking = true
            Log.trace("Attack state enabled")
        end
    else
        -- If not attacking now, schedule disabling after cooldown
        FPSCombatMode.scheduleAttackStateDisable()
    end
end

--- Schedules disabling of the attack state after a cooldown period
function FPSCombatMode.scheduleAttackStateDisable()
    -- Only schedule if currently in attacking state and not already scheduled
    if STATE.tracking.fps.isAttacking and not Scheduler.isScheduled(ATTACK_STATE_DEBOUNCE_ID) then
        Scheduler.debounce(function()
            -- Only clear if we're still in combat mode
            if STATE.tracking.fps.combatModeEnabled then
                FPSCombatMode.clearAttackingState()
                Log.trace("Attack state disabled after cooldown")
            end
        end, ATTACK_STATE_COOLDOWN, ATTACK_STATE_DEBOUNCE_ID)
    end
end

--- Clear attacking state immediately (no debounce)
function FPSCombatMode.clearAttackingState()
    -- Cancel any pending attack state changes
    Scheduler.cancel(ATTACK_STATE_DEBOUNCE_ID)

    if not STATE.tracking.fps.isAttacking then
        return
    end

    Log.debug("clear attack state")
    STATE.tracking.fps.isAttacking = false
    STATE.tracking.fps.weaponPos = nil
    STATE.tracking.fps.weaponDir = nil
    STATE.tracking.fps.activeWeaponNum = nil
    STATE.tracking.fps.lastTargetPos = nil -- Clear the last target position
    STATE.tracking.fps.lastTargetUnitID = nil -- Clear the last target unit ID
    STATE.tracking.fps.lastTargetUnitName = nil -- Clear the last target unit name
    STATE.tracking.fps.lastTargetType = nil -- Clear the last target type
    STATE.tracking.fps.lastRotationRx = nil -- Clear last rotation values
    STATE.tracking.fps.lastRotationRy = nil
    STATE.tracking.fps.targetRotationHistory = {} -- Clear rotation history
end

--- Extracts target position from a weapon target
---@param unitID number The unit ID
---@param weaponNum number The weapon number
---@return table|nil targetPos The target position or nil if no valid target
function FPSCombatMode.getWeaponTargetPosition(unitID, weaponNum)
    -- Get weapon target
    local targetType, _, target = Spring.GetUnitWeaponTarget(unitID, weaponNum)

    -- Check if weapon has a proper target
    if not (targetType and targetType > 0 and target) then
        return nil
    end

    local targetPos

    -- Unit target
    if targetType == 1 then
        if Spring.ValidUnitID(target) then
            local x, y, z = Spring.GetUnitPosition(target)
            targetPos = { x = x, y = y, z = z }

            -- Add logging for unit target
            FPSCombatMode.logTargetAcquisition(targetPos, target, targetType, weaponNum)
        end
        -- Ground target
    elseif targetType == 2 then
        targetPos = { x = target[1], y = target[2], z = target[3] }

        -- Add logging for ground target
        FPSCombatMode.logTargetAcquisition(targetPos, nil, targetType, weaponNum)
    end

    return targetPos
end

function FPSCombatMode.chooseWeapon(unitID, unitDef)
    local bestTarget, bestWeaponNum

    -- If we have a forced weapon number, only check that specific weapon
    if STATE.tracking.fps.forcedWeaponNumber then
        local weaponNum = STATE.tracking.fps.forcedWeaponNumber

        -- Verify that this weapon exists for the unit
        if unitDef.weapons[weaponNum] then
            -- Get target for forced weapon
            local targetPos = FPSCombatMode.getWeaponTargetPosition(unitID, weaponNum)

            if targetPos then
                return targetPos, weaponNum
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
            local targetPos = FPSCombatMode.getWeaponTargetPosition(unitID, weaponNum)

            if targetPos then
                bestTarget = targetPos
                bestWeaponNum = weaponNum
                -- Found a valid target, no need to check more weapons
                break
            end
        end
    end

    return bestTarget, bestWeaponNum
end

--- Checks if unit is currently attacking a target (even without explicit command)
--- @param unitID number Unit ID to check
--- @return table|nil targetPos Position of the current attack target or nil
--- @return number|nil weaponNum The weapon number that is firing at the target
function FPSCombatMode.getCurrentAttackTarget(unitID)
    if not Spring.ValidUnitID(unitID) then
        -- Schedule disabling attack state when unit is invalid
        FPSCombatMode.scheduleAttackStateDisable()
        return nil, nil
    end

    local unitDefID = Spring.GetUnitDefID(unitID)
    local unitDef = UnitDefs[unitDefID]

    if not unitDef or not unitDef.weapons then
        -- Schedule disabling attack state when unit has no weapons
        FPSCombatMode.scheduleAttackStateDisable()
        return nil, nil
    end

    local targetPos, weaponNum = FPSCombatMode.chooseWeapon(unitID, unitDef)

    -- If no target was found, but we have a last target position and we're in attacking state
    if not targetPos and STATE.tracking.fps.isAttacking and STATE.tracking.fps.lastTargetPos then
        Log.debug("Using last target position for " .. (STATE.tracking.fps.lastTargetUnitName or "unknown target"))
        FPSCombatMode.scheduleAttackStateDisable()
        -- Return the last known target position and the active weapon number
        return STATE.tracking.fps.lastTargetPos, STATE.tracking.fps.activeWeaponNum
    end

    -- If no target was found at all, schedule disabling attack state
    if not targetPos then
        Log.debug("no target pos")
        FPSCombatMode.scheduleAttackStateDisable()
    else
        -- We found a target, cancel any pending disable and ensure attacking state is on
        Scheduler.cancel(ATTACK_STATE_DEBOUNCE_ID)
        STATE.tracking.fps.isAttacking = true

        -- Store the active weapon number for later use
        STATE.tracking.fps.activeWeaponNum = weaponNum

        -- Save the current target position for later use
        STATE.tracking.fps.lastTargetPos = targetPos
    end

    return targetPos, weaponNum
end

--- Checks if unit has a target (from any source) and returns target position if valid
--- @param unitID number Unit ID to check
--- @return table|nil targetPos Position of the target or nil if no valid target
--- @return number|nil weaponNum The weapon number that is firing at the target (if applicable)
function FPSCombatMode.getTargetPosition(unitID)
    if not Spring.ValidUnitID(unitID) then
        return nil, nil
    end

    -- Check for current attack target (autonomous attack)
    local autoTarget, weaponNum = FPSCombatMode.getCurrentAttackTarget(unitID)
    if autoTarget then
        return autoTarget, weaponNum
    end

    return nil, nil
end

--- Gets camera position for a unit, optionally using weapon position
--- @param unitID number Unit ID
--- @return table camPos Camera position with offsets applied
function FPSCombatMode.getCameraPositionForActiveWeapon(unitID, applyOffsets)
    local x, y, z = Spring.GetUnitPosition(unitID)
    local front, up, right = Spring.GetUnitVectors(unitID)
    local unitPos = { x = x, y = y, z = z }
    local weaponNum = STATE.tracking.fps.activeWeaponNum

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
            STATE.tracking.fps.weaponPos = unitPos
            STATE.tracking.fps.weaponDir = normalizedDir
            STATE.tracking.fps.activeWeaponNum = weaponNum
        end
    end

    -- Apply offsets to the position (applyOffsets will choose the right offset type)
    return applyOffsets(unitPos, front, up, right)
end

--- Toggles combat mode on/off
--- @return boolean success Whether the toggle was successful
function FPSCombatMode.toggleCombatMode()
    if Util.isTurboBarCamDisabled() then
        return false
    end
    if Util.isModeDisabled('fps') then
        return false
    end

    if STATE.tracking.fps.combatModeEnabled then
        FPSCombatMode.setCombatMode(false)
    else
        FPSCombatMode.setCombatMode(true)
    end

    return true
end

--- Switches between combat and normal modes
--- @param enable boolean Whether to enable combat mode
--- @param unitID number|nil The unit ID to use (defaults to STATE.tracking.unitID)
--- @return boolean success Whether the switch was successful
function FPSCombatMode.setCombatMode(enable, unitID)
    unitID = unitID or STATE.tracking.unitID

    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.trace("No valid unit for combat mode")
        return false
    end

    -- Set the combat mode flag
    STATE.tracking.fps.combatModeEnabled = enable

    if enable then
        -- Enable combat mode
        local unitDefID = Spring.GetUnitDefID(unitID)
        local unitDef = UnitDefs[unitDefID]

        -- Find a default weapon to use if not already set
        if not STATE.tracking.fps.forcedWeaponNumber and unitDef and unitDef.weapons then
            local weaponNumbers = {}
            for weaponNum, weaponData in pairs(unitDef.weapons) do
                if type(weaponNum) == "number" and WeaponDefs[weaponData.weaponDef].range > 100 then
                    table.insert(weaponNumbers, weaponNum)
                end
            end

            if #weaponNumbers > 0 then
                table.sort(weaponNumbers)
                STATE.tracking.fps.forcedWeaponNumber = weaponNumbers[1]
            end
        end

        -- Check if actively targeting something
        local weaponNum = STATE.tracking.fps.forcedWeaponNumber
        if weaponNum then
            local targetPos = FPSCombatMode.getWeaponTargetPosition(unitID, weaponNum)

            -- Set attacking state with proper debounce handling
            if targetPos then
                -- Unit is attacking - enable immediately
                STATE.tracking.fps.isAttacking = true
                Scheduler.cancel(ATTACK_STATE_DEBOUNCE_ID)
            else
                -- Unit is not attacking - start with attacking false
                Log.debug("unit not attacking")
                STATE.tracking.fps.isAttacking = false
            end

            -- Get weapon position and direction
            local posX, posY, posZ, destX, destY, destZ = Spring.GetUnitWeaponVectors(unitID, weaponNum)
            if posX and destX then
                -- Use weapon position
                STATE.tracking.fps.weaponPos = { x = posX, y = posY, z = posZ }

                -- Create normalized vector
                local magnitude = math.sqrt(destX * destX + destY * destY + destZ * destZ)
                if magnitude > 0 then
                    STATE.tracking.fps.weaponDir = {
                        destX / magnitude,
                        destY / magnitude,
                        destZ / magnitude
                    }
                else
                    STATE.tracking.fps.weaponDir = { destX, destY, destZ }
                end

                STATE.tracking.fps.activeWeaponNum = weaponNum
            end
        end

        Log.info("Combat mode enabled")
    else
        -- Disable combat mode - immediately clear attacking state
        Scheduler.cancel(ATTACK_STATE_DEBOUNCE_ID)
        STATE.tracking.fps.isAttacking = false
        STATE.tracking.fps.weaponPos = nil
        STATE.tracking.fps.weaponDir = nil

        Log.info("Combat mode disabled")
    end

    -- Trigger a transition for smooth camera movement
    STATE.tracking.isModeTransitionInProgress = true
    STATE.tracking.transitionStartTime = Spring.GetTimer()
    return true
end

return {
    FPSCombatMode = FPSCombatMode
}