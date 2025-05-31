---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/core/settings_manager.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local ModeManager = CommonModules.ModeManager

---@class OrbitCameraUtils
local OrbitCameraUtils = {}

--- Calculates camera position on orbit path
---@param targetPos table Target position {x, y, z}
---@return table camPos Camera position {x, y, z}
function OrbitCameraUtils.calculateOrbitPosition(targetPos)
    -- Calculate precise sine and cosine for the orbit angle
    local angle = STATE.mode.orbit.angle
    local distance = CONFIG.CAMERA_MODES.ORBIT.DISTANCE

    -- Calculate precise orbit offset
    local offsetX = distance * math.sin(angle)
    local offsetZ = distance * math.cos(angle)

    return {
        x = targetPos.x + offsetX,
        y = targetPos.y + CONFIG.CAMERA_MODES.ORBIT.HEIGHT,
        z = targetPos.z + offsetZ
    }
end

function OrbitCameraUtils.ensureHeightIsSet()
    if CONFIG.CAMERA_MODES.ORBIT.HEIGHT then
        return
    end

    if STATE.mode.targetType == STATE.TARGET_TYPES.UNIT then
        local unitHeight = math.max(Util.getUnitHeight(STATE.mode.unitID), 100)
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

    Util.adjustParams(params, "ORBIT", function()
        OrbitCameraUtils.resetSettings()
    end)
    SettingsManager.saveModeSettings(STATE.mode.name, STATE.mode.unitID)
end

--- Resets orbit settings to defaults
---@return boolean success Whether settings were reset successfully
function OrbitCameraUtils.resetSettings()
    CONFIG.CAMERA_MODES.ORBIT.SPEED = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_SPEED
    CONFIG.CAMERA_MODES.ORBIT.DISTANCE = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_DISTANCE
    CONFIG.CAMERA_MODES.ORBIT.HEIGHT = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_HEIGHT
    Log.trace("Restored orbit camera settings to defaults")
end

--- Resets orbit settings to defaults
---@return boolean success Whether settings were reset successfully
function OrbitCameraUtils.getTargetPosition()
    local targetPos
    if STATE.mode.targetType == STATE.TARGET_TYPES.UNIT then
        -- Check if unit still exists
        if not Spring.ValidUnitID(STATE.mode.unitID) then
            Log.trace("Unit no longer exists, switching to point tracking")

            -- Switch to point tracking using last known position
            if STATE.mode.lastTargetPoint then
                STATE.mode.targetType = STATE.TARGET_TYPES.POINT
                STATE.mode.targetPoint = STATE.mode.lastTargetPoint
                STATE.mode.unitID = nil

                -- Use the last target point for this update
                targetPos = STATE.mode.targetPoint
            else
                -- No position info available, disable tracking
                ModeManager.disableMode()
                return
            end
        else
            -- Unit exists, get its position
            local x, y, z = Spring.GetUnitPosition(STATE.mode.unitID)
            targetPos = { x = x, y = y, z = z }

            -- Update last target point for fallback
            STATE.mode.lastTargetPoint = { x = x, y = y, z = z }
        end
    else
        -- Point tracking
        targetPos = STATE.mode.targetPoint
    end
    return targetPos
end

--- Calculates camera position on orbit path for a specific angle.
---@param targetPos table Target position {x, y, z}
---@param angle number The specific angle (in radians) to calculate the orbit position for.
---@return table camPos Camera position {x, y, z}
function OrbitCameraUtils.calculateOrbitPositionWithAngle(targetPos, angle)
    local distance = CONFIG.CAMERA_MODES.ORBIT.DISTANCE
    local offsetX = distance * math.sin(angle)
    local offsetZ = distance * math.cos(angle)

    OrbitCameraUtils.ensureHeightIsSet() -- Call ensureHeightIsSet using existing state for target type.

    return {
        x = targetPos.x + offsetX,
        y = targetPos.y + (CONFIG.CAMERA_MODES.ORBIT.HEIGHT or 0),
        z = targetPos.z + offsetZ
    }
end

return {
    OrbitCameraUtils = OrbitCameraUtils
}
