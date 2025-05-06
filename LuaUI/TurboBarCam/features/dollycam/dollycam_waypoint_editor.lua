---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log
---@type Util
local Util = VFS.Include("LuaUI/TurboBarCam/common/utils.lua").Util
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type MouseManager
local MouseManager = VFS.Include("LuaUI/TurboBarCam/standalone/mouse_manager.lua").MouseManager
---@type DollyCamPathPlanner
local DollyCamPathPlanner = VFS.Include("LuaUI/TurboBarCam/features/dollycam/dollycam_path_planner.lua").DollyCamPathPlanner
---@type DollyCamEditor
local DollyCamEditor = VFS.Include("LuaUI/TurboBarCam/features/dollycam/dollycam_editor.lua").DollyCamEditor
---@type DollyCamDataStructures
local DollyCamDataStructures = VFS.Include("LuaUI/TurboBarCam/features/dollycam/dollycam_data_structures.lua").DollyCamDataStructures

local STATE = WidgetContext.STATE

-- Initialize required STATE properties
STATE.dollyCam = STATE.dollyCam or {}
STATE.dollyCam.hoveredWaypointIndex = nil
STATE.dollyCam.selectedWaypointIndex = nil
STATE.dollyCam.hoveredPathPointIndex = nil
STATE.dollyCam.lastMouseScreenPos = { x = 0, y = 0 }
STATE.dollyCam.lastMouseWorldPos = { x = 0, y = 0, z = 0 }
STATE.dollyCam.movementSpeed = 1.0

---@class DollyCamWaypointEditor
local DollyCamWaypointEditor = {}

-- Constants
DollyCamWaypointEditor.WAYPOINT_SELECTION_THRESHOLD = 200 -- Distance in world units to highlight waypoint
DollyCamWaypointEditor.PATH_POINT_SELECTION_THRESHOLD = 150 -- Distance to highlight path points

-- Initialize the waypoint editor
function DollyCamWaypointEditor.initialize()
    -- Register mouse modes
    MouseManager.registerMode('waypointEditor')
    
    -- Register mouse handlers
    MouseManager.onLMB('waypointEditor', DollyCamWaypointEditor.handleLeftClick)
    MouseManager.onRMB('waypointEditor', DollyCamWaypointEditor.handleRightClick)
    
    -- Register mouse movement handler
    MouseManager.onMouseMove('waypointEditor', DollyCamWaypointEditor.handleMouseMove)

    STATE.tracking.mode = "waypointEditor"
    
    -- Set editing state
    STATE.dollyCam.isEditing = true
    STATE.dollyCam.visualizationEnabled = true
    Log.info("[DollyCam] Waypoint Editor enabled")
end

-- Clean up and disable the waypoint editor
function DollyCamWaypointEditor.disable()
    -- Reset editor state
    STATE.dollyCam.hoveredWaypointIndex = nil
    STATE.dollyCam.selectedWaypointIndex = nil
    STATE.dollyCam.hoveredPathPointIndex = nil
    
    -- Set editing state
    STATE.dollyCam.isEditing = false
    STATE.tracking.mode = nil
    
    Log.info("[DollyCam] Waypoint Editor disabled")
end

-- Toggle the waypoint editor on/off
function DollyCamWaypointEditor.toggle()
    if STATE.dollyCam.isEditing then
        DollyCamWaypointEditor.disable()
    else
        DollyCamWaypointEditor.initialize()
    end
    
    return STATE.dollyCam.isEditing
end

-- Update mouse position in world coordinates and find closest waypoint by ray casting
---@param mx number Mouse X coordinate on screen
---@param my number Mouse Y coordinate on screen
function DollyCamWaypointEditor.updateMouseWorldPosition(mx, my)
    -- Store screen position
    STATE.dollyCam.lastMouseScreenPos = { x = mx, y = my }

    -- Also store a world position for ground interaction
    local groundHit, groundX, groundY, groundZ = Spring.TraceScreenRay(mx, my, true)
    if groundHit and groundX then
        STATE.dollyCam.lastMouseWorldPos = { x = groundX, y = groundY, z = groundZ }
    else
        -- No hit, try using the far plane instead (sky ray)
        local skyHit, skyX, skyY, skyZ = Spring.TraceScreenRay(mx, my, false)
        if skyHit and skyX then
            STATE.dollyCam.lastMouseWorldPos = { x = skyX, y = skyY, z = skyZ }
        end
    end
end

-- Find closest waypoint to mouse cursor using improved methods
function DollyCamWaypointEditor.findClosestWaypointToMouse()
    if not STATE.dollyCam.route or not STATE.dollyCam.route.points or #STATE.dollyCam.route.points == 0 then
        return nil, math.huge
    end

    -- First, try the screen-space approach (most reliable)
    local closestIndex = nil
    local closestDist = math.huge
    local mouseX, mouseY = STATE.dollyCam.lastMouseScreenPos.x, STATE.dollyCam.lastMouseScreenPos.y

    -- Loop through waypoints to find closest in screen space
    for i, waypoint in ipairs(STATE.dollyCam.route.points) do
        -- Convert waypoint position to screen coordinates
        local screenX, screenY, visible = Spring.WorldToScreenCoords(
                waypoint.position.x,
                waypoint.position.y,
                waypoint.position.z
        )

        -- Only consider visible waypoints
        if visible and screenX and screenY then
            local dist = math.sqrt((screenX - mouseX)^2 + (screenY - mouseY)^2)

            if dist < closestDist then
                closestDist = dist
                closestIndex = i
            end
        end
    end

    -- If we found a waypoint in screen space...
    if closestIndex then
        -- Use a screen-space threshold (in pixels)
        local SCREEN_THRESHOLD = 30 -- pixels

        if closestDist <= SCREEN_THRESHOLD then
            return closestIndex, closestDist
        end
    end

    -- No waypoint found
    return nil, math.huge
end

-- Find closest path point to mouse cursor using improved methods
function DollyCamWaypointEditor.findClosestPathPointToMouse()
    if not STATE.dollyCam.route or not STATE.dollyCam.route.path or #STATE.dollyCam.route.path == 0 then
        return nil, math.huge
    end

    -- First, try the screen-space approach (most reliable)
    local closestIndex = nil
    local closestDist = math.huge
    local mouseX, mouseY = STATE.dollyCam.lastMouseScreenPos.x, STATE.dollyCam.lastMouseScreenPos.y

    -- Loop through path points to find closest in screen space
    for i, point in ipairs(STATE.dollyCam.route.path) do
        -- Convert point position to screen coordinates
        local screenX, screenY, visible = Spring.WorldToScreenCoords(
                point.x,
                point.y,
                point.z
        )

        -- Only consider visible points
        if visible and screenX and screenY then
            local dist = math.sqrt((screenX - mouseX)^2 + (screenY - mouseY)^2)

            if dist < closestDist then
                closestDist = dist
                closestIndex = i
            end
        end
    end

    -- If we found a path point in screen space...
    if closestIndex then
        -- Use a screen-space threshold (in pixels)
        local SCREEN_THRESHOLD = 20 -- pixels (smaller than waypoint threshold)

        if closestDist <= SCREEN_THRESHOLD then
            return closestIndex, closestDist
        end
    end

    -- No path point found
    return nil, math.huge
end

-- Handle mouse movement
---@param mx number Mouse X coordinate
---@param my number Mouse Y coordinate
function DollyCamWaypointEditor.handleMouseMove(mx, my)
    -- Update mouse world position
    DollyCamWaypointEditor.updateMouseWorldPosition(mx, my)
    
    -- Find closest waypoint to mouse
    local waypointIndex, waypointDist = DollyCamWaypointEditor.findClosestWaypointToMouse()
    STATE.dollyCam.hoveredWaypointIndex = waypointIndex
    
    -- Find closest path point to mouse (only if not hovering over a waypoint)
    if not waypointIndex then
        local pathPointIndex, pathPointDist = DollyCamWaypointEditor.findClosestPathPointToMouse()
        STATE.dollyCam.hoveredPathPointIndex = pathPointIndex
    else
        STATE.dollyCam.hoveredPathPointIndex = nil
    end
end

-- Handle left mouse button click
function DollyCamWaypointEditor.handleLeftClick()
    -- If hovering over a waypoint, select it
    if STATE.dollyCam.hoveredWaypointIndex then
        DollyCamWaypointEditor.selectWaypoint(STATE.dollyCam.hoveredWaypointIndex)
        return true
    end
    
    -- If hovering over a path point, add a new waypoint
    if STATE.dollyCam.hoveredPathPointIndex then
        DollyCamWaypointEditor.addWaypointAtPathPoint(STATE.dollyCam.hoveredPathPointIndex)
        return true
    end
    
    -- If clicking elsewhere, deselect current waypoint
    STATE.dollyCam.selectedWaypointIndex = nil
    return false
end

-- Handle middle mouse button click
function DollyCamWaypointEditor.handleMiddleClick()
    -- For now, just add a waypoint at the current camera position
    local success, action = DollyCamEditor.addOrEditWaypointAtCurrentPosition()
    
    if success then
        Log.info("Added new waypoint with MMB")
    end
    
    return success
end

-- Handle right mouse button click
function DollyCamWaypointEditor.handleRightClick()
    -- If hovering over a waypoint, delete it
    if STATE.dollyCam.hoveredWaypointIndex then
        DollyCamWaypointEditor.deleteSelectedWaypoint(STATE.dollyCam.hoveredWaypointIndex)
        return true
    end
    
    return false
end

-- Select a waypoint by index
---@param index number Index of the waypoint to select
function DollyCamWaypointEditor.selectWaypoint(index)
    if not STATE.dollyCam.route or not STATE.dollyCam.route.points or index < 1 or index > #STATE.dollyCam.route.points then
        return false
    end
    
    STATE.dollyCam.selectedWaypointIndex = index
    Log.info(string.format("Selected waypoint %d", index))
    return true
end

-- Delete the selected waypoint
---@param index number Index of the waypoint to delete
function DollyCamWaypointEditor.deleteSelectedWaypoint(index)
    if not STATE.dollyCam.route or not STATE.dollyCam.route.points or index < 1 or index > #STATE.dollyCam.route.points then
        return false
    end
    
    -- Don't allow deleting if only 2 waypoints remain
    if #STATE.dollyCam.route.points <= 2 then
        Log.warn("Cannot delete waypoint: Route needs at least 2 waypoints")
        return false
    end
    
    -- Delete the waypoint
    local success = DollyCamEditor.deleteWaypoint(index)
    
    if success then
        Log.info(string.format("Deleted waypoint %d", index))
        STATE.dollyCam.hoveredWaypointIndex = nil
        STATE.dollyCam.selectedWaypointIndex = nil
        
        -- Regenerate the path
        DollyCamPathPlanner.generateSmoothPath()
    end
    
    return success
end

-- Add a waypoint at a path point
---@param pathPointIndex number Index of the path point to add a waypoint at
function DollyCamWaypointEditor.addWaypointAtPathPoint(pathPointIndex)
    if not STATE.dollyCam.route or not STATE.dollyCam.route.path or pathPointIndex < 1 or pathPointIndex > #STATE.dollyCam.route.path then
        return false
    end
    
    -- Get the path point position
    local pathPoint = STATE.dollyCam.route.path[pathPointIndex]
    
    -- Create a new waypoint at this position
    local position = {
        x = pathPoint.x,
        y = pathPoint.y,
        z = pathPoint.z
    }
    
    -- Find the best insertion index
    local bestIndex = 1
    local bestDistance = math.huge
    
    -- Calculate traversed distances to find best insertion point
    local totalTraversed = 0
    
    for i, segmentDist in ipairs(STATE.dollyCam.route.segmentDistances) do
        local midSegmentDistance = totalTraversed + segmentDist / 2
        local distance = math.abs(midSegmentDistance - pathPointIndex * STATE.dollyCam.route.totalDistance / #STATE.dollyCam.route.path)
        
        if distance < bestDistance then
            bestDistance = distance
            bestIndex = i + 1
        end
        
        totalTraversed = totalTraversed + segmentDist
    end
    
    -- Create and insert the new waypoint
    local waypoint = DollyCamDataStructures.createWaypoint(position)
    table.insert(STATE.dollyCam.route.points, bestIndex, waypoint)
    
    -- Regenerate the path
    DollyCamPathPlanner.generateSmoothPath()
    
    -- Select the new waypoint
    DollyCamWaypointEditor.selectWaypoint(bestIndex)
    
    Log.info(string.format("Added waypoint at path point %d at position (%.1f, %.1f, %.1f)",
            pathPointIndex, position.x, position.y, position.z))
            
    return true
end

-- Move the selected waypoint along an axis
---@param axis string Axis to move along: "x", "y", "z"
---@param value number Amount to move (positive or negative)
function DollyCamWaypointEditor.moveWaypointAlongAxis(axis, value)
    local index = STATE.dollyCam.selectedWaypointIndex
    
    if not index or not STATE.dollyCam.route or not STATE.dollyCam.route.points or index < 1 or index > #STATE.dollyCam.route.points then
        return false
    end
    
    -- Get the waypoint
    local waypoint = STATE.dollyCam.route.points[index]
    
    -- Calculate movement amount
    local amount = value
    
    -- Update the waypoint position
    if axis == "x" then
        waypoint.position.x = waypoint.position.x + amount
    elseif axis == "y" then
        waypoint.position.y = waypoint.position.y + amount
    elseif axis == "z" then
        waypoint.position.z = waypoint.position.z + amount
    else
        Log.warn("Invalid axis: " .. axis)
        return false
    end
    
    -- Regenerate the path
    DollyCamPathPlanner.generateSmoothPath()
    
    return true
end

return {
    DollyCamWaypointEditor = DollyCamWaypointEditor
}
