---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log
---@type Util
local Util = VFS.Include("LuaUI/TurboBarCam/common/utils.lua").Util
---@type CameraCommons
local CameraCommons = VFS.Include("LuaUI/TurboBarCam/common/camera_commons.lua").CameraCommons
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/settings/settings_manager.lua").SettingsManager
---@type TransitionManager
local TransitionManager = VFS.Include("LuaUI/TurboBarCam/standalone/transition_manager.lua").TransitionManager

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE

---@class TrackingManager
local TrackingManager = {}

local MODE_TRANSITION_ID = "TrackingManager.MODE_TRANSITION_ID"

--- Initializes tracking
---@param mode string Tracking mode ('fps', 'unit_tracking', 'orbit', 'overview', 'projectile_camera')
---@param target any The target to track (unitID number or point table {x,y,z})
---@param targetType string|nil Target type (optional, will be auto-detected if nil)
---@param automaticMode boolean|nil True if this is an automatic transition
---@param optionalTargetState table|nil Optional camera state to transition towards
---@return boolean success Whether tracking was initialized successfully
function TrackingManager.initializeMode(mode, target, targetType, automaticMode, optionalTargetState)
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

    local allowReinit = optionalTargetState ~= nil
    if STATE.tracking.mode == mode and validType == STATE.tracking.targetType and not TransitionManager.isTransitioning(MODE_TRANSITION_ID) and not allowReinit then
        if validType == STATE.TARGET_TYPES.UNIT and validTarget == STATE.tracking.unitID then
            SettingsManager.saveModeSettings(mode, STATE.tracking.unitID)
            TrackingManager.disableMode()
            return false
        end
    end

    if STATE.tracking.mode ~= mode and not automaticMode then
        -- Clear current mode before enabling a new one, unless it's an automatic transition (e.g., projectile cam activating)
        TrackingManager.disableMode()
    end

    STATE.tracking.transitionTarget = optionalTargetState -- Store target for transition logic if provided

    TrackingManager.startModeTransition(mode) -- This now handles the transition start using TransitionManager
    STATE.tracking.targetType = validType

    if validType == STATE.TARGET_TYPES.UNIT then
        STATE.tracking.unitID = validTarget
        local x, y, z = Spring.GetUnitPosition(validTarget)
        STATE.tracking.targetPoint = { x = x, y = y, z = z } -- Store unit's current position as target point
        STATE.tracking.lastTargetPoint = { x = x, y = y, z = z }
        SettingsManager.loadModeSettings(mode, validTarget)
    else -- STATE.TARGET_TYPES.POINT
        STATE.tracking.targetPoint = validTarget
        STATE.tracking.lastTargetPoint = Util.deepCopy(validTarget)
        STATE.tracking.unitID = nil -- Ensure no unitID is stale
        SettingsManager.loadModeSettings(mode, "point")
    end

    Spring.SelectUnitArray(Spring.GetSelectedUnits()) -- Refreshes selection, could be related to command UI
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
    TransitionManager.stopAll() -- Stop all ongoing transitions

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

    STATE.tracking.projectileWatching = {} -- Reset projectile specific state
    STATE.tracking.projectile = {}         -- Reset projectile specific state

    -- Reset overview state
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
    -- Reset FPS specific state
    STATE.tracking.fps.targetUnitID = nil
    STATE.tracking.fps.isFreeCameraActive = false
    STATE.tracking.graceTimer = nil
    STATE.tracking.lastUnitID = nil
    STATE.tracking.fps.fixedPoint = nil
    STATE.tracking.fps.isFixedPointActive = false
    STATE.tracking.mode = nil -- Critical: Set current mode to nil

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

    -- Reset DollyCam state
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
    STATE.tracking.transitionTarget = nil
    STATE.tracking.transitionProgress = nil -- Clear general mode transition progress
    STATE.tracking.isModeTransitionInProgress = false -- Clear general mode transition flag
    STATE.tracking.transitionStartState = nil -- Clear stored start state
end

--- Starts a mode transition
function TrackingManager.startModeTransition(newMode)
    -- Allow re-transition if a target state is provided, otherwise check if mode is same
    if STATE.tracking.mode == newMode and not STATE.tracking.transitionTarget then
        -- Already in this mode and no specific target state to transition to.
        -- Potentially, one might want to "refresh" the view or re-acquire target if it moved,
        -- but for now, we prevent re-starting the same transition if already in mode.
        return false
    end
    SettingsManager.saveModeSettings(STATE.tracking.mode, STATE.tracking.unitID)

    STATE.tracking.fps.prevMode = STATE.tracking.mode -- Store previous mode, used by FPS
    STATE.tracking.mode = newMode

    -- Get start state *before* starting the transition
    local startState = CameraManager.getCameraState("TrackingManager.startModeTransition")
    STATE.tracking.transitionStartState = startState -- Store for modes that might need it during their update

    -- Use TransitionManager.force to handle timing and cleanup
    TransitionManager.force({
        id = MODE_TRANSITION_ID,
        duration = CONFIG.TRANSITION.MODE_TRANSITION_DURATION,
        easingFn = CameraCommons.easeInOut,
        onUpdate = function(progress, easedProgress, dt)
            -- Update the global progress value that CameraCommons.handleModeTransition will use
            STATE.tracking.transitionProgress = easedProgress
            -- This flag might still be used by some older logic, or can be phased out.
            -- For now, keep it consistent with the transition's lifecycle.
            STATE.tracking.isModeTransitionInProgress = true
        end,
        onComplete = function()
            -- Clear progress and flags on completion
            STATE.tracking.transitionProgress = nil
            STATE.tracking.isModeTransitionInProgress = false
            STATE.tracking.transitionStartState = nil -- Clear the stored start state
            Log.trace("Mode transition completed for mode: " .. STATE.tracking.mode)
        end
    })

    TrackingManager.updateTrackingState(startState) -- Initialize lastCamPos etc. with the start of the transition
    return true
end

return {
    TrackingManager = TrackingManager
}