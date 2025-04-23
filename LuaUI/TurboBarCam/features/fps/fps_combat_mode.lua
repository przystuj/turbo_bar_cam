---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/standalone/settings_manager.lua").SettingsManager

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log

---@class FPSCombatMode
local FPSCombatMode = {}

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

    -- Enable combat mode with the new weapon
    FPSCombatMode.setCombatMode(true)

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
        FPSCombatMode.setCombatMode(true)
    end

    Log.debug("Cleared weapon selection. Combat mode remains " ..
            (STATE.tracking.fps.combatModeEnabled and "enabled" or "disabled") .. ".")
end

function FPSCombatMode.clearAttackingState()
    if not STATE.tracking.fps.isAttacking then
        return
    end
    STATE.tracking.fps.isAttacking = false
    STATE.tracking.fps.weaponPos = nil
    STATE.tracking.fps.weaponDir = nil
    STATE.tracking.fps.activeWeaponNum = nil
    SettingsManager.loadModeSettings("fps", STATE.tracking.unitID)
end

--- Gets appropriate offsets based on whether the unit is attacking and which weapon is active
---@return table offsets The offsets to apply
function FPSCombatMode.getAppropriateOffsets()
    if STATE.tracking.fps.isAttacking then
        return {
            HEIGHT = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_HEIGHT,
            FORWARD = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_FORWARD,
            SIDE = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_SIDE,
            ROTATION = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_ROTATION
        }
    else
        return {
            HEIGHT = CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT,
            FORWARD = CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD,
            SIDE = CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE,
            ROTATION = CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION
        }
    end
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
        end
        -- Ground target
    elseif targetType == 2 then
        targetPos = { x = target[1], y = target[2], z = target[3] }
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
    -- Skip target detection if combat mode is not enabled
    if not STATE.tracking.fps.combatModeEnabled then
        -- Reset attacking state when not in combat mode
        FPSCombatMode.clearAttackingState()
        return nil, nil
    end

    if not Spring.ValidUnitID(unitID) then
        -- Reset attacking state when unit is invalid
        FPSCombatMode.clearAttackingState()
        return nil, nil
    end

    local unitDefID = Spring.GetUnitDefID(unitID)
    local unitDef = UnitDefs[unitDefID]

    if not unitDef or not unitDef.weapons then
        -- Reset attacking state when unit has no weapons
        FPSCombatMode.clearAttackingState()
        return nil, nil
    end

    local targetPos, weaponNum = FPSCombatMode.chooseWeapon(unitID, unitDef)

    -- If no target was found, reset attacking state
    if not targetPos then
        FPSCombatMode.clearAttackingState()
    else
        -- Store the active weapon number for later use
        STATE.tracking.fps.activeWeaponNum = weaponNum
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
            local magnitude = math.sqrt(destX*destX + destY*destY + destZ*destZ)
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
            STATE.tracking.fps.isAttacking = true
            STATE.tracking.fps.weaponPos = unitPos
            STATE.tracking.fps.weaponDir = normalizedDir
            STATE.tracking.fps.activeWeaponNum = weaponNum
        else
            -- If weapon vectors couldn't be retrieved, reset state
            STATE.tracking.fps.isAttacking = false
            STATE.tracking.fps.weaponPos = nil
            STATE.tracking.fps.weaponDir = nil
            STATE.tracking.fps.activeWeaponNum = nil
        end
    else
        -- No weapon specified, reset state
        STATE.tracking.fps.isAttacking = false
        STATE.tracking.fps.weaponPos = nil
        STATE.tracking.fps.weaponDir = nil
        STATE.tracking.fps.activeWeaponNum = nil
    end

    -- Apply offsets to the position
    return applyOffsets(unitPos, front, up, right)
end

function FPSCombatMode.saveWeaponSettings(unitId)
    local unitDef = UnitDefs[Spring.GetUnitDefID(unitId)]
    Log.info("Weapon offsets for " .. unitDef.name)
    Log.info(CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_FORWARD)
    Log.info(CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_HEIGHT)
    Log.info(CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_SIDE)
    Log.info(CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_ROTATION)
end

--- Switches between combat and normal modes
--- @param enable boolean Whether to enable combat mode
--- @param unitID number|nil The unit ID to use (defaults to STATE.tracking.unitID)
--- @return boolean success Whether the switch was successful
function FPSCombatMode.setCombatMode(enable, unitID)
    unitID = unitID or STATE.tracking.unitID

    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.debug("No valid unit for combat mode")
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

        -- Set "isAttacking" to true so the camera uses weapon offsets
        STATE.tracking.fps.isAttacking = true

        -- Get weapon position and direction if available
        if STATE.tracking.fps.forcedWeaponNumber then
            local weaponNum = STATE.tracking.fps.forcedWeaponNumber
            local posX, posY, posZ, destX, destY, destZ = Spring.GetUnitWeaponVectors(unitID, weaponNum)

            if posX and destX then
                -- Use weapon position
                STATE.tracking.fps.weaponPos = { x = posX, y = posY, z = posZ }

                -- Create normalized weapon direction vector
                local magnitude = math.sqrt(destX*destX + destY*destY + destZ*destZ)
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

        Log.info("Combat mode enabled - using weapon view")
    else
        -- Disable combat mode
        STATE.tracking.fps.isAttacking = false
        STATE.tracking.fps.weaponPos = nil
        STATE.tracking.fps.weaponDir = nil
        -- We don't clear activeWeaponNum or forcedWeaponNumber to remember last used weapon

        Log.info("Combat mode disabled - using unit view")
    end

    -- Trigger a transition for smooth camera movement
    STATE.tracking.isModeTransitionInProgress = true
    STATE.tracking.transitionStartTime = Spring.GetTimer()

    return true
end

return {
    FPSCombatMode = FPSCombatMode
}