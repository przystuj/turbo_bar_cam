-- Turbo Overview Camera module for TURBOBARCAM
---@type {CONFIG: CONFIG, STATE: STATE}
local TurboConfig = VFS.Include("LuaUI/TURBOBARCAM/camera_turbobarcam_config.lua")
---@type {Util: Util}
local TurboUtils = VFS.Include("LuaUI/TURBOBARCAM/camera_turbobarcam_utils.lua")

local CONFIG = TurboConfig.CONFIG
local STATE = TurboConfig.STATE
local Util = TurboUtils.Util

---@class TurboOverviewCamera
local TurboOverviewCamera = {}

-- Helper function to calculate camera height based on current zoom level
local function calculateCurrentHeight()
    local zoomFactor = STATE.turboOverview.zoomLevels[STATE.turboOverview.zoomLevel]
    -- Enforce minimum height to prevent getting too close to ground
    return math.max(STATE.turboOverview.height / zoomFactor, 500)
end

-- Helper function to get cursor world position
local function getCursorWorldPosition()
    local mx, my = Spring.GetMouseState()
    local _, pos = Spring.TraceScreenRay(mx, my, true)

    if pos then
        return { x = pos[1], y = pos[2], z = pos[3] }
    else
        -- Return center of map if cursor is not over the map
        return { x = Game.mapSizeX / 2, y = 0, z = Game.mapSizeZ / 2 }
    end
end

--- Toggles turbo overview camera mode
function TurboOverviewCamera.toggle()
    if not STATE.enabled then
        Util.debugEcho("TURBOBARCAM must be enabled first")
        return
    end

    -- If we're already in turbo overview mode, turn it off
    if STATE.tracking.mode == 'turbo_overview' then
        Util.disableTracking()
        Util.debugEcho("Turbo Overview camera disabled")
        return
    end

    -- Get map dimensions to calculate height
    local mapX = Game.mapSizeX
    local mapZ = Game.mapSizeZ
    local mapDiagonal = math.sqrt(mapX * mapX + mapZ * mapZ)

    Util.debugEcho("Map dimensions: " .. mapX .. " x " .. mapZ)
    Util.debugEcho("Map diagonal: " .. mapDiagonal)

    -- Initialize turbo overview state with guaranteed values
    STATE.turboOverview = STATE.turboOverview or {}
    STATE.turboOverview.zoomLevel = STATE.turboOverview.zoomLevel or 1
    STATE.turboOverview.zoomLevels = STATE.turboOverview.zoomLevels or { 1, 2, 4 }
    STATE.turboOverview.smoothing = STATE.turboOverview.smoothing or 0.05

    -- Set a good default height based on map size
    STATE.turboOverview.height = math.max(mapDiagonal / 3, 500)
    Util.debugEcho("Base camera height: " .. STATE.turboOverview.height)

    -- Get current cursor position on the map
    STATE.turboOverview.lastCursorWorldPos = getCursorWorldPosition()

    -- Calculate current height based on zoom level
    local currentHeight = calculateCurrentHeight()
    Util.debugEcho("Current camera height: " .. currentHeight)

    -- Get current camera position to improve the transition
    local currentCamState = Spring.GetCameraState()

    -- Set up initial camera state before transition
    STATE.tracking.lastCamPos = {
        x = currentCamState.px,
        y = currentCamState.py,
        z = currentCamState.pz
    }

    -- Begin mode transition from previous mode to turbo overview mode
    -- This must be called after initializing lastCamPos for smooth transition
    Util.beginModeTransition('turbo_overview')

    -- Create camera state at cursor position
    local camStatePatch = {
        name = "fps",
        mode = 0, -- FPS camera mode
        px = STATE.turboOverview.lastCursorWorldPos.x,
        py = currentHeight,
        pz = STATE.turboOverview.lastCursorWorldPos.z,
        rx = math.pi, -- Looking down in Spring engine
        ry = 0,
        rz = 0
    }

    -- Apply the camera state with a longer transition time to avoid initial fast movement
    Spring.SetCameraState(camStatePatch, 0.5)

    Util.debugEcho("Turbo Overview camera enabled (Zoom: x" ..
            STATE.turboOverview.zoomLevels[STATE.turboOverview.zoomLevel] .. ")")
end

--- Updates the turbo overview camera's position
function TurboOverviewCamera.update()
    if STATE.tracking.mode ~= 'turbo_overview' then
        return
    end

    -- Get current cursor position on the map
    local cursorWorldPos = getCursorWorldPosition()

    -- Calculate current height based on zoom level
    local currentHeight = calculateCurrentHeight()

    -- Get current camera state
    local camState = Spring.GetCameraState()

    -- Ensure we're in FPS mode
    if camState.mode ~= 0 then
        camState.mode = 0
        camState.name = "fps"
    end

    -- Determine smoothing factor based on whether we're in a mode transition
    local smoothFactor = STATE.turboOverview.smoothing

    if STATE.tracking.modeTransition then
        -- Use a gentler transition factor during mode changes to avoid fast movement
        smoothFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR * 0.5

        -- Check if we should end the transition (after ~1 second)
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.transitionStartTime)
        if elapsed > 1.0 then
            STATE.tracking.modeTransition = false
        end
    end

    -- If this is the first update, initialize last positions to current
    if STATE.tracking.lastCamPos.x == 0 and
            STATE.tracking.lastCamPos.y == 0 and
            STATE.tracking.lastCamPos.z == 0 then
        STATE.tracking.lastCamPos = { x = camState.px, y = camState.py, z = camState.pz }
    end

    -- Prepare camera state patch with smoothed values
    local camStatePatch = {
        mode = 0,
        name = "fps",

        -- Smooth camera position (x and z follow cursor, y is fixed height)
        px = Util.smoothStep(STATE.tracking.lastCamPos.x, cursorWorldPos.x, smoothFactor),
        py = Util.smoothStep(STATE.tracking.lastCamPos.y, currentHeight, smoothFactor),
        pz = Util.smoothStep(STATE.tracking.lastCamPos.z, cursorWorldPos.z, smoothFactor),

        -- Looking straight down
        rx = math.pi,
        ry = 0,
        rz = 0
    }

    -- Update last position for next frame
    STATE.tracking.lastCamPos.x = camStatePatch.px
    STATE.tracking.lastCamPos.y = camStatePatch.py
    STATE.tracking.lastCamPos.z = camStatePatch.pz

    -- Update last cursor position
    STATE.turboOverview.lastCursorWorldPos = cursorWorldPos

    -- Apply camera state
    Spring.SetCameraState(camStatePatch, 0)
end

--- Toggles between available zoom levels
function TurboOverviewCamera.toggleZoom()
    if STATE.tracking.mode ~= 'turbo_overview' then
        Util.debugEcho("Turbo Overview camera must be enabled first")
        return
    end

    -- Cycle to the next zoom level
    STATE.turboOverview.zoomLevel = STATE.turboOverview.zoomLevel + 1
    if STATE.turboOverview.zoomLevel > #STATE.turboOverview.zoomLevels then
        STATE.turboOverview.zoomLevel = 1
    end

    local newZoom = STATE.turboOverview.zoomLevels[STATE.turboOverview.zoomLevel]
    Util.debugEcho("Turbo Overview camera zoom: x" .. newZoom)

    -- Force an immediate update to apply the new zoom
    TurboOverviewCamera.update()
end

--- Sets a specific zoom level
---@param level number Zoom level index
function TurboOverviewCamera.setZoomLevel(level)
    if STATE.tracking.mode ~= 'turbo_overview' then
        Util.debugEcho("Turbo Overview camera must be enabled first")
        return
    end

    level = tonumber(level)
    if not level or level < 1 or level > #STATE.turboOverview.zoomLevels then
        Util.debugEcho("Invalid zoom level. Available levels: 1-" .. #STATE.turboOverview.zoomLevels)
        return
    end

    STATE.turboOverview.zoomLevel = level
    local newZoom = STATE.turboOverview.zoomLevels[STATE.turboOverview.zoomLevel]
    Util.debugEcho("Turbo Overview camera zoom set to: x" .. newZoom)

    -- Force an immediate update to apply the new zoom
    TurboOverviewCamera.update()
end

--- Adjusts the smoothing factor for cursor following
---@param amount number Amount to adjust smoothing by
function TurboOverviewCamera.adjustSmoothing(amount)
    if STATE.tracking.mode ~= 'turbo_overview' then
        Util.debugEcho("Turbo Overview camera must be enabled first")
        return
    end

    -- Adjust smoothing factor (keep between 0.001 and 0.5)
    STATE.turboOverview.smoothing = math.max(0.001, math.min(0.5, STATE.turboOverview.smoothing + amount))
    Util.debugEcho("Turbo Overview smoothing: " .. STATE.turboOverview.smoothing)
end

return {
    TurboOverviewCamera = TurboOverviewCamera
}