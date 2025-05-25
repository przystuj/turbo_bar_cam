---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua")
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
---@param mode string Tracking mode ('fps', 'unit_tracking', 'orbit', 'overview', 'projectile_camera')
---@param target any The target to track (unitID number or point table {x,y,z})
---@param targetType string|nil Target type (optional, will be auto-detected if nil)
---@return boolean success Whether tracking was initialized successfully
function TrackingManager.initializeMode(mode, target, targetType, automaticMode)
    if Util.isTurboBarCamDisabled() then
        return false
    end

    local validTarget, validType
    if targetType then
        validTarget = target
        validType = targetType
    else
        validTarget, validType = Util.validateTarget(target)
    end

    if validType == STATE.TARGET_TYPES.NONE then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            validTarget = selectedUnits[1]
            validType = STATE.TARGET_TYPES.UNIT
        else
            return false
        end
    end

    if STATE.tracking.mode == mode and validType == STATE.tracking.targetType and not STATE.tracking.isModeTransitionInProgress then
        if validType == STATE.TARGET_TYPES.UNIT and validTarget == STATE.tracking.unitID then
            SettingsManager.saveModeSettings(mode, STATE.tracking.unitID)
            TrackingManager.disableMode()
            return false
        elseif validType == STATE.TARGET_TYPES.POINT and Util.arePointsEqual(validTarget, STATE.tracking.targetPoint) then
            SettingsManager.saveModeSettings(mode, "point")
            TrackingManager.disableMode()
            return false
        end
    end
    -- clear current mode before enabling new one
    if STATE.tracking.mode ~= mode and not automaticMode then
        TrackingManager.disableMode()
    end

    TrackingManager.startModeTransition(mode)
    STATE.tracking.targetType = validType

    if validType == STATE.TARGET_TYPES.UNIT then
        STATE.tracking.unitID = validTarget
        local x, y, z = Spring.GetUnitPosition(validTarget)
        STATE.tracking.targetPoint = { x = x, y = y, z = z }
        STATE.tracking.lastTargetPoint = { x = x, y = y, z = z }
        SettingsManager.loadModeSettings(mode, validTarget)
    else
        -- POINT
        STATE.tracking.targetPoint = validTarget
        STATE.tracking.lastTargetPoint = Util.deepCopy(validTarget)
        STATE.tracking.unitID = nil
        SettingsManager.loadModeSettings(mode, "point")
    end

    Spring.SelectUnitArray(Spring.GetSelectedUnits())
    return true
end

function TrackingManager.getDefaultHeightForUnitTracking(unitID)
    return math.max(Util.getUnitHeight(unitID), 100)
end

--- Updates tracking state values after applying camera state
---@param camState table Camera state that was applied
function TrackingManager.updateTrackingState(camState)
    STATE.tracking.lastCamPos.x = camState.px
    STATE.tracking.lastCamPos.y = camState.py
    STATE.tracking.lastCamPos.z = camState.pz
    STATE.tracking.lastCamDir.x = camState.dx
    STATE.tracking.lastCamDir.y = camState.dy
    STATE.tracking.lastCamDir.z = camState.dz
    STATE.tracking.lastRotation.rx = camState.rx
    STATE.tracking.lastRotation.ry = camState.ry
    STATE.tracking.lastRotation.rz = camState.rz
end

--- Disables tracking and resets tracking state
function TrackingManager.disableMode()
    if STATE.tracking.targetType == STATE.TARGET_TYPES.UNIT then
        SettingsManager.saveModeSettings(STATE.tracking.mode, STATE.tracking.unitID)
    elseif STATE.tracking.targetType == STATE.TARGET_TYPES.POINT then
        SettingsManager.saveModeSettings(STATE.tracking.mode, "point")
    end

    STATE.transition.active = false
    STATE.transition.currentAnchorIndex = nil
    STATE.tracking.targetType = STATE.TARGET_TYPES.NONE
    STATE.tracking.targetPoint = nil
    STATE.tracking.lastTargetPoint = nil

    STATE.tracking.projectileWatching = {}
    STATE.tracking.projectile = {}

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

    STATE.tracking.unitID = nil
    STATE.tracking.fps.targetUnitID = nil
    STATE.tracking.fps.isFreeCameraActive = false
    STATE.tracking.graceTimer = nil
    STATE.tracking.lastUnitID = nil
    STATE.tracking.fps.fixedPoint = nil
    STATE.tracking.fps.isFixedPointActive = false
    STATE.tracking.mode = nil

    STATE.tracking.fps.inTargetSelectionMode = false
    STATE.tracking.fps.prevFreeCamState = false
    STATE.tracking.fps.prevMode = nil
    STATE.tracking.fps.prevFixedPoint = nil
    STATE.tracking.fps.prevFixedPointActive = nil

    if STATE.tracking.orbit then
        STATE.tracking.orbit.lastPosition = nil
    end

    if STATE.tracking.fps and STATE.tracking.fps.freeCam then
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
        isNavigating = false,
        currentDistance = 0,
        targetSpeed = 0,
        currentSpeed = 0,
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
    if STATE.tracking.mode == newMode then
        return false
    end
    SettingsManager.saveModeSettings(STATE.tracking.mode, STATE.tracking.unitID)

    STATE.tracking.fps.prevMode = STATE.tracking.mode
    STATE.tracking.mode = newMode

    STATE.tracking.isModeTransitionInProgress = true
    STATE.tracking.transitionStartState = CameraManager.getCameraState("TrackingManager.startModeTransition")
    STATE.tracking.transitionStartTime = Spring.GetTimer()

    TrackingManager.updateTrackingState(STATE.tracking.transitionStartState)
    return true
end

return {
    TrackingManager = TrackingManager
}
