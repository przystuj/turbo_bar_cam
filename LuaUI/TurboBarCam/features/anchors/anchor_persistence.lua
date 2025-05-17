---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/settings/settings_manager.lua").SettingsManager

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log

---@class CameraAnchorPersistence
local CameraAnchorPersistence = {}

-- Function to get the map name without version number
-- Removes version patterns like "1.2.3" or "V1.2.3" from the end of map names
local function getCleanMapName()
    local mapName = Game.mapName

    -- Remove version numbers at the end (patterns like 1.2.3 or V1.2.3)
    local cleanName = mapName:gsub("%s+[vV]?%d+%.?%d*%.?%d*$", "")

    return cleanName
end

--- Serializes the current camera anchors to a storable format
---@return table serializedData Serialized anchors data
local function serializeAnchors()
    local data = {
        anchors = {}
    }

    -- Serialize anchors
    for id, anchorState in pairs(STATE.anchors) do
        data.anchors[tostring(id)] = {
            px = anchorState.px,
            py = anchorState.py,
            pz = anchorState.pz,
            rx = anchorState.rx,
            ry = anchorState.ry,
            rz = anchorState.rz,
            dx = anchorState.dx,
            dy = anchorState.dy,
            dz = anchorState.dz
        }
    end

    return data
end

--- Deserializes and loads anchors from stored data
---@param data table Stored anchor data
---@return boolean success Whether loading was successful
local function deserializeAnchors(data)
    if not data then
        return false
    end

    -- Clear current anchors if we're loading new ones
    if data.anchors and next(data.anchors) then
        STATE.anchors = {}

        -- Load anchors
        for idStr, anchorData in pairs(data.anchors) do
            local id = tonumber(idStr)
            if id and id >= 0 and id <= 9 then
                STATE.anchors[id] = {
                    mode = 0,
                    name = "fps",
                    px = anchorData.px,
                    py = anchorData.py,
                    pz = anchorData.pz,
                    rx = anchorData.rx,
                    ry = anchorData.ry,
                    rz = anchorData.rz,
                    dx = anchorData.dx,
                    dy = anchorData.dy,
                    dz = anchorData.dz
                }
                Log.info("Loaded anchor " .. id)
            end
        end
    end

    return true
end

--- Saves current anchors to a settings file, organized by map
---@param anchorSetId string Identifier for the saved configuration
---@param includeQueue boolean Ignored parameter (kept for backward compatibility)
---@return boolean success Whether saving was successful
function CameraAnchorPersistence.saveToFile(anchorSetId, includeQueue)
    if not anchorSetId or anchorSetId == "" then
        Log.warn("Cannot save - no identifier specified")
        return false
    end

    -- Check if we have any anchors to save
    local anchorCount = 0
    for _ in pairs(STATE.anchors) do
        anchorCount = anchorCount + 1
    end

    if anchorCount == 0 then
        Log.warn("No anchors to save")
        return false
    end

    -- Serialize the data
    local data = serializeAnchors()

    -- Get clean map name
    local mapName = getCleanMapName()

    -- Load existing camera presets for all maps
    local mapPresets = SettingsManager.loadUserSetting("anchors", mapName) or {}

    -- Save preset for current map
    mapPresets[anchorSetId] = data

    -- Save the entire structure back to storage
    local success = SettingsManager.saveUserSetting("anchors", mapName, mapPresets)

    if success then
        Log.info(string.format("Saved %d anchors with ID: %s for map: %s",
                anchorCount, anchorSetId, mapName))
    else
        Log.error("Failed to save configuration")
    end

    return success
end

--- Loads anchors from a settings file for the current map
---@param id string Identifier for the saved configuration
---@return boolean success Whether loading was successful
function CameraAnchorPersistence.loadFromFile(id)
    if not id or id == "" then
        Log.warn("Cannot load - no identifier specified")
        return false
    end

    -- Get clean map name
    local mapName = getCleanMapName()

    -- Load all map presets
    local mapPresets = SettingsManager.loadUserSetting("anchors", mapName)

    -- Check if we have presets for this map
    if not mapPresets or not mapPresets[id] then
        Log.warn("No saved configuration found with ID: " .. id .. " for map: " .. mapName)
        return false
    end

    -- Get data for this specific preset
    local data = mapPresets[id]

    -- Deserialize and load the data
    local success = deserializeAnchors(data)

    if success then
        Log.info("Successfully loaded configuration with ID: " .. id .. " for map: " .. mapName)
    else
        Log.error("Failed to load configuration with ID: " .. id)
    end

    return success
end

--- Lists all maps that have saved presets
---@return boolean success Whether any maps with presets were found
function CameraAnchorPersistence.listAllMapsWithPresets()
    -- Load all map presets
    local allMapPresets = SettingsManager.loadUserSetting("anchors")

    -- Check if we have any presets
    if not allMapPresets or not next(allMapPresets) then
        Log.info("No saved camera presets found for any maps")
        return false
    end

    -- Display all maps with presets
    Log.info("Maps with saved camera presets:")
    for mapName, mapPresets in pairs(allMapPresets) do
        local presetCount = 0
        for _ in pairs(mapPresets) do
            presetCount = presetCount + 1
        end

        Log.info(string.format("  - %s: %d presets", mapName, presetCount))
    end

    return true
end

return {
    CameraAnchorPersistence = CameraAnchorPersistence
}