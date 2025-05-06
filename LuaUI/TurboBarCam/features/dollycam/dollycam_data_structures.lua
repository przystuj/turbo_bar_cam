---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE

---@class DollyCamDataStructures
local DollyCamDataStructures = {}

---@class DollyCamWaypoint
---@field position table {x, y, z}
---@field rotation table {rx, ry, rz} Camera rotation at this waypoint
---@field tension number Controls curve tightness (0.0-1.0)
---@field time number Parameterized time value (calculated)

---@class DollyCamRoute
---@field points DollyCamWaypoint[] User-defined waypoints
---@field path table[] Interpolated points forming the complete path
---@field segments table[][] Path divided into segments between waypoints
---@field totalDistance number Total path length for navigation
---@field segmentDistances number[] Length of each segment
---@field name string Optional name for the route
---@field knotVector table Parameterized knot vector for Catmull-Rom

-- Create a new waypoint at the given position
---@param position table {x, y, z} Position for the waypoint
---@param tension number|nil Optional tension value (0.0-1.0)
---@return DollyCamWaypoint waypoint The created waypoint
function DollyCamDataStructures.createWaypoint(position, tension)
    local waypoint = {
        position = {
            x = position.x,
            y = position.y,
            z = position.z
        },
        tension = tension or 0.5, -- Default tension value
        time = nil -- Will be calculated during knot vector creation
    }
    
    return waypoint
end

-- Remove a waypoint from a route
---@param route DollyCamRoute Route to remove waypoint from
---@param index number Index of waypoint to remove
---@return boolean success Whether the waypoint was removed
function DollyCamDataStructures.removeWaypoint(route, index)
    if not route or not route.points then
        return false
    end
    
    if index < 1 or index > #route.points then
        Log.warn("Invalid waypoint index: " .. index)
        return false
    end
    
    -- Don't allow removing the last waypoint
    if #route.points <= 1 then
        Log.warn("Cannot remove the last waypoint")
        return false
    end
    
    table.remove(route.points, index)
    return true
end

-- Serialize a route to a string for saving
---@return string serialized Serialized route data
function DollyCamDataStructures.serializeRoute()
    local serialized = {
        points = {}
    }
    
    for i, point in ipairs(STATE.dollyCam.route.points) do
        serialized.points[i] = {
            position = {
                x = point.position.x,
                y = point.position.y,
                z = point.position.z
            },
            tension = point.tension
        }
    end
    
    return serialized
end

-- Deserialize a route from a string
---@param serialized string Serialized route data
---@return DollyCamRoute|nil route The deserialized route, or nil if invalid
function DollyCamDataStructures.deserializeRoute(serialized)
    if not serialized then
        Log.warn("Failed to deserialize route data")
        return nil
    end
    
    local route = {
        points = {},
        path = {},
        segments = {},
        totalDistance = 0,
        segmentDistances = {},
        knotVector = {}
    }
    
    for i, pointData in ipairs(serialized.points) do
        local point = {
            position = {
                x = pointData.position.x,
                y = pointData.position.y,
                z = pointData.position.z
            },
            tension = pointData.tension or 0.5
        }
        
        table.insert(route.points, point)
    end
    
    return route
end

return {
    DollyCamDataStructures = DollyCamDataStructures
}
