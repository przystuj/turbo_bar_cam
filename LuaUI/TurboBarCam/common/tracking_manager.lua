---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log
---@type Util
local Util = VFS.Include("LuaUI/TurboBarCam/common/utils.lua").Util
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/settings/settings_manager.lua").SettingsManager

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE

---@class TrackingManager
local TrackingManager = {}

--- Initializes tracking
---@param mode string Tracking mode ('fps', 'unit_tracking', 'orbit', 'overview')
---@param target any The target to track (unitID number or point table {x,y,z})
---@param targetType string|nil Target type (optional, will be auto-detected if nil)
---@return boolean success Whether tracking was initialized successfully
function TrackingManager.initializeTracking(mode, target, targetType)
    if Util.isTurboBarCamDisabled() then
        return false
    end

    -- Validate and normalize the target
    local validTarget, validType
    if targetType then
        -- Use the provided type
        validTarget = target
        validType = targetType
    else
        -- Auto-detect target type
        validTarget, validType = Util.validateTarget(target)
    end

    -- If target validation failed, try to get a unit from selection
    if validType == STATE.TARGET_TYPES.NONE then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            validTarget = selectedUnits[1]
            validType = STATE.TARGET_TYPES.UNIT
        else
            Log.debug("No valid target for " .. mode .. " view")
            return false
        end
    end

    -- Check if we're already tracking this exact target in the same mode
    if STATE.tracking.mode == mode and validType == STATE.tracking.targetType then
        if validType == STATE.TARGET_TYPES.UNIT and validTarget == STATE.tracking.unitID then
            SettingsManager.saveModeSettings(mode, STATE.tracking.unitID)
            TrackingManager.disableTracking()
            Log.debug(mode .. " camera detached")
            return false
        end
    end

    -- Begin mode transition from previous mode
    TrackingManager.startModeTransition(mode)

    -- Set the appropriate tracking target fields
    STATE.tracking.targetType = validType

    if validType == STATE.TARGET_TYPES.UNIT then
        STATE.tracking.unitID = validTarget
        -- Store the initial position as the target point too
        local x, y, z = Spring.GetUnitPosition(validTarget)
        STATE.tracking.targetPoint = { x = x, y = y, z = z }
        STATE.tracking.lastTargetPoint = { x = x, y = y, z = z }
        SettingsManager.loadModeSettings(mode, validTarget)
    else
        -- POINT
        STATE.tracking.targetPoint = validTarget
        STATE.tracking.lastTargetPoint = Util.deepCopy(validTarget)
        STATE.tracking.unitID = nil
        -- For point tracking, we can use a generic identifier
        SettingsManager.loadModeSettings(mode, "point")
    end

    -- refresh unit command bar to add custom command if needed
    Spring.SelectUnitArray(Spring.GetSelectedUnits())
    return true
end

function TrackingManager.getDefaultHeightForUnitTracking(unitID)
    return math.max(Util.getUnitHeight(unitID), 100)
end

--- Updates tracking state values after applying camera state
---@param camState table Camera state that was applied
function TrackingManager.updateTrackingState(camState)
    -- Update last camera position
    STATE.tracking.lastCamPos.x = camState.px
    STATE.tracking.lastCamPos.y = camState.py
    STATE.tracking.lastCamPos.z = camState.pz

    -- Update last camera direction
    STATE.tracking.lastCamDir.x = camState.dx
    STATE.tracking.lastCamDir.y = camState.dy
    STATE.tracking.lastCamDir.z = camState.dz

    -- Update last rotation
    STATE.tracking.lastRotation.rx = camState.rx
    STATE.tracking.lastRotation.ry = camState.ry
    STATE.tracking.lastRotation.rz = camState.rz
end

--- Disables tracking and resets tracking state
function TrackingManager.disableTracking()
    if STATE.tracking.targetType == STATE.TARGET_TYPES.UNIT then
        SettingsManager.saveModeSettings(STATE.tracking.mode, STATE.tracking.unitID)
    elseif STATE.tracking.targetType == STATE.TARGET_TYPES.POINT then
        SettingsManager.saveModeSettings(STATE.tracking.mode, "point")
    end

    STATE.transition.active = false
    STATE.transition.currentAnchorIndex = nil

    -- Clear target tracking fields
    STATE.tracking.targetType = STATE.TARGET_TYPES.NONE
    STATE.tracking.targetPoint = nil
    STATE.tracking.lastTargetPoint = nil

    -- Clean up projectile camera state if active
    if STATE.tracking.mode == 'projectile_camera' or STATE.projectileWatching then
        if STATE.projectileWatching then
            STATE.projectileWatching.enabled = false
            STATE.projectileWatching.watchedUnitID = nil
            STATE.projectileWatching.impactTimer = nil
            STATE.projectileWatching.impactPosition = nil
        end

        if STATE.tracking.projectile then
            STATE.tracking.projectile.selectedProjectileID = nil
            STATE.tracking.projectile.currentProjectileID = nil
            STATE.tracking.projectile.smoothedPositions = nil
        end

        Log.trace("Projectile tracking disabled during tracking disablement")
    end

    -- Clean up overview-specific states if in overview mode
    if STATE.tracking.mode == 'overview' then
        STATE.overview.moveButtonPressed = false
        STATE.overview.isRotationModeActive = false
        STATE.overview.rotationCenter = nil
        STATE.overview.rotationDistance = nil
        STATE.overview.rotationAngle = nil
        STATE.overview.lastTargetPoint = nil
        STATE.overview.targetPoint = nil
        STATE.overview.targetCamPos = nil
        STATE.overview.fixedCamPos = nil
        STATE.overview.targetRx = nil
        STATE.overview.targetRy = nil
        STATE.overview.heightLevel = nil
        STATE.overview.targetHeight = nil
        STATE.overview.currentTransitionFactor = nil
        STATE.overview.lastTransitionDistance = nil
        STATE.overview.initialMoveDistance = nil
        STATE.overview.stuckFrameCount = 0
        STATE.overview.userLookedAround = false
        STATE.overview.pendingRotationMode = nil
        STATE.overview.pendingRotationCenter = nil
        STATE.overview.pendingRotationDistance = nil
        STATE.overview.pendingRotationAngle = nil
        STATE.overview.enableRotationAfterToggle = nil
        STATE.overview.movementVelocity = nil
        STATE.overview.velocityDecay = nil

        Log.trace("Overview camera states reset during tracking disablement")
    end

    STATE.tracking.unitID = nil
    STATE.tracking.fps.targetUnitID = nil  -- Clear the target unit ID
    STATE.tracking.fps.isFreeCameraActive = false
    STATE.tracking.graceTimer = nil
    STATE.tracking.lastUnitID = nil
    STATE.tracking.fps.fixedPoint = nil
    STATE.tracking.fps.isFixedPointActive = false
    STATE.tracking.mode = nil

    -- Clear target selection state
    STATE.tracking.fps.inTargetSelectionMode = false
    STATE.tracking.fps.prevFreeCamState = false
    STATE.tracking.fps.prevMode = nil
    STATE.tracking.fps.prevFixedPoint = nil
    STATE.tracking.fps.prevFixedPointActive = nil

    -- Reset orbit-specific states
    if STATE.tracking.orbit then
        STATE.tracking.orbit.lastPosition = nil
    end

    -- Clear freeCam state to prevent null pointer exceptions
    if STATE.tracking.freeCam then
        STATE.tracking.fps.freeCam.lastMouseX = nil
        STATE.tracking.fps.freeCam.lastMouseY = nil
        STATE.tracking.fps.freeCam.targetRx = nil
        STATE.tracking.fps.freeCam.targetRy = nil
        STATE.tracking.fps.freeCam.lastUnitHeading = nil
    end

    if STATE.anchorQueue then
        STATE.anchorQueue.active = false
        STATE.anchorQueue.currentStep = 1
        STATE.anchorQueue.stepStartTime = 0
    end

    STATE.dollyCam = {
        route = { points = {} },
        isNavigating = false, -- Whether navigation is active
        currentDistance = 0, -- Current position along path
        targetSpeed = 0, -- Target speed (-1.0 to 1.0)
        currentSpeed = 0, -- Current interpolated speed
        maxSpeed = 800,
        acceleration = 120,
        alpha = 1,
        visualizationEnabled = true
    }
end

--- Starts a mode transition
---@param newMode string New camera mode
---@return boolean success Whether transition started successfully
function TrackingManager.startModeTransition(newMode)
    -- Only start a transition if we're switching between different modes
    if STATE.tracking.mode == newMode then
        return false
    end
    SettingsManager.saveModeSettings(STATE.tracking.mode, STATE.tracking.unitID)

    -- Disable projectile tracking when switching to a different mode
    if STATE.tracking.mode == 'projectile_camera' or STATE.projectileWatching then
        -- Clean up projectile tracking state
        if STATE.projectileWatching then
            STATE.projectileWatching.enabled = false
            STATE.projectileWatching.watchedUnitID = nil
            STATE.projectileWatching.impactTimer = nil
            STATE.projectileWatching.impactPosition = nil
        end

        -- Clear projectile tracking data
        if STATE.tracking.projectile then
            STATE.tracking.projectile.selectedProjectileID = nil
            STATE.tracking.projectile.currentProjectileID = nil
            STATE.tracking.projectile.smoothedPositions = nil
        end

        Log.trace("Projectile tracking disabled due to mode change to " .. newMode)
    end

    -- Store modes
    STATE.tracking.fps.prevMode = STATE.tracking.mode
    STATE.tracking.mode = newMode

    -- Set up transition state
    STATE.tracking.isModeTransitionInProgress = true
    STATE.tracking.transitionStartState = CameraManager.getCameraState("TrackingManager.startModeTransition")
    STATE.tracking.transitionStartTime = Spring.GetTimer()

    TrackingManager.updateTrackingState(STATE.tracking.transitionStartState)
    return true
end

return {
    TrackingManager = TrackingManager
}