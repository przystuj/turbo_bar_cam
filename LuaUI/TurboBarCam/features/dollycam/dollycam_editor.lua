---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua")
---@type DollyCamPathPlanner
local DollyCamPathPlanner = VFS.Include("LuaUI/TurboBarCam/features/dollycam/dollycam_path_planner.lua").DollyCamPathPlanner
---@type DollyCamDataStructures
local DollyCamDataStructures = VFS.Include("LuaUI/TurboBarCam/features/dollycam/dollycam_data_structures.lua").DollyCamDataStructures

local STATE = WidgetContext.STATE

---@class DollyCamEditor
local DollyCamEditor = {}

-- Selection threshold for editing waypoints (distance in world units)
DollyCamEditor.SELECTION_THRESHOLD = 200

-- Add a waypoint at the current camera position
---@return boolean success Whether the waypoint was added
---@return number|nil index Index of the added waypoint, or nil if failed
function DollyCamEditor.addWaypointAtPosition(position)
    STATE.dollyCam.route = STATE.dollyCam.route or { points = {} }

    -- If we're navigating, find the best insertion point
    local insertIndex = #STATE.dollyCam.route.points + 1

    if STATE.dollyCam.isNavigating then
        Log.debug("Can't edit route while navigating")
        return
    end

    -- Insert the new waypoint
    local waypoint = DollyCamDataStructures.createWaypoint(position)
    table.insert(STATE.dollyCam.route.points, insertIndex, waypoint)

    -- Regenerate the path
    DollyCamPathPlanner.generateSmoothPath()

    Log.info(string.format("Added waypoint at position (%.1f, %.1f, %.1f) at index %d",
            position.x, position.y, position.z, insertIndex))

    return true, insertIndex
end

-- Edit a waypoint's position and rotation
---@param waypointIndex number Index of the waypoint to edit
---@param newPosition table|nil New position {x, y, z}, or nil to use current camera position
---@param newRotation table|nil New rotation {rx, ry, rz}, or nil to use current camera rotation
---@return boolean success Whether the waypoint was edited
function DollyCamEditor.editWaypoint(waypointIndex, newPosition, newRotation)
    if not STATE.dollyCam.route.points[waypointIndex] then
        Log.warn("Cannot edit waypoint: Invalid waypoint index: " .. waypointIndex)
        return false
    end

    if not newPosition or not newRotation then
        local camState = Spring.GetCameraState()

        newPosition = newPosition or {
            x = camState.px,
            y = camState.py,
            z = camState.pz
        }
    end

    -- Update the waypoint data
    STATE.dollyCam.route.points[waypointIndex].position = {
        x = newPosition.x,
        y = newPosition.y,
        z = newPosition.z
    }

    -- Regenerate the path
    DollyCamPathPlanner.generateSmoothPath()
    return true
end

-- Delete a waypoint
---@param waypointIndex number Index of the waypoint to delete
---@return boolean success Whether the waypoint was deleted
function DollyCamEditor.deleteWaypoint(waypointIndex)
    if not STATE.dollyCam.route.points[waypointIndex] then
        Log.warn("Cannot delete waypoint: Invalid waypoint index: " .. waypointIndex)
        return false
    end

    -- Don't allow deleting if only 2 waypoints remain
    if #STATE.dollyCam.route.points <= 2 then
        Log.warn("Cannot delete waypoint: Route needs at least 2 waypoints")
        return false
    end

    -- Store the waypoint position for logging
    local position = STATE.dollyCam.route.points[waypointIndex].position

    -- Remove the waypoint
    table.remove(STATE.dollyCam.route.points, waypointIndex)

    -- Regenerate the path
    DollyCamPathPlanner.generateSmoothPath()

    Log.info(string.format("Deleted waypoint %d at (%.1f, %.1f, %.1f)",
            waypointIndex, position.x, position.y, position.z))

    return true
end

-- Adjust a waypoint's tension
---@param waypointIndex number Index of the waypoint to adjust
---@param newTension number New tension value (0.0-1.0)
---@return boolean success Whether the tension was adjusted
function DollyCamEditor.adjustWaypointTension(waypointIndex, newTension)
    if not STATE.dollyCam.route.points[waypointIndex] then
        Log.warn("Cannot adjust waypoint tension: Invalid waypoint index: " .. waypointIndex)
        return false
    end

    -- Clamp tension to valid range
    newTension = math.max(0.0, math.min(1.0, newTension))

    -- Store the original tension for logging
    local oldTension = STATE.dollyCam.route.points[waypointIndex].tension

    -- Update the waypoint tension
    STATE.dollyCam.route.points[waypointIndex].tension = newTension

    -- Regenerate the path
    DollyCamPathPlanner.generateSmoothPath()

    Log.info(string.format("Adjusted waypoint %d tension from %.2f to %.2f",
            waypointIndex, oldTension, newTension))

    return true
end

-- Find the closest waypoint to edit
---@param position table Position to search from {x, y, z}, or nil to use current camera position
---@return number|nil waypointIndex Index of closest waypoint, or nil if none within threshold
---@return number|nil distance Distance to the closest waypoint, or nil if none found
function DollyCamEditor.findClosestWaypointToEdit(position)
    local threshold = 200

    -- If no position provided, use current camera position
    if not position then
        local camState = Spring.GetCameraState()
        position = {
            x = camState.px,
            y = camState.py,
            z = camState.pz
        }
    end

    -- Find closest waypoint
    local closestIndex, closestDist = DollyCamPathPlanner.findClosestWaypoint(position)

    -- Check if within threshold
    if closestIndex and closestDist <= threshold then
        return closestIndex, closestDist
    end

    return nil, nil
end

local function addOrEditWaypointAtPosition(position)
    -- Check if we're near an existing waypoint
    local closestIndex = DollyCamEditor.findClosestWaypointToEdit(position)

    if closestIndex then
        -- Edit existing waypoint
        DollyCamEditor.editWaypoint(closestIndex, position)
        return true, "edited", closestIndex
    else
        -- Add new waypoint
        local success, index = DollyCamEditor.addWaypointAtPosition(position)
        return success, "added", index
    end
end

function DollyCamEditor.addOrEditWaypointAtMousePosition()
    local mx, my = Spring.GetMouseState()
    local _, pos = Spring.TraceScreenRay(mx, my, true)
    local position = { x = pos[1], y = pos[2], z = pos[3] }

    return addOrEditWaypointAtPosition(position)
end

-- Add or edit waypoint at current position
---@return boolean success Whether a waypoint was added or edited
---@return string action The action performed ("added" or "edited")
---@return number|nil waypointIndex Index of the added or edited waypoint, or nil if failed
function DollyCamEditor.addOrEditWaypointAtCurrentPosition()
    -- Get current camera position
    local camState = Spring.GetCameraState()
    local position = {
        x = camState.px,
        y = camState.py,
        z = camState.pz
    }

    return addOrEditWaypointAtPosition(position)
end

return {
    DollyCamEditor = DollyCamEditor
}