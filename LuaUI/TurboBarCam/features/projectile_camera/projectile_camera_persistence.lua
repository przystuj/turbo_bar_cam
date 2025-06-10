---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local Log = ModuleManager.Log(function(m) Log = m end, "ProjectileCameraPersistence")
local SettingsManager = ModuleManager.SettingsManager(function(m) SettingsManager = m end)

---@class ProjectileCameraPersistence
local ProjectileCameraPersistence = {}

local STORAGE_NAME = "projectile_camera_settings"

--- Saves projectile camera settings for a specific unit type
---@param unitName string The name of the unit type
---@param settings table The settings table to save {FOLLOW = {...}, STATIC = {...}}
---@return boolean success Whether saving was successful
function ProjectileCameraPersistence.saveSettings(unitName, settings)
    if not unitName or not settings then
        Log:warn("ProjectileCameraPersistence: Cannot save - unitName or settings missing.")
        return false
    end

    local success = SettingsManager.saveUserSetting(STORAGE_NAME, unitName, settings)
    if success then
        Log:trace("ProjectileCameraPersistence: Saved settings for " .. unitName)
    else
        Log:error("ProjectileCameraPersistence: Failed to save settings for " .. unitName)
    end
    return success
end

--- Loads projectile camera settings for a specific unit type
---@param unitName string The name of the unit type
---@return table|nil settings The loaded settings table, or nil if not found
function ProjectileCameraPersistence.loadSettings(unitName)
    if not unitName then
        Log:warn("ProjectileCameraPersistence: Cannot load - unitName missing.")
        return nil
    end

    local settings = SettingsManager.loadUserSetting(STORAGE_NAME, unitName)
    if settings then
        Log:trace("ProjectileCameraPersistence: Loaded settings for " .. unitName)
        return settings
    else
        Log:trace("ProjectileCameraPersistence: No settings found for " .. unitName)
        return nil
    end
end

return ProjectileCameraPersistence