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
    rotationMomentum = 0

    local logReason = reason or "user action"
    Log.debug("Rotation mode canceled due to " .. logReason)
    return true
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

        -- Use the last target point as rotation center
        local targetPoint = STATE.overview.lastTargetPoint

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

        -- IMPORTANT: Preserve current camera position
        if not STATE.overview.fixedCamPos then
            STATE.overview.fixedCamPos = {
                x = currentCamState.px,
                z = currentCamState.pz
            }
        end

        -- Set rotation state
        STATE.overview.isRotationModeActive = true
        STATE.overview.rotationCenter = {
            x = targetPoint.x,
            y = targetPoint.y or Spring.GetGroundHeight(targetPoint.x, targetPoint.z) or 0,
            z = targetPoint.z
        }
        STATE.overview.rotationDistance = distance
        STATE.overview.rotationAngle = angle
        STATE.overview.rotationSpeed = 0  -- Initialize with no speed
        rotationMomentum = 0

        -- Calculate desired look direction to the center
        local lookDir = CameraCommons.calculateCameraDirectionToThePoint(
                { x = currentCamState.px, y = currentCamState.py, z = currentCamState.pz },
                STATE.overview.rotationCenter
        )

        -- Update target rotation to look at the rotation center
        STATE.overview.targetRx = lookDir.rx
        STATE.overview.targetRy = lookDir.ry

        -- Start a transition to smooth camera movement to face the center
        if not STATE.tracking.isModeTransitionInProgress then
            STATE.tracking.isModeTransitionInProgress = true
            STATE.tracking.transitionStartTime = Spring.GetTimer()
            STATE.overview.currentTransitionFactor = CONFIG.CAMERA_MODES.OVERVIEW.TRANSITION_FACTOR * 1.5
        end

        Log.debug("Rotation mode enabled around last target point (" ..
                math.floor(targetPoint.x) .. ", " ..
                math.floor(targetPoint.y or 0) .. ", " ..
                math.floor(targetPoint.z) .. ") at distance " ..
                math.floor(distance) .. ", angle " ..
                math.floor(angle * 180 / math.pi)
        )
        return true
    end
end

function RotationUtils.updateRotation()
    if not STATE.overview.isRotationModeActive then
        Log.debug("Rotation update called when not in rotation mode")
        return false
    end

    -- Ensure rotation parameters are properly initialized
    ensureRotationParams()

    -- Ensure we have all required state values
    if not STATE.overview.rotationCenter or not STATE.overview.rotationDistance then
        Log.debug("Missing rotation state values - disabling rotation mode")
        RotationUtils.cancelRotation("missing state values")
        return false
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
    STATE.overview.rotationAngle = STATE.overview.rotationAngle + rotationMomentum
    STATE.overview.rotationAngle = CameraCommons.normalizeAngle(STATE.overview.rotationAngle)

    -- Get current camera state to obtain height
    local camState = CameraManager.getCameraState("RotationUtils.updateRotationMode")

    -- Calculate new camera position based on rotation parameters
    local newCamPos = {
        x = STATE.overview.rotationCenter.x + STATE.overview.rotationDistance * math.sin(STATE.overview.rotationAngle),
        y = camState.py, -- Keep the same height
        z = STATE.overview.rotationCenter.z + STATE.overview.rotationDistance * math.cos(STATE.overview.rotationAngle)
    }

    -- Update fixed camera position
    STATE.overview.fixedCamPos = {
        x = newCamPos.x,
        z = newCamPos.z
    }

    -- Calculate look direction to the target point
    local lookDir = CameraCommons.calculateCameraDirectionToThePoint(
            newCamPos,
            STATE.overview.rotationCenter
    )

    -- Update target rotations
    STATE.overview.targetRx = lookDir.rx
    STATE.overview.targetRy = lookDir.ry

    Log.debug(string.format("Rotation updated: angle=%.2f, speed=%.4f, momentum=%.4f",
            STATE.overview.rotationAngle, STATE.overview.rotationSpeed, rotationMomentum))

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

-- Simple pass-through function for API compatibility
function RotationUtils.adjustParams(params)
    -- This function is kept for API compatibility but all values will be set through
    -- the ensureRotationParams function with hardcoded defaults
    Log.debug("Using hardcoded rotation parameters")
end

return {
    RotationUtils = RotationUtils
}