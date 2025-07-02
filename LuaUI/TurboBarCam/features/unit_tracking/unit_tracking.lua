---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CONSTANTS = ModuleManager.CONSTANTS(function(m) CONSTANTS = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "UnitTrackingCamera")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local CameraDriver = ModuleManager.CameraDriver(function(m) CameraDriver = m end)
local ParamUtils = ModuleManager.ParamUtils(function(m) ParamUtils = m end)

---@class UnitTrackingCamera
local UnitTrackingCamera = {}

function UnitTrackingCamera.toggle()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    local selectedUnits = Spring.GetSelectedUnits()

    if #selectedUnits == 0 then
        if STATE.active.mode.name == 'unit_tracking' then
            ModeManager.disableAndStopDriver()
            Log:trace("UnitTrackingCamera: Disabled (no units selected).")
        else
            Log:trace("UnitTrackingCamera: No unit selected.")
        end
        return
    end
    local selectedUnitID = selectedUnits[1]

    if STATE.active.mode.name == 'unit_tracking' and
            STATE.active.mode.unitID == selectedUnitID and
            not STATE.active.mode.optionalTargetCameraStateForModeEntry then
        ModeManager.disableAndStopDriver()
        Log:trace("UnitTrackingCamera: Disabled for unit " .. selectedUnitID)
        return
    end

    if ModeManager.initializeMode('unit_tracking', selectedUnitID, CONSTANTS.TARGET_TYPE.UNIT, false, nil) then
        Log:trace("UnitTrackingCamera: Enabled for unit " .. selectedUnitID)
    else
        Log:warn("UnitTrackingCamera: Failed to initializeMode for unit_tracking.")
    end
end

function UnitTrackingCamera.update()
    if STATE.active.mode.name ~= 'unit_tracking' then
        return
    end

    local unitID = STATE.active.mode.unitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log:trace("UnitTrackingCamera: Tracked unit " .. tostring(unitID) .. " no longer exists, disabling.")
        ModeManager.disableAndStopDriver()
        return
    end

    if STATE.core.driver.target and STATE.core.driver.target.targetUnitId == unitID then
        -- already tracking this unit
        return
    end

    local smoothing = CONFIG.CAMERA_MODES.UNIT_TRACKING.DECELERATION_PROFILE.DURATION
    local cameraDriverJob = CameraDriver.prepare(CONSTANTS.TARGET_TYPE.UNIT, unitID)
    cameraDriverJob.positionSmoothing = smoothing
    cameraDriverJob.rotationSmoothing = smoothing / 4
    cameraDriverJob.run()
end

function UnitTrackingCamera.adjustParams(params)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if STATE.active.mode.name ~= 'unit_tracking' then
        return
    end
    if not STATE.active.mode.unitID then
        Log:trace("UnitTrackingCamera: No unit is tracked for adjustParams.")
        return
    end
    ParamUtils.adjustParams(params, "UNIT_TRACKING", function()
        CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT = 0
    end)
end

return UnitTrackingCamera