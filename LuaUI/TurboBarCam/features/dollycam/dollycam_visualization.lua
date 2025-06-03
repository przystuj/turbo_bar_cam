---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local DollyCamPathPlanner = ModuleManager.DollyCamPathPlanner(function(m) DollyCamPathPlanner = m end)

---@class DollyCamVisualization
local DollyCamVisualization = {}

-- Visualization colors
DollyCamVisualization.colors = {
    waypoint = { 1.0, 0.2, 0.2, 1.0 }, -- Red for waypoints
    selectedWaypoint = { 1.0, 1.0, 0.2, 1.0 }, -- Yellow for selected waypoint
    hoveredWaypoint = { 0.2, 1.0, 1.0, 1.0 }, -- Cyan for hovered waypoint
    path = { 0.2, 0.7, 1.0, 0.6 }, -- Blue for path
    hoveredPathPoint = { 0.2, 1.0, 0.7, 1.0 }, -- Light cyan for hovered path point
    currentPosition = { 0.0, 1.0, 0.0, 1.0 }, -- Green for current position
    waypoint_direction = { 1.0, 0.5, 0.1, 0.8 }, -- Orange for waypoint orientation
    pathSegmentStart = { 0.8, 0.2, 0.8, 1.0 }, -- Purple for segment starts
    pathSegmentEnd = { 0.4, 0.8, 0.4, 1.0 }, -- Light green for segment ends
    distanceMarker = { 1.0, 1.0, 1.0, 0.7 }, -- White for distance markers
    speedPoint = { 0.3, 0.9, 0.9, 1.0 }, -- Cyan-ish for speed points (different from waypoint color)
    lookAtPoint = { 1.0, 0.5, 0.0, 1.0 }, -- Orange for lookAt points
    lookAtLine = { 0.8, 0.6, 0.0, 0.8 }, -- Light orange for lookAt lines
    inheritedSpeed = { 0.8, 0.8, 0.2, 1.0 }      -- Yellow for inherited speed
}

-- Visual settings
DollyCamVisualization.settings = {
    waypointSize = 40, -- Size of waypoint markers
    pathPointSize = 10, -- Size of path points
    hoveredPathPointSize = 15, -- Size of hovered path points
    currentPosSize = 20, -- Size of current position marker
    pathSegmentSkip = 2, -- Show every Nth path segment (for performance)
    maxPathSegments = 300, -- Maximum number of path segments to draw
    directionLineLength = 40, -- Length of the direction indicator line
    distanceMarkerInterval = 200, -- Distance between markers along path (world units)
    drawWaypointLabels = true, -- Whether to draw waypoint labels
    drawPathTangents = false, -- Whether to draw path tangent vectors
    drawDistanceMarkers = true, -- Whether to draw distance markers
    drawSegmentBoundaries = true, -- Whether to draw segment start/end markers
    waypointLabelSize = 30, -- Font size for waypoint labels
    distanceLabelSize = 20, -- Font size for distance labels
    speedIndicatorSize = 15, -- Font size for speed indicators
    lookAtIndicatorSize = 15      -- Font size for lookAt indicators
}

-- Default target speed value
DollyCamVisualization.DEFAULT_SPEED = 1.0

-- Toggle visualization
---@return boolean enabled New state of visualization
function DollyCamVisualization.toggle()
    STATE.dollyCam.visualizationEnabled = not STATE.dollyCam.visualizationEnabled
    Log:info("DollyCam visualization: " .. (STATE.dollyCam.visualizationEnabled and "Enabled" or "Disabled"))
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
---@param color table|nil Optional color, defaults to white
local function drawTextLabel(x, y, z, text, yOffset, size, color)
    gl.PushMatrix()
    gl.Translate(x, y + yOffset, z)
    gl.Billboard()
    if color then
        gl.Color(unpack(color))
    end
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

-- Helper function to calculate effective speed for a waypoint, considering propagation
-- Returns both the effective speed and whether it's explicitly set or inherited
---@param index number Waypoint index
---@return number speed The effective speed
---@return boolean isExplicit Whether the speed is explicitly set or inherited
local function getEffectiveWaypointSpeed(index)
    local waypoints = STATE.dollyCam.route.points
    if not waypoints or #waypoints == 0 or index < 1 or index > #waypoints then
        return DollyCamVisualization.DEFAULT_SPEED, false
    end

    local waypoint = waypoints[index]

    -- If this waypoint has an explicitly set speed that's not the default, it's explicit
    if waypoint.targetSpeed and waypoint.targetSpeed ~= DollyCamVisualization.DEFAULT_SPEED then
        return waypoint.targetSpeed, true
    end

    -- If this waypoint has explicitly set default speed, it's also explicit
    if waypoint.targetSpeed == DollyCamVisualization.DEFAULT_SPEED and waypoint.hasExplicitSpeed then
        return waypoint.targetSpeed, true
    end

    -- Otherwise, look back to find the last explicitly set speed
    for i = index - 1, 1, -1 do
        local prevWaypoint = waypoints[i]
        if prevWaypoint.targetSpeed and
                (prevWaypoint.targetSpeed ~= DollyCamVisualization.DEFAULT_SPEED or prevWaypoint.hasExplicitSpeed) then
            return prevWaypoint.targetSpeed, false
        end
    end

    -- If no previous explicit speed found, use default
    return DollyCamVisualization.DEFAULT_SPEED, false
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

-- Draw all waypoints with their special properties
local function drawWaypoints(hoveredWaypointIndex)
    for i, waypoint in ipairs(STATE.dollyCam.route.points) do
        local color = DollyCamVisualization.colors.waypoint
        local size = DollyCamVisualization.settings.waypointSize

        -- Determine waypoint appearance based on state
        local isSelected = false

        -- Check if this waypoint is selected (in multi-selection mode)
        if STATE.dollyCam.isEditing then
            for _, selectedIndex in ipairs(STATE.dollyCam.selectedWaypoints) do
                if selectedIndex == i then
                    isSelected = true
                    break
                end
            end
        end

        if STATE.dollyCam.isEditing and isSelected then
            -- Selected waypoint gets priority
            color = DollyCamVisualization.colors.selectedWaypoint
            size = size * 1.5
        elseif STATE.dollyCam.isEditing and STATE.dollyCam.hoveredWaypointIndex == i then
            -- Hovered waypoint
            color = DollyCamVisualization.colors.hoveredWaypoint
            size = size * 1.2
        elseif hoveredWaypointIndex == i then
            -- Navigation closest waypoint
            color = DollyCamVisualization.colors.selectedWaypoint
            size = size * 1.25
        end

        -- Draw waypoint marker
        drawPoint(
                waypoint.position.x, waypoint.position.y, waypoint.position.z,
                size, color
        )

        -- Draw waypoint index text and properties
        local labelText = tostring(i)

        -- Add selection indicator to label
        if isSelected then
            labelText = "◉ " .. labelText
        end

        -- Get the effective speed for this waypoint
        local effectiveSpeed, isExplicitSpeed = getEffectiveWaypointSpeed(i)

        -- Only in edit mode, show special properties
        if STATE.dollyCam.isEditing then
            -- Show speed only if it's non-default or inherited
            if isExplicitSpeed and effectiveSpeed ~= DollyCamVisualization.DEFAULT_SPEED then
                -- Explicitly set non-default speed
                drawTextLabel(
                        waypoint.position.x, waypoint.position.y, waypoint.position.z,
                        string.format("Speed=%.1f", effectiveSpeed),
                        -15, -- Below the waypoint
                        DollyCamVisualization.settings.speedIndicatorSize,
                        DollyCamVisualization.colors.speedPoint
                )
            elseif not isExplicitSpeed and effectiveSpeed ~= DollyCamVisualization.DEFAULT_SPEED then
                -- Inherited non-default speed
                drawTextLabel(
                        waypoint.position.x, waypoint.position.y, waypoint.position.z,
                        string.format("[Speed=%.1f]", effectiveSpeed),
                        -15, -- Below the waypoint
                        DollyCamVisualization.settings.speedIndicatorSize,
                        DollyCamVisualization.colors.inheritedSpeed
                )
            end

            -- Show lookAt indicator if defined
            if waypoint.hasLookAt then
                if waypoint.lookAtUnitID then
                    labelText = labelText .. " [L:Unit]"
                elseif waypoint.lookAtPoint then
                    labelText = labelText .. " [L:Point]"
                end

                -- Draw lookAt visualization if defined
                if waypoint.lookAtPoint then
                    -- Draw lookAt target point
                    drawPoint(
                            waypoint.lookAtPoint.x, waypoint.lookAtPoint.y, waypoint.lookAtPoint.z,
                            DollyCamVisualization.settings.pathPointSize * 1.5,
                            DollyCamVisualization.colors.lookAtPoint
                    )

                    -- Draw line from waypoint to lookAt point
                    drawLine(
                            waypoint.position.x, waypoint.position.y, waypoint.position.z,
                            waypoint.lookAtPoint.x, waypoint.lookAtPoint.y, waypoint.lookAtPoint.z,
                            DollyCamVisualization.colors.lookAtLine, 1.5
                    )

                    -- Label the lookAt point
                    drawTextLabel(
                            waypoint.lookAtPoint.x, waypoint.lookAtPoint.y, waypoint.lookAtPoint.z,
                            "LookAt #" .. i,
                            10,
                            DollyCamVisualization.settings.lookAtIndicatorSize
                    )
                elseif waypoint.lookAtUnitID and Spring.ValidUnitID(waypoint.lookAtUnitID) then
                    -- Get unit position for visualization
                    local x, y, z = Spring.GetUnitPosition(waypoint.lookAtUnitID)

                    if x and y and z then
                        -- Draw line from waypoint to unit
                        drawLine(
                                waypoint.position.x, waypoint.position.y, waypoint.position.z,
                                x, y, z,
                                DollyCamVisualization.colors.lookAtLine, 1.5
                        )

                        -- Label the unit being tracked
                        drawTextLabel(
                                x, y, z,
                                "Track #" .. waypoint.lookAtUnitID,
                                30,
                                DollyCamVisualization.settings.lookAtIndicatorSize
                        )
                    end
                end
            end
        end

        -- Always draw the waypoint index
        drawTextLabel(
                waypoint.position.x, waypoint.position.y, waypoint.position.z,
                labelText, 15,
                DollyCamVisualization.settings.waypointLabelSize
        )
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

    -- Draw text with current distance and speed information
    local infoText = string.format("%.1f / %.1f (%.1f%%)",
            STATE.dollyCam.currentDistance,
            STATE.dollyCam.route.totalDistance,
            (STATE.dollyCam.currentDistance / STATE.dollyCam.route.totalDistance) * 100)

    -- Add direction info
    infoText = infoText .. string.format("\n%s %.2f",
            STATE.dollyCam.direction > 0 and "→" or "←",
            STATE.dollyCam.currentSpeed)

    drawTextLabel(
            currentPos.x, currentPos.y, currentPos.z,
            infoText,
            25, 12
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
                    { 1, 1, 0, 0.7 }, 2.0
            )
        end
    end

    -- Draw active lookAt visualization if present
    if STATE.dollyCam.activeLookAt then
        local lookAtPos = nil

        if STATE.dollyCam.activeLookAt.unitID and Spring.ValidUnitID(STATE.dollyCam.activeLookAt.unitID) then
            -- Get unit position
            local x, y, z = Spring.GetUnitPosition(STATE.dollyCam.activeLookAt.unitID)
            if x and y and z then
                lookAtPos = { x = x, y = y, z = z }
            end
        elseif STATE.dollyCam.activeLookAt.point then
            -- Use fixed point
            lookAtPos = STATE.dollyCam.activeLookAt.point
        end

        if lookAtPos then
            -- Draw line from current position to lookAt target
            drawLine(
                    currentPos.x, currentPos.y, currentPos.z,
                    lookAtPos.x, lookAtPos.y, lookAtPos.z,
                    DollyCamVisualization.colors.lookAtLine, 2.0
            )
        end
    end
end

-- Draw editor-specific visualizations
local function drawEditorVisualizations()
    -- If we have selected waypoints, draw movement handles
    if STATE.dollyCam.isEditing and STATE.dollyCam.selectedWaypoints and #STATE.dollyCam.selectedWaypoints > 0 then
        -- Calculate center point of all selected waypoints
        local centerX, centerY, centerZ = 0, 0, 0
        local count = 0

        for _, index in ipairs(STATE.dollyCam.selectedWaypoints) do
            if index >= 1 and index <= #STATE.dollyCam.route.points then
                local pos = STATE.dollyCam.route.points[index].position
                centerX = centerX + pos.x
                centerY = centerY + pos.y
                centerZ = centerZ + pos.z
                count = count + 1
            end
        end

        if count > 0 then
            centerX = centerX / count
            centerY = centerY / count
            centerZ = centerZ / count

            local axisLength = 70

            -- Draw movement axes for center of selected waypoints
            -- X axis (red)
            drawLine(
                    centerX - axisLength, centerY, centerZ,
                    centerX + axisLength, centerY, centerZ,
                    { 1.0, 0.0, 0.0, 0.7 }, 2.0
            )

            -- Y axis (green)
            drawLine(
                    centerX, centerY - axisLength, centerZ,
                    centerX, centerY + axisLength, centerZ,
                    { 0.0, 1.0, 0.0, 0.7 }, 2.0
            )

            -- Z axis (blue)
            drawLine(
                    centerX, centerY, centerZ - axisLength,
                    centerX, centerY, centerZ + axisLength,
                    { 0.0, 0.0, 1.0, 0.7 }, 2.0
            )

            -- Draw a label showing selection count
            if count > 1 then
                drawTextLabel(
                        centerX, centerY, centerZ,
                        count .. " waypoints selected",
                        axisLength + 15, 15,
                        { 1.0, 1.0, 1.0, 0.9 }
                )
            end

            -- Draw connections between selected waypoints if more than one is selected
            if count > 1 then
                local selectedWaypoints = {}
                for _, index in ipairs(STATE.dollyCam.selectedWaypoints) do
                    if index >= 1 and index <= #STATE.dollyCam.route.points then
                        table.insert(selectedWaypoints, STATE.dollyCam.route.points[index])
                    end
                end

                -- Sort waypoints by their index
                table.sort(STATE.dollyCam.selectedWaypoints)

                -- Draw selection group boundary lines
                gl.LineWidth(1.5)
                gl.Color(0.9, 0.9, 0.2, 0.5)  -- Yellow, semi-transparent
                gl.BeginEnd(GL.LINE_LOOP, function()
                    for _, index in ipairs(STATE.dollyCam.selectedWaypoints) do
                        if index >= 1 and index <= #STATE.dollyCam.route.points then
                            local pos = STATE.dollyCam.route.points[index].position
                            gl.Vertex(pos.x, pos.y, pos.z)
                        end
                    end
                end)
                gl.LineWidth(1.0)
            end
        end
    end
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

return DollyCamVisualization