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
    if STATE.settings.initialized then return end

    -- Create weapon settings storage (persistent)
    STATE.settings.weaponSettings = PersistentStorage.new("weapon_settings", true)
    STATE.settings.storages["weapon"] = STATE.settings.weaponSettings

    -- Create other in-memory storages here if needed

    STATE.settings.initialized = true
    Log.info("SettingsManager initialized")
end

--- Update function to be called in widget:Update
function SettingsManager.update()
    if not STATE.settings.initialized then return end

    for name, storage in pairs(STATE.settings.storages) do
        storage:update()
    end
end

function SettingsManager.shutdown()
    if not STATE.settings.initialized then return end

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

    Log.trace(string.format("Saving settings for %s=%s", CONFIG.PERSISTENT_UNIT_SETTINGS, identifier))

    if mode == 'fps' then
        FeatureModules.FPSCamera.saveSettings(identifier)
        if CONFIG.PERSISTENT_WEAPON_SETTINGS then
            SettingsManager.saveWeaponSettings(unitID)
        end
    elseif mode == 'orbit' then
        FeatureModules.OrbitingCamera.saveSettings(identifier)
    end
end

--- Loads custom settings
---@param mode string Camera mode
---@param unitID number Unit ID
function SettingsManager.loadModeSettings(mode, unitID)
    ---@type FeatureModules
    local FeatureModules = WG.TurboBarCam.FeatureModules
    local identifier = SettingsManager.chooseIdentifier(mode, unitID)

    Log.trace(string.format("Loading settings for %s=%s", CONFIG.PERSISTENT_UNIT_SETTINGS, identifier))

    if mode == 'fps' then
        FeatureModules.FPSCamera.loadSettings(identifier)
        if CONFIG.PERSISTENT_WEAPON_SETTINGS then
            SettingsManager.loadWeaponSettings(unitID)
        end
    elseif mode == 'orbit' then
        FeatureModules.OrbitingCamera.loadSettings(identifier)
    end
end

--- Saves weapon settings
---@param unitId number Unit ID
function SettingsManager.saveWeaponSettings(unitId)
    if not STATE.settings.initialized then SettingsManager.initializePersistentStorage() end
    if not Spring.ValidUnitID(unitId) then return end

    local unitDef = UnitDefs[Spring.GetUnitDefID(unitId)]
    local unitName = unitDef.name

    Log.trace("Saving weapon offsets for " .. unitName)

    -- Set the current weapon settings in storage
    STATE.settings.weaponSettings:set(unitName, {
        FORWARD = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_FORWARD,
        HEIGHT = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_HEIGHT,
        SIDE = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_SIDE,
        ROTATION = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_ROTATION
    })

    Log.trace("Updated settings for " .. unitName)
end

--- Loads weapon settings for a specific unit
---@param unitId number Unit ID
---@return boolean Success
function SettingsManager.loadWeaponSettings(unitId)
    if not STATE.settings.initialized then SettingsManager.initializePersistentStorage() end

    local unitDef = UnitDefs[Spring.GetUnitDefID(unitId)]
    local unitName = unitDef.name

    -- Get settings for this unit if they exist
    local settings = STATE.settings.weaponSettings:get(unitName)

    if settings then
        CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_FORWARD = settings.FORWARD
        CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_HEIGHT = settings.HEIGHT
        CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_SIDE = settings.SIDE
        CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_ROTATION = settings.ROTATION

        Log.trace("Loaded weapon settings for " .. unitName)
        return true
    else
        Log.trace("No weapon settings found for " .. unitName)
        return false
    end
end

return {
    SettingsManager = SettingsManager
}