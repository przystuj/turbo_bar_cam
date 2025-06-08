---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local SettingsManager = ModuleManager.SettingsManager(function(m) SettingsManager = m end)
local Log = ModuleManager.Log(function(m) Log = m end)

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
end

---@param unitId number Unit ID
function UnitFollowPersistence.loadUnitSettings(_, unitId)
    local function loadOffsets(mode, unitName)
        local storageName = "unit_follow_" .. string.lower(mode) .. "_offsets"
        local settings = SettingsManager.loadUserSetting(storageName, unitName, CONFIG.CAMERA_MODES.UNIT_FOLLOW.DEFAULT_OFFSETS[mode])
        Utils.patchTable(CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS[mode], settings)
    end

    local unitName = getUnitName(unitId)

    loadOffsets("DEFAULT", unitName)
    loadOffsets("COMBAT", unitName)
    loadOffsets("WEAPON", unitName)
end

STATE.settings.loadModeSettingsFn.unit_follow = UnitFollowPersistence.loadUnitSettings
STATE.settings.saveModeSettingsFn.unit_follow = UnitFollowPersistence.saveUnitSettings

return UnitFollowPersistence
