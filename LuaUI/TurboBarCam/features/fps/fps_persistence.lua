---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Util = ModuleManager.Util(function(m) Util = m end)
local SettingsManager = ModuleManager.SettingsManager(function(m) SettingsManager = m end)
local Log = ModuleManager.Log(function(m) Log = m end)

---@class FPSPersistence
local FPSPersistence = {}

local function getUnitName(unitId)
    local unitDefId = Spring.GetUnitDefID(unitId)
    local unitDef = UnitDefs[unitDefId]
    local unitName = unitDef.name

    if not unitName then
        Log:warn("Cannot save settings - invalid unit id")
    end
    return unitName
end

---@param unitId number Unit ID
function FPSPersistence.saveUnitSettings(_, unitId)
    local function saveOffsets(mode, unitName)
        local storageName = "fps_" .. string.lower(mode) .. "_offsets"
        SettingsManager.saveUserSetting(storageName, unitName, Util.deepCopy(CONFIG.CAMERA_MODES.FPS.OFFSETS[mode]))
    end

    local unitName = getUnitName(unitId)

    if not unitName then
        return
    end

    saveOffsets("PEACE", unitName)
    saveOffsets("COMBAT", unitName)
    saveOffsets("WEAPON", unitName)
end

---@param unitId number Unit ID
function FPSPersistence.loadUnitSettings(_, unitId)
    local function loadOffsets(mode, unitName)
        local storageName = "fps_" .. string.lower(mode) .. "_offsets"
        local settings = SettingsManager.loadUserSetting(storageName, unitName) or CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS[mode]
        CONFIG.CAMERA_MODES.FPS.OFFSETS[mode] = Util.deepCopy(settings)
    end

    local unitName = getUnitName(unitId)

    loadOffsets("PEACE", unitName)
    loadOffsets("COMBAT", unitName)
    loadOffsets("WEAPON", unitName)
end

STATE.settings.loadModeSettingsFn.fps = FPSPersistence.loadUnitSettings
STATE.settings.saveModeSettingsFn.fps = FPSPersistence.saveUnitSettings

return FPSPersistence
