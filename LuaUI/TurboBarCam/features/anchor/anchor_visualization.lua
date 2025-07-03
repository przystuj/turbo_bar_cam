---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "CameraAnchorVisualization")
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)

---@class CameraAnchorVisualization
local CameraAnchorVisualization = {}

-- Define colors for different visualization elements
CameraAnchorVisualization.colors = {
    positionPoint = { 0.2, 0.6, 1.0, 1.0 },   -- Blue
    lookAtPoint_Point = { 1.0, 0.8, 0.0, 1.0 }, -- Gold
    lookAtPoint_Unit = { 1.0, 0.4, 0.2, 1.0 },  -- Orange-Red
    line = { 1.0, 1.0, 1.0, 0.5 },            -- White, semi-transparent
    label = { 1.0, 1.0, 1.0, 0.9 },           -- White

    highlight = { 0.2, 1.0, 0.2, 1.0 },       -- Bright Green
    highlightLine = { 0.5, 1.0, 0.5, 0.8 },   -- Bright Green, semi-transparent
}

CameraAnchorVisualization.settings = {
    markerSize = 30,
    labelBaseSize = 1.0, -- This is now a factor for scaling, not a pixel size
    labelScaleFactor = 0.03, -- Adjust this to control how fast labels scale with distance
    lineWidth = 2.0,
    highlightMultiplier = 1.5, -- How much bigger to make the highlighted anchor
}

--- Helper function to draw a single point
---@param x, y, z, size, color
local function drawPoint(x, y, z, size, color)
    gl.PointSize(size)
    gl.Color(unpack(color))
    gl.BeginEnd(GL.POINTS, function()
        gl.Vertex(x, y, z)
    end)
    gl.PointSize(1.0)
end

--- Helper function to draw a billboarded text label that scales with distance
---@param x, y, z, text, camPos
local function drawTextLabel(x, y, z, text, camPos, isHighlighted)
    -- Calculate distance from camera to the point for scaling
    local dx = x - camPos.x
    local dy = y - camPos.y
    local dz = z - camPos.z
    local distance = math.sqrt(dx*dx + dy*dy + dz*dz)

    -- Calculate the world-space size of the text based on distance
    local scale = distance * CameraAnchorVisualization.settings.labelScaleFactor
    if scale < 1.0 then scale = 1.0 end -- Prevent it from becoming too small
    if isHighlighted then scale = scale * CameraAnchorVisualization.settings.highlightMultiplier end

    gl.PushMatrix()
    gl.Translate(x, y, z)
    gl.Billboard()
    gl.Scale(scale, scale, scale)
    gl.Color(unpack(CameraAnchorVisualization.colors.label))

    -- The size parameter here is now relative to the matrix scale
    gl.Text(text, 0, 1, CameraAnchorVisualization.settings.labelBaseSize, "c")
    gl.PopMatrix()
end

--- Helper function to draw a line
---@param x1, y1, z1, x2, y2, z2, color, width
local function drawLine(x1, y1, z1, x2, y2, z2, color, width)
    gl.LineWidth(width or 1.0)
    gl.Color(unpack(color))
    gl.BeginEnd(GL.LINES, function()
        gl.Vertex(x1, y1, z1)
        gl.Vertex(x2, y2, z2)
    end)
    gl.LineWidth(1.0)
end

--- Main draw function for anchor visualizations
function CameraAnchorVisualization.draw()
    if not STATE.active.anchor.visualizationEnabled then
        return
    end

    if not STATE.anchor.points or TableUtils.tableCount(STATE.anchor.points) == 0 then
        return
    end

    -- Get camera position once for distance calculations
    local camX, camY, camZ = Spring.GetCameraPosition()
    local camPos = { x = camX, y = camY, z = camZ }
    local activeAnchorId = STATE.active.anchor.lastUsedAnchor

    for id, anchor in pairs(STATE.anchor.points) do
        if anchor and anchor.position then
            local isHighlighted = (id == activeAnchorId)
            local sizeMultiplier = isHighlighted and CameraAnchorVisualization.settings.highlightMultiplier or 1.0

            -- Always draw the main position point and its label for all anchors.
            local pos = anchor.position
            local posColor = isHighlighted and CameraAnchorVisualization.colors.highlight or CameraAnchorVisualization.colors.positionPoint
            drawPoint(pos.px, pos.py, pos.pz,
                    CameraAnchorVisualization.settings.markerSize * sizeMultiplier,
                    posColor)

            drawTextLabel(pos.px, pos.py, pos.pz, tostring(id), camPos, isHighlighted)

            -- Handle visualization for the look-at target, if it exists.
            if anchor.target then
                local lookAtPos, lookAtColor
                if anchor.target.type == "unit" then
                    local unitID = anchor.target.data
                    if Spring.ValidUnitID(unitID) then
                        local uX, uY, uZ = Spring.GetUnitPosition(unitID)
                        if uX then lookAtPos = { x = uX, y = uY, z = uZ } end
                    end
                    lookAtColor = isHighlighted and CameraAnchorVisualization.colors.highlight or CameraAnchorVisualization.colors.lookAtPoint_Unit
                else -- "point" type
                    lookAtPos = anchor.target.data
                    lookAtColor = isHighlighted and CameraAnchorVisualization.colors.highlight or CameraAnchorVisualization.colors.lookAtPoint_Point
                end

                if lookAtPos then
                    if isHighlighted then
                        -- If this anchor is active, only draw the connecting line.
                        local lineColor = CameraAnchorVisualization.colors.highlightLine
                        drawLine(pos.px, pos.py, pos.pz,
                                lookAtPos.x, lookAtPos.y, lookAtPos.z,
                                lineColor,
                                CameraAnchorVisualization.settings.lineWidth * sizeMultiplier)
                    elseif not activeAnchorId and lookAtPos and type(lookAtPos) == "table" then
                        -- If no anchor is active, draw full details for all anchors.
                        drawPoint(lookAtPos.x, lookAtPos.y, lookAtPos.z,
                                CameraAnchorVisualization.settings.markerSize,
                                lookAtColor)

                        drawTextLabel(lookAtPos.x, lookAtPos.y, lookAtPos.z, tostring(id), camPos, false)

                        local lineColor = CameraAnchorVisualization.colors.line
                        drawLine(pos.px, pos.py, pos.pz,
                                lookAtPos.x, lookAtPos.y, lookAtPos.z,
                                lineColor,
                                CameraAnchorVisualization.settings.lineWidth)
                    end
                    -- If an anchor is active, but this is not it, we do nothing,
                    -- which hides the lines and target points for all inactive anchors.
                end
            end
        end
    end
end

return CameraAnchorVisualization