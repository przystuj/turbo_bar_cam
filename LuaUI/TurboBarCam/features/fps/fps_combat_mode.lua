---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/standalone/settings_manager.lua").SettingsManager
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons

---@class FPSCombatMode
local FPSCombatMode = {}

function FPSCombatMode.findNearbyProjectile()
    local unitID = STATE.tracking.unitID
    if not unitID then return nil end

    -- Get unit position
    local ux, uy, uz = Spring.GetUnitPosition(unitID)
    if not ux then return nil end

    -- Define small search box around unit
    local boxSize = 200  -- Small box to catch newly fired projectiles

    -- Get projectiles in the small box around unit
    local projectiles = Spring.GetProjectilesInRectangle(
            ux - boxSize, uz - boxSize,
            ux + boxSize, uz + boxSize
    )

    -- Look for projectiles owned by our unit
    for i=1, #projectiles do
        local projectileID = projectiles[i]
        local ownerID = Spring.GetProjectileOwnerID(projectileID)

        if ownerID == unitID then
            return projectileID
        end
    end

    return nil
end

-- Add new projectiles when they're created
function FPSCombatMode.handleProjectileTracking(frameNum)
    if frameNum % 5 ~= 0 then return end

    if not STATE.tracking.mode == "fps" or not STATE.tracking.unitID then
        return
    end

    -- don't override if we are in the middle of tracking
    if not STATE.tracking.fps.lastUnitProjectileID or not STATE.tracking.fps.projectileTrackingEnabled then
        local projectileId = FPSCombatMode.findNearbyProjectile()
        -- dont override with nil
        if STATE.tracking.fps.lastUnitProjectileID and not projectileId then
            return
        end
        STATE.tracking.fps.lastUnitProjectileID = projectileId
        if STATE.tracking.fps.lastUnitProjectileID then
            Log.debug("Projectile found: " .. tostring(STATE.tracking.fps.lastUnitProjectileID))
        end
    end
end

-- Helper function to get the current position of the tracked projectile
function FPSCombatMode.getTrackedProjectilePosition()
    if STATE.tracking.unitID and STATE.tracking.fps.lastUnitProjectileID then
        local px, py, pz = Spring.GetProjectilePosition(STATE.tracking.fps.lastUnitProjectileID)
        if px then
            return px, py, pz
        end
    end
    return nil, nil, nil
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

    local unitDefID = Spring.GetUnitDefID(STATE.tracking.unitID)
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
    Log.debug("Cleared weapon selection.")
end

function FPSCombatMode.clearAttackingState()
    if not STATE.tracking.fps.isAttacking then
        return
    end
    STATE.tracking.fps.isAttacking = false
    STATE.tracking.fps.weaponPos = nil
    STATE.tracking.fps.weaponDir = nil
    STATE.tracking.fps.activeWeaponNum = nil
    STATE.tracking.fps.forcedWeaponNumber = nil
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
            front = { destX, destY, destZ }

            -- Update state for tracking
            STATE.tracking.fps.isAttacking = true
            STATE.tracking.fps.weaponPos = unitPos
            STATE.tracking.fps.weaponDir = front
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

function FPSCombatMode.handleProjectileCamera()
    if not STATE.tracking.fps.projectileTrackingEnabled then
        return false
    end

    local unitID = STATE.tracking.unitID
    local projectileID = STATE.tracking.fps.lastUnitProjectileID
    local px, py, pz, vx, vy, vz

    -- Check if we have an active projectile or if we're at the impact position
    if projectileID then
        -- Get projectile position and velocity
        px, py, pz = Spring.GetProjectilePosition(projectileID)
        vx, vy, vz = Spring.GetProjectileVelocity(projectileID)

        if not px or not vx then
            -- If we can't get the projectile position but we have a stored position,
            -- immediately switch to using the impact position without returning false
            if STATE.tracking.fps.lastProjectilePosition then
                px = STATE.tracking.fps.lastProjectilePosition.x
                py = STATE.tracking.fps.lastProjectilePosition.y
                pz = STATE.tracking.fps.lastProjectilePosition.z

                if STATE.tracking.fps.lastProjectilePosition.vx then
                    vx = STATE.tracking.fps.lastProjectilePosition.vx
                    vy = STATE.tracking.fps.lastProjectilePosition.vy
                    vz = STATE.tracking.fps.lastProjectilePosition.vz
                else
                    vx, vy, vz = 0, -0.5, 0
                end

                -- Clear projectile ID since it doesn't exist anymore
                STATE.tracking.fps.lastUnitProjectileID = nil
                Log.debug("Switching to impact position")
            else
                return false
            end
        else
            -- Store current position for potential impact view
            STATE.tracking.fps.lastProjectilePosition = {
                x = px,
                y = py,
                z = pz,
                vx = nil,
                vy = nil,
                vz = nil
            }

            -- Calculate speed and normalize velocity
            local speed = math.sqrt(vx*vx + vy*vy + vz*vz)
            if speed > 0 then
                STATE.tracking.fps.lastProjectilePosition.vx = vx / speed
                STATE.tracking.fps.lastProjectilePosition.vy = vy / speed
                STATE.tracking.fps.lastProjectilePosition.vz = vz / speed

                vx = vx / speed
                vy = vy / speed
                vz = vz / speed
            end
        end
    else
        -- Use the stored impact position
        if not STATE.tracking.fps.lastProjectilePosition then
            return false
        end

        px = STATE.tracking.fps.lastProjectilePosition.x
        py = STATE.tracking.fps.lastProjectilePosition.y
        pz = STATE.tracking.fps.lastProjectilePosition.z

        if STATE.tracking.fps.lastProjectilePosition.vx then
            vx = STATE.tracking.fps.lastProjectilePosition.vx
            vy = STATE.tracking.fps.lastProjectilePosition.vy
            vz = STATE.tracking.fps.lastProjectilePosition.vz
        else
            vx, vy, vz = 0, -0.5, 0
        end
    end

    -- Position camera behind and above the projectile/impact point
    local distance = 200  -- distance behind projectile
    local height = 100    -- height above projectile path

    local cameraPos = {
        x = px - (vx * distance),
        y = py - (vy * distance) + height,
        z = pz - (vz * distance) + height
    }

    -- Get target position
    local targetPos, weaponNum = FPSCombatMode.getTargetPosition(unitID)

    -- If no target found, use the impact/projectile position as target
    if not targetPos then
        if projectileID then
            -- For active projectile, look ahead along trajectory
            local projectionDistance = 500
            targetPos = {
                x = px + (vx * projectionDistance),
                y = py + (vy * projectionDistance),
                z = pz + (vz * projectionDistance)
            }
        else
            -- For impact view, look at the impact point
            targetPos = {
                x = px,
                y = py,
                z = pz
            }
        end
    end

    -- Calculate camera direction
    local direction = CameraCommons.calculateCameraDirectionToThePoint(cameraPos, targetPos)

    -- Create camera state
    local cameraState = {
        mode = 0,
        name = "projectile",

        -- Position
        px = cameraPos.x,
        py = cameraPos.y,
        pz = cameraPos.z,

        -- Direction
        dx = direction.dx,
        dy = direction.dy,
        dz = direction.dz,

        -- Rotation
        rx = direction.rx,
        ry = direction.ry,
        rz = direction.rz
    }

    -- Apply camera state
    CameraManager.setCameraState(cameraState, 1, "FPSCamera.projectileTracking")

    -- Update tracking state
    STATE.tracking.lastCamDir = { x = direction.dx, y = direction.dy, z = direction.dz }
    STATE.tracking.lastRotation = { rx = direction.rx, ry = direction.ry, rz = direction.rz }
    STATE.tracking.lastCamPos = { x = cameraPos.x, y = cameraPos.y, z = cameraPos.z }

    return true
end

function FPSCombatMode.resetProjectileTracking()
    STATE.tracking.fps.lastUnitProjectileID = nil
    STATE.tracking.fps.projectileTrackingEnabled = false
    STATE.tracking.fps.lastProjectilePosition = nil
    Log.debug("Projectile tracking reset")
end

function FPSCombatMode.saveWeaponSettings(unitId)
    local unitDef = UnitDefs[Spring.GetUnitDefID(unitId)]
    Log.info("Weapon offsets for " .. unitDef.name)
    Log.info(CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_FORWARD)
    Log.info(CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_HEIGHT)
    Log.info(CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_SIDE)
    Log.info(CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_ROTATION)
end

return {
    FPSCombatMode = FPSCombatMode
}