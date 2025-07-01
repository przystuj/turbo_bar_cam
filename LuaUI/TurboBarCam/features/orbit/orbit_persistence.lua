---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CONSTANTS = ModuleManager.CONSTANTS(function(m) CONSTANTS = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "OrbitPersistence")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local WorldUtils = ModuleManager.WorldUtils(function(m) WorldUtils = m end)
local SettingsManager = ModuleManager.SettingsManager(function(m) SettingsManager = m end)
local OrbitCameraUtils = ModuleManager.OrbitCameraUtils(function(m) OrbitCameraUtils = m end)

---@class OrbitPersistence
local OrbitPersistence = {}

--- Serializes the current orbit state for storage
---@return table|nil serializedData Serialized orbit data, or nil if not in orbit mode
function OrbitPersistence.serializeCurrentOrbitState()
    if STATE.active.mode.name ~= 'orbit' then
        Log:warn("[OrbitPersistence] Not in orbit mode, cannot serialize state.")
        return nil
    end

    local data = {
        angle = STATE.active.mode.orbit.angle,
        speed = CONFIG.CAMERA_MODES.ORBIT.OFFSETS.SPEED,
        distance = CONFIG.CAMERA_MODES.ORBIT.OFFSETS.DISTANCE,
        height = CONFIG.CAMERA_MODES.ORBIT.OFFSETS.HEIGHT,
        targetType = STATE.active.mode.targetType,
        targetID = nil,
        targetPoint = nil,
        isPaused = STATE.active.mode.orbit.isPaused or false -- Save paused state
    }

    if STATE.active.mode.targetType == CONSTANTS.TARGET_TYPE.UNIT then
        data.targetID = STATE.active.mode.unitID
    elseif STATE.active.mode.targetType == CONSTANTS.TARGET_TYPE.POINT then
        if STATE.active.mode.targetPoint then
            data.targetPoint = TableUtils.deepCopy(STATE.active.mode.targetPoint)
        else
            Log:warn("[OrbitPersistence] Target type is POINT but targetPoint is nil. Saving without point.")
        end
    end

    Log:trace("[OrbitPersistence] Serialized orbit state: angle=" .. data.angle .. ", speed=" .. data.speed)
    return data
end

--- Saves the provided orbit data to a settings file, organized by map.
---@param orbitSetId string Identifier for the saved orbit configuration (e.g., "orbit_slot_1")
---@param dataToSave table The orbit data to save (typically from serializeCurrentOrbitState)
---@return boolean success Whether saving was successful
function OrbitPersistence.saveToFile(orbitSetId, dataToSave)
    if not orbitSetId or orbitSetId == "" then
        Log:warn("[OrbitPersistence] Cannot save - no identifier specified for orbit set.")
        return false
    end

    if not dataToSave then
        Log:warn("[OrbitPersistence] No data provided to save for orbit set ID: " .. orbitSetId)
        return false
    end

    local mapName = WorldUtils.getCleanMapName()
    local mapOrbitPresets = SettingsManager.loadUserSetting("orbit_presets", mapName, {})
    mapOrbitPresets[orbitSetId] = dataToSave

    local success = SettingsManager.saveUserSetting("orbit_presets", mapName, mapOrbitPresets)

    if success then
        Log:info(string.format("[OrbitPersistence] Saved orbit configuration with ID '%s' for map '%s'.", orbitSetId, mapName))
    else
        Log:error("[OrbitPersistence] Failed to save orbit configuration with ID: " .. orbitSetId)
    end

    return success
end

--- Loads an orbit configuration from a settings file for the current map.
---@param orbitSetId string Identifier for the saved orbit configuration.
---@return table|nil loadedData The loaded orbit data, or nil if not found or error.
function OrbitPersistence.loadFromFile(orbitSetId)
    if not orbitSetId or orbitSetId == "" then
        Log:warn("[OrbitPersistence] Cannot load - no identifier specified for orbit set.")
        return nil
    end

    local mapName = WorldUtils.getCleanMapName()
    local mapOrbitPresets = SettingsManager.loadUserSetting("orbit_presets", mapName)

    if not mapOrbitPresets or not mapOrbitPresets[orbitSetId] then
        Log:warn(string.format("[OrbitPersistence] No saved orbit configuration found with ID '%s' for map '%s'.", orbitSetId, mapName))
        return nil
    end

    local loadedData = mapOrbitPresets[orbitSetId]
    Log:info(string.format("[OrbitPersistence] Successfully loaded orbit configuration with ID '%s' for map '%s'.", orbitSetId, mapName))
    return loadedData
end

function OrbitPersistence.saveSettings(_, _)
    SettingsManager.saveUserSetting("orbit_offsets", "orbit", CONFIG.CAMERA_MODES.ORBIT.OFFSETS)
end

function OrbitPersistence.loadSettings(_, _)
    Utils.patchTable(CONFIG.CAMERA_MODES.ORBIT.OFFSETS,SettingsManager.loadUserSetting("orbit_offsets", "orbit", CONFIG.CAMERA_MODES.ORBIT.DEFAULT_OFFSETS))
    OrbitCameraUtils.ensureHeightIsSet()
end

STATE.settings.loadModeSettingsFn.orbit = OrbitPersistence.loadSettings
STATE.settings.saveModeSettingsFn.orbit = OrbitPersistence.saveSettings

return OrbitPersistence
