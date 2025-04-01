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

---@param centerPoint table Center point of orbit {x, y, z}
---@param angle number Angle in radians
---@param distance number Distance from center
---@param height number Height above ground
---@return table position Position on orbit {x, y, z}
local function calculateOrbitPosition(centerPoint, angle, distance, height)
    return {
        x = centerPoint.x + distance * math.sin(angle),
        y = centerPoint.y + height,
        z = centerPoint.z + distance * math.cos(angle)
    }
end

-- Helper function to calculate orbit angle between two positions
---@param centerPoint table Center point {x, y, z}
---@param position table Position {x, y, z}
---@return number angle Angle in radians
local function calculateOrbitAngle(centerPoint, position)
    return math.atan2(position.x - centerPoint.x, position.z - centerPoint.z)
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

    -- Initialize orbit mode variables
    STATE.turboOverview.isOrbiting = false
    STATE.turboOverview.orbitCenter = nil
    STATE.turboOverview.orbitDistance = 300
    STATE.turboOverview.orbitAngle = 0
    STATE.turboOverview.orbitAngularVelocity = 0
    STATE.turboOverview.orbitMaxAngularVelocity = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ORBIT.MAX_ANGULAR_VELOCITY
    STATE.turboOverview.orbitAngularAcceleration = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ORBIT.ANGULAR_ACCELERATION
    STATE.turboOverview.orbitAngularDamping = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ORBIT.ANGULAR_DAMPING
    STATE.turboOverview.orbitForwardVelocity = 0
    STATE.turboOverview.orbitMaxForwardVelocity = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ORBIT.MAX_FORWARD_VELOCITY
    STATE.turboOverview.orbitForwardAcceleration = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ORBIT.FORWARD_ACCELERATION
    STATE.turboOverview.orbitForwardDamping = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ORBIT.FORWARD_DAMPING
    STATE.turboOverview.orbitMinDistance = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ORBIT.MIN_DISTANCE

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

-- Updates orbit movement based on mouse position and button state
---@param deltaTime number Time since last update
local function updateOrbitMovement(deltaTime)
    if not STATE.turboOverview.isOrbiting then
        return
    end

    local mouseX, mouseY = Spring.GetMouseState()

    -- Initialize last mouse position if needed
    if not STATE.turboOverview.lastMouseX or not STATE.turboOverview.lastMouseY then
        STATE.turboOverview.lastMouseX = mouseX
        STATE.turboOverview.lastMouseY = mouseY
        return
    end

    -- Calculate mouse movement
    local deltaX = mouseX - STATE.turboOverview.lastMouseX
    STATE.turboOverview.lastMouseX = mouseX
    STATE.turboOverview.lastMouseY = mouseY

    -- Apply angular acceleration based on mouse movement
    if STATE.turboOverview.movingToTarget then
        -- Add angular velocity based on mouse movement (left/right)
        STATE.turboOverview.orbitAngularVelocity = STATE.turboOverview.orbitAngularVelocity +
                deltaX * STATE.turboOverview.orbitAngularAcceleration

        -- Limit maximum angular velocity
        STATE.turboOverview.orbitAngularVelocity = math.max(
                -STATE.turboOverview.orbitMaxAngularVelocity,
                math.min(STATE.turboOverview.orbitMaxAngularVelocity, STATE.turboOverview.orbitAngularVelocity)
        )

        -- Add forward velocity (gradually approach target)
        STATE.turboOverview.orbitForwardVelocity = math.min(
                STATE.turboOverview.orbitMaxForwardVelocity,
                STATE.turboOverview.orbitForwardVelocity + STATE.turboOverview.orbitForwardAcceleration
        )
    else
        -- Apply damping when not actively moving
        STATE.turboOverview.orbitAngularVelocity = STATE.turboOverview.orbitAngularVelocity * STATE.turboOverview.orbitAngularDamping
        STATE.turboOverview.orbitForwardVelocity = STATE.turboOverview.orbitForwardVelocity * STATE.turboOverview.orbitForwardDamping

        -- Stop completely if velocity is very small
        if math.abs(STATE.turboOverview.orbitAngularVelocity) < 0.0001 then
            STATE.turboOverview.orbitAngularVelocity = 0
        end

        if math.abs(STATE.turboOverview.orbitForwardVelocity) < 0.1 then
            STATE.turboOverview.orbitForwardVelocity = 0

            -- If we've completely stopped, exit orbit mode
            if STATE.turboOverview.orbitAngularVelocity == 0 then
                STATE.turboOverview.isOrbiting = false
                Util.debugEcho("Exiting orbit mode")
                return
            end
        end
    end

    -- Update orbit angle based on angular velocity
    STATE.turboOverview.orbitAngle = STATE.turboOverview.orbitAngle + STATE.turboOverview.orbitAngularVelocity

    -- Update orbit distance based on forward velocity
    STATE.turboOverview.orbitDistance = math.max(
            STATE.turboOverview.orbitMinDistance,
            STATE.turboOverview.orbitDistance - STATE.turboOverview.orbitForwardVelocity
    )

    -- Calculate new position on orbit
    local newPos = calculateOrbitPosition(
            STATE.turboOverview.orbitCenter,
            STATE.turboOverview.orbitAngle,
            STATE.turboOverview.orbitDistance,
            calculateCurrentHeight()
    )

    -- Update fixed camera position
    STATE.turboOverview.fixedCamPos = newPos
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

    -- Update orbit movement if in orbit mode
    if STATE.turboOverview.isOrbiting then
        -- Calculate elapsed time (approximate using fixed time step)
        local deltaTime = 1/30 -- Assuming 30 FPS
        updateOrbitMovement(deltaTime)

        -- Get camera position with current height
        local camPos = {
            x = STATE.turboOverview.fixedCamPos.x,
            y = currentHeight,
            z = STATE.turboOverview.fixedCamPos.z
        }

        -- Calculate look direction to the orbit center
        local lookDir = Util.calculateLookAtPoint(camPos, STATE.turboOverview.orbitCenter)

        -- Prepare camera state patch
        local camStatePatch = {
            mode = 0,
            name = "fps",
            -- Updated camera position
            px = camPos.x,
            py = camPos.y,
            pz = camPos.z,
            -- Direction vector to look at target
            dx = lookDir.dx,
            dy = lookDir.dy,
            dz = lookDir.dz,
            -- Rotation from look direction
            rx = lookDir.rx,
            ry = lookDir.ry,
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
        return
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

--- Toggle orbit mode for camera movement
---@return boolean success Whether orbit mode was toggled successfully
function TurboOverviewCamera.moveToPoint()
    if STATE.tracking.mode ~= 'turbo_overview' then
        Util.debugEcho("Turbo Overview camera must be enabled first")
        return false
    end

    -- Toggle orbit mode on/off
    if STATE.turboOverview.isOrbiting and STATE.turboOverview.movingToTarget then
        -- Turn off orbit mode (button released)
        STATE.turboOverview.movingToTarget = false
        Util.debugEcho("Orbit movement stopped")
    else
        -- Turn on orbit mode (button pressed)
        -- Get cursor position and set it as orbit center
        STATE.turboOverview.orbitCenter = getCursorWorldPosition()
        STATE.turboOverview.isOrbiting = true
        STATE.turboOverview.movingToTarget = true

        -- Initialize orbit parameters
        local camPos = STATE.turboOverview.fixedCamPos
        STATE.turboOverview.orbitAngle = calculateOrbitAngle(STATE.turboOverview.orbitCenter, camPos)

        -- Calculate initial distance
        local dx = camPos.x - STATE.turboOverview.orbitCenter.x
        local dz = camPos.z - STATE.turboOverview.orbitCenter.z
        STATE.turboOverview.orbitDistance = math.sqrt(dx*dx + dz*dz)

        -- Reset velocities
        STATE.turboOverview.orbitAngularVelocity = 0
        STATE.turboOverview.orbitForwardVelocity = 0

        -- Record the start time for gradual acceleration
        STATE.turboOverview.moveStartTime = Spring.GetTimer()

        -- Get current mouse position for orbit movement calculation
        STATE.turboOverview.lastMouseX, STATE.turboOverview.lastMouseY = Spring.GetMouseState()

        Util.debugEcho("Orbit movement started")
    end

    return true
end

return {
    TurboOverviewCamera = TurboOverviewCamera
}