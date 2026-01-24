---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CONSTANTS = ModuleManager.CONSTANTS(function(m) CONSTANTS = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "UnitFollowCamera")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local WorldUtils = ModuleManager.WorldUtils(function(m) WorldUtils = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local CameraDriver = ModuleManager.CameraDriver(function(m) CameraDriver = m end)
local UnitFollowUtils = ModuleManager.UnitFollowUtils(function(m) UnitFollowUtils = m end)
local UnitFollowCombatMode = ModuleManager.UnitFollowCombatMode(function(m) UnitFollowCombatMode = m end)
local UnitFollowTargeting = ModuleManager.UnitFollowTargeting(function(m) UnitFollowTargeting = m end)
local ProjectileTracker = ModuleManager.ProjectileTracker(function(m) ProjectileTracker = m end)

local prevActiveCmd

---@class UnitFollowCamera
local UnitFollowCamera = {}

UnitFollowCamera.COMMAND_DEFINITION = {
    id = CONFIG.COMMANDS.SET_FIXED_LOOK_POINT,
    type = CMDTYPE.ICON_UNIT_OR_MAP,
    name = 'Set Fixed Look Point',
    tooltip = 'Click on a location to focus camera on while following unit',
    cursor = 'settarget',
    action = 'turbobarcam_unit_follow_set_fixed_look_point',
}

local function disableMode()
    ModeManager.disableAndStopDriver()
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits > 0 then
        Spring.SelectUnitArray(selectedUnits)
    end
end

--- Toggles Unit Follow camera attached to a unit
function UnitFollowCamera.toggle(unitID)
    if Utils.isTurboBarCamDisabled() then
        return
    end

    if not unitID then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            unitID = selectedUnits[1]
        else
            Log:debug("No unit selected for unit_follow view")
            disableMode()
            return
        end
    end

    if not Spring.ValidUnitID(unitID) then
        Log:trace("Invalid unit ID for unit_follow view: " .. tostring(unitID))
        disableMode()
        return
    end

    if STATE.active.mode.name == 'unit_follow' and STATE.active.mode.unitID == unitID and not STATE.active.mode.optionalTargetCameraStateForModeEntry then
        disableMode()
        return
    end

    ModeManager.initializeMode('unit_follow', unitID, CONSTANTS.TARGET_TYPE.UNIT)
end

--- Updates the unit_follow camera position and orientation
function UnitFollowCamera.update()
    if not UnitFollowUtils.shouldUpdateCamera() then
        CameraDriver.stop()
        return
    end

    local cameraPosition = UnitFollowCamera.getCameraPosition()
    local target, targetType = UnitFollowCamera.getCameraDirection(cameraPosition)

    local cameraDriverJob = CameraDriver.prepare(targetType, target)
    cameraDriverJob.position = cameraPosition
    cameraDriverJob.positionSmoothing = UnitFollowUtils.getSmoothingFactor('position')
    cameraDriverJob.rotationSmoothing = UnitFollowUtils.getSmoothingFactor('rotation')
    cameraDriverJob.run()
end

function UnitFollowCamera.getCameraPosition()
    local unitPos, front, up, right = WorldUtils.getUnitVectors(STATE.active.mode.unitID)
    local camPos = UnitFollowUtils.applyOffsets(unitPos, front, up, right)
    return camPos
end

function UnitFollowCamera.getCameraDirection()
    if STATE.active.mode.unit_follow.isFixedPointActive then
        return STATE.active.mode.unit_follow.fixedTarget, STATE.active.mode.unit_follow.fixedTargetType
    else
        return UnitFollowUtils.handleNormalFollowMode(STATE.active.mode.unitID)
    end
end

function UnitFollowCamera.checkFixedPointCommandActivation()
    if Utils.isTurboBarCamDisabled() then
        return
    end

    local _, activeCmd = Spring.GetActiveCommand()

    if activeCmd ~= prevActiveCmd then
        if activeCmd == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT then
            if STATE.active.mode.name == 'unit_follow' and STATE.active.mode.unitID then
                STATE.active.mode.unit_follow.inTargetSelectionMode = true
                STATE.active.mode.unit_follow.prevFixedTarget = STATE.active.mode.unit_follow.fixedTarget
                STATE.active.mode.unit_follow.prevFixedPointActive = STATE.active.mode.unit_follow.isFixedPointActive

                if STATE.active.mode.unit_follow.isFixedPointActive then
                    STATE.active.mode.unit_follow.isFixedPointActive = false
                end
            end
        elseif prevActiveCmd == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT and STATE.active.mode.unit_follow.inTargetSelectionMode then
            STATE.active.mode.unit_follow.inTargetSelectionMode = false
            if STATE.active.mode.unit_follow.prevFixedPointActive and STATE.active.mode.unit_follow.prevFixedTarget then
                STATE.active.mode.unit_follow.isFixedPointActive = true
                STATE.active.mode.unit_follow.fixedTarget = STATE.active.mode.unit_follow.prevFixedTarget
            end
        end
    end
    prevActiveCmd = activeCmd
end

function UnitFollowCamera.setFixedLookPoint(targetType, cmdParams)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled("unit_follow") then
        return
    end
    if not STATE.active.mode.unitID then
        Log:debug("No unit being tracked for fixed point camera")
        return false
    end

    local x, y, z
    STATE.active.mode.unit_follow.fixedTarget = nil
    STATE.active.mode.unit_follow.fixedTargetType = targetType

    if targetType == CONSTANTS.TARGET_TYPE.UNIT then
        local unitID = cmdParams[1]
        if Spring.ValidUnitID(unitID) then
            STATE.active.mode.unit_follow.fixedTarget = unitID
            x, y, z = Spring.GetUnitPosition(unitID)
        end
    elseif targetType == CONSTANTS.TARGET_TYPE.PROJECTILE then

        local projectileID = cmdParams[1]
        local projectile = ProjectileTracker.getProjectileByID(projectileID)

        if projectile then
            x, y, z = projectile.position.x, projectile.position.y, projectile.position.z
            STATE.active.mode.unit_follow.fixedTarget = projectileID
        end
    elseif targetType == CONSTANTS.TARGET_TYPE.POINT then
        x, y, z = cmdParams[1], cmdParams[2], cmdParams[3]
        STATE.active.mode.unit_follow.fixedTarget = { x = x, y = y, z = z }
    end

    if not x or not y or not z then
        return false
    end

    STATE.active.mode.unit_follow.isFixedPointActive = true
    STATE.active.mode.unit_follow.inTargetSelectionMode = false
    STATE.active.mode.unit_follow.prevFixedTarget = nil
end

function UnitFollowCamera.clearFixedLookPoint()
    UnitFollowUtils.clearFixedLookPoint()
end

function UnitFollowCamera.nextWeapon()
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
    UnitFollowCombatMode.nextWeapon()
end

function UnitFollowCamera.resetAttackState(delay)
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
    UnitFollowCombatMode.resetAttackState(delay)
end

function UnitFollowCamera.clearWeaponSelection()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled('unit_follow') then
        return
    end
    UnitFollowCombatMode.clearWeaponSelection()
end

function UnitFollowCamera.adjustParams(params, isTemporary)
    UnitFollowUtils.adjustParams(params, isTemporary)
end

function UnitFollowCamera.toggleCombatMode()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled('unit_follow') then
        return
    end
    UnitFollowCombatMode.toggleCombatMode()
end

function UnitFollowCamera.handleSelectNewUnit()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled('unit_follow') then
        return
    end
    UnitFollowCombatMode.clearAttackingState()
end

function UnitFollowCamera.setFixedLookTarget(args)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled('unit_follow') then
        return
    end
    local params = { args[2], args[3], args[4] }
    Log:debug("Looking at", args[1], args[2], args[3], args[4])
    UnitFollowCamera.setFixedLookPoint(args[1], params)
end

return UnitFollowCamera
