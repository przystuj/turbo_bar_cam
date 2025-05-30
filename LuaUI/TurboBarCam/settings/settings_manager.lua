---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log
---@type PersistentStorage
local PersistentStorage = VFS.Include("LuaUI/TurboBarCam/settings/persistent_storage.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE

-- Initialize the settings state if it doesn't exist
if not STATE.settings then
    STATE.settings = {
        initialized = false,
        storages = {}
    }
end

---@class SettingsManager
local SettingsManager = {}

--- Initialize the settings manager
function SettingsManager.initializePersistentStorage()
    if STATE.settings.initialized then
        return
    end

    STATE.settings.fpsWeaponOffsets = PersistentStorage.new("fps_weapon_offsets", true)
    STATE.settings.storages["fps_weapon"] = STATE.settings.fpsWeaponOffsets

    STATE.settings.fpsPeaceOffsets = PersistentStorage.new("fps_peace_offsets", true)
    STATE.settings.storages["fps_peace"] = STATE.settings.fpsPeaceOffsets

    STATE.settings.fpsCombatOffsets = PersistentStorage.new("fps_combat_offsets", true)
    STATE.settings.storages["fps_combat"] = STATE.settings.fpsCombatOffsets

    STATE.settings["anchors"] = PersistentStorage.new("anchors", true)
    STATE.settings.storages["anchors"] = STATE.settings["anchors"]

    STATE.settings["dollycam"] = PersistentStorage.new("dollycam", true)
    STATE.settings.storages["dollycam"] = STATE.settings["dollycam"]

    STATE.settings["orbit_presets"] = PersistentStorage.new("orbit_presets", true)
    STATE.settings.storages["orbit_presets"] = STATE.settings["orbit_presets"]

    STATE.settings["projectile_camera_settings"] = PersistentStorage.new("projectile_camera_settings", true)
    STATE.settings.storages["projectile_camera_settings"] = STATE.settings["projectile_camera_settings"]

    STATE.settings.initialized = true
    Log.info("SettingsManager initialized")
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

    Log.info("SettingsManager shutdown")
end

function SettingsManager.chooseIdentifier(mode, unitID)
    if CONFIG.PERSISTENT_UNIT_SETTINGS == "UNIT" then
        return unitID
    elseif CONFIG.PERSISTENT_UNIT_SETTINGS == "MODE" then
        return mode
    else
        return nil
    end
end

--- Saves custom settings
---@param mode string Camera mode
---@param unitID number Unit ID
function SettingsManager.saveModeSettings(mode, unitID)
    ---@type FeatureModules
    local FeatureModules = WG.TurboBarCam.FeatureModules
    local identifier = SettingsManager.chooseIdentifier(mode, unitID)

    if not identifier then
        return
    end

    -- Always use unitID for FPS and Projectile Camera for unit-type saving
    local currentUnitID = (STATE.mode.targetType == STATE.TARGET_TYPES.UNIT) and STATE.mode.unitID or unitID

    Log.trace(string.format("Saving settings for %s=%s (Mode: %s)", CONFIG.PERSISTENT_UNIT_SETTINGS, tostring(identifier), mode))

    if mode == 'fps' and currentUnitID then
        SettingsManager.saveFPSOffsets(currentUnitID)
    elseif mode == 'orbit' then
        FeatureModules.OrbitingCamera.saveSettings(identifier)
    elseif mode == 'projectile_camera' and currentUnitID then
        FeatureModules.ProjectileCamera.saveSettings(currentUnitID)
    end
end

--- Loads custom settings
---@param mode string Camera mode
---@param unitID number Unit ID
function SettingsManager.loadModeSettings(mode, unitID)
    ---@type FeatureModules
    local FeatureModules = WG.TurboBarCam.FeatureModules
    local identifier = SettingsManager.chooseIdentifier(mode, unitID)

    Log.trace(string.format("Loading settings for %s=%s (Mode: %s)", CONFIG.PERSISTENT_UNIT_SETTINGS, tostring(identifier), mode))

    if mode == 'fps' and unitID then
        SettingsManager.loadFPSOffsets(unitID)
    elseif mode == 'orbit' then
        FeatureModules.OrbitingCamera.loadSettings(identifier)
    elseif mode == 'projectile_camera' and unitID then
        FeatureModules.ProjectileCamera.loadSettings(unitID)
    end
end

--- Saves FPS camera offsets
---@param unitId number Unit ID
function SettingsManager.saveFPSOffsets(unitId)
    if not STATE.settings.initialized then
        SettingsManager.initializePersistentStorage()
    end
    if not Spring.ValidUnitID(unitId) then
        return
    end

    local unitDef = UnitDefs[Spring.GetUnitDefID(unitId)]
    local unitName = unitDef.name

    local function saveOffsets(mode, settingsSetter)
        local offsets = CONFIG.CAMERA_MODES.FPS.OFFSETS[mode]
        settingsSetter:set(unitName, {
            FORWARD = offsets.FORWARD,
            HEIGHT = offsets.HEIGHT,
            SIDE = offsets.SIDE,
            ROTATION = offsets.ROTATION
        })
    end

    saveOffsets("PEACE", STATE.settings.fpsPeaceOffsets)
    saveOffsets("COMBAT", STATE.settings.fpsCombatOffsets)
    saveOffsets("WEAPON", STATE.settings.fpsWeaponOffsets)

    Log.trace("Updated FPS camera offsets for " .. unitName)
end

--- Loads FPS camera offsets
---@param unitId number Unit ID
---@return boolean Success
function SettingsManager.loadFPSOffsets(unitId)
    if not STATE.settings.initialized then
        SettingsManager.initializePersistentStorage()
    end

    local unitDef = UnitDefs[Spring.GetUnitDefID(unitId)]
    if not unitDef then
        return false
    end
    local unitName = unitDef.name

    local loaded = false

    local function loadOffsets(mode, settingsGetter)
        local settings = settingsGetter:get(unitName)
        local offsets = CONFIG.CAMERA_MODES.FPS.OFFSETS[mode]
        local defaults = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS[mode]

        if settings then
            offsets.FORWARD = settings.FORWARD
            offsets.HEIGHT = settings.HEIGHT
            offsets.SIDE = settings.SIDE
            offsets.ROTATION = settings.ROTATION
            loaded = true
            Log.trace("Loaded " .. mode:lower() .. " offsets for " .. unitName)
        else
            offsets.FORWARD = defaults.FORWARD
            offsets.HEIGHT = defaults.HEIGHT
            offsets.SIDE = defaults.SIDE
            offsets.ROTATION = defaults.ROTATION
            Log.trace("No " .. mode:lower() .. " offsets found for " .. unitName)
        end
    end

    loadOffsets("PEACE", STATE.settings.fpsPeaceOffsets)
    loadOffsets("COMBAT", STATE.settings.fpsCombatOffsets)
    loadOffsets("WEAPON", STATE.settings.fpsWeaponOffsets)

    return loaded
end

function SettingsManager.saveUserSetting(name, id, data)
    if not STATE.settings.storages[name] then
        Log.warn("Storage not initialized: " .. name)
        return false
    end
    STATE.settings.storages[name]:set(id, data)
    return true
end

function SettingsManager.loadUserSetting(name, id)
    if not STATE.settings.storages[name] then
        Log.warn("Storage not initialized: " .. name)
        return nil
    end
    return STATE.settings.storages[name]:get(id)
end

return {
    SettingsManager = SettingsManager
}