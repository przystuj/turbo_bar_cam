---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local SettingsManager = ModuleManager.SettingsManager(function(m) SettingsManager = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "UnitFollowPersistence")

---@class UnitFollowPersistence
local UnitFollowPersistence = {}

local function getUnitName(unitId)
    local unitDefId = Spring.GetUnitDefID(unitId)
    local unitDef = UnitDefs[unitDefId]
    local unitName = unitDef and unitDef.name

    if not unitName then
        Log:warn("Cannot save settings - invalid unit id")
    end
    return unitName
end

---@param unitId number Unit ID
function UnitFollowPersistence.saveUnitSettings(_, unitId)
    local function saveOffsets(mode, unitName)
        local storageName = "unit_follow_" .. string.lower(mode) .. "_offsets"
        SettingsManager.saveUserSetting(storageName, unitName, CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS[mode])
    end

    local unitName = getUnitName(unitId)

    if not unitName then
        return
    end

    saveOffsets("DEFAULT", unitName)
    saveOffsets("COMBAT", unitName)
    saveOffsets("WEAPON", unitName)

    local settings = SettingsManager.loadUserSetting("unit_follow_settings", unitName, {})
    settings.attack_state_cooldown = CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.ATTACK_STATE_COOLDOWN

    -- Resetting the chosen weapon should not affect the saved setting
    if CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.FORCED_WEAPON_NUMBER then
        settings.forced_weapon_number = CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.FORCED_WEAPON_NUMBER
    end

    SettingsManager.saveUserSetting("unit_follow_settings", unitName, settings)
end

---@param unitId number Unit ID
function UnitFollowPersistence.loadUnitSettings(_, unitId)
    local function loadOffsets(mode, unitName)
        local storageName = "unit_follow_" .. string.lower(mode) .. "_offsets"
        local settings = SettingsManager.loadUserSetting(storageName, unitName, CONFIG.CAMERA_MODES.UNIT_FOLLOW.DEFAULT_OFFSETS[mode])
        TableUtils.patchTable(CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS[mode], settings)
    end

    local unitName = getUnitName(unitId)

    loadOffsets("DEFAULT", unitName)
    loadOffsets("COMBAT", unitName)
    loadOffsets("WEAPON", unitName)

    local settings = SettingsManager.loadUserSetting("unit_follow_settings", unitName, {})

    CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.ATTACK_STATE_COOLDOWN = settings.attack_state_cooldown or
            SettingsManager.loadUserSetting("unit_follow_attack_state_cooldown", unitName) or
            CONFIG.CAMERA_MODES.UNIT_FOLLOW.DEFAULT_OFFSETS.ATTACK_STATE_COOLDOWN

    CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.FORCED_WEAPON_NUMBER = settings.forced_weapon_number or
            CONFIG.CAMERA_MODES.UNIT_FOLLOW.DEFAULT_OFFSETS.FORCED_WEAPON_NUMBER

    if STATE.active.mode.name == "unit_follow" and STATE.active.mode.unit_follow then
        STATE.active.mode.unit_follow.forcedWeaponNumber = CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS.FORCED_WEAPON_NUMBER
    end
end

STATE.settings.loadModeSettingsFn.unit_follow = UnitFollowPersistence.loadUnitSettings
STATE.settings.saveModeSettingsFn.unit_follow = UnitFollowPersistence.saveUnitSettings

return UnitFollowPersistence
