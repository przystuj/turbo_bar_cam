---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type TransitionManager
local TransitionManager = VFS.Include("LuaUI/TurboBarCam/core/transition_manager.lua")
---@type CameraTracker
local CameraTracker = VFS.Include("LuaUI/TurboBarCam/standalone/camera_tracker.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log

---@type FreeCam
local FreeCam = VFS.Include("LuaUI/TurboBarCam/features/fps/fps_free_camera.lua").FreeCam
---@type FPSCameraUtils
local FPSCameraUtils = VFS.Include("LuaUI/TurboBarCam/features/fps/fps_utils.lua").FPSCameraUtils
---@type FPSCombatMode
local FPSCombatMode = VFS.Include("LuaUI/TurboBarCam/features/fps/fps_combat_mode.lua").FPSCombatMode
---@type FPSTargetingSmoothing
local FPSTargetingSmoothing = VFS.Include("LuaUI/TurboBarCam/features/fps/fps_targeting_smoothing.lua").FPSTargetingSmoothing

local CameraCommons = CommonModules.CameraCommons
local ModeManager = CommonModules.ModeManager

local prevActiveCmd

---@class FPSCamera
local FPSCamera = {}

FPSCamera.COMMAND_DEFINITION = {
    id = CONFIG.COMMANDS.SET_FIXED_LOOK_POINT,
    type = CMDTYPE.ICON_UNIT_OR_MAP,
    name = 'Set Fixed Look Point',
    tooltip = 'Click on a location to focus camera on while following unit',
    cursor = 'settarget',
    action = 'turbobarcam_fps_set_fixed_look_point',
}

local FPS_ENTRY_TRANSITION_ID = "FPSCamera.EntryTransition"

--- Internal: Starts a smooth transition into FPS mode by scaling steady-state smoothing factors.
---@param unitID number The ID of the unit to focus on.
local function startFPSEntryTransition(unitID)
    -- init camera state when starting transition
    STATE.mode.fps.isModeInitialized = true
    if not Spring.ValidUnitID(unitID) then
        Log.warn("[FPSCamera] Invalid unitID for startFPSEntryTransition: " .. unitID)
        return
    end

    TransitionManager.force({
        id = FPS_ENTRY_TRANSITION_ID,
        duration = CONFIG.CAMERA_MODES.FPS.INITIAL_TRANSITION_DURATION,
        easingFn = CameraCommons.easeOut,
        respectGameSpeed = false,
        onUpdate = function(raw_progress, eased_progress, dt_effective)
            if not Spring.ValidUnitID(unitID) then
                TransitionManager.cancel(FPS_ENTRY_TRANSITION_ID)
                ModeManager.disableMode()
                return
            end

            local cameraPosition = FPSCamera.getCameraPosition(eased_progress)
            local directionState = FPSCamera.getCameraDirection(cameraPosition, eased_progress)

            if not directionState or not cameraPosition then
                TransitionManager.cancel(FPS_ENTRY_TRANSITION_ID)
                ModeManager.disableMode()
                return
            end

            local camStatePatch = FPSCameraUtils.createCameraState(cameraPosition, directionState)
            CameraTracker.updateLastKnownCameraState(camStatePatch)
            Spring.SetCameraState(camStatePatch, 0)
        end,
        onComplete = function()
            -- NO-OP
        end
    })
end

--- Toggles FPS camera attached to a unit
---@param unitID number|nil The unit to track. If nil, uses the first selected unit.
---@param targetSubmode string|nil The target submode for entry ("PEACE" or "COMBAT"). Defaults to "PEACE".
function FPSCamera.toggle(unitID, targetSubmode)
    if Util.isTurboBarCamDisabled() then
        return
    end

    targetSubmode = targetSubmode or "PEACE"

    if not unitID then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            unitID = selectedUnits[1]
        else
            Log.debug("No unit selected for FPS view")
            return
        end
    end

    if not Spring.ValidUnitID(unitID) then
        Log.trace("Invalid unit ID for FPS view: " .. tostring(unitID))
        return
    end

    if STATE.mode.name == 'fps' and STATE.mode.unitID == unitID and not STATE.mode.optionalTargetCameraStateForModeEntry then
        ModeManager.disableMode()
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            Spring.SelectUnitArray(selectedUnits)
        end
        return
    end

    if ModeManager.initializeMode('fps', unitID) then
        FPSTargetingSmoothing.configure({
            rotationConstraint = true,
            targetPrediction = true,
            cloudBlendFactor = 0.9,
            maxRotationRate = 0.05,
            rotationDamping = 0.9
        })

        Log.trace("FPS camera attached to unit " .. unitID .. " with target entry submode: " .. targetSubmode)
    end
end

--- Updates the FPS camera position and orientation
function FPSCamera.update()
    if not FPSCameraUtils.shouldUpdateFPSCamera() then
        return
    end

    if STATE.mode.fps and not STATE.mode.fps.isModeInitialized then
        startFPSEntryTransition(STATE.mode.unitID)
    end

    if TransitionManager.isTransitioning(FPS_ENTRY_TRANSITION_ID) then
        return
    end

    local cameraPosition = FPSCamera.getCameraPosition()
    local directionState = FPSCamera.getCameraDirection(cameraPosition)

    if directionState then
        local camStatePatch = FPSCameraUtils.createCameraState(cameraPosition, directionState)
        Spring.SetCameraState(camStatePatch, 0)
        CameraTracker.updateLastKnownCameraState(camStatePatch)
    end
end

function FPSCamera.getCameraPosition(additionalFactor)
    additionalFactor = additionalFactor or 1
    local unitPos, front, up, right = Util.getUnitVectors(STATE.mode.unitID)
    local camPos = FPSCameraUtils.applyFPSOffsets(unitPos, front, up, right)

    local posFactor = FPSCameraUtils.getSmoothingFactor('position', additionalFactor)

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

function FPSCamera.getCameraDirection(cameraPosition, additionalFactor)
    local rotFactor = FPSCameraUtils.getSmoothingFactor('rotation', additionalFactor)

    local directionState
    if STATE.mode.fps.isFixedPointActive then
        FPSCameraUtils.updateFixedPointTarget()
        directionState = CameraCommons.focusOnPoint(
                cameraPosition,
                STATE.mode.fps.fixedPoint,
                rotFactor,
                rotFactor
        )
    elseif STATE.mode.fps.isFreeCameraActive then
        local rotation = FreeCam.updateMouseRotation(rotFactor)
        FreeCam.updateUnitHeadingTracking(STATE.mode.unitID)
        directionState = FreeCam.createCameraState(
                cameraPosition,
                rotation,
                STATE.mode.lastCamDir,
                STATE.mode.lastRotation,
                rotFactor
        )
    else
        directionState = FPSCameraUtils.handleNormalFPSMode(STATE.mode.unitID, rotFactor)
    end

    return directionState
end

function FPSCamera.checkFixedPointCommandActivation()
    if Util.isTurboBarCamDisabled() then
        return
    end

    local _, activeCmd = Spring.GetActiveCommand()

    if activeCmd ~= prevActiveCmd then
        if activeCmd == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT then
            if STATE.mode.name == 'fps' and STATE.mode.unitID then
                STATE.mode.fps.inTargetSelectionMode = true
                STATE.mode.fps.prevFreeCamState = STATE.mode.fps.isFreeCameraActive
                STATE.mode.fps.prevMode = STATE.mode.name
                STATE.mode.fps.prevFixedPoint = STATE.mode.fps.fixedPoint
                STATE.mode.fps.prevFixedPointActive = STATE.mode.fps.isFixedPointActive

                if STATE.mode.fps.isFixedPointActive then
                    STATE.mode.fps.isFixedPointActive = false
                    STATE.mode.fps.fixedPoint = nil
                end

                local camState = Spring.GetCameraState()
                STATE.mode.fps.freeCam.targetRx = camState.rx
                STATE.mode.fps.freeCam.targetRy = camState.ry
                STATE.mode.fps.freeCam.lastMouseX, STATE.mode.fps.freeCam.lastMouseY = Spring.GetMouseState()

                if Spring.ValidUnitID(STATE.mode.unitID) then
                    STATE.mode.fps.freeCam.lastUnitHeading = Spring.GetUnitHeading(STATE.mode.unitID, true)
                end
                STATE.mode.fps.isFreeCameraActive = true
                Log.trace("Target selection mode activated - select a target to look at")
            end
        elseif prevActiveCmd == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT and STATE.mode.fps.inTargetSelectionMode then
            STATE.mode.fps.inTargetSelectionMode = false
            if STATE.mode.fps.prevFixedPointActive and STATE.mode.fps.prevFixedPoint then
                STATE.mode.fps.isFixedPointActive = true
                STATE.mode.fps.fixedPoint = STATE.mode.fps.prevFixedPoint
                Log.trace("Target selection canceled, returning to fixed point view")
            end
            STATE.mode.fps.isFreeCameraActive = STATE.mode.fps.prevFreeCamState
            if not STATE.mode.fps.prevFixedPointActive then
                Log.trace("Target selection canceled, returning to unit view")
            end
        end
    end
    prevActiveCmd = activeCmd
end

function FPSCamera.setFixedLookPoint(cmdParams)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("fps") then
        return
    end
    if not STATE.mode.unitID then
        Log.debug("No unit being tracked for fixed point camera")
        return false
    end

    local x, y, z
    STATE.mode.fps.targetUnitID = nil

    if cmdParams then
        if #cmdParams == 1 then
            local unitID = cmdParams[1]
            if Spring.ValidUnitID(unitID) then
                STATE.mode.fps.targetUnitID = unitID
                x, y, z = Spring.GetUnitPosition(unitID)
                Log.trace("Camera will follow current unit but look at unit " .. unitID)
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
        Log.trace("Could not find a valid position")
        return false
    end

    local fixedPoint = { x = x, y = y, z = z }
    return FPSCameraUtils.setFixedLookPoint(fixedPoint, STATE.mode.fps.targetUnitID)
end

function FPSCamera.clearFixedLookPoint()
    FPSCameraUtils.clearFixedLookPoint()
end

function FPSCamera.toggleFreeCam()
    if Util.isTurboBarCamDisabled() then
        return
    end
    if STATE.mode.name ~= 'fps' or not STATE.mode.unitID then
        Log.debug("Free camera only works when tracking a unit in FPS mode")
        return
    end
    FreeCam.toggle()
    if not STATE.mode.fps.isFreeCameraActive and STATE.mode.fps.isFixedPointActive then
        FPSCameraUtils.clearFixedLookPoint()
    end
end

function FPSCamera.nextWeapon()
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled('fps') then
        return
    end
    if not STATE.mode.unitID or not Spring.ValidUnitID(STATE.mode.unitID) then
        Log.debug("No unit selected.")
        return
    end
    FPSCombatMode.nextWeapon()
end

function FPSCamera.clearWeaponSelection()
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled('fps') then
        return
    end
    FPSCombatMode.clearWeaponSelection()
end

function FPSCamera.adjustParams(params)
    FPSCameraUtils.adjustParams(params)
end

function FPSCamera.toggleCombatMode()
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled('fps') then
        return
    end
    FPSCombatMode.toggleCombatMode()
end

function FPSCamera.handleSelectNewUnit()
    FPSCombatMode.clearAttackingState()
end

return {
    FPSCamera = FPSCamera
}