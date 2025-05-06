---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log
---@type DollyCamDataStructures
local DollyCamDataStructures = VFS.Include("LuaUI/TurboBarCam/features/dollycam/dollycam_data_structures.lua").DollyCamDataStructures
---@type DollyCamPathPlanner
local DollyCamPathPlanner = VFS.Include("LuaUI/TurboBarCam/features/dollycam/dollycam_path_planner.lua").DollyCamPathPlanner

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE

---@class DollyCamVisualization
local DollyCamVisualization = {}

-- Visualization colors
DollyCamVisualization.colors = {
    waypoint = { 1.0, 0.2, 0.2, 1.0 },           -- Red for waypoints
    selectedWaypoint = { 1.0, 1.0, 0.2, 1.0 },   -- Yellow for selected waypoint
    hoveredWaypoint = { 0.2, 1.0, 1.0, 1.0 },    -- Cyan for hovered waypoint
    path = { 0.2, 0.7, 1.0, 0.6 },               -- Blue for path
    hoveredPathPoint = { 0.2, 1.0, 0.7, 1.0 },   -- Light cyan for hovered path point
    currentPosition = { 0.0, 1.0, 0.0, 1.0 },    -- Green for current position
    waypoint_direction = { 1.0, 0.5, 0.1, 0.8 }, -- Orange for waypoint orientation
    pathSegmentStart = { 0.8, 0.2, 0.8, 1.0 },   -- Purple for segment starts
    pathSegmentEnd = { 0.4, 0.8, 0.4, 1.0 },     -- Light green for segment ends
    distanceMarker = { 1.0, 1.0, 1.0, 0.7 }      -- White for distance markers
}

-- Visual settings
DollyCamVisualization.settings = {
    waypointSize = 40,            -- Size of waypoint markers
    pathPointSize = 10,           -- Size of path points
    hoveredPathPointSize = 15,    -- Size of hovered path points
    currentPosSize = 20,          -- Size of current position marker
    pathSegmentSkip = 2,          -- Show every Nth path segment (for performance)
    maxPathSegments = 300,        -- Maximum number of path segments to draw
    directionLineLength = 40,     -- Length of the direction indicator line
    distanceMarkerInterval = 200, -- Distance between markers along path (world units)
    drawWaypointLabels = true,    -- Whether to draw waypoint labels
    drawPathTangents = false,     -- Whether to draw path tangent vectors
    drawDistanceMarkers = true,   -- Whether to draw distance markers
    drawSegmentBoundaries = true, -- Whether to draw segment start/end markers
    waypointLabelSize = 30,       -- Font size for waypoint labels
    distanceLabelSize = 20        -- Font size for distance labels
}

-- Toggle visualization
---@return boolean enabled New state of visualization
function DollyCamVisualization.toggle()
    STATE.dollyCam.visualizationEnabled = not STATE.dollyCam.visualizationEnabled
    Log.info("DollyCam visualization: " .. (STATE.dollyCam.visualizationEnabled and "Enabled" or "Disabled"))
    return STATE.dollyCam.visualizationEnabled
end

-- Draw a distance marker at a specific point on the path
---@param position table Position {x, y, z}
---@param distance number Distance along the path
local function drawDistanceMarker(position, distance)
    -- Draw a small point
    gl.PointSize(DollyCamVisualization.settings.pathPointSize * 1.5)
    gl.Color(DollyCamVisualization.colors.distanceMarker)
    gl.BeginEnd(GL.POINTS, function()
        gl.Vertex(position.x, position.y, position.z)
    end)

    -- Draw distance label
    if DollyCamVisualization.settings.drawWaypointLabels then
        gl.PushMatrix()
        gl.Translate(position.x, position.y + 10, position.z)
        gl.Billboard()
        gl.Text(string.format("%.0f", distance), 0, 0,
                DollyCamVisualization.settings.distanceLabelSize, "c")
        gl.PopMatrix()
    end
end

-- Main draw function for visualization
function DollyCamVisualization.draw()
    if not STATE.dollyCam.visualizationEnabled then
        return
    end

    if not STATE.dollyCam.route then
        return
    end

    -- Find closest waypoint based on context
    local closestWaypointIndex = nil

    if STATE.dollyCam.isNavigating then
        -- During navigation, highlight closest waypoint to current position
        local currentPosition = DollyCamPathPlanner.getPositionAtDistance(STATE.dollyCam.currentDistance)
        if currentPosition then
            closestWaypointIndex, _ = DollyCamPathPlanner.findClosestWaypoint(currentPosition)
        end
    elseif STATE.dollyCam.isEditing then
        -- During editing, use hover/selection state from STATE
        closestWaypointIndex = STATE.dollyCam.hoveredWaypointIndex
    end

    -- Draw waypoints
    for i, waypoint in ipairs(STATE.dollyCam.route.points) do
        local color = DollyCamVisualization.colors.waypoint
        local size = DollyCamVisualization.settings.waypointSize

        -- Determine waypoint appearance based on state
        if STATE.dollyCam.isEditing and STATE.dollyCam.selectedWaypointIndex == i then
            -- Selected waypoint gets priority
            color = DollyCamVisualization.colors.selectedWaypoint
            size = size * 1.5
        elseif STATE.dollyCam.isEditing and STATE.dollyCam.hoveredWaypointIndex == i then
            -- Hovered waypoint
            color = DollyCamVisualization.colors.hoveredWaypoint
            size = size * 1.2
        elseif closestWaypointIndex == i then
            -- Navigation closest waypoint
            color = DollyCamVisualization.colors.selectedWaypoint
            size = size * 1.25
        end

        -- Draw waypoint marker
        gl.PointSize(size)
        gl.Color(color)
        gl.BeginEnd(GL.POINTS, function()
            gl.Vertex(waypoint.position.x, waypoint.position.y, waypoint.position.z)
        end)

        -- Draw waypoint index text
        if DollyCamVisualization.settings.drawWaypointLabels then
            gl.PushMatrix()
            gl.Translate(waypoint.position.x, waypoint.position.y + 15, waypoint.position.z)
            gl.Billboard()
            gl.Text(tostring(i), 0, 0, DollyCamVisualization.settings.waypointLabelSize, "c")
            gl.PopMatrix()
        end
    end

    -- Draw path points
    if STATE.dollyCam.route.path and #STATE.dollyCam.route.path > 0 then
        -- Only draw a subset of points for performance
        local step = math.max(1, math.floor(#STATE.dollyCam.route.path / DollyCamVisualization.settings.maxPathSegments))

        gl.PointSize(DollyCamVisualization.settings.pathPointSize)
        gl.Color(DollyCamVisualization.colors.path)

        -- First pass: draw regular path points
        gl.BeginEnd(GL.POINTS, function()
            for i = 1, #STATE.dollyCam.route.path, step do
                -- Skip the hovered path point, we'll draw it later
                if not (STATE.dollyCam.isEditing and STATE.dollyCam.hoveredPathPointIndex == i) then
                    local point = STATE.dollyCam.route.path[i]
                    gl.Vertex(point.x, point.y, point.z)
                end
            end
        end)

        -- Second pass: draw hovered path point if any
        if STATE.dollyCam.isEditing and STATE.dollyCam.hoveredPathPointIndex then
            local hoveredPoint = STATE.dollyCam.route.path[STATE.dollyCam.hoveredPathPointIndex]
            gl.PointSize(DollyCamVisualization.settings.hoveredPathPointSize)
            gl.Color(DollyCamVisualization.colors.hoveredPathPoint)
            gl.BeginEnd(GL.POINTS, function()
                gl.Vertex(hoveredPoint.x, hoveredPoint.y, hoveredPoint.z)
            end)
        end
    end

    -- Draw segment boundaries
    if DollyCamVisualization.settings.drawSegmentBoundaries and #STATE.dollyCam.route.points > 1 then
        local distance = 0

        for i = 1, #STATE.dollyCam.route.segmentDistances do
            -- Draw start marker
            local startPos = DollyCamPathPlanner.getPositionAtDistance(distance)
            if startPos and i > 1 then
                -- Skip the very first marker which overlaps with waypoint
                gl.PointSize(DollyCamVisualization.settings.pathPointSize * 2)
                gl.Color(DollyCamVisualization.colors.pathSegmentStart)
                gl.BeginEnd(GL.POINTS, function()
                    gl.Vertex(startPos.x, startPos.y, startPos.z)
                end)
            end

            -- Draw end marker
            distance = distance + STATE.dollyCam.route.segmentDistances[i]
            local endPos = DollyCamPathPlanner.getPositionAtDistance(distance)
            if endPos and i < #STATE.dollyCam.route.segmentDistances then
                -- Skip the very last marker which overlaps with waypoint
                gl.PointSize(DollyCamVisualization.settings.pathPointSize * 2)
                gl.Color(DollyCamVisualization.colors.pathSegmentEnd)
                gl.BeginEnd(GL.POINTS, function()
                    gl.Vertex(endPos.x, endPos.y, endPos.z)
                end)
            end
        end
    end

    -- Draw distance markers
    if DollyCamVisualization.settings.drawDistanceMarkers and STATE.dollyCam.route.totalDistance and STATE.dollyCam.route.totalDistance > 0 then
        local interval = DollyCamVisualization.settings.distanceMarkerInterval
        local markerCount = math.floor(STATE.dollyCam.route.totalDistance / interval)

        for i = 1, markerCount do
            local markerDistance = i * interval
            local markerPos = DollyCamPathPlanner.getPositionAtDistance(markerDistance)

            if markerPos then
                drawDistanceMarker(markerPos, markerDistance)
            end
        end
    end

    -- Draw current position on path if navigating
    if STATE.dollyCam.isNavigating then
        local currentPos = DollyCamPathPlanner.getPositionAtDistance(STATE.dollyCam.currentDistance)

        if currentPos then
            gl.PointSize(DollyCamVisualization.settings.currentPosSize)
            gl.Color(DollyCamVisualization.colors.currentPosition)
            gl.BeginEnd(GL.POINTS, function()
                gl.Vertex(currentPos.x, currentPos.y, currentPos.z)
            end)

            -- Draw a text label with current distance information
            gl.PushMatrix()
            gl.Translate(currentPos.x, currentPos.y + 20, currentPos.z)
            gl.Billboard()
            gl.Text(string.format("%.1f / %.1f (%.1f%%)",
                    STATE.dollyCam.currentDistance,
                    STATE.dollyCam.route.totalDistance,
                    (STATE.dollyCam.currentDistance / STATE.dollyCam.route.totalDistance) * 100),
                    0, 0, 12, "c")
            gl.PopMatrix()

            -- Draw tangent if enabled
            if DollyCamVisualization.settings.drawPathTangents then
                local tangent = DollyCamPathPlanner.getPathTangentAtDistance(STATE.dollyCam.currentDistance)

                if tangent then
                    -- Draw tangent vector
                    local tanLength = DollyCamVisualization.settings.directionLineLength
                    gl.Color(1, 1, 0, 0.7)
                    gl.LineWidth(2.0)
                    gl.BeginEnd(GL.LINES, function()
                        gl.Vertex(currentPos.x, currentPos.y, currentPos.z)
                        gl.Vertex(
                                currentPos.x + tangent.x * tanLength,
                                currentPos.y + tangent.y * tanLength,
                                currentPos.z + tangent.z * tanLength
                        )
                    end)
                    gl.LineWidth(1.0)
                end
            end
        end
    end

    -- Draw editor-specific visualizations
    if STATE.dollyCam.isEditing and STATE.dollyCam.selectedWaypointIndex then
        local selectedWaypoint = STATE.dollyCam.route.points[STATE.dollyCam.selectedWaypointIndex]

        -- Draw movement axes for selected waypoint
        gl.LineWidth(2.0)

        -- X axis (red)
        gl.Color(1.0, 0.0, 0.0, 0.7)
        gl.BeginEnd(GL.LINES, function()
            gl.Vertex(selectedWaypoint.position.x - 50, selectedWaypoint.position.y, selectedWaypoint.position.z)
            gl.Vertex(selectedWaypoint.position.x + 50, selectedWaypoint.position.y, selectedWaypoint.position.z)
        end)

        -- Y axis (green)
        gl.Color(0.0, 1.0, 0.0, 0.7)
        gl.BeginEnd(GL.LINES, function()
            gl.Vertex(selectedWaypoint.position.x, selectedWaypoint.position.y - 50, selectedWaypoint.position.z)
            gl.Vertex(selectedWaypoint.position.x, selectedWaypoint.position.y + 50, selectedWaypoint.position.z)
        end)

        -- Z axis (blue)
        gl.Color(0.0, 0.0, 1.0, 0.7)
        gl.BeginEnd(GL.LINES, function()
            gl.Vertex(selectedWaypoint.position.x, selectedWaypoint.position.y, selectedWaypoint.position.z - 50)
            gl.Vertex(selectedWaypoint.position.x, selectedWaypoint.position.y, selectedWaypoint.position.z + 50)
        end)

        gl.LineWidth(1.0)
    end
end

return {
    DollyCamVisualization = DollyCamVisualization
}