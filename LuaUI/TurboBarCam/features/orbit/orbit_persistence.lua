---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/settings/settings_manager.lua").SettingsManager

local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG -- Used for accessing STATE.TARGET_TYPES
local Util = CommonModules.Util
local Log = CommonModules.Log

---@class OrbitPersistence
local OrbitPersistence = {}

--- Serializes the current orbit state for storage
---@return table|nil serializedData Serialized orbit data, or nil if not in orbit mode
function OrbitPersistence.serializeCurrentOrbitState()
    if STATE.mode.name ~= 'orbit' then
        Log.warn("[OrbitPersistence] Not in orbit mode, cannot serialize state.")
        return nil
    end

    local data = {
        angle = STATE.mode.orbit.angle,
        speed = CONFIG.CAMERA_MODES.ORBIT.SPEED,
        distance = CONFIG.CAMERA_MODES.ORBIT.DISTANCE,
        height = CONFIG.CAMERA_MODES.ORBIT.HEIGHT,
        targetType = STATE.mode.targetType,
        targetID = nil,
        targetPoint = nil,
        isPaused = STATE.mode.orbit.isPaused or false -- Save paused state
    }

    if STATE.mode.targetType == STATE.TARGET_TYPES.UNIT then
        data.targetID = STATE.mode.unitID
    elseif STATE.mode.targetType == STATE.TARGET_TYPES.POINT then
        if STATE.mode.targetPoint then
            data.targetPoint = Util.deepCopy(STATE.mode.targetPoint)
        else
            Log.warn("[OrbitPersistence] Target type is POINT but targetPoint is nil. Saving without point.")
        end
    end

    Log.trace("[OrbitPersistence] Serialized orbit state: angle=" .. data.angle .. ", speed=" .. data.speed)
    return data
end

--- Saves the provided orbit data to a settings file, organized by map.
---@param orbitSetId string Identifier for the saved orbit configuration (e.g., "orbit_slot_1")
---@param dataToSave table The orbit data to save (typically from serializeCurrentOrbitState)
---@return boolean success Whether saving was successful
function OrbitPersistence.saveToFile(orbitSetId, dataToSave)
    if not orbitSetId or orbitSetId == "" then
        Log.warn("[OrbitPersistence] Cannot save - no identifier specified for orbit set.")
        return false
    end

    if not dataToSave then
        Log.warn("[OrbitPersistence] No data provided to save for orbit set ID: " .. orbitSetId)
        return false
    end

    local mapName = Util.getCleanMapName()
    local mapOrbitPresets = SettingsManager.loadUserSetting("orbit_presets", mapName) or {}
    mapOrbitPresets[orbitSetId] = dataToSave

    local success = SettingsManager.saveUserSetting("orbit_presets", mapName, mapOrbitPresets)

    if success then
        Log.info(string.format("[OrbitPersistence] Saved orbit configuration with ID '%s' for map '%s'.", orbitSetId, mapName))
    else
        Log.error("[OrbitPersistence] Failed to save orbit configuration with ID: " .. orbitSetId)
    end

    return success
end

--- Loads an orbit configuration from a settings file for the current map.
---@param orbitSetId string Identifier for the saved orbit configuration.
---@return table|nil loadedData The loaded orbit data, or nil if not found or error.
function OrbitPersistence.loadFromFile(orbitSetId)
    if not orbitSetId or orbitSetId == "" then
        Log.warn("[OrbitPersistence] Cannot load - no identifier specified for orbit set.")
        return nil
    end

    local mapName = Util.getCleanMapName()
    local mapOrbitPresets = SettingsManager.loadUserSetting("orbit_presets", mapName)

    if not mapOrbitPresets or not mapOrbitPresets[orbitSetId] then
        Log.warn(string.format("[OrbitPersistence] No saved orbit configuration found with ID '%s' for map '%s'.", orbitSetId, mapName))
        return nil
    end

    local loadedData = mapOrbitPresets[orbitSetId]
    Log.info(string.format("[OrbitPersistence] Successfully loaded orbit configuration with ID '%s' for map '%s'.", orbitSetId, mapName))
    return loadedData
end

return {
    OrbitPersistence = OrbitPersistence
}
