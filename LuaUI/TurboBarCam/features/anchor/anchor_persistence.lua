---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local Util = ModuleManager.Util(function(m) Util = m end)
local SettingsManager = ModuleManager.SettingsManager(function(m) SettingsManager = m end)

---@class CameraAnchorPersistence
local CameraAnchorPersistence = {}

--- Saves current anchors to a settings file, organized by map
---@param anchorSetId string Identifier for the saved configuration
---@return boolean success Whether saving was successful
function CameraAnchorPersistence.saveToFile(anchorSetId)
    if not anchorSetId or anchorSetId == "" then
        Log:warn("Cannot save - no identifier specified")
        return false
    end

    -- Check if we have any anchors to save
    Util.tableCount(STATE.anchor.points)

    if Util.tableCount(STATE.anchor.points) == 0 then
        Log:warn("No anchors to save")
        return false
    end

    -- Get clean map name
    local mapName = Util.getCleanMapName()

    -- Load existing camera presets for all maps
    local mapPresets = SettingsManager.loadUserSetting("anchors", mapName) or {}

    -- Save preset for current map
    mapPresets[anchorSetId] = STATE.anchor

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
function CameraAnchorPersistence.loadFromFile(id)
    if not id or id == "" then
        Log:warn("Cannot load - no identifier specified")
        return false
    end

    -- Get clean map name
    local mapName = Util.getCleanMapName()

    -- Load all map presets
    local mapPresets = SettingsManager.loadUserSetting("anchors", mapName)

    -- Check if we have presets for this map
    if not mapPresets or not mapPresets[id] then
        Log:warn("No saved configuration found with ID: " .. id .. " for map: " .. mapName)
        return false
    end

    local anchorSet = mapPresets[id]

    -- Check for and migrate old anchor format
    if anchorSet.points and #anchorSet.points > 0 then
        local firstPoint = anchorSet.points[1]
        if firstPoint and firstPoint.px and firstPoint.rx and not firstPoint.target then
            Log:info("Old anchor format detected. Migrating anchors for set '" .. id .. "'...")
            local newPoints = {}
            for i, oldAnchor in ipairs(anchorSet.points) do
                -- Calculate direction from old rotation (Euler ZYX: ry, rx, rz)
                local ry, rx = oldAnchor.ry or 0, oldAnchor.rx or 0
                local cos_rx = math.cos(rx)
                local dir_x = -math.sin(ry) * cos_rx
                local dir_y = math.sin(rx)
                local dir_z = math.cos(ry) * cos_rx

                -- Create a look-at point far away in the direction of the old camera view
                local DISTANCE = 10000
                local lookAt = {
                    x = oldAnchor.px + dir_x * DISTANCE,
                    y = oldAnchor.py + dir_y * DISTANCE,
                    z = oldAnchor.pz + dir_z * DISTANCE
                }

                newPoints[i] = {
                    position = { px = oldAnchor.px, py = oldAnchor.py, pz = oldAnchor.pz },
                    target = {
                        type = "point",
                        data = lookAt
                    },
                    fov = oldAnchor.fov,
                }
            end
            anchorSet.points = newPoints
            Log:info("Anchor migration complete. Please review and re-save your anchors if needed.")
        end
    end

    STATE.anchor = anchorSet

    Log:info("Loaded ID: " .. id .. " for map: " .. mapName .. ". Easing: " .. STATE.anchor.easing)
    return true
end

return CameraAnchorPersistence