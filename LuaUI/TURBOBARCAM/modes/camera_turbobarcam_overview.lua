-- Turbo Overview Camera module for TURBOBARCAM with improved freecam
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

-- Helper function to calculate position on movement path
---@param targetPoint table Target point {x, y, z}
---@param angle number Angle in radians
---@param distance number Distance from target
---@param height number Height above ground
---@return table position Position on movement path {x, y, z}
local function calculateMovementPosition(targetPoint, angle, distance, height)
    return {
        x = targetPoint.x + distance * math.sin(angle),
        y = targetPoint.y + height,
        z = targetPoint.z + distance * math.cos(angle)
    }
end

-- Helper function to calculate movement angle between two positions
---@param targetPoint table Target point {x, y, z}
---@param position table Position {x, y, z}
---@return number angle Angle in radians
local function calculateMovementAngle(targetPoint, position)
    return math.atan2(position.x - targetPoint.x, position.z - targetPoint.z)
end

-- NEW: Function for continuous rotation toward cursor position
local function updateCursorTracking()
    -- Skip if we're in another movement mode
    if STATE.turboOverview.isMovingToTarget or STATE.turboOverview.movingToTarget then
        return
    end

    -- Get current mouse position
    local mouseX, mouseY = Spring.GetMouseState()
    local screenWidth, screenHeight = Spring.GetViewGeometry()

    -- Calculate normalized cursor position (-1 to 1) from screen center
    local normalizedX = (mouseX - (screenWidth / 2)) / (screenWidth / 2)
    local normalizedY = (mouseY - (screenHeight / 2)) / (screenHeight / 2)

    -- Calculate distance from center (0-1 range)
    local distanceFromCenter = math.sqrt(normalizedX * normalizedX + normalizedY * normalizedY)

    -- Buffer zone in screen center - no rotation in this area
    if distanceFromCenter < CONFIG.CAMERA_MODES.TURBO_OVERVIEW.BUFFER_ZONE then
        -- Inside buffer zone, no rotation adjustment needed
        return
    end

    -- Calculate gradual rotation multiplier based on distance from buffer zone
    -- This creates a smooth ramp-up from buffer edge to screen edge
    local availableRange = 1.0 - CONFIG.CAMERA_MODES.TURBO_OVERVIEW.BUFFER_ZONE
    local distanceBeyondBuffer = distanceFromCenter - CONFIG.CAMERA_MODES.TURBO_OVERVIEW.BUFFER_ZONE

    -- Apply quadratic/cubic easing for smoother acceleration
    -- This gives a more natural feel with gradual start and stronger finish
    local gradualMultiplier = (distanceBeyondBuffer / availableRange) ^ 2

    -- Check if cursor is at the very edge for maximum speed
    local EDGE_THRESHOLD = 0.05
    local thresholdPixelsX = screenWidth * EDGE_THRESHOLD
    local thresholdPixelsY = screenHeight * EDGE_THRESHOLD

    local isAtEdge = mouseX < thresholdPixelsX or
            mouseX > screenWidth - thresholdPixelsX or
            mouseY < thresholdPixelsY or
            mouseY > screenHeight - thresholdPixelsY

    -- Apply edge multiplier on top of gradual multiplier if at the edge
    local finalMultiplier = gradualMultiplier
    if isAtEdge then
        finalMultiplier = gradualMultiplier * STATE.turboOverview.edgeRotationMultiplier
    end

    -- Calculate rotation speeds based on cursor position and gradual multiplier
    local rySpeed = normalizedX * STATE.turboOverview.maxRotationSpeed * finalMultiplier
    local rxSpeed = -normalizedY * STATE.turboOverview.maxRotationSpeed * finalMultiplier

    -- Update target rotations
    STATE.turboOverview.targetRy = STATE.turboOverview.targetRy + rySpeed
    STATE.turboOverview.targetRx = STATE.turboOverview.targetRx + rxSpeed

    -- Normalize angles
    STATE.turboOverview.targetRy = Util.normalizeAngle(STATE.turboOverview.targetRy)

    -- Vertical rotation constraint
    STATE.turboOverview.targetRx = math.max(math.pi / 2, math.min(math.pi, STATE.turboOverview.targetRx))
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
    STATE.turboOverview.zoomLevels = STATE.turboOverview.zoomLevels or CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ZOOM_LEVELS
    STATE.turboOverview.movementSmoothing = STATE.turboOverview.movementSmoothing or CONFIG.CAMERA_MODES.TURBO_OVERVIEW.DEFAULT_SMOOTHING
    STATE.turboOverview.initialMovementSmoothing = STATE.turboOverview.initialMovementSmoothing or CONFIG.CAMERA_MODES.TURBO_OVERVIEW.INITIAL_SMOOTHING
    STATE.turboOverview.zoomTransitionFactor = STATE.turboOverview.zoomTransitionFactor or CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ZOOM_TRANSITION_FACTOR

    -- NEW: Add configuration for improved cursor tracking
    STATE.turboOverview.cursorTrackingEnabled = true  -- Always enabled, no toggle needed
    STATE.turboOverview.rotationAcceleration = 0.005  -- How fast rotation accelerates toward cursor
    STATE.turboOverview.maxRotationSpeed = 0.015       -- Maximum rotation speed
    STATE.turboOverview.edgeRotationMultiplier = 2.0  -- Faster rotation at screen edges

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
    STATE.turboOverview.mouseMoveSensitivity = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.MOUSE_MOVE_SENSITIVITY / 10
    STATE.turboOverview.targetRx = 0
    STATE.turboOverview.targetRy = 0

    -- Initialize target movement mode variables
    STATE.turboOverview.isMovingToTarget = false
    STATE.turboOverview.targetPoint = nil
    STATE.turboOverview.distanceToTarget = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.TARGET_MOVEMENT.MIN_DISTANCE
    STATE.turboOverview.movementAngle = 0
    STATE.turboOverview.angularVelocity = 0
    STATE.turboOverview.maxAngularVelocity = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.TARGET_MOVEMENT.MAX_ANGULAR_VELOCITY
    STATE.turboOverview.angularDamping = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.TARGET_MOVEMENT.ANGULAR_DAMPING
    STATE.turboOverview.forwardVelocity = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.TARGET_MOVEMENT.FORWARD_VELOCITY
    STATE.turboOverview.minDistanceToTarget = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.TARGET_MOVEMENT.MIN_DISTANCE
    STATE.turboOverview.movementTransitionFactor = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.TARGET_MOVEMENT.TRANSITION_FACTOR
    STATE.turboOverview.inMovementTransition = false
    STATE.turboOverview.targetMovementAngle = 0
    STATE.turboOverview.modeTransitionTime = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.MODE_TRANSITION_TIME

    -- Set a good default height based on map size
    STATE.turboOverview.height = math.max(mapDiagonal * CONFIG.CAMERA_MODES.TURBO_OVERVIEW.HEIGHT_FACTOR, 500)
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
    STATE.turboOverview.targetRx = currentCamState.rx or 0.3
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

-- Updates target movement based on mouse position and button state
local function updateTargetMovement()
    if not STATE.turboOverview.isMovingToTarget then
        return
    end

    -- Get current mouse position
    local mouseX, mouseY = Spring.GetMouseState()

    -- Initialize screen center if needed
    if not STATE.turboOverview.screenCenterX or not STATE.turboOverview.screenCenterY then
        local screenWidth, screenHeight = Spring.GetViewGeometry()
        STATE.turboOverview.screenCenterX = screenWidth / 2
        STATE.turboOverview.screenCenterY = screenHeight / 2
    end

    -- Initialize last mouse position if needed
    if not STATE.turboOverview.lastMouseX or not STATE.turboOverview.lastMouseY then
        STATE.turboOverview.lastMouseX = mouseX
        STATE.turboOverview.lastMouseY = mouseY
        return
    end

    -- Calculate position-based steering
    -- The further from center, the stronger the steering effect
    local distFromCenterX = mouseX - STATE.turboOverview.screenCenterX
    local screenWidth = STATE.turboOverview.screenCenterX * 2
    local normalizedDistFromCenter = distFromCenterX / (screenWidth * 0.5)

    -- Apply a deadzone in the center for stability
    local DEADZONE = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.TARGET_MOVEMENT.DEADZONE
    if math.abs(normalizedDistFromCenter) < DEADZONE then
        normalizedDistFromCenter = 0
    else
        -- Adjust for deadzone and rescale to 0-1 range
        normalizedDistFromCenter = normalizedDistFromCenter * (1.0 / (1.0 - DEADZONE))
        if normalizedDistFromCenter > 1.0 then
            normalizedDistFromCenter = 1.0
        elseif normalizedDistFromCenter < -1.0 then
            normalizedDistFromCenter = -1.0
        end
    end

    -- Set angular velocity based on mouse position
    STATE.turboOverview.angularVelocity = normalizedDistFromCenter * STATE.turboOverview.maxAngularVelocity

    -- Forward velocity is constant when the button is pressed
    if STATE.turboOverview.movingToTarget then
        STATE.turboOverview.forwardVelocity = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.TARGET_MOVEMENT.FORWARD_VELOCITY
    else
        -- Apply damping to angular velocity to smoothly stop turning
        STATE.turboOverview.angularVelocity = STATE.turboOverview.angularVelocity * STATE.turboOverview.angularDamping

        -- Exit movement mode if button is released
        STATE.turboOverview.isMovingToTarget = false
        Util.debugEcho("Exiting target movement mode")
        return
    end

    -- Update movement angle based on angular velocity (steering)
    STATE.turboOverview.movementAngle = STATE.turboOverview.movementAngle + STATE.turboOverview.angularVelocity

    -- Update distance to target based on forward velocity
    STATE.turboOverview.distanceToTarget = math.max(
            STATE.turboOverview.minDistanceToTarget,
            STATE.turboOverview.distanceToTarget - STATE.turboOverview.forwardVelocity
    )

    -- Calculate new position on movement path
    local newPos = calculateMovementPosition(
            STATE.turboOverview.targetPoint,
            STATE.turboOverview.movementAngle,
            STATE.turboOverview.distanceToTarget,
            calculateCurrentHeight()
    )

    -- Update fixed camera position with transitional smoothing during movement initialization
    if STATE.turboOverview.inMovementTransition then
        -- During transition, smoothly move from current position to new position
        STATE.turboOverview.fixedCamPos = {
            x = Util.smoothStep(STATE.turboOverview.fixedCamPos.x, newPos.x, STATE.turboOverview.movementTransitionFactor),
            y = Util.smoothStep(STATE.turboOverview.fixedCamPos.y, newPos.y, STATE.turboOverview.movementTransitionFactor),
            z = Util.smoothStep(STATE.turboOverview.fixedCamPos.z, newPos.z, STATE.turboOverview.movementTransitionFactor)
        }

        -- Calculate look direction to target
        local targetLookDir = Util.calculateLookAtPoint(STATE.turboOverview.fixedCamPos, STATE.turboOverview.targetPoint)

        -- Smoothly transition rotation to point to target
        STATE.turboOverview.targetRx = Util.smoothStep(STATE.turboOverview.targetRx, targetLookDir.rx, STATE.turboOverview.movementTransitionFactor)
        STATE.turboOverview.targetRy = Util.smoothStepAngle(STATE.turboOverview.targetRy, targetLookDir.ry, STATE.turboOverview.movementTransitionFactor)

        -- Check if we've reached the movement path (close enough)
        local dx = STATE.turboOverview.fixedCamPos.x - newPos.x
        local dz = STATE.turboOverview.fixedCamPos.z - newPos.z
        local distSquared = dx * dx + dz * dz

        if distSquared < 1 then
            STATE.turboOverview.inMovementTransition = false
            STATE.turboOverview.fixedCamPos = newPos
        end
    else
        STATE.turboOverview.fixedCamPos = newPos
    end

    -- Check if we're very close to the target, and if so, stop moving
    if STATE.turboOverview.distanceToTarget <= STATE.turboOverview.minDistanceToTarget + 1 then
        STATE.turboOverview.isMovingToTarget = false
        STATE.turboOverview.movingToTarget = false
        Util.debugEcho("Reached target position")
    end
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

    -- Update target movement if in that mode
    if STATE.turboOverview.isMovingToTarget then
        updateTargetMovement()

        -- Get camera position with current height
        local camPos = {
            x = STATE.turboOverview.fixedCamPos.x,
            y = currentHeight,
            z = STATE.turboOverview.fixedCamPos.z
        }

        -- Calculate look direction to the target point
        local lookDir = Util.calculateLookAtPoint(camPos, STATE.turboOverview.targetPoint)

        -- During movement transition, smoothly interpolate between current rotation and target rotation
        local rx, ry
        if STATE.turboOverview.inMovementTransition then
            rx = Util.smoothStep(STATE.tracking.lastRotation.rx, lookDir.rx, STATE.turboOverview.movementTransitionFactor)
            ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, lookDir.ry, STATE.turboOverview.movementTransitionFactor)
        else
            rx = lookDir.rx
            ry = lookDir.ry
        end

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
        return
    end

    -- Use continuous rotation based on cursor position
    updateCursorTracking()

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

--- Moves the camera toward a target point with steering capability
---@return boolean success Whether the camera started moving successfully
function TurboOverviewCamera.moveToTarget()
    if STATE.tracking.mode ~= 'turbo_overview' then
        Util.debugEcho("Turbo Overview camera must be enabled first")
        return false
    end

    -- Toggle target movement mode on/off
    if STATE.turboOverview.movingToTarget then
        STATE.turboOverview.movingToTarget = false
        Util.debugEcho("Target movement mode exited")
    else
        -- Get cursor position and set it as target point
        STATE.turboOverview.targetPoint = getCursorWorldPosition()

        -- Get current camera state
        local currentCamState = Spring.GetCameraState()

        -- Begin mode transition explicitly
        STATE.tracking.modeTransition = true
        STATE.tracking.transitionStartTime = Spring.GetTimer()

        -- Start movement mode
        STATE.turboOverview.isMovingToTarget = true

        -- Store the screen center coordinates for relative cursor position calculations
        local screenWidth, screenHeight = Spring.GetViewGeometry()
        STATE.turboOverview.screenCenterX = screenWidth / 2
        STATE.turboOverview.screenCenterY = screenHeight / 2

        -- Initialize movement parameters
        local camPos = STATE.turboOverview.fixedCamPos

        -- Calculate initial look angle to target
        local lookDir = Util.calculateLookAtPoint(camPos, STATE.turboOverview.targetPoint)

        -- Set initial target rotation to match current view direction
        -- This ensures smooth transition from current view to target
        STATE.turboOverview.targetRx = currentCamState.rx
        STATE.turboOverview.targetRy = currentCamState.ry

        -- Calculate the movement angle based on camera position
        STATE.turboOverview.movementAngle = calculateMovementAngle(STATE.turboOverview.targetPoint, camPos)
        STATE.turboOverview.targetMovementAngle = STATE.turboOverview.movementAngle

        -- Calculate initial distance
        local dx = camPos.x - STATE.turboOverview.targetPoint.x
        local dz = camPos.z - STATE.turboOverview.targetPoint.z
        STATE.turboOverview.distanceToTarget = math.sqrt(dx * dx + dz * dz)

        -- Set the angular velocity to 0 initially
        STATE.turboOverview.angularVelocity = 0

        -- Set the forward velocity constant from CONFIG
        STATE.turboOverview.forwardVelocity = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.TARGET_MOVEMENT.FORWARD_VELOCITY

        -- Turn on active movement
        STATE.turboOverview.movingToTarget = true

        -- Enable movement transition mode (for smooth entry)
        STATE.turboOverview.inMovementTransition = true

        -- Record the start time for gradual acceleration
        STATE.turboOverview.moveStartTime = Spring.GetTimer()

        -- Get current mouse position
        STATE.turboOverview.lastMouseX, STATE.turboOverview.lastMouseY = Spring.GetMouseState()

        Util.debugEcho("Target movement mode started")
    end

    return true
end

return {
    TurboOverviewCamera = TurboOverviewCamera
}