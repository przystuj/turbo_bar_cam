---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log

local CONFIG = WidgetContext.CONFIG

---@class SettingsManager
local SettingsManager = {}

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

    Log.debug(string.format("Saving settings for %s=%s", CONFIG.PERSISTENT_UNIT_SETTINGS, identifier))

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

    Log.debug(string.format("Loading settings for %s=%s", CONFIG.PERSISTENT_UNIT_SETTINGS, identifier))

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
    local unitDef = UnitDefs[Spring.GetUnitDefID(unitId)]
    local unitName = unitDef.name

    Log.info("Saving weapon offsets for " .. unitName)

    local filePath = "LuaUI/TurboBarCam/weapon_settings.lua"
    local settings = {}

    -- Try to load existing settings
    local existingFile = io.open(filePath, "r")
    if existingFile then
        local content = existingFile:read("*all")
        existingFile:close()

        -- Execute the file content to get the settings table
        local func, err = loadstring(content)
        if func then
            local success, result = pcall(func)
            if success and type(result) == "table" then
                settings = result  -- This preserves all existing entries
                Log.debug("Loaded existing settings for " .. table.getn(settings) .. " units")
            else
                Log.warn("Error parsing existing settings file: " .. tostring(result))
            end
        else
            Log.warn("Error loading settings file: " .. tostring(err))
        end
    else
        Log.debug("Creating new weapon settings file")
    end

    -- Update settings with current unit's values
    settings[unitName] = {
        FORWARD = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_FORWARD,
        HEIGHT = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_HEIGHT,
        SIDE = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_SIDE,
        ROTATION = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_ROTATION
    }

    Log.debug("Added/updated settings for " .. unitName)

    -- Convert settings table to string with return statement
    local content = "return {\n"
    for unit, offsets in pairs(settings) do
        content = content .. string.format('  ["%s"] = {\n', unit)
        content = content .. string.format('    FORWARD = %s,\n', tostring(offsets.FORWARD))
        content = content .. string.format('    HEIGHT = %s,\n', tostring(offsets.HEIGHT))
        content = content .. string.format('    SIDE = %s,\n', tostring(offsets.SIDE))
        content = content .. string.format('    ROTATION = %s\n', tostring(offsets.ROTATION))
        content = content .. "  },\n"
    end
    content = content .. "}"

    -- Save to file
    local file = io.open(filePath, "w")
    if file then
        file:write(content)
        file:close()
        Log.info("Weapon settings saved to " .. filePath)
    else
        Log.error("Failed to save weapon settings to " .. filePath)
    end
end

function SettingsManager.loadWeaponSettings(unitId)
    local unitDef = UnitDefs[Spring.GetUnitDefID(unitId)]
    local unitName = unitDef.name

    local filePath = "LuaUI/TurboBarCam/weapon_settings.lua"

    -- Try to include the file directly
    local success, settings
    success, settings = pcall(function()
        return VFS.Include(filePath)
    end)

    if not success or type(settings) ~= "table" then
        Log.debug("No weapon settings file found or error loading settings")
        return false
    end

    -- Apply settings for this unit if they exist
    if settings[unitName] then
        CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_FORWARD = settings[unitName].FORWARD
        CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_HEIGHT = settings[unitName].HEIGHT
        CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_SIDE = settings[unitName].SIDE
        CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_ROTATION = settings[unitName].ROTATION

        Log.info("Loaded weapon settings for " .. unitName)
        return true
    else
        Log.debug("No weapon settings found for " .. unitName)
        return false
    end
end

return {
    SettingsManager = SettingsManager
}