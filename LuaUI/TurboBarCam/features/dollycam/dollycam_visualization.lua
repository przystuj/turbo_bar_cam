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

-- Helper function to draw a single point
---@param x number X coordinate
---@param y number Y coordinate
---@param z number Z coordinate
---@param size number Point size
---@param color table Color array {r, g, b, a}
local function drawPoint(x, y, z, size, color)
    gl.PointSize(size)
    gl.Color(unpack(color))
    gl.BeginEnd(GL.POINTS, function()
        gl.Vertex(x, y, z)
    end)
end

-- Helper function to draw a billboarded text label
---@param x number X coordinate
---@param y number Y coordinate
---@param z number Z coordinate
---@param text string Text to display
---@param yOffset number Y offset for the text
---@param size number Font size
local function drawTextLabel(x, y, z, text, yOffset, size)
    gl.PushMatrix()
    gl.Translate(x, y + yOffset, z)
    gl.Billboard()
    gl.Text(text, 0, 0, size, "c")
    gl.PopMatrix()
end

-- Helper function to draw a line
---@param x1 number Start X coordinate
---@param y1 number Start Y coordinate
---@param z1 number Start Z coordinate
---@param x2 number End X coordinate
---@param y2 number End Y coordinate
---@param z2 number End Z coordinate
---@param color table Color array {r, g, b, a}
---@param width number Line width
local function drawLine(x1, y1, z1, x2, y2, z2, color, width)
    gl.LineWidth(width or 1.0)
    gl.Color(unpack(color))
    gl.BeginEnd(GL.LINES, function()
        gl.Vertex(x1, y1, z1)
        gl.Vertex(x2, y2, z2)
    end)
    gl.LineWidth(1.0)
end

-- Draw a distance marker at a specific point on the path
---@param position table Position {x, y, z}
---@param distance number Distance along the path
local function drawDistanceMarker(position, distance)
    -- Draw a small point
    drawPoint(
            position.x, position.y, position.z,
            DollyCamVisualization.settings.pathPointSize * 1.5,
            DollyCamVisualization.colors.distanceMarker
    )

    -- Draw distance label
    if DollyCamVisualization.settings.drawWaypointLabels then
        drawTextLabel(
                position.x, position.y, position.z,
                string.format("%.0f", distance),
                10,
                DollyCamVisualization.settings.distanceLabelSize
        )
    end
end

-- Draw all waypoints
local function drawWaypoints(closestWaypointIndex)
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
        drawPoint(
                waypoint.position.x, waypoint.position.y, waypoint.position.z,
                size, color
        )

        -- Draw waypoint index text
        if DollyCamVisualization.settings.drawWaypointLabels then
            drawTextLabel(
                    waypoint.position.x, waypoint.position.y, waypoint.position.z,
                    tostring(i), 15,
                    DollyCamVisualization.settings.waypointLabelSize
            )
        end
    end
end

-- Draw path points
local function drawPathPoints()
    if not (STATE.dollyCam.route.path and #STATE.dollyCam.route.path > 0) then
        return
    end

    -- Only draw a subset of points for performance
    local step = math.max(1, math.floor(#STATE.dollyCam.route.path / DollyCamVisualization.settings.maxPathSegments))

    -- First pass: draw regular path points
    gl.PointSize(DollyCamVisualization.settings.pathPointSize)
    gl.Color(unpack(DollyCamVisualization.colors.path))
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
        drawPoint(
                hoveredPoint.x, hoveredPoint.y, hoveredPoint.z,
                DollyCamVisualization.settings.hoveredPathPointSize,
                DollyCamVisualization.colors.hoveredPathPoint
        )
    end
end

-- Draw segment boundaries
local function drawSegmentBoundaries()
    if not DollyCamVisualization.settings.drawSegmentBoundaries or #STATE.dollyCam.route.points <= 1 then
        return
    end

    local distance = 0

    for i = 1, #STATE.dollyCam.route.segmentDistances do
        -- Draw start marker
        local startPos = DollyCamPathPlanner.getPositionAtDistance(distance)
        if startPos and i > 1 then
            -- Skip the very first marker which overlaps with waypoint
            drawPoint(
                    startPos.x, startPos.y, startPos.z,
                    DollyCamVisualization.settings.pathPointSize * 2,
                    DollyCamVisualization.colors.pathSegmentStart
            )
        end

        -- Draw end marker
        distance = distance + STATE.dollyCam.route.segmentDistances[i]
        local endPos = DollyCamPathPlanner.getPositionAtDistance(distance)
        if endPos and i < #STATE.dollyCam.route.segmentDistances then
            -- Skip the very last marker which overlaps with waypoint
            drawPoint(
                    endPos.x, endPos.y, endPos.z,
                    DollyCamVisualization.settings.pathPointSize * 2,
                    DollyCamVisualization.colors.pathSegmentEnd
            )
        end
    end
end

-- Draw distance markers
local function drawDistanceMarkers()
    if not (DollyCamVisualization.settings.drawDistanceMarkers and
            STATE.dollyCam.route.totalDistance and
            STATE.dollyCam.route.totalDistance > 0) then
        return
    end

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

-- Draw current position during navigation
local function drawCurrentPosition()
    if not STATE.dollyCam.isNavigating then
        return
    end

    local currentPos = DollyCamPathPlanner.getPositionAtDistance(STATE.dollyCam.currentDistance)
    if not currentPos then
        return
    end

    -- Draw position marker
    drawPoint(
            currentPos.x, currentPos.y, currentPos.z,
            DollyCamVisualization.settings.currentPosSize,
            DollyCamVisualization.colors.currentPosition
    )

    -- Draw text with current distance information
    drawTextLabel(
            currentPos.x, currentPos.y, currentPos.z,
            string.format("%.1f / %.1f (%.1f%%)",
                    STATE.dollyCam.currentDistance,
                    STATE.dollyCam.route.totalDistance,
                    (STATE.dollyCam.currentDistance / STATE.dollyCam.route.totalDistance) * 100),
            20, 12
    )

    -- Draw tangent if enabled
    if DollyCamVisualization.settings.drawPathTangents then
        local tangent = DollyCamPathPlanner.getPathTangentAtDistance(STATE.dollyCam.currentDistance)

        if tangent then
            -- Draw tangent vector
            local tanLength = DollyCamVisualization.settings.directionLineLength
            drawLine(
                    currentPos.x, currentPos.y, currentPos.z,
                    currentPos.x + tangent.x * tanLength,
                    currentPos.y + tangent.y * tanLength,
                    currentPos.z + tangent.z * tanLength,
                    {1, 1, 0, 0.7}, 2.0
            )
        end
    end
end

-- Draw editor-specific visualizations
local function drawEditorVisualizations()
    if not (STATE.dollyCam.isEditing and STATE.dollyCam.selectedWaypointIndex) then
        return
    end

    local selectedWaypoint = STATE.dollyCam.route.points[STATE.dollyCam.selectedWaypointIndex]
    local pos = selectedWaypoint.position
    local axisLength = 50

    -- Draw movement axes for selected waypoint
    -- X axis (red)
    drawLine(
            pos.x - axisLength, pos.y, pos.z,
            pos.x + axisLength, pos.y, pos.z,
            {1.0, 0.0, 0.0, 0.7}, 2.0
    )

    -- Y axis (green)
    drawLine(
            pos.x, pos.y - axisLength, pos.z,
            pos.x, pos.y + axisLength, pos.z,
            {0.0, 1.0, 0.0, 0.7}, 2.0
    )

    -- Z axis (blue)
    drawLine(
            pos.x, pos.y, pos.z - axisLength,
            pos.x, pos.y, pos.z + axisLength,
            {0.0, 0.0, 1.0, 0.7}, 2.0
    )
end

-- Main draw function for visualization
function DollyCamVisualization.draw()
    if not STATE.dollyCam.visualizationEnabled or not STATE.dollyCam.route then
        return
    end

    local closestWaypointIndex = STATE.dollyCam.hoveredWaypointIndex

    -- Draw all visualization elements
    drawWaypoints(closestWaypointIndex)
    drawPathPoints()
    drawSegmentBoundaries()
    drawDistanceMarkers()
    drawCurrentPosition()
    drawEditorVisualizations()
end

return {
    DollyCamVisualization = DollyCamVisualization
}