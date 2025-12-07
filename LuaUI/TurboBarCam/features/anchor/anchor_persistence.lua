---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "CameraAnchorPersistence")
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local WorldUtils = ModuleManager.WorldUtils(function(m) WorldUtils = m end)
local SettingsManager = ModuleManager.SettingsManager(function(m) SettingsManager = m end)

---@class CameraAnchorPersistence
local CameraAnchorPersistence = {}

--- Saves current anchors to a settings file, organized by map
---@param anchorSetId string Identifier for the saved configuration
---@return boolean success Whether saving was successful
function CameraAnchorPersistence.saveToFile(anchorSetId)
    if not anchorSetId or anchorSetId == "" then
        Log:info("No id specified - saving as default")
        anchorSetId = "default"
    end

    -- Check if we have any anchors to save
    if TableUtils.tableCount(STATE.anchor.points) == 0 then
        Log:warn("No anchors to save")
        return false
    end

    -- Get clean map name
    local mapName = WorldUtils.getCleanMapName()

    -- Load existing camera presets for all maps
    local mapPresets = SettingsManager.loadUserSetting("anchors", mapName) or {}

    -- Save preset for current map
    mapPresets[anchorSetId] = STATE.anchor.points

    -- Save the entire structure back to storage
    local success = SettingsManager.saveUserSetting("anchors", mapName, mapPresets)

    if success then
        Log:info(string.format("Saved anchor set with ID: %s for map: %s", anchorSetId, mapName))
    else
        Log:error("Failed to save configuration")
    end

    return success
end

--- Loads anchors from a settings file for the current map
---@param id string Identifier for the saved configuration
---@return boolean success Whether loading was successful
function CameraAnchorPersistence.loadFromFile(id, isInit)
    if not id or id == "" then
        Log:info("No id specified - loading default")
        id = "default"
    end

    -- Get clean map name
    local mapName = WorldUtils.getCleanMapName()

    -- Load all map presets
    local mapPresets = SettingsManager.loadUserSetting("anchors", mapName)

    -- Check if we have presets for this map
    if not mapPresets or not mapPresets[id] then
        if not isInit then
            Log:warn("No saved configuration found with ID: " .. id .. " for map: " .. mapName)
        end
        return false
    end

    STATE.anchor.points = mapPresets[id]

    Log:info("Loaded ID: " .. id .. " for map: " .. mapName)
    return true
end

return CameraAnchorPersistence
