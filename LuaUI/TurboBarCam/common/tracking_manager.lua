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

--- Initializes unit tracking
---@param mode string Tracking mode ('fps', 'unit_tracking', 'fixed_point', 'orbit')
---@param unitID number|nil Unit ID to track (optional)
---@return boolean success Whether tracking was initialized successfully
function TrackingManager.initializeTracking(mode, unitID)
    if Util.isTurboBarCamDisabled() then
        return
    end

    -- If no unit provided, use first selected unit
    if not unitID then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits == 0 then
            Log.debug("No unit selected for " .. mode .. " view")
            return false
        end
        unitID = selectedUnits[1]
    end

    -- Check if it's a valid unit
    if not Spring.ValidUnitID(unitID) then
        Log.trace("Invalid unit ID for " .. mode .. " view")
        return false
    end

    -- If we're already tracking this exact unit in the same mode, turn it off
    if STATE.tracking.mode == mode and STATE.tracking.unitID == unitID then
        SettingsManager.saveModeSettings(mode, unitID)
        TrackingManager.disableTracking()
        Log.debug(mode .. " camera detached")
        return false
    end

    -- Begin mode transition from previous mode
    TrackingManager.startModeTransition(mode)
    STATE.tracking.unitID = unitID
    SettingsManager.loadModeSettings(mode, unitID)

    -- refresh unit command bar to add custom command
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
    SettingsManager.saveModeSettings(STATE.tracking.mode, STATE.tracking.unitID)

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