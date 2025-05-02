---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/settings/settings_manager.lua").SettingsManager

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local TrackingManager = CommonModules.TrackingManager

---@class OrbitCameraUtils
local OrbitCameraUtils = {}

--- Calculates camera position on orbit path
---@param targetPos table Target position {x, y, z}
---@return table camPos Camera position {x, y, z}
function OrbitCameraUtils.calculateOrbitPosition(targetPos)
    return {
        x = targetPos.x + CONFIG.CAMERA_MODES.ORBIT.DISTANCE * math.sin(STATE.tracking.orbit.angle),
        y = targetPos.y + CONFIG.CAMERA_MODES.ORBIT.HEIGHT,
        z = targetPos.z + CONFIG.CAMERA_MODES.ORBIT.DISTANCE * math.cos(STATE.tracking.orbit.angle)
    }
end

function OrbitCameraUtils.ensureHeightIsSet()
    if CONFIG.CAMERA_MODES.ORBIT.HEIGHT then
        return
    end

    if STATE.tracking.targetType == STATE.TARGET_TYPES.UNIT then
        local unitHeight = TrackingManager.getDefaultHeightForUnitTracking(STATE.tracking.unitID)
        CONFIG.CAMERA_MODES.ORBIT.HEIGHT = unitHeight * CONFIG.CAMERA_MODES.ORBIT.HEIGHT_FACTOR
    else
        CONFIG.CAMERA_MODES.ORBIT.HEIGHT = 1000
    end
end

---@see ModifiableParams
---@see Util#adjustParams
function OrbitCameraUtils.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("orbit") then
        return
    end

    Util.adjustParams(params, "ORBIT", function() OrbitCameraUtils.resetSettings() end)
    SettingsManager.saveModeSettings(STATE.tracking.mode, STATE.tracking.unitID)
end

--- Resets orbit settings to defaults
---@return boolean success Whether settings were reset successfully
function OrbitCameraUtils.resetSettings()
    CONFIG.CAMERA_MODES.ORBIT.SPEED = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_SPEED
    CONFIG.CAMERA_MODES.ORBIT.DISTANCE = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_DISTANCE
    CONFIG.CAMERA_MODES.ORBIT.HEIGHT = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_HEIGHT
    Log.trace("Restored orbit camera settings to defaults")
end

return {
    OrbitCameraUtils = OrbitCameraUtils
}