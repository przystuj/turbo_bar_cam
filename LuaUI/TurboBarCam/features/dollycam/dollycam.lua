---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua")
---@type Util
local Util = VFS.Include("LuaUI/TurboBarCam/common/utils.lua")
---@type ModeManager
local ModeManager = VFS.Include("LuaUI/TurboBarCam/common/mode_manager.lua")
---@type DollyCamPathPlanner
local DollyCamPathPlanner = VFS.Include("LuaUI/TurboBarCam/features/dollycam/dollycam_path_planner.lua").DollyCamPathPlanner
---@type DollyCamNavigator
local DollyCamNavigator = VFS.Include("LuaUI/TurboBarCam/features/dollycam/dollycam_navigator.lua").DollyCamNavigator
---@type DollyCamEditor
local DollyCamEditor = VFS.Include("LuaUI/TurboBarCam/features/dollycam/dollycam_editor.lua").DollyCamEditor
---@type DollyCamDataStructures
local DollyCamDataStructures = VFS.Include("LuaUI/TurboBarCam/features/dollycam/dollycam_data_structures.lua").DollyCamDataStructures
---@type DollyCamVisualization
local DollyCamVisualization = VFS.Include("LuaUI/TurboBarCam/features/dollycam/dollycam_visualization.lua").DollyCamVisualization
---@type DollyCamWaypointEditor
local DollyCamWaypointEditor = VFS.Include("LuaUI/TurboBarCam/features/dollycam/dollycam_waypoint_editor.lua").DollyCamWaypointEditor
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/core/settings_manager.lua")

local STATE = WidgetContext.STATE

-- Initialize STATE.dollyCam if not already done
STATE.dollyCam = STATE.dollyCam or {}
STATE.dollyCam.isEditing = STATE.dollyCam.isEditing or false

---@class DollyCam
local DollyCam = {}

-- Define key constants
DollyCam.KEYS = {
    LEFT = 276,
    RIGHT = 275,
    UP = 273,
    DOWN = 274,
    PAGEUP = 280,
    PAGEDOWN = 281
}

---@return boolean success Whether the waypoint was added
function DollyCam.addCurrentPositionToRoute()
    if Util.isTurboBarCamDisabled() then
        return false
    end

    local success, action = DollyCamEditor.addOrEditWaypointAtCurrentPosition()

    if success then
        if STATE.dollyCam.route and #STATE.dollyCam.route.points >= 2 then
            DollyCamPathPlanner.generateSmoothPath()
            Log.debug("Regenerated path for active route after waypoint " .. action)
            STATE.dollyCam.visualizationEnabled = true
        end
    end

    return success
end

function DollyCam.setWaypointLookAtUnit()
    if Util.isTurboBarCamDisabled() then
        return false
    end

    DollyCamWaypointEditor.setWaypointLookAtUnit()
end

function DollyCam.setWaypointTargetSpeed(speed)
    if Util.isTurboBarCamDisabled() then
        return false
    end

    if tonumber(speed) == 1 then
        DollyCamWaypointEditor.resetWaypointSpeed()
    else
        DollyCamWaypointEditor.setWaypointTargetSpeed(speed)
    end
end

-- Delete a waypoint by index
---@param waypointIndex number Index of the waypoint to delete
---@return boolean success Whether the waypoint was deleted
function DollyCam.deleteWaypoint(waypointIndex)
    if Util.isTurboBarCamDisabled() then
        return false
    end

    return DollyCamEditor.deleteWaypoint(waypointIndex)
end

-- Update the DollyCam system state
---@param deltaTime number Time since last update in seconds
---@return boolean active Whether the DollyCam system is active
function DollyCam.update(deltaTime)
    if Util.isTurboBarCamDisabled() then
        return
    end

    -- Only update navigation if it's active
    if STATE.dollyCam.isNavigating then
        return DollyCamNavigator.update(deltaTime)
    end
end

-- Draw function called in DrawWorld
function DollyCam.draw()
    if not STATE.dollyCam.visualizationEnabled then
        return
    end
    DollyCamVisualization.draw()
end

-- Save a route to a file
---@param name string ID of the route to save
---@return boolean success Whether the route was saved
function DollyCam.saveRoute(name)
    if Util.isTurboBarCamDisabled() then
        return false
    end

    -- Serialize the route
    local routeData = DollyCamDataStructures.serializeRoute()

    -- Get clean map name
    local mapName = Util.getCleanMapName()

    -- Load existing camera presets for all maps
    local mapPresets = SettingsManager.loadUserSetting("dollycam", mapName) or {}

    -- Save preset for current map
    mapPresets[name] = routeData

    -- Save the entire structure back to storage
    local success = SettingsManager.saveUserSetting("dollycam", mapName, mapPresets)

    if success then
        Log.info(string.format("Saved route %s for map: %s", name, mapName))
    else
        Log.error("Failed to save")
    end
    return true
end

-- Load a route from a file
---@param name string Filename to load from
---@return string|nil routeId ID of the loaded route, or nil if loading failed
function DollyCam.loadRoute(name)
    if Util.isTurboBarCamDisabled() then
        return nil
    end

    -- Get clean map name
    local mapName = Util.getCleanMapName()

    local mapPresets = SettingsManager.loadUserSetting("dollycam", mapName)

    -- Check if we have presets for this map
    if not mapPresets or not mapPresets[name] then
        Log.warn("No saved route " .. name .. " for map: " .. mapName)
        return false
    end

    -- Deserialize the route
    local route = DollyCamDataStructures.deserializeRoute(mapPresets[name])

    if route then
        Log.info("Successfully loaded route " .. name .. " for map: " .. mapName)
    else
        Log.error("Failed to load route " .. name)
    end

    STATE.dollyCam.route = route

    -- Generate path
    DollyCamPathPlanner.generateSmoothPath()
    return name
end

-- Toggle navigation on a route
---@return boolean success Whether navigation was started
function DollyCam.toggleNavigation(noCam)
    if Util.isTurboBarCamDisabled() then
        return false
    end

    -- If in editing mode, disable it before navigating
    if STATE.dollyCam.isEditing then
        DollyCamWaypointEditor.disable()
    end

    -- Stop navigating if active
    if STATE.dollyCam.isNavigating then
        DollyCamNavigator.stopNavigation()
        return
    end

    -- Stop tracking if active
    if STATE.mode.name then
        ModeManager.disableMode()
    end

    return DollyCamNavigator.startNavigation(noCam == "true" or false)
end

-- Set navigation speed
---@param speed number Speed from -1.0 (full reverse) to 1.0 (full forward)
---@return boolean success Whether speed was set
function DollyCam.adjustSpeed(speed)
    if Util.isTurboBarCamDisabled() then
        return false
    end

    if not STATE.dollyCam.isNavigating then
        Log.trace("Cannot set speed: Not currently navigating")
        return false
    end

    return DollyCamNavigator.adjustSpeed(speed)
end

-- Set navigation speed
---@param direction number Reverse: -1.0, Forward: 1.0
---@return boolean success Whether speed was set
function DollyCam.setDirection(direction)
    if Util.isTurboBarCamDisabled() then
        return false
    end

    if not STATE.dollyCam.isNavigating then
        Log.trace("Cannot set direction: Not currently navigating")
        return false
    end

    if direction ~= "-1" and direction ~= "1" then
        Log.warn("Wrong value. Only 1 and -1 is allowed")
        return false
    end

    STATE.dollyCam.direction = tonumber(direction)
    Log.debug("Direction set to " .. STATE.dollyCam.direction)
end

-- Set navigation speed
---@return boolean success Whether speed was set
function DollyCam.toggleDirection()
    if Util.isTurboBarCamDisabled() then
        return false
    end

    if not STATE.dollyCam.isNavigating then
        Log.trace("Cannot set direction: Not currently navigating")
        return false
    end

    STATE.dollyCam.direction = STATE.dollyCam.direction * -1
    Log.debug("Direction set to " .. STATE.dollyCam.direction)
end

-- Toggle waypoint editor mode
---@return boolean enabled Whether the editor was enabled
function DollyCam.toggleWaypointEditor()
    if Util.isTurboBarCamDisabled() then
        return false
    end

    -- If navigating, stop first
    if STATE.dollyCam.isNavigating then
        DollyCamNavigator.stopNavigation()
    end

    -- Toggle the waypoint editor
    return DollyCamWaypointEditor.toggle()
end

-- Move selected waypoint along an axis
---@param axis string Axis to move along: "x", "y", "z"
---@param value number Amount to move (positive or negative)
---@return boolean success Whether the waypoint was moved
function DollyCam.moveSelectedWaypoint(axis, value)
    if Util.isTurboBarCamDisabled() or not STATE.dollyCam.isEditing then
        return false
    end

    return DollyCamWaypointEditor.moveWaypointAlongAxis(axis, value)
end

function DollyCam.resetWaypointSpeed()
    if Util.isTurboBarCamDisabled() then
        return false
    end

    DollyCamWaypointEditor.resetWaypointSpeed()
end

function DollyCam.clearWaypointLookAt()
    if Util.isTurboBarCamDisabled() then
        return false
    end

    DollyCamWaypointEditor.clearWaypointLookAt()
end

-- todo remove at some point
function DollyCam.test()
    if Util.isTurboBarCamDisabled() then
        return false
    end

    DollyCam.loadRoute("test")
end

return {
    DollyCam = DollyCam
}