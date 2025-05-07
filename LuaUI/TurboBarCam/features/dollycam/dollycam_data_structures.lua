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
        time = nil, -- Will be calculated during knot vector creation
        targetSpeed = 1.0, -- Default target speed
        hasLookAt = false, -- Default to no lookAt
        lookAtPoint = nil, -- Will be set if needed
        lookAtUnitID = nil -- Will be set if tracking a unit
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

function DollyCamDataStructures.serializeRoute()
    local serialized = {
        points = {}
    }

    for i, point in ipairs(STATE.dollyCam.route.points) do
        local pointData = {
            position = {
                x = point.position.x,
                y = point.position.y,
                z = point.position.z
            },
            tension = point.tension,
            targetSpeed = point.targetSpeed
        }

        -- Add lookAt properties if present
        if point.hasLookAt then
            pointData.hasLookAt = true

            if point.lookAtPoint then
                pointData.lookAtPoint = {
                    x = point.lookAtPoint.x,
                    y = point.lookAtPoint.y,
                    z = point.lookAtPoint.z
                }
            end

            if point.lookAtUnitID then
                pointData.lookAtUnitID = point.lookAtUnitID
            end
        end

        serialized.points[i] = pointData
    end

    return serialized
end

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
            tension = pointData.tension or 0.5,
            targetSpeed = pointData.targetSpeed or 1.0,
            hasLookAt = pointData.hasLookAt or false
        }

        -- Deserialize lookAt properties if present
        if pointData.hasLookAt then
            if pointData.lookAtPoint then
                point.lookAtPoint = {
                    x = pointData.lookAtPoint.x,
                    y = pointData.lookAtPoint.y,
                    z = pointData.lookAtPoint.z
                }
            end

            if pointData.lookAtUnitID then
                point.lookAtUnitID = pointData.lookAtUnitID
            end
        end

        table.insert(route.points, point)
    end

    return route
end

return {
    DollyCamDataStructures = DollyCamDataStructures
}
