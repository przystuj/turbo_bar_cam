---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "SettingsManager")
local PersistentStorage = ModuleManager.PersistentStorage(function(m) PersistentStorage = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)

---@class SettingsManager
local SettingsManager = {}

local function initStorage(name, persistent)
    STATE.settings.storages[name] = PersistentStorage.new(name, persistent)
end

--- Initialize the settings manager
function SettingsManager.initializePersistentStorage()
    if STATE.settings.initialized then
        return
    end

    initStorage("unit_follow_weapon_offsets", true)
    initStorage("unit_follow_default_offsets", true)
    initStorage("unit_follow_combat_offsets", true)
    initStorage("anchors", true)
    initStorage("dollycam", true)
    initStorage("orbit_offsets", true)
    initStorage("orbit_presets", true)
    initStorage("projectile_camera_settings", true)

    STATE.settings.initialized = true
end

--- Update function to be called in widget:Update
function SettingsManager.update()
    if not STATE.settings.initialized then
        SettingsManager.initializePersistentStorage()
    end

    for _, storage in pairs(STATE.settings.storages) do
        storage:update()
    end
end

function SettingsManager.shutdown()
    if not STATE.settings.initialized then
        return
    end

    for name, storage in pairs(STATE.settings.storages) do
        storage:close()
    end

    Log:info("SettingsManager shutdown")
end

-----@param modeName string
-----@param modeTargetId number
function SettingsManager.loadModeSettings(modeName, modeTargetId)
    if not modeName or not STATE.settings.loadModeSettingsFn[modeName] then
        return
    end
    STATE.settings.loadModeSettingsFn[modeName](modeName, modeTargetId)
end

-----@param modeName string
-----@param modeTargetId number
function SettingsManager.saveModeSettings(modeName, modeTargetId)
    if not modeName or not STATE.settings.saveModeSettingsFn[modeName] then
        return
    end
    STATE.settings.saveModeSettingsFn[modeName](modeName, modeTargetId)
end

function SettingsManager.saveUserSetting(name, id, data)
    if not STATE.settings.storages[name] then
        Log:warn("Storage not initialized: " .. name)
        return false
    end

    STATE.settings.storages[name]:set(id, TableUtils.deepCopy(data))
    return true
end

function SettingsManager.loadUserSetting(name, id, default)
    if not STATE.settings.storages[name] then
        Log:warn("Storage not initialized: " .. name)
        return nil
    end
    return TableUtils.deepCopy(STATE.settings.storages[name]:get(id) or TableUtils.deepCopy(default) or nil)
end

return SettingsManager