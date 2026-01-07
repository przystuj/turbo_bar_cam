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
local UnitFollowTargetingSmoothing = ModuleManager.UnitFollowTargetingSmoothing(function(m) UnitFollowTargetingSmoothing = m end)

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
function UnitFollowCamera.toggle()
    local unitID
    if Utils.isTurboBarCamDisabled() then
        return
    end

    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits > 0 then
        unitID = selectedUnits[1]
    else
        Log:debug("No unit selected for unit_follow view")
        disableMode()
        return
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

    if ModeManager.initializeMode('unit_follow', unitID) then
        UnitFollowTargetingSmoothing.configure({
            rotationConstraint = true,
            targetPrediction = true,
            cloudBlendFactor = 0.9,
            maxRotationRate = 0.05,
            rotationDamping = 0.9
        })

        Log:trace("Unit Follow camera attached to unit " .. unitID)
    end
end

--- Updates the unit_follow camera position and orientation
function UnitFollowCamera.update()
    if not UnitFollowUtils.shouldUpdateCamera() then
        CameraDriver.stop()
        return
    end

    local cameraPosition = UnitFollowCamera.getCameraPosition()
    local target, targetType = UnitFollowCamera.getCameraDirection(cameraPosition)

    local camTarget = {
        position = cameraPosition,
        smoothTimePos = UnitFollowUtils.getSmoothingFactor('position'),
        smoothTimeRot = UnitFollowUtils.getSmoothingFactor('rotation')
    }

    if targetType ~= CONSTANTS.TARGET_TYPE.NONE then
        camTarget.lookAt = { type = targetType, data = target }
    else
        camTarget.euler = { rx = target.rx, ry = target.ry }
    end

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
        return UnitFollowUtils.updateFixedPointTarget()
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
                STATE.active.mode.unit_follow.prevFreeCamState = STATE.active.mode.unit_follow.isFreeCameraActive
                STATE.active.mode.unit_follow.prevFixedPoint = STATE.active.mode.unit_follow.fixedPoint
                STATE.active.mode.unit_follow.prevFixedPointActive = STATE.active.mode.unit_follow.isFixedPointActive

                if STATE.active.mode.unit_follow.isFixedPointActive then
                    STATE.active.mode.unit_follow.isFixedPointActive = false
                    STATE.active.mode.unit_follow.fixedPoint = nil
                end

                local camState = Spring.GetCameraState()
                STATE.active.mode.unit_follow.freeCam.targetRx = camState.rx
                STATE.active.mode.unit_follow.freeCam.targetRy = camState.ry
                STATE.active.mode.unit_follow.freeCam.lastMouseX, STATE.active.mode.unit_follow.freeCam.lastMouseY = Spring.GetMouseState()

                if Spring.ValidUnitID(STATE.active.mode.unitID) then
                    STATE.active.mode.unit_follow.freeCam.lastUnitHeading = Spring.GetUnitHeading(STATE.active.mode.unitID, true)
                end
                STATE.active.mode.unit_follow.isFreeCameraActive = true
                Log:trace("Target selection mode activated - select a target to look at")
            end
        elseif prevActiveCmd == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT and STATE.active.mode.unit_follow.inTargetSelectionMode then
            STATE.active.mode.unit_follow.inTargetSelectionMode = false
            if STATE.active.mode.unit_follow.prevFixedPointActive and STATE.active.mode.unit_follow.prevFixedPoint then
                STATE.active.mode.unit_follow.isFixedPointActive = true
                STATE.active.mode.unit_follow.fixedPoint = STATE.active.mode.unit_follow.prevFixedPoint
                Log:trace("Target selection canceled, returning to fixed point view")
            end
            STATE.active.mode.unit_follow.isFreeCameraActive = STATE.active.mode.unit_follow.prevFreeCamState
            if not STATE.active.mode.unit_follow.prevFixedPointActive then
                Log:trace("Target selection canceled, returning to unit view")
            end
        end
    end
    prevActiveCmd = activeCmd
end

function UnitFollowCamera.setFixedLookPoint(cmdParams)
    Log:error("test error")
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
    STATE.active.mode.unit_follow.targetUnitID = nil

    if cmdParams then
        if #cmdParams == 1 then
            local unitID = cmdParams[1]
            if Spring.ValidUnitID(unitID) then
                STATE.active.mode.unit_follow.targetUnitID = unitID
                x, y, z = Spring.GetUnitPosition(unitID)
                Log:trace("Camera will follow current unit but look at unit " .. unitID)
            end
        elseif #cmdParams == 3 then
            x, y, z = cmdParams[1], cmdParams[2], cmdParams[3]
        end
    else
        local _, pos = Spring.TraceScreenRay(Spring.GetMouseState(), true)
        if pos then
            x, y, z = pos[1], pos[2], pos[3]
        end
    end

    if not x or not y or not z then
        Log:trace("Could not find a valid position")
        return false
    end

    local fixedPoint = { x = x, y = y, z = z }
    return UnitFollowUtils.setFixedLookPoint(fixedPoint, STATE.active.mode.unit_follow.targetUnitID)
end

function UnitFollowCamera.clearFixedLookPoint()
    UnitFollowUtils.clearFixedLookPoint()
end

function UnitFollowCamera.toggleFreeCam()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if STATE.active.mode.name ~= 'unit_follow' or not STATE.active.mode.unitID then
        Log:debug("Free camera only works when tracking a unit in unit_follow mode")
        return
    end
    if not STATE.active.mode.unit_follow.isFreeCameraActive and STATE.active.mode.unit_follow.isFixedPointActive then
        UnitFollowUtils.clearFixedLookPoint()
    end
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

function UnitFollowCamera.resetAttackState()
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
    UnitFollowCombatMode.resetAttackState()
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

function UnitFollowCamera.adjustParams(params)
    UnitFollowUtils.adjustParams(params)
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
    if STATE.active.mode.name ~= 'unit_follow' then
        return
    end
    UnitFollowCombatMode.clearAttackingState()
end

return UnitFollowCamera
