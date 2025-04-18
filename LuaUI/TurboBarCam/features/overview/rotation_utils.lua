---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type OverviewCameraUtils
local OverviewCameraUtils = VFS.Include("LuaUI/TurboBarCam/features/overview/overview_utils.lua").OverviewCameraUtils

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons
local TrackingManager = CommonModules.TrackingManager

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

    Log.trace("Initialized cursor rotation at " .. startX .. "," .. startY)
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
    STATE.overview.targetRy = STATE.overview.targetRy + rotationFactorX
    STATE.overview.targetRx = STATE.overview.targetRx - rotationFactorY

    -- Normalize angles
    STATE.overview.targetRy = CameraCommons.normalizeAngle(STATE.overview.targetRy)

    -- Vertical rotation constraint - allow looking more downward
    STATE.overview.targetRx = math.max(math.pi / 3, math.min(math.pi, STATE.overview.targetRx))

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
    STATE.overview.maxRotationSpeed = 0.05 -- Hardcoded default value
    STATE.overview.edgeRotationMultiplier = 2.0 -- Hardcoded default value
    STATE.overview.maxAngularVelocity = 0.1 -- Hardcoded default value
    STATE.overview.angularDamping = 0.98 -- Hardcoded default value

    Log.debug("Rotation parameters initialized with hardcoded values")
end

function RotationUtils.toggleRotation()
    if Util.isModeDisabled("overview") then
        return false
    end

    if STATE.overview.isRotationModeActive then
        -- Disable rotation mode
        STATE.overview.isRotationModeActive = false
        STATE.overview.rotationCenter = nil
        STATE.overview.rotationDistance = nil
        STATE.overview.rotationAngle = nil
        STATE.overview.rotationSpeed = nil
        rotationMomentum = 0
        Log.debug("Rotation mode disabled")
        return false
    else
        -- Ensure rotation parameters are properly initialized
        ensureRotationParams()

        -- Enable rotation mode ONLY if we have a last target point
        if not STATE.overview.lastTargetPoint then
            Log.debug("Cannot enable rotation: No target point available. Use 'Move to Target' first.")
            return false
        end

        -- Get current camera state
        local currentCamState = CameraManager.getCameraState("RotationUtils.toggleRotation")
        Log.debug(string.format("[DEBUG-ROTATION] Initial camera position: (%.2f, %.2f, %.2f)",
                currentCamState.px, currentCamState.py, currentCamState.pz))

        -- Use the last target point as rotation center
        local targetPoint = STATE.overview.lastTargetPoint
        Log.debug(string.format("[DEBUG-ROTATION] Target point: (%.2f, %.2f)",
                targetPoint.x, targetPoint.z))

        -- Calculate current distance from target
        local currentDistance = math.sqrt(
                (currentCamState.px - targetPoint.x) ^ 2 +
                        (currentCamState.pz - targetPoint.z) ^ 2
        )

        -- CRITICAL: Calculate ideal viewing position
        local currentHeight = currentCamState.py

        -- Calculate a distance factor based on height
        local baseFactor = 0.85
        if currentHeight > 3000 then
            baseFactor = 0.85
        elseif currentHeight > 1500 then
            baseFactor = 0.82
        elseif currentHeight < 800 then
            baseFactor = 0.75
        end

        -- Calculate ideal distance for this height
        local idealDistance = currentHeight * baseFactor

        -- Calculate current angle (but we'll use a different angle for target position)
        local currentAngle = math.atan2(
                currentCamState.px - targetPoint.x,
                currentCamState.pz - targetPoint.z
        )

        -- We'll use an angle 30 degrees (0.5 radians) different from current
        -- This forces the camera to move to a new position
        local angleOffset = 0.785  -- 45 degrees in radians
        local targetAngle

        -- Try to make a more dramatic change in viewing angle
        -- Use opposite side of the target point if close to straight line
        if math.abs(math.sin(currentAngle)) < 0.3 then
            -- If looking directly at target from front/back, move to side view
            targetAngle = currentAngle + math.pi/2
        elseif math.abs(math.cos(currentAngle)) < 0.3 then
            -- If looking directly from side, move to front/back view
            targetAngle = currentAngle + math.pi/2
        else
            -- Otherwise use a 45-degree offset
            targetAngle = currentAngle + angleOffset
        end

        -- Normalize the angle
        targetAngle = CameraCommons.normalizeAngle(targetAngle)

        Log.debug(string.format("[DEBUG-ROTATION] Calculated current distance: %.2f, current angle: %.4f",
                currentDistance, currentAngle))
        Log.debug(string.format("[DEBUG-ROTATION] Using target angle: %.4f, ideal distance: %.2f",
                targetAngle, idealDistance))

        -- Calculate map dimensions for boundary checks
        local mapX = Game.mapSizeX
        local mapZ = Game.mapSizeZ

        -- Calculate target position at idealDistance and the new angle
        local targetX = targetPoint.x + math.sin(targetAngle) * idealDistance
        local targetZ = targetPoint.z + math.cos(targetAngle) * idealDistance

        -- Check if position is within map boundaries with margin
        local margin = 200
        local isPositionValid = targetX >= margin and targetX <= mapX - margin and
                targetZ >= margin and targetZ <= mapZ - margin

        -- If position is invalid, try different angles
        if not isPositionValid then
            -- Try angles in both directions from current angle
            for i = 1, 12 do  -- Try up to 12 different angles
                local offset = (i % 2 == 0) and (i/2) * 0.2 or -(i/2) * 0.2  -- Alternate between positive and negative offsets
                local testAngle = currentAngle + offset
                local testX = targetPoint.x + math.sin(testAngle) * idealDistance
                local testZ = targetPoint.z + math.cos(testAngle) * idealDistance

                if testX >= margin and testX <= mapX - margin and
                        testZ >= margin and testZ <= mapZ - margin then
                    targetX = testX
                    targetZ = testZ
                    targetAngle = testAngle
                    isPositionValid = true
                    Log.debug(string.format("[DEBUG-ROTATION] Found valid position at angle offset: %.2f", offset))
                    break
                end
            end
        end

        -- If still no valid position, use current angle but adjust distance
        if not isPositionValid then
            local adjustedDistance = idealDistance * 0.8  -- Try 80% of ideal distance
            targetX = targetPoint.x + math.sin(currentAngle) * adjustedDistance
            targetZ = targetPoint.z + math.cos(currentAngle) * adjustedDistance

            -- Check if this position is valid
            isPositionValid = targetX >= margin and targetX <= mapX - margin and
                    targetZ >= margin and targetZ <= mapZ - margin

            if isPositionValid then
                targetAngle = currentAngle
                idealDistance = adjustedDistance
                Log.debug(string.format("[DEBUG-ROTATION] Using reduced distance: %.2f", adjustedDistance))
            else
                -- If still invalid, just use current position as fallback
                targetX = currentCamState.px
                targetZ = currentCamState.pz
                targetAngle = currentAngle
                Log.debug("[DEBUG-ROTATION] Could not find valid position, using current position")
            end
        end

        -- Prepare target camera position
        local targetCamPos = {
            x = targetX,
            y = currentHeight,
            z = targetZ
        }

        Log.debug(string.format("[DEBUG-ROTATION] Target camera position: (%.2f, %.2f, %.2f)",
                targetCamPos.x, targetCamPos.y, targetCamPos.z))

        -- Calculate move distance for transition
        local moveDistance = math.sqrt(
                (targetCamPos.x - currentCamState.px) ^ 2 +
                        (targetCamPos.z - currentCamState.pz) ^ 2
        )

        -- Set up rotation state (but don't activate yet)
        STATE.overview.isRotationModeActive = false
        STATE.overview.rotationCenter = {
            x = targetPoint.x,
            y = targetPoint.y or Spring.GetGroundHeight(targetPoint.x, targetPoint.z) or 0,
            z = targetPoint.z
        }

        -- We'll recalculate exact rotation parameters after movement
        STATE.overview.rotationDistance = idealDistance
        STATE.overview.rotationAngle = targetAngle
        STATE.overview.rotationSpeed = 0
        rotationMomentum = 0

        -- Set up the transition
        STATE.overview.fixedCamPos = {
            x = currentCamState.px,
            y = currentCamState.py,
            z = currentCamState.pz
        }

        STATE.overview.targetCamPos = targetCamPos
        STATE.overview.targetPoint = targetPoint

        -- Calculate look direction to the target point
        local lookDir = CameraCommons.calculateCameraDirectionToThePoint(targetCamPos, targetPoint)
        STATE.overview.targetRx = lookDir.rx
        STATE.overview.targetRy = lookDir.ry

        -- Reset transition tracking variables
        STATE.overview.stuckFrameCount = 0
        STATE.overview.initialMoveDistance = moveDistance
        STATE.overview.lastTransitionDistance = moveDistance

        -- Use a smooth transition factor
        STATE.overview.currentTransitionFactor = CONFIG.CAMERA_MODES.OVERVIEW.TRANSITION_FACTOR

        -- Begin mode transition
        STATE.tracking.isModeTransitionInProgress = true
        STATE.tracking.transitionStartTime = Spring.GetTimer()

        -- Flag to enable rotation mode after transition
        STATE.overview.enableRotationAfterToggle = true

        -- Update tracking state
        TrackingManager.updateTrackingState(currentCamState)

        Log.debug(string.format("Starting rotation setup transition. Distance to move: %.2f", moveDistance))
        return true
    end
end

function RotationUtils.updateRotation()
    if not STATE.overview.isRotationModeActive then
        Log.trace("Rotation update called when not in rotation mode")
        return false
    end

    -- Ensure we have all required state values
    if not STATE.overview.rotationCenter or not STATE.overview.rotationDistance then
        Log.debug("Missing rotation state values - disabling rotation mode")
        RotationUtils.cancelRotation("missing state values")
        return false
    end

    -- Only initialize parameters when actually needed (to reduce log spam)
    if not STATE.overview.rotationParametersInitialized then
        -- Ensure rotation parameters are properly initialized
        ensureRotationParams()
        STATE.overview.rotationParametersInitialized = true
    end

    -- Apply rotation speed or momentum
    if not STATE.overview.rotationSpeed then
        STATE.overview.rotationSpeed = 0
    end

    -- If we have a non-zero rotationSpeed, use it directly
    if STATE.overview.rotationSpeed ~= 0 then
        -- When actively controlling, use the current rotation speed
        rotationMomentum = STATE.overview.rotationSpeed
    else
        -- Apply momentum with decay when not actively controlling
        rotationMomentum = rotationMomentum * ROTATION_MOMENTUM_DECAY

        -- Stop rotation if momentum is too small
        if math.abs(rotationMomentum) < MIN_ROTATION_SPEED then
            rotationMomentum = 0
        end
    end

    -- Apply the effective rotation speed to the angle
    local prevAngle = STATE.overview.rotationAngle
    STATE.overview.rotationAngle = STATE.overview.rotationAngle + rotationMomentum
    STATE.overview.rotationAngle = CameraCommons.normalizeAngle(STATE.overview.rotationAngle)

    -- Get current camera state to obtain height
    local camState = CameraManager.getCameraState("RotationUtils.updateRotationMode")

    -- Calculate sin/cos of the angle
    local sinAngle = math.sin(STATE.overview.rotationAngle)
    local cosAngle = math.cos(STATE.overview.rotationAngle)

    -- Calculate new camera position based on rotation parameters
    local newCamPos = {
        x = STATE.overview.rotationCenter.x + STATE.overview.rotationDistance * sinAngle,
        y = camState.py, -- Keep the same height
        z = STATE.overview.rotationCenter.z + STATE.overview.rotationDistance * cosAngle
    }

    -- Update fixed camera position
    STATE.overview.fixedCamPos.x = newCamPos.x
    STATE.overview.fixedCamPos.z = newCamPos.z

    -- Calculate look direction to the target point
    local lookDir = CameraCommons.calculateCameraDirectionToThePoint(
            newCamPos,
            STATE.overview.rotationCenter
    )

    -- Update target rotations
    STATE.overview.targetRx = lookDir.rx
    STATE.overview.targetRy = lookDir.ry

    -- Only log rotation updates when actively rotating or angle changed (to reduce spam)
    if rotationMomentum ~= 0 or STATE.overview.rotationSpeed ~= 0 or prevAngle ~= STATE.overview.rotationAngle then
        Log.trace(string.format("Rotation updated: angle=%.2f, speed=%.4f, momentum=%.4f",
                STATE.overview.rotationAngle, STATE.overview.rotationSpeed, rotationMomentum))
    end

    return true
end

--- Cancel rotation mode and clean up related states
function RotationUtils.cancelRotation(reason)
    if not STATE.overview.isRotationModeActive then
        return false -- Not in rotation mode, nothing to cancel
    end

    STATE.overview.isRotationModeActive = false
    STATE.overview.rotationCenter = nil
    STATE.overview.rotationDistance = nil
    STATE.overview.rotationAngle = nil
    STATE.overview.rotationSpeed = nil
    STATE.overview.rotationParametersInitialized = nil
    STATE.overview.isRmbHoldRotation = nil
    STATE.overview.exactFinalPosition = nil  -- Clear the exact position storage

    rotationMomentum = 0

    local logReason = reason or "user action"
    Log.debug("Rotation mode canceled due to " .. logReason)
    return true
end

--- Updates rotation speed based on cursor position
---@param cursorX number Current X position of cursor
---@param cursorY number Current Y position of cursor
function RotationUtils.updateRotationSpeed(cursorX, cursorY)
    if not STATE.overview.isRotationModeActive then
        Log.debug("Cannot update rotation speed: not in rotation mode")
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
    local baseSpeed = scaledDistance * STATE.overview.maxRotationSpeed

    -- Apply edge multiplier for more responsive rotation near screen edges
    if math.abs(distanceFromCenterX) > 0.8 then
        baseSpeed = baseSpeed * STATE.overview.edgeRotationMultiplier
    end

    -- Limit maximum rotation speed
    baseSpeed = math.max(-MAX_ROTATION_SPEED, math.min(MAX_ROTATION_SPEED, baseSpeed))

    -- Only update if significantly different from current
    if math.abs(baseSpeed - STATE.overview.rotationSpeed) > 0.0001 then
        STATE.overview.rotationSpeed = baseSpeed

        Log.debug(string.format("Rotation speed updated: %.4f", baseSpeed))
    end

    return true
end

--- Apply momentum after releasing RMB
function RotationUtils.applyMomentum()
    if not STATE.overview.isRotationModeActive then
        return false
    end

    -- Transfer current rotation speed to momentum when releasing
    rotationMomentum = STATE.overview.rotationSpeed

    -- Clear active control speed to signal we're in momentum mode
    STATE.overview.rotationSpeed = 0

    Log.debug(string.format("Applied rotation momentum: %.4f", rotationMomentum))
    return true
end

return {
    RotationUtils = RotationUtils
}