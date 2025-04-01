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
    STATE.turboOverview.movementSmoothing = STATE.turboOverview.movementSmoothing or CONFIG.CAMERA_MODES.TURBO_OVERVIEW.DEFAULT_SMOOTHING
    STATE.turboOverview.initialMovementSmoothing = STATE.turboOverview.initialMovementSmoothing or 0.01 -- Slower initial movement
    STATE.turboOverview.zoomTransitionFactor = STATE.turboOverview.zoomTransitionFactor or 0.04 -- Smooth zoom transitions

    -- For tracking zoom transitions
    STATE.turboOverview.targetHeight = nil
    STATE.turboOverview.inZoomTransition = false

    -- Fixed camera position
    STATE.turboOverview.fixedCamPos = STATE.turboOverview.fixedCamPos or { x = 0, y = 0, z = 0 }
    -- Target position when movement button is pressed
    STATE.turboOverview.targetPos = STATE.turboOverview.targetPos or { x = 0, y = 0, z = 0 }
    -- Whether we're currently moving to a target
    STATE.turboOverview.movingToTarget = false
    -- Keep track of movement start time for smooth acceleration
    STATE.turboOverview.moveStartTime = nil

    -- Initialize mouse control variables
    STATE.turboOverview.lastMouseX = nil
    STATE.turboOverview.lastMouseY = nil
    STATE.turboOverview.mouseMoveSensitivity = 0.003
    STATE.turboOverview.targetRx = 0
    STATE.turboOverview.targetRy = 0

    -- Set a good default height based on map size
    STATE.turboOverview.height = math.max(mapDiagonal / 3, 500)
    Util.debugEcho("Base camera height: " .. STATE.turboOverview.height)

    -- Calculate current height based on zoom level
    local currentHeight = calculateCurrentHeight()
    STATE.turboOverview.targetHeight = currentHeight -- Initialize target height
    Util.debugEcho("Current camera height: " .. currentHeight)

    -- Get current camera position to improve the transition
    local currentCamState = Spring.GetCameraState()

    -- Initialize fixed camera position to current position
    STATE.turboOverview.fixedCamPos = {
        x = currentCamState.px,
        y = currentHeight,
        z = currentCamState.pz
    }

    -- Initialize rotation targets with current camera rotation
    STATE.turboOverview.targetRx = currentCamState.rx or math.pi / 4
    STATE.turboOverview.targetRy = currentCamState.ry or 0

    -- Get current mouse position for initialization
    STATE.turboOverview.lastMouseX, STATE.turboOverview.lastMouseY = Spring.GetMouseState()

    -- Set up initial camera state before transition
    STATE.tracking.lastCamPos = {
        x = currentCamState.px,
        y = currentCamState.py,
        z = currentCamState.pz
    }

    -- Initialize last rotation for smooth transitions
    STATE.tracking.lastRotation = {
        rx = currentCamState.rx or math.pi / 4,
        ry = currentCamState.ry or 0,
        rz = 0
    }

    -- Begin mode transition from previous mode to turbo overview mode
    -- This must be called after initializing lastCamPos for smooth transition
    Util.beginModeTransition('turbo_overview')

    -- Create camera state at current position
    local camStatePatch = {
        name = "fps",
        mode = 0, -- FPS camera mode
        px = STATE.turboOverview.fixedCamPos.x,
        py = currentHeight,
        pz = STATE.turboOverview.fixedCamPos.z,
        rx = STATE.tracking.lastRotation.rx,
        ry = STATE.tracking.lastRotation.ry,
        rz = 0
    }

    -- Apply the camera state with a longer transition time to avoid initial fast movement
    Spring.SetCameraState(camStatePatch, 0.5)

    Util.debugEcho("Turbo Overview camera enabled (Zoom: x" ..
            STATE.turboOverview.zoomLevels[STATE.turboOverview.zoomLevel] .. ")")
end

--- Updates the turbo overview camera's position and orientation
function TurboOverviewCamera.update()
    if STATE.tracking.mode ~= 'turbo_overview' then
        return
    end

    -- Get current camera state
    local camState = Spring.GetCameraState()

    -- Ensure we're in FPS mode
    if camState.mode ~= 0 then
        camState.mode = 0
        camState.name = "fps"
    end

    -- Determine smoothing factor based on whether we're in a mode transition
    local smoothFactor = STATE.turboOverview.movementSmoothing
    local rotFactor = CONFIG.SMOOTHING.FREE_CAMERA_FACTOR * 0.5

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
        -- Initialize fixed camera position too
        STATE.turboOverview.fixedCamPos = { x = camState.px, y = camState.py, z = camState.pz }
    end

    -- Handle zoom height transitions
    local currentHeight = camState.py
    local targetHeight = STATE.turboOverview.targetHeight or calculateCurrentHeight()

    if math.abs(currentHeight - targetHeight) > 1 then
        -- We're in a zoom transition
        STATE.turboOverview.inZoomTransition = true
        currentHeight = Util.smoothStep(currentHeight, targetHeight, STATE.turboOverview.zoomTransitionFactor)
    else
        STATE.turboOverview.inZoomTransition = false
        currentHeight = targetHeight
    end

    -- Update camera rotation based on mouse movement (FPS free camera style)
    local mouseX, mouseY = Spring.GetMouseState()

    -- Initialize last mouse position if needed
    if not STATE.turboOverview.lastMouseX or not STATE.turboOverview.lastMouseY then
        STATE.turboOverview.lastMouseX = mouseX
        STATE.turboOverview.lastMouseY = mouseY
    end

    -- Update target rotations based on mouse movement
    if mouseX ~= STATE.turboOverview.lastMouseX or mouseY ~= STATE.turboOverview.lastMouseY then
        -- Calculate delta movement
        local deltaX = mouseX - STATE.turboOverview.lastMouseX
        local deltaY = mouseY - STATE.turboOverview.lastMouseY

        -- Update target rotations based on mouse movement
        STATE.turboOverview.targetRy = STATE.turboOverview.targetRy + deltaX * STATE.turboOverview.mouseMoveSensitivity
        STATE.turboOverview.targetRx = STATE.turboOverview.targetRx - deltaY * STATE.turboOverview.mouseMoveSensitivity

        -- Normalize yaw angle
        STATE.turboOverview.targetRy = Util.normalizeAngle(STATE.turboOverview.targetRy)

        -- Remember mouse position for next frame
        STATE.turboOverview.lastMouseX = mouseX
        STATE.turboOverview.lastMouseY = mouseY
    end

    -- When moving to target, update the fixed position until we reach the target
    if STATE.turboOverview.movingToTarget then
        -- Calculate distance to target
        local dx = STATE.turboOverview.targetPos.x - STATE.turboOverview.fixedCamPos.x
        local dz = STATE.turboOverview.targetPos.z - STATE.turboOverview.fixedCamPos.z
        local distSquared = dx * dx + dz * dz

        -- If we're close enough to the target, stop moving
        if distSquared < 25 then
            -- 5 units squared
            STATE.turboOverview.fixedCamPos.x = STATE.turboOverview.targetPos.x
            STATE.turboOverview.fixedCamPos.z = STATE.turboOverview.targetPos.z
            STATE.turboOverview.movingToTarget = false
            STATE.turboOverview.moveStartTime = nil
            Util.debugEcho("Reached target position")
        else
            -- Calculate dynamic smoothing factor for gradual acceleration
            local moveSmoothFactor = smoothFactor

            -- If we just started moving, use slow initial movement and accelerate over time
            if STATE.turboOverview.moveStartTime then
                local now = Spring.GetTimer()
                local elapsed = Spring.DiffTimers(now, STATE.turboOverview.moveStartTime)

                -- Gradually increase speed over 1.5 seconds
                if elapsed < 1.5 then
                    local t = elapsed / 1.5 -- Normalized time (0-1)
                    -- Ease-in speed from initial to normal
                    moveSmoothFactor = STATE.turboOverview.initialMovementSmoothing +
                            (smoothFactor - STATE.turboOverview.initialMovementSmoothing) *
                                    Util.easeInOutCubic(t)
                end
            end

            -- Smoothly move fixed camera position toward target position
            STATE.turboOverview.fixedCamPos.x = Util.smoothStep(STATE.turboOverview.fixedCamPos.x, STATE.turboOverview.targetPos.x, moveSmoothFactor)
            STATE.turboOverview.fixedCamPos.z = Util.smoothStep(STATE.turboOverview.fixedCamPos.z, STATE.turboOverview.targetPos.z, moveSmoothFactor)
        end
    end

    -- Get camera position
    local camPos = {
        x = STATE.turboOverview.fixedCamPos.x,
        y = currentHeight,
        z = STATE.turboOverview.fixedCamPos.z
    }

    -- Smoothly interpolate current camera rotation toward target rotation
    local rx = Util.smoothStep(STATE.tracking.lastRotation.rx, STATE.turboOverview.targetRx, rotFactor)
    local ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, STATE.turboOverview.targetRy, rotFactor)

    -- Calculate direction vector from rotation angles
    local cosRx = math.cos(rx)
    local dx = math.sin(ry) * cosRx
    local dz = math.cos(ry) * cosRx
    local dy = math.sin(rx)

    -- Prepare camera state patch
    local camStatePatch = {
        mode = 0,
        name = "fps",
        -- Fixed camera position (only moves when going to target)
        px = camPos.x,
        py = camPos.y,
        pz = camPos.z,
        -- Direction vector calculated from rotation angles
        dx = dx,
        dy = dy,
        dz = dz,
        -- Smoothed rotation angles
        rx = rx,
        ry = ry,
        rz = 0
    }

    -- Update last position for next frame
    STATE.tracking.lastCamPos.x = camStatePatch.px
    STATE.tracking.lastCamPos.y = camStatePatch.py
    STATE.tracking.lastCamPos.z = camStatePatch.pz

    -- Update last rotation for next frame
    STATE.tracking.lastRotation.rx = camStatePatch.rx
    STATE.tracking.lastRotation.ry = camStatePatch.ry
    STATE.tracking.lastRotation.rz = camStatePatch.rz

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

    -- Update target height for smooth transition
    STATE.turboOverview.targetHeight = calculateCurrentHeight()

    local newZoom = STATE.turboOverview.zoomLevels[STATE.turboOverview.zoomLevel]
    Util.debugEcho("Turbo Overview camera zoom: x" .. newZoom)

    -- Force an update to start the transition
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

    -- Set the new zoom level
    STATE.turboOverview.zoomLevel = level

    -- Update target height for smooth transition
    STATE.turboOverview.targetHeight = calculateCurrentHeight()

    local newZoom = STATE.turboOverview.zoomLevels[STATE.turboOverview.zoomLevel]
    Util.debugEcho("Turbo Overview camera zoom set to: x" .. newZoom)

    -- Force an update to start the transition
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
    STATE.turboOverview.movementSmoothing = math.max(0.001, math.min(0.5, STATE.turboOverview.movementSmoothing + amount))
    Util.debugEcho("Turbo Overview smoothing: " .. STATE.turboOverview.movementSmoothing)

end

--- Move camera to cursor position
function TurboOverviewCamera.moveToPoint()
    if STATE.tracking.mode ~= 'turbo_overview' then
        Util.debugEcho("Turbo Overview camera must be enabled first")
        return
    end

    -- Get cursor position and set it as target
    STATE.turboOverview.targetPos = getCursorWorldPosition()
    STATE.turboOverview.movingToTarget = true

    -- Record the start time for gradual acceleration
    STATE.turboOverview.moveStartTime = Spring.GetTimer()

    Util.debugEcho("Moving to cursor position")
end

return {
    TurboOverviewCamera = TurboOverviewCamera
}