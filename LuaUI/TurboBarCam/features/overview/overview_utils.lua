---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log

---@class OverviewCameraUtils
local OverviewCameraUtils = {}

--- Uses the current zoom level to determine the appropriate height above ground
---@return number height The camera height in world units
function OverviewCameraUtils.calculateCurrentHeight()
    local zoomFactor = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ZOOM_LEVELS[STATE.turboOverview.zoomLevel]
    -- Enforce minimum height to prevent getting too close to ground
    return math.max(STATE.turboOverview.height / zoomFactor, 500)
end

--- Converts screen cursor position to 3D world coordinates
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
--- Provides gradual rotation speed based on cursor distance from screen center
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

--- Handles moving the camera toward a target point with steering
---@param state table Overview camera state
---@return boolean stateChanged Whether state was updated
function OverviewCameraUtils.updateTargetMovement()
    if not STATE.turboOverview.isMovingToTarget then
        return false
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
        return false
    end

    -- Calculate position-based steering
    -- The further from center, the stronger the steering effect
    local distFromCenterX = mouseX - STATE.turboOverview.screenCenterX
    local screenWidth = STATE.turboOverview.screenCenterX * 2
    local normalizedDistFromCenter = distFromCenterX / (screenWidth * 0.5)

    -- Apply a deadzone in the center for stability
    local DEADZONE = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.DEADZONE
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
        STATE.turboOverview.forwardVelocity = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.FORWARD_VELOCITY
    else
        -- Apply damping to angular velocity to smoothly stop turning
        STATE.turboOverview.angularVelocity = STATE.turboOverview.angularVelocity * STATE.turboOverview.angularDamping
        if CONFIG.CAMERA_MODES.TURBO_OVERVIEW.INVERT_SIDE_MOVEMENT then
            STATE.turboOverview.angularVelocity = STATE.turboOverview.angularVelocity * -1
        end

        -- Exit movement mode if button is released
        STATE.turboOverview.isMovingToTarget = false
        Log.debug("Exiting target movement mode")
        return true
    end

    -- Update movement angle based on angular velocity (steering)
    STATE.turboOverview.movementAngle = STATE.turboOverview.movementAngle + STATE.turboOverview.angularVelocity

    -- Update distance to target based on forward velocity
    STATE.turboOverview.distanceToTarget = math.max(
            STATE.turboOverview.minDistanceToTarget,
            STATE.turboOverview.distanceToTarget - STATE.turboOverview.forwardVelocity
    )

    -- Calculate new position on movement path
    local newPos = OverviewCameraUtils.calculateOrbitPosition(
            STATE.turboOverview.targetPoint,
            STATE.turboOverview.movementAngle,
            STATE.turboOverview.distanceToTarget,
            OverviewCameraUtils.calculateCurrentHeight()
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
        Log.debug("Reached target position")
        return true
    end

    return false
end


--- Calculates a position for orbit-style camera placement
---@param targetPoint table Target point {x, y, z}
---@param angle number Angle in radians
---@param distance number Distance from target
---@param height number Height above ground
---@return table position Position on orbit path {x, y, z}
function OverviewCameraUtils.calculateOrbitPosition(targetPoint, angle, distance, height)
    return {
        x = targetPoint.x + distance * math.sin(angle),
        y = targetPoint.y + height,
        z = targetPoint.z + distance * math.cos(angle)
    }
end

--- Calculates movement angle between two positions
---@param targetPoint table Target point {x, y, z}
---@param position table Position {x, y, z}
---@return number angle Angle in radians
function OverviewCameraUtils.calculateMovementAngle(targetPoint, position)
    return math.atan2(position.x - targetPoint.x, position.z - targetPoint.z)
end

---@see ModifiableParams
---@see Util#adjustParams
function OverviewCameraUtils.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end

    if Util.isModeDisabled("turbo_overview") then
        return false
    end

    Util.

    -- Adjust smoothing factor (keep between 0.001 and 0.5)
    CONFIG.CAMERA_MODES.TURBO_OVERVIEW.MOVEMENT_SMOOTHING = math.max(0.001, math.min(0.5, CONFIG.CAMERA_MODES.TURBO_OVERVIEW.MOVEMENT_SMOOTHING + amount))

    return true
end

return {
    OverviewCameraUtils = OverviewCameraUtils
}