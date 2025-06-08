---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local WorldUtils = ModuleManager.WorldUtils(function(m) WorldUtils = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local TransitionManager = ModuleManager.TransitionManager(function(m) TransitionManager = m end)
local CameraTracker = ModuleManager.CameraTracker(function(m) CameraTracker = m end)
local UnitFollowFreeCam = ModuleManager.UnitFollowFreeCam(function(m) UnitFollowFreeCam = m end)
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

local UNIT_FOLLOW_ENTRY_TRANSITION_ID = "UnitFollowCamera.EntryTransition"

--- Internal: Starts a smooth transition into unit_follow mode by scaling steady-state smoothing factors.
---@param unitID number The ID of the unit to focus on.
local function startEntryTransition(unitID)
    -- init camera state when starting transition
    STATE.mode.unit_follow.isModeInitialized = true
    if not Spring.ValidUnitID(unitID) then
        Log:warn("[UnitFollowCamera] Invalid unitID for startEntryTransition: " .. unitID)
        return
    end

    TransitionManager.force({
        id = UNIT_FOLLOW_ENTRY_TRANSITION_ID,
        duration = CONFIG.CAMERA_MODES.UNIT_FOLLOW.INITIAL_TRANSITION_DURATION,
        easingFn = CameraCommons.easeOut,
        respectGameSpeed = false,
        onUpdate = function(raw_progress, eased_progress, dt_effective)
            if not Spring.ValidUnitID(unitID) then
                TransitionManager.cancel(UNIT_FOLLOW_ENTRY_TRANSITION_ID)
                ModeManager.disableMode()
                return
            end

            local cameraPosition = UnitFollowCamera.getCameraPosition(eased_progress)
            local directionState = UnitFollowCamera.getCameraDirection(cameraPosition, eased_progress)

            if not directionState or not cameraPosition then
                TransitionManager.cancel(UNIT_FOLLOW_ENTRY_TRANSITION_ID)
                ModeManager.disableMode()
                return
            end

            local camStatePatch = UnitFollowUtils.createCameraState(cameraPosition, directionState)
            CameraTracker.updateLastKnownCameraState(camStatePatch)
            Spring.SetCameraState(camStatePatch, 0)
        end,
        onComplete = function()
            -- NO-OP
        end
    })
end

--- Toggles Unit Follow camera attached to a unit
---@param unitID number|nil The unit to track. If nil, uses the first selected unit.
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
            return
        end
    end

    if not Spring.ValidUnitID(unitID) then
        Log:trace("Invalid unit ID for unit_follow view: " .. tostring(unitID))
        return
    end

    if STATE.mode.name == 'unit_follow' and STATE.mode.unitID == unitID and not STATE.mode.optionalTargetCameraStateForModeEntry then
        ModeManager.disableMode()
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            Spring.SelectUnitArray(selectedUnits)
        end
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
        return
    end

    if STATE.mode.unit_follow and not STATE.mode.unit_follow.isModeInitialized then
        startEntryTransition(STATE.mode.unitID)
    end

    if TransitionManager.isTransitioning(UNIT_FOLLOW_ENTRY_TRANSITION_ID) then
        return
    end

    local cameraPosition = UnitFollowCamera.getCameraPosition()
    local directionState = UnitFollowCamera.getCameraDirection(cameraPosition)

    if directionState then
        local camStatePatch = UnitFollowUtils.createCameraState(cameraPosition, directionState)
        Spring.SetCameraState(camStatePatch, 0)
        CameraTracker.updateLastKnownCameraState(camStatePatch)
    end
end

function UnitFollowCamera.getCameraPosition(additionalFactor)
    additionalFactor = additionalFactor or 1
    local unitPos, front, up, right = WorldUtils.getUnitVectors(STATE.mode.unitID)
    local camPos = UnitFollowUtils.applyOffsets(unitPos, front, up, right)

    local posFactor = UnitFollowUtils.getSmoothingFactor('position', additionalFactor)

    local center = { x = unitPos.x, y = unitPos.y, z = unitPos.z }
    local smoothedPos

    if CameraCommons.shouldUseSphericalInterpolation(STATE.mode.lastCamPos, camPos, center) then
        smoothedPos = CameraCommons.sphericalInterpolate(center, STATE.mode.lastCamPos, camPos, posFactor, true)
    else
        smoothedPos = {
            x = CameraCommons.lerp(STATE.mode.lastCamPos.x, camPos.x, posFactor),
            y = CameraCommons.lerp(STATE.mode.lastCamPos.y, camPos.y, posFactor),
            z = CameraCommons.lerp(STATE.mode.lastCamPos.z, camPos.z, posFactor)
        }
    end
    return smoothedPos
end

function UnitFollowCamera.getCameraDirection(cameraPosition, additionalFactor)
    local rotFactor = UnitFollowUtils.getSmoothingFactor('rotation', additionalFactor)

    local directionState
    if STATE.mode.unit_follow.isFixedPointActive then
        UnitFollowUtils.updateFixedPointTarget()
        directionState = CameraCommons.focusOnPoint(
                cameraPosition,
                STATE.mode.unit_follow.fixedPoint,
                rotFactor,
                rotFactor
        )
    elseif STATE.mode.unit_follow.isFreeCameraActive then
        local rotation = UnitFollowFreeCam.updateMouseRotation(rotFactor)
        UnitFollowFreeCam.updateUnitHeadingTracking(STATE.mode.unitID)
        directionState = UnitFollowFreeCam.createCameraState(
                cameraPosition,
                rotation,
                STATE.mode.lastCamDir,
                STATE.mode.lastRotation,
                rotFactor
        )
    else
        directionState = UnitFollowUtils.handleNormalFollowMode(STATE.mode.unitID, rotFactor)
    end

    return directionState
end

function UnitFollowCamera.checkFixedPointCommandActivation()
    if Utils.isTurboBarCamDisabled() then
        return
    end

    local _, activeCmd = Spring.GetActiveCommand()

    if activeCmd ~= prevActiveCmd then
        if activeCmd == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT then
            if STATE.mode.name == 'unit_follow' and STATE.mode.unitID then
                STATE.mode.unit_follow.inTargetSelectionMode = true
                STATE.mode.unit_follow.prevFreeCamState = STATE.mode.unit_follow.isFreeCameraActive
                STATE.mode.unit_follow.prevMode = STATE.mode.name
                STATE.mode.unit_follow.prevFixedPoint = STATE.mode.unit_follow.fixedPoint
                STATE.mode.unit_follow.prevFixedPointActive = STATE.mode.unit_follow.isFixedPointActive

                if STATE.mode.unit_follow.isFixedPointActive then
                    STATE.mode.unit_follow.isFixedPointActive = false
                    STATE.mode.unit_follow.fixedPoint = nil
                end

                local camState = Spring.GetCameraState()
                STATE.mode.unit_follow.freeCam.targetRx = camState.rx
                STATE.mode.unit_follow.freeCam.targetRy = camState.ry
                STATE.mode.unit_follow.freeCam.lastMouseX, STATE.mode.unit_follow.freeCam.lastMouseY = Spring.GetMouseState()

                if Spring.ValidUnitID(STATE.mode.unitID) then
                    STATE.mode.unit_follow.freeCam.lastUnitHeading = Spring.GetUnitHeading(STATE.mode.unitID, true)
                end
                STATE.mode.unit_follow.isFreeCameraActive = true
                Log:trace("Target selection mode activated - select a target to look at")
            end
        elseif prevActiveCmd == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT and STATE.mode.unit_follow.inTargetSelectionMode then
            STATE.mode.unit_follow.inTargetSelectionMode = false
            if STATE.mode.unit_follow.prevFixedPointActive and STATE.mode.unit_follow.prevFixedPoint then
                STATE.mode.unit_follow.isFixedPointActive = true
                STATE.mode.unit_follow.fixedPoint = STATE.mode.unit_follow.prevFixedPoint
                Log:trace("Target selection canceled, returning to fixed point view")
            end
            STATE.mode.unit_follow.isFreeCameraActive = STATE.mode.unit_follow.prevFreeCamState
            if not STATE.mode.unit_follow.prevFixedPointActive then
                Log:trace("Target selection canceled, returning to unit view")
            end
        end
    end
    prevActiveCmd = activeCmd
end

function UnitFollowCamera.setFixedLookPoint(cmdParams)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled("unit_follow") then
        return
    end
    if not STATE.mode.unitID then
        Log:debug("No unit being tracked for fixed point camera")
        return false
    end

    local x, y, z
    STATE.mode.unit_follow.targetUnitID = nil

    if cmdParams then
        if #cmdParams == 1 then
            local unitID = cmdParams[1]
            if Spring.ValidUnitID(unitID) then
                STATE.mode.unit_follow.targetUnitID = unitID
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
    return UnitFollowUtils.setFixedLookPoint(fixedPoint, STATE.mode.unit_follow.targetUnitID)
end

function UnitFollowCamera.clearFixedLookPoint()
    UnitFollowUtils.clearFixedLookPoint()
end

function UnitFollowCamera.toggleFreeCam()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if STATE.mode.name ~= 'unit_follow' or not STATE.mode.unitID then
        Log:debug("Free camera only works when tracking a unit in unit_follow mode")
        return
    end
    UnitFollowFreeCam.toggle()
    if not STATE.mode.unit_follow.isFreeCameraActive and STATE.mode.unit_follow.isFixedPointActive then
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
    if not STATE.mode.unitID or not Spring.ValidUnitID(STATE.mode.unitID) then
        Log:debug("No unit selected.")
        return
    end
    UnitFollowCombatMode.nextWeapon()
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
    UnitFollowCombatMode.clearAttackingState()
end

return UnitFollowCamera