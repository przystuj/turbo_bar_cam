-- Overview Camera utils for TURBOBARCAM
---@type {CONFIG: CONFIG, STATE: STATE}
local TurboConfig = VFS.Include("LuaUI/TURBOBARCAM/config/config.lua")
---@type {CameraCommons: CameraCommons, Util: Util, Movement: CameraMovement, Transition: CameraTransition, FreeCam: FreeCam, Tracking: TrackingManager, WidgetControl: WidgetControl}
local TurboCore = VFS.Include("LuaUI/TURBOBARCAM/core.lua")

local CONFIG = TurboConfig.CONFIG
local STATE = TurboConfig.STATE
local Util = TurboCore.Util
local CameraMovement = TurboCore.Movement

---@class OverviewCameraUtils
local OverviewCameraUtils = {}

--- Calculates camera height based on zoom level
---@return number height The camera height
function OverviewCameraUtils.calculateCurrentHeight()
    local zoomFactor = STATE.turboOverview.zoomLevels[STATE.turboOverview.zoomLevel]
    -- Enforce minimum height to prevent getting too close to ground
    return math.max(STATE.turboOverview.height / zoomFactor, 500)
end

--- Gets cursor world position
---@return table position Position {x, y, z}
function OverviewCameraUtils.getCursorWorldPosition()
    local mx, my = Spring.GetMouseState()
    local _, pos = Spring.TraceScreenRay(mx, my, true)

    if pos then
        return { x = pos[1], y = pos[2], z = pos[3] }
    else
        -- Return center of map if cursor is not over the map
        return { x = Game.mapSizeX / 2, y = 0, z = Game.mapSizeZ / 2 }
    end
end

--- Updates camera rotation based on cursor position
---@param state table State object with cursor tracking properties
---@return boolean updated Whether rotation was updated
function OverviewCameraUtils.updateCursorTracking(state)
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
        return false
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
        finalMultiplier = gradualMultiplier * state.edgeRotationMultiplier
    end

    -- Calculate rotation speeds based on cursor position and gradual multiplier
    local rySpeed = normalizedX * state.maxRotationSpeed * finalMultiplier
    local rxSpeed = -normalizedY * state.maxRotationSpeed * finalMultiplier

    -- Update target rotations
    state.targetRy = state.targetRy + rySpeed
    state.targetRx = state.targetRx + rxSpeed

    -- Normalize angles
    state.targetRy = Util.normalizeAngle(state.targetRy)

    -- Vertical rotation constraint
    state.targetRx = math.max(math.pi / 2, math.min(math.pi, state.targetRx))
    
    return true
end

--- Updates target movement mode
---@param state table Overview camera state 
---@return boolean stateChanged Whether state was updated
function OverviewCameraUtils.updateTargetMovement(state)
    if not state.isMovingToTarget then
        return false
    end

    -- Get current mouse position
    local mouseX, mouseY = Spring.GetMouseState()

    -- Initialize screen center if needed
    if not state.screenCenterX or not state.screenCenterY then
        local screenWidth, screenHeight = Spring.GetViewGeometry()
        state.screenCenterX = screenWidth / 2
        state.screenCenterY = screenHeight / 2
    end

    -- Initialize last mouse position if needed
    if not state.lastMouseX or not state.lastMouseY then
        state.lastMouseX = mouseX
        state.lastMouseY = mouseY
        return false
    end

    -- Calculate position-based steering
    -- The further from center, the stronger the steering effect
    local distFromCenterX = mouseX - state.screenCenterX
    local screenWidth = state.screenCenterX * 2
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
    state.angularVelocity = normalizedDistFromCenter * state.maxAngularVelocity

    -- Forward velocity is constant when the button is pressed
    if state.movingToTarget then
        state.forwardVelocity = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.TARGET_MOVEMENT.FORWARD_VELOCITY
    else
        -- Apply damping to angular velocity to smoothly stop turning
        state.angularVelocity = state.angularVelocity * state.angularDamping

        -- Exit movement mode if button is released
        state.isMovingToTarget = false
        Util.debugEcho("Exiting target movement mode")
        return true
    end

    -- Update movement angle based on angular velocity (steering)
    state.movementAngle = state.movementAngle + state.angularVelocity

    -- Update distance to target based on forward velocity
    state.distanceToTarget = math.max(
            state.minDistanceToTarget,
            state.distanceToTarget - state.forwardVelocity
    )

    -- Calculate new position on movement path
    local newPos = CameraMovement.calculateOrbitPosition(
            state.targetPoint,
            state.movementAngle,
            state.distanceToTarget,
            OverviewCameraUtils.calculateCurrentHeight()
    )

    -- Update fixed camera position with transitional smoothing during movement initialization
    if state.inMovementTransition then
        -- During transition, smoothly move from current position to new position
        state.fixedCamPos = {
            x = Util.smoothStep(state.fixedCamPos.x, newPos.x, state.movementTransitionFactor),
            y = Util.smoothStep(state.fixedCamPos.y, newPos.y, state.movementTransitionFactor),
            z = Util.smoothStep(state.fixedCamPos.z, newPos.z, state.movementTransitionFactor)
        }

        -- Calculate look direction to target
        local targetLookDir = Util.calculateLookAtPoint(state.fixedCamPos, state.targetPoint)

        -- Smoothly transition rotation to point to target
        state.targetRx = Util.smoothStep(state.targetRx, targetLookDir.rx, state.movementTransitionFactor)
        state.targetRy = Util.smoothStepAngle(state.targetRy, targetLookDir.ry, state.movementTransitionFactor)

        -- Check if we've reached the movement path (close enough)
        local dx = state.fixedCamPos.x - newPos.x
        local dz = state.fixedCamPos.z - newPos.z
        local distSquared = dx * dx + dz * dz

        if distSquared < 1 then
            state.inMovementTransition = false
            state.fixedCamPos = newPos
        end
    else
        state.fixedCamPos = newPos
    end

    -- Check if we're very close to the target, and if so, stop moving
    if state.distanceToTarget <= state.minDistanceToTarget + 1 then
        state.isMovingToTarget = false
        state.movingToTarget = false
        Util.debugEcho("Reached target position")
        return true
    end
    
    return false
end

--- Adjusts the smoothing factor for cursor following
---@param amount number Amount to adjust smoothing by
---@return boolean success Whether smoothing was adjusted
function OverviewCameraUtils.adjustSmoothing(amount)
    if not STATE.enabled then
        Util.debugEcho("TURBOBARCAM must be enabled first")
        return false
    end

    if STATE.tracking.mode ~= 'turbo_overview' then
        Util.debugEcho("Turbo Overview camera must be enabled first")
        return false
    end

    -- Adjust smoothing factor (keep between 0.001 and 0.5)
    STATE.turboOverview.movementSmoothing = math.max(0.001, math.min(0.5, STATE.turboOverview.movementSmoothing + amount))

    Util.debugEcho("Turbo Overview smoothing: " .. STATE.turboOverview.movementSmoothing)
    return true
end

return {
    OverviewCameraUtils = OverviewCameraUtils
}