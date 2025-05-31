---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log
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
STATE.dollyCam.selectedWaypoints = STATE.dollyCam.selectedWaypoints or {}
STATE.dollyCam.hoveredPathPointIndex = nil
STATE.dollyCam.lastMouseScreenPos = { x = 0, y = 0 }
STATE.dollyCam.lastMouseWorldPos = { x = 0, y = 0, z = 0 }
STATE.dollyCam.movementSpeed = 1.0

---@class DollyCamWaypointEditor
local DollyCamWaypointEditor = {}

-- Constants
DollyCamWaypointEditor.WAYPOINT_SELECTION_THRESHOLD = 200 -- Distance in world units to highlight waypoint
DollyCamWaypointEditor.PATH_POINT_SELECTION_THRESHOLD = 150 -- Distance to highlight path points
DollyCamWaypointEditor.DEFAULT_TARGET_SPEED = 1.0 -- Default target speed for new waypoints
DollyCamWaypointEditor.DEFAULT_LOOKAT_OFFSET = { x = 0, y = 0, z = 0 } -- Default lookAt offset

-- Initialize the waypoint editor
function DollyCamWaypointEditor.initialize()
    -- Register mouse modes
    MouseManager.registerMode('waypointEditor')

    -- Register mouse handlers
    MouseManager.onLMB('waypointEditor', DollyCamWaypointEditor.handleLeftClick)
    MouseManager.onDoubleLMB('waypointEditor', DollyCamWaypointEditor.handleLeftDoubleClick)
    MouseManager.onRMB('waypointEditor', DollyCamWaypointEditor.handleRightClick)
    MouseManager.onDoubleMMB('waypointEditor', DollyCamWaypointEditor.handleDoubleMiddleClick)

    -- Register mouse movement handler
    MouseManager.onMouseMove('waypointEditor', DollyCamWaypointEditor.handleMouseMove)

    STATE.mode.name = "waypointEditor"

    -- Set editing state
    STATE.dollyCam.isEditing = true
    STATE.dollyCam.visualizationEnabled = true
    Log.info("[DollyCam] Waypoint Editor enabled")
end

-- Clean up and disable the waypoint editor
function DollyCamWaypointEditor.disable()
    -- Reset editor state
    STATE.dollyCam.hoveredWaypointIndex = nil
    STATE.dollyCam.selectedWaypoints = {}
    STATE.dollyCam.hoveredPathPointIndex = nil

    -- Set editing state
    STATE.dollyCam.isEditing = false
    STATE.mode.name = nil

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

function DollyCamWaypointEditor.findClosestPointToMouse(points, getPositionFunc, screenThreshold)
    if not points or #points == 0 then
        return nil, math.huge
    end

    -- Screen-space approach
    local closestIndex = nil
    local closestDist = math.huge
    local mouseX, mouseY = STATE.dollyCam.lastMouseScreenPos.x, STATE.dollyCam.lastMouseScreenPos.y

    -- Loop through points to find closest in screen space
    for i, point in ipairs(points) do
        -- Get position using the provided function
        local x, y, z = getPositionFunc(point)

        -- Convert point position to screen coordinates
        local screenX, screenY, visible = Spring.WorldToScreenCoords(x, y, z)

        -- Only consider visible points
        if visible and screenX and screenY then
            local dist = math.sqrt((screenX - mouseX) ^ 2 + (screenY - mouseY) ^ 2)

            if dist < closestDist then
                closestDist = dist
                closestIndex = i
            end
        end
    end

    -- If we found a point in screen space...
    if closestIndex then
        if closestDist <= screenThreshold then
            return closestIndex, closestDist
        end
    end

    -- No point found
    return nil, math.huge
end

function DollyCamWaypointEditor.findClosestWaypointToMouse()
    local getWaypointPosition = function(waypoint)
        return waypoint.position.x, waypoint.position.y, waypoint.position.z
    end

    return DollyCamWaypointEditor.findClosestPointToMouse(
            STATE.dollyCam.route and STATE.dollyCam.route.points,
            getWaypointPosition,
            30 -- SCREEN_THRESHOLD for waypoints
    )
end

function DollyCamWaypointEditor.findClosestPathPointToMouse()
    local getPathPointPosition = function(point)
        return point.x, point.y, point.z
    end

    return DollyCamWaypointEditor.findClosestPointToMouse(
            STATE.dollyCam.route and STATE.dollyCam.route.path,
            getPathPointPosition,
            20 -- SCREEN_THRESHOLD for path points
    )
end

-- Helper function to check if a waypoint is selected
---@param index number Waypoint index to check
---@return boolean selected Whether the waypoint is selected
function DollyCamWaypointEditor.isWaypointSelected(index)
    for _, selectedIndex in ipairs(STATE.dollyCam.selectedWaypoints) do
        if selectedIndex == index then
            return true
        end
    end
    return false
end

-- Helper function to add a waypoint to selection
---@param index number Waypoint index to add to selection
function DollyCamWaypointEditor.addWaypointToSelection(index)
    if not DollyCamWaypointEditor.isWaypointSelected(index) then
        table.insert(STATE.dollyCam.selectedWaypoints, index)
        Log.info(string.format("Added waypoint %d to selection", index))
    end
end

-- Helper function to remove a waypoint from selection
---@param index number Waypoint index to remove from selection
function DollyCamWaypointEditor.removeWaypointFromSelection(index)
    for i, selectedIndex in ipairs(STATE.dollyCam.selectedWaypoints) do
        if selectedIndex == index then
            table.remove(STATE.dollyCam.selectedWaypoints, i)
            Log.info(string.format("Removed waypoint %d from selection", index))
            return
        end
    end
end

-- Toggle a waypoint's selection status (add if not selected, remove if selected)
---@param index number Waypoint index to toggle
function DollyCamWaypointEditor.toggleWaypointSelection(index)
    if DollyCamWaypointEditor.isWaypointSelected(index) then
        DollyCamWaypointEditor.removeWaypointFromSelection(index)
    else
        DollyCamWaypointEditor.addWaypointToSelection(index)
    end
end

-- Select a single waypoint, clearing any previous selection
---@param index number Index of the waypoint to select
function DollyCamWaypointEditor.selectWaypoint(index)
    if not STATE.dollyCam.route or not STATE.dollyCam.route.points or
            index < 1 or index > #STATE.dollyCam.route.points then
        return false
    end

    -- Clear previous selection
    STATE.dollyCam.selectedWaypoints = {}
    -- Add the waypoint to selection
    DollyCamWaypointEditor.addWaypointToSelection(index)
    Log.info(string.format("Selected waypoint %d", index))
    return true
end

-- Select all waypoints
function DollyCamWaypointEditor.selectAllWaypoints()
    if not STATE.dollyCam.route or not STATE.dollyCam.route.points then
        return false
    end

    -- Clear previous selection
    STATE.dollyCam.selectedWaypoints = {}

    -- Add all waypoints to selection
    for i = 1, #STATE.dollyCam.route.points do
        table.insert(STATE.dollyCam.selectedWaypoints, i)
    end

    Log.info(string.format("Selected all %d waypoints", #STATE.dollyCam.route.points))
    return true
end

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

function DollyCamWaypointEditor.handleLeftClick()
    -- If hovering over a waypoint
    if STATE.dollyCam.hoveredWaypointIndex then
        local index = STATE.dollyCam.hoveredWaypointIndex

        -- Check for shift key (multi-selection)
        local _, _, _, shift = Spring.GetModKeyState()

        if shift then
            DollyCamWaypointEditor.toggleWaypointSelection(index)
        else
            DollyCamWaypointEditor.selectWaypoint(index)
        end
        return true
    end

    -- If hovering over a path point, add a new waypoint
    if STATE.dollyCam.hoveredPathPointIndex then
        DollyCamWaypointEditor.addWaypointAtPathPoint(STATE.dollyCam.hoveredPathPointIndex)
        return true
    end

    -- If clicking elsewhere and not holding shift, deselect all
    local _, _, _, shift = Spring.GetModKeyState()
    if not shift then
        STATE.dollyCam.selectedWaypoints = {}
    end

    return false
end

function DollyCamWaypointEditor.handleLeftDoubleClick()
    local index = STATE.dollyCam.hoveredWaypointIndex

    -- Check for double-click on an already selected waypoint
    if DollyCamWaypointEditor.isWaypointSelected(index) then
        DollyCamWaypointEditor.selectAllWaypoints()
        return true
    end

    return false
end

function DollyCamWaypointEditor.handleDoubleMiddleClick()
    local success, action, index = DollyCamEditor.addOrEditWaypointAtMousePosition()

    if success then
        Log.info("Added new waypoint with MMB")
        -- Make sure to select the new waypoint
        if index then
            DollyCamWaypointEditor.selectWaypoint(index)
        end
    end

    return success
end

function DollyCamWaypointEditor.handleRightClick()
    -- If hovering over a waypoint, delete it
    if STATE.dollyCam.hoveredWaypointIndex then
        DollyCamWaypointEditor.deleteSelectedWaypoint(STATE.dollyCam.hoveredWaypointIndex)
        return true
    end

    return false
end

-- Delete the selected waypoint
---@param index number Index of the waypoint to delete, or nil to use selectedWaypointIndex
function DollyCamWaypointEditor.deleteSelectedWaypoint(index)
    -- If no index provided, use the currently selected waypoint
    if not index and #STATE.dollyCam.selectedWaypoints > 0 then
        index = STATE.dollyCam.selectedWaypoints[1]
    end

    if not index or not STATE.dollyCam.route or not STATE.dollyCam.route.points or
            index < 1 or index > #STATE.dollyCam.route.points then
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

        -- Remove from selection
        DollyCamWaypointEditor.removeWaypointFromSelection(index)

        -- Adjust indices of selected waypoints after the deleted one
        for i, selectedIndex in ipairs(STATE.dollyCam.selectedWaypoints) do
            if selectedIndex > index then
                STATE.dollyCam.selectedWaypoints[i] = selectedIndex - 1
            end
        end

        -- Regenerate the path
        DollyCamPathPlanner.generateSmoothPath()
    end

    return success
end

-- Add a waypoint at a path point
---@param pathPointIndex number Index of the path point to add a waypoint at
function DollyCamWaypointEditor.addWaypointAtPathPoint(pathPointIndex)
    if not STATE.dollyCam.route or not STATE.dollyCam.route.path or
            pathPointIndex < 1 or pathPointIndex > #STATE.dollyCam.route.path then
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

    -- Find which segment this path point belongs to by finding the actual distance
    local bestIndex = 1
    local pathDistance = 0

    -- Measure actual distance along the path to this point
    for i = 1, pathPointIndex - 1 do
        local p1 = STATE.dollyCam.route.path[i]
        local p2 = STATE.dollyCam.route.path[i + 1]
        local dx = p2.x - p1.x
        local dy = p2.y - p1.y
        local dz = p2.z - p1.z
        pathDistance = pathDistance + math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    -- Find which segment this distance belongs to
    local totalDistance = 0
    for i, segmentDist in ipairs(STATE.dollyCam.route.segmentDistances) do
        totalDistance = totalDistance + segmentDist
        if totalDistance >= pathDistance then
            -- We've found the segment that contains this point
            bestIndex = i + 1
            break
        end
    end

    -- Create and insert the new waypoint with default properties
    local waypoint = DollyCamDataStructures.createWaypoint(position)
    waypoint.targetSpeed = DollyCamWaypointEditor.DEFAULT_TARGET_SPEED -- Add speed point property
    waypoint.hasLookAt = false -- Default to no lookAt
    waypoint.lookAtPoint = nil -- Will be set if needed
    waypoint.lookAtUnitID = nil -- Will be set if tracking a unit

    table.insert(STATE.dollyCam.route.points, bestIndex, waypoint)

    -- Regenerate the path
    DollyCamPathPlanner.generateSmoothPath()

    -- Select the new waypoint
    DollyCamWaypointEditor.selectWaypoint(bestIndex)

    -- Adjust indices of selected waypoints after the inserted one
    for i, selectedIndex in ipairs(STATE.dollyCam.selectedWaypoints) do
        if selectedIndex >= bestIndex and selectedIndex ~= bestIndex then
            STATE.dollyCam.selectedWaypoints[i] = selectedIndex + 1
        end
    end

    Log.info(string.format("Added waypoint at path point %d at position (%.1f, %.1f, %.1f)",
            pathPointIndex, position.x, position.y, position.z))

    return true
end

-- Move the selected waypoint along an axis
---@param axis string Axis to move along: "x", "y", "z"
---@param value number Amount to move (positive or negative)
function DollyCamWaypointEditor.moveWaypointAlongAxis(axis, value)
    if #STATE.dollyCam.selectedWaypoints == 0 or not STATE.dollyCam.route or
            not STATE.dollyCam.route.points then
        return false
    end

    -- Calculate movement amount
    local amount = value
    local moved = false

    -- Apply movement to all selected waypoints
    for _, index in ipairs(STATE.dollyCam.selectedWaypoints) do
        if index >= 1 and index <= #STATE.dollyCam.route.points then
            -- Get the waypoint
            local waypoint = STATE.dollyCam.route.points[index]

            -- Update the waypoint position
            if axis == "x" then
                waypoint.position.x = waypoint.position.x + amount
                moved = true
            elseif axis == "y" then
                waypoint.position.y = waypoint.position.y + amount
                moved = true
            elseif axis == "z" then
                waypoint.position.z = waypoint.position.z + amount
                moved = true
            else
                Log.warn("Invalid axis: " .. axis)
                return false
            end
        end
    end

    if moved then
        -- Regenerate the path after all waypoints have been moved
        DollyCamPathPlanner.generateSmoothPath()

        local count = #STATE.dollyCam.selectedWaypoints
        Log.info(string.format("Moved %d waypoint%s along %s axis by %.1f units",
                count, count > 1 and "s" or "", axis, amount))
    end

    return moved
end

-- Set target speed for a waypoint
---@param speed number Target speed (0.0-1.0)
---@return boolean success Whether the speed was set
function DollyCamWaypointEditor.setWaypointTargetSpeed(speed)
    if #STATE.dollyCam.selectedWaypoints == 0 then
        return false
    end

    -- Clamp speed to valid range
    speed = tonumber(speed)
    if not speed then
        return false
    end

    speed = math.max(0.0, math.min(1.0, speed))
    local changed = false

    for _, index in ipairs(STATE.dollyCam.selectedWaypoints) do
        if index >= 1 and index <= #STATE.dollyCam.route.points then
            -- Store the original speed for logging
            local oldSpeed = STATE.dollyCam.route.points[index].targetSpeed or DollyCamWaypointEditor.DEFAULT_TARGET_SPEED

            -- Update the waypoint speed
            STATE.dollyCam.route.points[index].targetSpeed = speed
            -- Mark this speed as explicitly set, even if it's the default value
            STATE.dollyCam.route.points[index].hasExplicitSpeed = true

            changed = true
            Log.info(string.format("Set waypoint %d target speed from %.2f to %.2f",
                    index, oldSpeed, speed))
        end
    end

    return changed
end

-- Set lookAt unit for a waypoint
---@return boolean success Whether the unit tracking was set
function DollyCamWaypointEditor.setWaypointLookAtUnit()
    if #STATE.dollyCam.selectedWaypoints == 0 then
        return false
    end

    local selected = Spring.GetSelectedUnits()
    if #selected == 0 then
        -- Disable lookAt for all selected waypoints
        for _, index in ipairs(STATE.dollyCam.selectedWaypoints) do
            if index >= 1 and index <= #STATE.dollyCam.route.points then
                local waypoint = STATE.dollyCam.route.points[index]
                waypoint.hasLookAt = false
                waypoint.lookAtPoint = nil
                waypoint.lookAtUnitID = nil

                Log.info(string.format("Disabled unit tracking for waypoint %d", index))
            end
        end
        return true
    end

    -- Enable unit tracking for all selected waypoints
    local unitID = selected[1]
    for _, index in ipairs(STATE.dollyCam.selectedWaypoints) do
        if index >= 1 and index <= #STATE.dollyCam.route.points then
            local waypoint = STATE.dollyCam.route.points[index]

            -- Enable unit tracking
            waypoint.hasLookAt = true
            waypoint.lookAtPoint = nil -- Clear fixed position if any
            waypoint.lookAtUnitID = unitID

            -- Get unit position for logging
            local x, y, z = Spring.GetUnitPosition(unitID)
            Log.info(string.format("Set waypoint %d to track unit %d at (%.1f, %.1f, %.1f)",
                    index, unitID, x, y, z))
        end
    end

    return true
end

-- Reset waypoint speed to default (but still mark it as explicitly set)
---@return boolean success Whether the speed was reset
function DollyCamWaypointEditor.resetWaypointSpeed()
    if #STATE.dollyCam.selectedWaypoints == 0 then
        return false
    end

    local changed = false

    -- Apply to all selected waypoints
    for _, index in ipairs(STATE.dollyCam.selectedWaypoints) do
        if index >= 1 and index <= #STATE.dollyCam.route.points then
            local waypoint = STATE.dollyCam.route.points[index]

            -- Set speed to default
            waypoint.targetSpeed = DollyCamWaypointEditor.DEFAULT_TARGET_SPEED
            -- Mark as explicit reset
            waypoint.hasExplicitSpeed = true

            changed = true
            Log.info(string.format("Reset waypoint %d speed to default %.2f (explicit)",
                    index, DollyCamWaypointEditor.DEFAULT_TARGET_SPEED))
        end
    end

    return changed
end

-- Clear waypoint lookAt properties
---@return boolean success Whether the lookAt was cleared
function DollyCamWaypointEditor.clearWaypointLookAt()
    if #STATE.dollyCam.selectedWaypoints == 0 then
        return false
    end

    local changed = false

    -- Apply to all selected waypoints
    for _, index in ipairs(STATE.dollyCam.selectedWaypoints) do
        if index >= 1 and index <= #STATE.dollyCam.route.points then
            local waypoint = STATE.dollyCam.route.points[index]

            -- Explicitly mark lookAt as set to none
            waypoint.hasLookAt = true
            waypoint.lookAtPoint = nil
            waypoint.lookAtUnitID = nil

            changed = true
            Log.info(string.format("Explicitly cleared lookAt for waypoint %d", index))
        end
    end

    return changed
end

return {
    DollyCamWaypointEditor = DollyCamWaypointEditor
}