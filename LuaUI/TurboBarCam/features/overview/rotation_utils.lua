---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "RotationUtils")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local CameraTracker = ModuleManager.CameraTracker(function(m) CameraTracker = m end)

---@class RotationUtils
local RotationUtils = {}

-- Track motion for smooth cursor-based rotation
local initialMouseX, initialMouseY, lastMouseX, lastMouseY
local hasInitializedCursorRotation = false

-- Constants for rotation
local ROTATION_MOMENTUM_DECAY = 0.95  -- How quickly rotation momentum decays (0-1)
local MIN_ROTATION_SPEED = 0.001      -- Minimum rotation speed to maintain momentum
local MAX_ROTATION_SPEED = 0.009      -- Maximum rotation speed

-- Current rotation momentum
local rotationMomentum = 0

--- Initialize cursor rotation state when starting a drag
---@param startX number Initial X position of cursor
---@param startY number Initial Y position of cursor
---@return boolean initialized Whether initialization was successful
function RotationUtils.initCursorRotation(startX, startY)
    initialMouseX = startX
    initialMouseY = startY
    lastMouseX = startX
    lastMouseY = startY
    hasInitializedCursorRotation = true

    Log:trace("Initialized cursor rotation at " .. startX .. "," .. startY)
    return true
end

--- Updates camera rotation based on cursor delta movement
---@param dx number Delta X movement since last update
---@param dy number Delta Y movement since last update
---@return boolean updated Whether rotation was updated
function RotationUtils.updateCursorRotation(dx, dy)
    -- Check if we've properly initialized
    if not hasInitializedCursorRotation then
        return false
    end

    -- If no significant movement, exit
    if math.abs(dx) < 1 and math.abs(dy) < 1 then
        return false
    end

    -- Update tracking positions
    lastMouseX = lastMouseX + dx
    lastMouseY = lastMouseY + dy

    -- Calculate rotation speed based on deltas
    local sensitivity = CONFIG.CAMERA_MODES.OVERVIEW.MOUSE_MOVE_SENSITIVITY * 2
    local screenWidth, screenHeight = Spring.GetViewGeometry()
    local rotationFactorX = sensitivity * (dx / screenWidth) * 15
    local rotationFactorY = sensitivity * (dy / screenHeight) * 15

    -- Update target rotations with INVERTED directions for natural feel
    STATE.active.mode.overview.targetRy = STATE.active.mode.overview.targetRy + rotationFactorX
    STATE.active.mode.overview.targetRx = STATE.active.mode.overview.targetRx - rotationFactorY

    -- Normalize angles
    STATE.active.mode.overview.targetRy = CameraCommons.normalizeAngle(STATE.active.mode.overview.targetRy)

    -- Vertical rotation constraint - allow looking more downward
    STATE.active.mode.overview.targetRx = math.max(math.pi / 3, math.min(math.pi, STATE.active.mode.overview.targetRx))

    return true
end

--- Reset cursor rotation state when drag is complete
function RotationUtils.resetCursorRotation()
    initialMouseX = nil
    initialMouseY = nil
    lastMouseX = nil
    lastMouseY = nil
    hasInitializedCursorRotation = false
end

-- Ensure rotation parameters are initialized with hardcoded defaults
local function ensureRotationParams()
    -- Set hardcoded values for required parameters
    STATE.active.mode.overview.maxRotationSpeed = 0.05 -- Hardcoded default value
    STATE.active.mode.overview.edgeRotationMultiplier = 2.0 -- Hardcoded default value
    STATE.active.mode.overview.maxAngularVelocity = 0.1 -- Hardcoded default value
    STATE.active.mode.overview.angularDamping = 0.98 -- Hardcoded default value

    Log:trace("Rotation parameters initialized with hardcoded values")
end

function RotationUtils.toggleRotation()
    if Utils.isModeDisabled("overview") then
        return false
    end

    if STATE.active.mode.overview.isRotationModeActive then
        -- Disable rotation mode
        STATE.active.mode.overview.isRotationModeActive = false
        STATE.active.mode.overview.rotationCenter = nil
        STATE.active.mode.overview.rotationDistance = nil
        STATE.active.mode.overview.rotationAngle = nil
        STATE.active.mode.overview.rotationSpeed = nil
        rotationMomentum = 0
        Log:trace("Rotation mode disabled")
        return false
    else
        -- Ensure rotation parameters are properly initialized
        ensureRotationParams()

        -- Enable rotation mode ONLY if we have a last target point
        if not STATE.active.mode.overview.lastTargetPoint then
            Log:trace("Cannot enable rotation: No target point available. Use 'Move to Target' first.")
            return false
        end

        -- Get current camera state
        local currentCamState = Spring.GetCameraState()
        Log:trace(string.format("[DEBUG-ROTATION] Initial camera position: (%.2f, %.2f, %.2f)",
                currentCamState.px, currentCamState.py, currentCamState.pz))

        -- Use the last target point as rotation center
        local targetPoint = STATE.active.mode.overview.lastTargetPoint
        Log:trace(string.format("[DEBUG-ROTATION] Target point: (%.2f, %.2f)",
                targetPoint.x, targetPoint.z))

        -- Calculate distance
        local distance = math.sqrt(
                (currentCamState.px - targetPoint.x) ^ 2 +
                        (currentCamState.pz - targetPoint.z) ^ 2
        )

        -- Calculate angle
        local angle = math.atan2(
                currentCamState.px - targetPoint.x,
                currentCamState.pz - targetPoint.z
        )
        Log:trace(string.format("[DEBUG-ROTATION] Calculated distance: %.2f, angle: %.4f",
                distance, angle))

        -- Calculate target position
        local targetCamPos = {
            x = currentCamState.px,  -- Keep current position for smooth transition
            y = currentCamState.py,
            z = currentCamState.pz
        }

        Log:trace(string.format("[DEBUG-ROTATION] Target camera position: (%.2f, %.2f, %.2f)",
                targetCamPos.x, targetCamPos.y, targetCamPos.z))

        -- Set up rotation state - but don't activate yet
        STATE.active.mode.overview.isRotationModeActive = false -- Will be set to true after transition
        STATE.active.mode.overview.rotationCenter = {
            x = targetPoint.x,
            y = targetPoint.y or Spring.GetGroundHeight(targetPoint.x, targetPoint.z) or 0,
            z = targetPoint.z
        }
        STATE.active.mode.overview.rotationDistance = distance
        STATE.active.mode.overview.rotationAngle = angle
        STATE.active.mode.overview.rotationSpeed = 0
        rotationMomentum = 0

        -- *** Set up the transition ***

        -- Store current camera position as starting point for transition
        STATE.active.mode.overview.fixedCamPos = {
            x = currentCamState.px,
            y = currentCamState.py,
            z = currentCamState.pz
        }

        -- Use current position as target (zero-distance transition)
        STATE.active.mode.overview.targetCamPos = targetCamPos

        -- Store the target point
        STATE.active.mode.overview.targetPoint = targetPoint

        -- Calculate look direction
        local lookDir = CameraCommons.calculateCameraDirectionToThePoint(targetCamPos, targetPoint)

        -- Set rotation targets
        STATE.active.mode.overview.targetRx = lookDir.rx
        STATE.active.mode.overview.targetRy = lookDir.ry

        -- Zero distance transition (just to trigger the completeTransition callback)
        local moveDistance = 0

        -- Reset transition tracking variables
        STATE.active.mode.overview.stuckFrameCount = 0
        STATE.active.mode.overview.initialMoveDistance = moveDistance
        STATE.active.mode.overview.lastTransitionDistance = moveDistance

        -- Use a fast transition factor
        STATE.active.mode.overview.currentTransitionFactor = CONFIG.CAMERA_MODES.OVERVIEW.TRANSITION_FACTOR * 2.0

        -- Begin mode transition to trigger completeTransition
        STATE.active.mode.isModeTransitionInProgress = true
        STATE.active.mode.transitionStartTime = Spring.GetTimer()

        -- Flag to enable rotation mode after transition
        STATE.active.mode.overview.enableRotationAfterToggle = true

        -- Update tracking state
        CameraTracker.updateLastKnownCameraState(currentCamState)

        Log:trace("Starting rotation setup (zero-distance transition)")
        return true
    end
end

function RotationUtils.updateRotation()
    if not STATE.active.mode.overview.isRotationModeActive then
        Log:trace("Rotation update called when not in rotation mode")
        return false
    end

    -- Ensure we have all required state values
    if not STATE.active.mode.overview.rotationCenter or not STATE.active.mode.overview.rotationDistance then
        Log:trace("Missing rotation state values - disabling rotation mode")
        RotationUtils.cancelRotation("missing state values")
        return false
    end

    -- Only initialize parameters when actually needed (to reduce log spam)
    if not STATE.active.mode.overview.rotationParametersInitialized then
        -- Ensure rotation parameters are properly initialized
        ensureRotationParams()
        STATE.active.mode.overview.rotationParametersInitialized = true
    end

    -- Apply rotation speed or momentum
    if not STATE.active.mode.overview.rotationSpeed then
        STATE.active.mode.overview.rotationSpeed = 0
    end

    -- If we have a non-zero rotationSpeed, use it directly
    if STATE.active.mode.overview.rotationSpeed ~= 0 then
        -- When actively controlling, use the current rotation speed
        rotationMomentum = STATE.active.mode.overview.rotationSpeed
    else
        -- Apply momentum with decay when not actively controlling
        rotationMomentum = rotationMomentum * ROTATION_MOMENTUM_DECAY

        -- Stop rotation if momentum is too small
        if math.abs(rotationMomentum) < MIN_ROTATION_SPEED then
            rotationMomentum = 0
        end
    end

    -- Apply the effective rotation speed to the angle
    local prevAngle = STATE.active.mode.overview.rotationAngle
    STATE.active.mode.overview.rotationAngle = STATE.active.mode.overview.rotationAngle + rotationMomentum
    STATE.active.mode.overview.rotationAngle = CameraCommons.normalizeAngle(STATE.active.mode.overview.rotationAngle)

    -- Get current camera state to obtain height
    local camState = Spring.GetCameraState()

    -- Calculate sin/cos of the angle
    local sinAngle = math.sin(STATE.active.mode.overview.rotationAngle)
    local cosAngle = math.cos(STATE.active.mode.overview.rotationAngle)

    -- Calculate new camera position based on rotation parameters
    local newCamPos = {
        x = STATE.active.mode.overview.rotationCenter.x + STATE.active.mode.overview.rotationDistance * sinAngle,
        y = camState.py, -- Keep the same height
        z = STATE.active.mode.overview.rotationCenter.z + STATE.active.mode.overview.rotationDistance * cosAngle
    }

    -- Update fixed camera position
    STATE.active.mode.overview.fixedCamPos.x = newCamPos.x
    STATE.active.mode.overview.fixedCamPos.z = newCamPos.z

    -- Calculate look direction to the target point
    local lookDir = CameraCommons.calculateCameraDirectionToThePoint(
            newCamPos,
            STATE.active.mode.overview.rotationCenter
    )

    -- Update target rotations
    STATE.active.mode.overview.targetRx = lookDir.rx
    STATE.active.mode.overview.targetRy = lookDir.ry

    -- Only log rotation updates when actively rotating or angle changed (to reduce spam)
    if rotationMomentum ~= 0 or STATE.active.mode.overview.rotationSpeed ~= 0 or prevAngle ~= STATE.active.mode.overview.rotationAngle then
        Log:trace(string.format("Rotation updated: angle=%.2f, speed=%.4f, momentum=%.4f",
                STATE.active.mode.overview.rotationAngle, STATE.active.mode.overview.rotationSpeed, rotationMomentum))
    end

    return true
end

--- Cancel rotation mode and clean up related states
function RotationUtils.cancelRotation(reason)
    if not STATE.active.mode.overview.isRotationModeActive then
        return false -- Not in rotation mode, nothing to cancel
    end

    STATE.active.mode.overview.isRotationModeActive = false
    STATE.active.mode.overview.rotationCenter = nil
    STATE.active.mode.overview.rotationDistance = nil
    STATE.active.mode.overview.rotationAngle = nil
    STATE.active.mode.overview.rotationSpeed = nil
    STATE.active.mode.overview.rotationParametersInitialized = nil
    STATE.active.mode.overview.isRmbHoldRotation = nil
    STATE.active.mode.overview.exactFinalPosition = nil  -- Clear the exact position storage

    rotationMomentum = 0

    local logReason = reason or "user action"
    Log:trace("Rotation mode canceled due to " .. logReason)
    return true
end

--- Updates rotation speed based on cursor position
---@param cursorX number Current X position of cursor
---@param cursorY number Current Y position of cursor
function RotationUtils.updateRotationSpeed(cursorX, cursorY)
    if not STATE.active.mode.overview.isRotationModeActive then
        Log:trace("Cannot update rotation speed: not in rotation mode")
        return false
    end

    -- Ensure rotation parameters are properly initialized
    ensureRotationParams()

    -- Get screen dimensions to calculate relative cursor position
    local screenWidth, screenHeight = Spring.GetViewGeometry()
    local screenCenterX = screenWidth / 2
    local screenCenterY = screenHeight / 2

    -- Calculate how far the cursor is from the center (normalized 0-1)
    local distanceFromCenterX = (cursorX - screenCenterX) / screenCenterX
    local distanceFromCenterY = (cursorY - screenCenterY) / screenCenterY

    -- Apply a non-linear curve to make speed ramp up more gradually
    -- Use a cubic function to create a more gradual response near the center
    local scaledDistance = math.pow(math.abs(distanceFromCenterX), 3) * (distanceFromCenterX < 0 and -1 or 1)

    -- Calculate rotation speed based on horizontal distance from center
    -- Further from center = faster rotation
    local baseSpeed = scaledDistance * STATE.active.mode.overview.maxRotationSpeed

    -- Apply edge multiplier for more responsive rotation near screen edges
    if math.abs(distanceFromCenterX) > 0.8 then
        baseSpeed = baseSpeed * STATE.active.mode.overview.edgeRotationMultiplier
    end

    -- Limit maximum rotation speed
    baseSpeed = math.max(-MAX_ROTATION_SPEED, math.min(MAX_ROTATION_SPEED, baseSpeed))

    -- Only update if significantly different from current
    if math.abs(baseSpeed - STATE.active.mode.overview.rotationSpeed) > 0.0001 then
        STATE.active.mode.overview.rotationSpeed = baseSpeed

        Log:trace(string.format("Rotation speed updated: %.4f", baseSpeed))
    end

    return true
end

--- Apply momentum after releasing RMB
function RotationUtils.applyMomentum()
    if not STATE.active.mode.overview.isRotationModeActive then
        return false
    end

    -- Transfer current rotation speed to momentum when releasing
    rotationMomentum = STATE.active.mode.overview.rotationSpeed

    -- Clear active control speed to signal we're in momentum mode
    STATE.active.mode.overview.rotationSpeed = 0

    Log:trace(string.format("Applied rotation momentum: %.4f", rotationMomentum))
    return true
end

return RotationUtils