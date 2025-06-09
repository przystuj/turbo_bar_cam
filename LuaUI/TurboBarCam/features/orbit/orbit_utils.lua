---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local SettingsManager = ModuleManager.SettingsManager(function(m) SettingsManager = m end)
local ParamUtils = ModuleManager.ParamUtils(function(m) ParamUtils = m end)
local WorldUtils = ModuleManager.WorldUtils(function(m) WorldUtils = m end)

---@class OrbitCameraUtils
local OrbitCameraUtils = {}

--- Calculates camera position on orbit path
---@param targetPos table Target position {x, y, z}
---@return table camPos Camera position {x, y, z}
function OrbitCameraUtils.calculateOrbitPosition(targetPos)
    OrbitCameraUtils.ensureHeightIsSet()
    -- Calculate precise sine and cosine for the orbit angle
    local angle = STATE.active.mode.orbit.angle
    local distance = CONFIG.CAMERA_MODES.ORBIT.OFFSETS.DISTANCE

    -- Calculate precise orbit offset
    local offsetX = distance * math.sin(angle)
    local offsetZ = distance * math.cos(angle)

    return {
        x = targetPos.x + offsetX,
        y = targetPos.y + CONFIG.CAMERA_MODES.ORBIT.OFFSETS.HEIGHT,
        z = targetPos.z + offsetZ
    }
end

function OrbitCameraUtils.ensureHeightIsSet()
    if CONFIG.CAMERA_MODES.ORBIT.OFFSETS.HEIGHT then
        return
    end

    if STATE.active.mode.targetType == STATE.TARGET_TYPES.UNIT then
        local unitHeight = math.max(WorldUtils.getUnitHeight(STATE.active.mode.unitID), 100)
        CONFIG.CAMERA_MODES.ORBIT.OFFSETS.HEIGHT = unitHeight * CONFIG.CAMERA_MODES.ORBIT.HEIGHT_FACTOR
    else
        CONFIG.CAMERA_MODES.ORBIT.OFFSETS.HEIGHT = 1000
    end
end

---@see ModifiableParams
---@see Utils#adjustParams
function OrbitCameraUtils.adjustParams(params)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled("orbit") then
        return
    end

    ParamUtils.adjustParams(params, "ORBIT", function()
        OrbitCameraUtils.resetSettings()
    end)
    SettingsManager.saveModeSettings(STATE.active.mode.name, STATE.active.mode.unitID)
end

--- Resets orbit settings to defaults
---@return boolean success Whether settings were reset successfully
function OrbitCameraUtils.resetSettings()
    Utils.patchTable(CONFIG.CAMERA_MODES.ORBIT.OFFSETS, CONFIG.CAMERA_MODES.ORBIT.DEFAULT_OFFSETS)
    Log:trace("Restored orbit camera settings to defaults")
end

--- Resets orbit settings to defaults
---@return boolean success Whether settings were reset successfully
function OrbitCameraUtils.getTargetPosition()
    local targetPos
    if STATE.active.mode.targetType == STATE.TARGET_TYPES.UNIT then
        -- Check if unit still exists
        if not Spring.ValidUnitID(STATE.active.mode.unitID) then
            Log:trace("Unit no longer exists, switching to point tracking")

            -- Switch to point tracking using last known position
            if STATE.active.mode.lastTargetPoint then
                STATE.active.mode.targetType = STATE.TARGET_TYPES.POINT
                STATE.active.mode.targetPoint = STATE.active.mode.lastTargetPoint
                STATE.active.mode.unitID = nil

                -- Use the last target point for this update
                targetPos = STATE.active.mode.targetPoint
            else
                -- No position info available, disable tracking
                ModeManager.disableMode()
                return
            end
        else
            -- Unit exists, get its position
            local x, y, z = Spring.GetUnitPosition(STATE.active.mode.unitID)
            targetPos = { x = x, y = y, z = z }

            -- Update last target point for fallback
            STATE.active.mode.lastTargetPoint = { x = x, y = y, z = z }
        end
    else
        -- Point tracking
        targetPos = STATE.active.mode.targetPoint
    end
    return targetPos
end

--- Calculates camera position on orbit path for a specific angle.
---@param targetPos table Target position {x, y, z}
---@param angle number The specific angle (in radians) to calculate the orbit position for.
---@return table camPos Camera position {x, y, z}
function OrbitCameraUtils.calculateOrbitPositionWithAngle(targetPos, angle)
    local distance = CONFIG.CAMERA_MODES.ORBIT.OFFSETS.DISTANCE
    local offsetX = distance * math.sin(angle)
    local offsetZ = distance * math.cos(angle)

    OrbitCameraUtils.ensureHeightIsSet() -- Call ensureHeightIsSet using existing state for target type.

    return {
        x = targetPos.x + offsetX,
        y = targetPos.y + (CONFIG.CAMERA_MODES.ORBIT.OFFSETS.HEIGHT or 0),
        z = targetPos.z + offsetZ
    }
end

return  OrbitCameraUtils
