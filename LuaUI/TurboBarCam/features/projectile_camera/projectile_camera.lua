---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type VelocityTracker
local VelocityTracker = VFS.Include("LuaUI/TurboBarCam/standalone/velocity_tracker.lua")
---@type ProjectileTracker
local ProjectileTracker = VFS.Include("LuaUI/TurboBarCam/standalone/projectile_tracker.lua")
---@type TransitionUtil
local TransitionUtil = VFS.Include("LuaUI/TurboBarCam/standalone/transition_util.lua")
---@type ProjectileCameraUtils
local ProjectileCameraUtils = VFS.Include("LuaUI/TurboBarCam/features/projectile_camera/projectile_camera_utils.lua")
---@type TransitionManager
local TransitionManager = VFS.Include("LuaUI/TurboBarCam/core/transition_manager.lua")
---@type CameraTracker
local CameraTracker = VFS.Include("LuaUI/TurboBarCam/standalone/camera_tracker.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons
local ModeManager = CommonModules.ModeManager

---@class ProjectileCamera
local ProjectileCamera = {}

local PROJECTILE_CAMERA_TRANSITION_PREFIX = "ProjectileCamera."
local MODE_ENTRY_TRANSITION_ID = PROJECTILE_CAMERA_TRANSITION_PREFIX .. "MODE_ENTRY_TRANSITION_ID"
local HIGH_ARC_DIRECTION_TRANSITION_ID = PROJECTILE_CAMERA_TRANSITION_PREFIX .. "HIGH_ARC_DIRECTION_TRANSITION_ID"
local IMPACT_DECELERATION_TRANSITION_ID = PROJECTILE_CAMERA_TRANSITION_PREFIX .. "IMPACT_DECELERATION_TRANSITION_ID"
local MIN_PROJECTILE_SPEED_FOR_TURN_DETECT = 1.0
local HIGH_ARC_THRESHOLD = 0.8

--------------------------------------------------------------------------------
-- Public API Functions
--------------------------------------------------------------------------------
function ProjectileCamera.followProjectile()
    return ProjectileCamera.toggle("follow")
end

function ProjectileCamera.trackProjectile()
    return ProjectileCamera.toggle("static")
end

--------------------------------------------------------------------------------
-- Core Toggling and State Management
--------------------------------------------------------------------------------
function ProjectileCamera.toggle(requestedSubMode)
    if Util.isTurboBarCamDisabled() then
        return
    end
    local unitToWatchForToggle = STATE.mode.unitID
    if not unitToWatchForToggle then
        return false
    end

    local currentActualMode = STATE.mode.name
    local isArmed = STATE.mode.projectile_camera.armed
    local isFollowingProjectileMode = currentActualMode == 'projectile_camera'
    local currentSubMode = STATE.mode.projectile_camera.cameraMode
    local isContinuous = (STATE.mode.projectile_camera.continuouslyArmedUnitID == unitToWatchForToggle)
    local isImpactDecelerating = TransitionManager.isTransitioning(IMPACT_DECELERATION_TRANSITION_ID)

    if isFollowingProjectileMode or isImpactDecelerating then
        if currentSubMode == requestedSubMode and not isImpactDecelerating then
            ProjectileCamera.saveSettings(unitToWatchForToggle)
            STATE.mode.projectile_camera.continuouslyArmedUnitID = nil
            ProjectileCamera.returnToPreviousMode(false)
            return true
        else
            return ProjectileCamera.switchCameraSubModes(requestedSubMode)
        end
    elseif isArmed then
        if currentSubMode == requestedSubMode then
            ProjectileCamera.saveSettings(unitToWatchForToggle)
            STATE.mode.projectile_camera.continuouslyArmedUnitID = nil
            ProjectileCamera.disableProjectileArming()
            return true
        else
            return ProjectileCamera.switchCameraSubModes(requestedSubMode)
        end
    elseif isContinuous then
        if currentSubMode == requestedSubMode then
            ProjectileCamera.saveSettings(unitToWatchForToggle)
            STATE.mode.projectile_camera.continuouslyArmedUnitID = nil
            ProjectileCamera.disableProjectileArming()
            return true
        else
            ProjectileCamera.loadSettings(unitToWatchForToggle)
            return ProjectileCamera.armProjectileTracking(requestedSubMode, unitToWatchForToggle)
        end
    else
        if Util.isTurboBarCamDisabled() then
            return false
        end
        if not currentActualMode or not Util.tableContains(CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.COMPATIBLE_MODES_FROM, currentActualMode) then
            return false
        end

        STATE.mode.projectile_camera.continuouslyArmedUnitID = unitToWatchForToggle
        ProjectileCamera.loadSettings(unitToWatchForToggle)
        return ProjectileCamera.armProjectileTracking(requestedSubMode, unitToWatchForToggle)
    end
end

function ProjectileCamera.armProjectileTracking(subMode, unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then
        return false
    end

    if not STATE.mode.projectile_camera.armed and STATE.mode.name ~= 'projectile_camera' then
        if not STATE.mode.projectile_camera.previousCameraState then
            STATE.mode.projectile_camera.previousMode = STATE.mode.name
            STATE.mode.projectile_camera.previousCameraState = Spring.GetCameraState()
        end
    end

    STATE.mode.projectile_camera.cameraMode = subMode

    if subMode == "static" then
        local camState = Spring.GetCameraState()
        STATE.mode.projectile_camera.initialCamPos = { x = camState.px, y = camState.py, z = camState.pz }
    else
        STATE.mode.projectile_camera.initialCamPos = nil
    end

    STATE.mode.projectile_camera.armed = true
    STATE.mode.projectile_camera.watchedUnitID = unitID
    STATE.mode.projectile_camera.lastArmingTime = Spring.GetGameSeconds()
    STATE.mode.projectile_camera.impactPosition = nil
    STATE.mode.projectile_camera.initialImpactVelocity = nil
    STATE.mode.projectile_camera.initialImpactRotVelocity = nil
    STATE.mode.projectile_camera.isHighArc = false

    TransitionManager.cancelPrefix(PROJECTILE_CAMERA_TRANSITION_PREFIX)
    STATE.mode.projectile_camera.transitionFactor = nil

    if STATE.mode.projectile_camera.projectile then
        STATE.mode.projectile_camera.projectile.selectedProjectileID = nil
        STATE.mode.projectile_camera.projectile.currentProjectileID = nil
        ProjectileCameraUtils.resetSmoothedPositions()
    end

    ProjectileTracker.initUnitTracking(unitID)
    return true
end

function ProjectileCamera.disableProjectileArming()
    STATE.mode.projectile_camera.armed = false
    STATE.mode.projectile_camera.impactPosition = nil
    STATE.mode.projectile_camera.initialImpactVelocity = nil
    STATE.mode.projectile_camera.initialImpactRotVelocity = nil
    STATE.mode.projectile_camera.isHighArc = false

    TransitionManager.cancelPrefix(HIGH_ARC_DIRECTION_TRANSITION_ID)

    if STATE.mode.projectile_camera.projectile then
        STATE.mode.projectile_camera.projectile.selectedProjectileID = nil
        STATE.mode.projectile_camera.projectile.currentProjectileID = nil
    end
    Log.debug("Projectile tracking disabled") -- This was an original log message
end

function ProjectileCamera.switchCameraSubModes(newSubMode)
    STATE.mode.projectile_camera.cameraMode = newSubMode
    if newSubMode == "static" and not STATE.mode.projectile_camera.initialCamPos then
        if STATE.mode.name == 'projectile_camera' or STATE.mode.projectile_camera.armed then
            local camState = Spring.GetCameraState()
            STATE.mode.projectile_camera.initialCamPos = { x = camState.px, y = camState.py, z = camState.pz }
        end
    end
    ProjectileCameraUtils.resetSmoothedPositions()
    return true
end

function ProjectileCamera.returnToPreviousMode(shouldReArm)
    local prevMode = STATE.mode.projectile_camera.previousMode
    local prevCamState = STATE.mode.projectile_camera.previousCameraState
    local previouslyWatchedUnitID = STATE.mode.projectile_camera.watchedUnitID
    local unitToReArmWith = STATE.mode.projectile_camera.continuouslyArmedUnitID

    local prevCamStateCopy = Util.deepCopy(prevCamState)
    ProjectileCamera.disableProjectileArming()

    local canReArm = shouldReArm and unitToReArmWith and Spring.ValidUnitID(unitToReArmWith)

    if prevMode and prevMode ~= 'projectile_camera' then
        local targetForPrevMode
        local effectiveTargetUnit = previouslyWatchedUnitID
        if ProjectileCameraUtils.isUnitCentricMode(prevMode) and effectiveTargetUnit and Spring.ValidUnitID(effectiveTargetUnit) then
            targetForPrevMode = effectiveTargetUnit
        elseif ProjectileCameraUtils.isUnitCentricMode(prevMode) and unitToReArmWith and Spring.ValidUnitID(unitToReArmWith) then
            targetForPrevMode = unitToReArmWith
        end
        ModeManager.initializeMode(prevMode, targetForPrevMode, nil, true, prevCamStateCopy)

    elseif STATE.mode.name == 'projectile_camera' then
        ModeManager.disableMode()
    end

    if not canReArm then
        STATE.mode.projectile_camera.continuouslyArmedUnitID = nil
        STATE.mode.projectile_camera.previousMode = nil
        STATE.mode.projectile_camera.previousCameraState = nil
    else
        ProjectileCamera.loadSettings(unitToReArmWith)
        ProjectileCamera.armProjectileTracking(STATE.mode.projectile_camera.cameraMode, unitToReArmWith)
    end
end

--------------------------------------------------------------------------------
-- Activation and Main Update Loop
--------------------------------------------------------------------------------
function ProjectileCamera.checkAndActivate()
    if STATE.mode.name == 'projectile_camera' and STATE.mode.projectile_camera.returnToPreviousMode then
        local unitID = STATE.mode.projectile_camera.watchedUnitID
        local reArm = (STATE.mode.projectile_camera.continuouslyArmedUnitID == unitID and Spring.ValidUnitID(unitID))
        if unitID and not reArm then
            ProjectileCamera.saveSettings(unitID)
        end
        ProjectileCamera.returnToPreviousMode(reArm)
        STATE.mode.projectile_camera.returnToPreviousMode = false
        return true
    end

    if not STATE.mode.projectile_camera.armed or STATE.mode.name == 'projectile_camera' then
        return false
    end

    local unitID = STATE.mode.projectile_camera.watchedUnitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        ProjectileCamera.disableProjectileArming()
        STATE.mode.projectile_camera.continuouslyArmedUnitID = nil
        return false
    end

    local allProjectiles = ProjectileTracker.getUnitProjectiles(unitID)
    local newProjectiles = {}
    for _, p in ipairs(allProjectiles) do
        if p.creationTime > STATE.mode.projectile_camera.lastArmingTime then
            table.insert(newProjectiles, p)
        end
    end

    if #newProjectiles == 0 then
        return false
    end

    local modeState = STATE.mode.projectile_camera
    if ModeManager.initializeMode('projectile_camera', unitID, STATE.TARGET_TYPES.UNIT) then
        STATE.mode.projectile_camera = modeState
        STATE.mode.projectile_camera.armed = false -- Consume armed state
        Log.trace("ProjectileCamera: CheckAndActivate - Activated, tracking new projectile from unit", unitID, "(Original log trace)")
        return true
    else
        local reArm = (STATE.mode.projectile_camera.continuouslyArmedUnitID == unitID)
        ProjectileCamera.returnToPreviousMode(reArm)
        return false
    end
end

function ProjectileCamera.update(dt)
    if not ProjectileCamera.shouldUpdate() then
        return
    end
    -- mode initialization is handled inside trackActiveProjectile because it has to select projectile first

    local unitID = STATE.mode.unitID
    if not ProjectileCamera.validateUnit(unitID) then
        local reArm = (STATE.mode.projectile_camera.continuouslyArmedUnitID == unitID)
        if unitID and not reArm then
            ProjectileCamera.saveSettings(unitID)
        end
        ProjectileCamera.returnToPreviousMode(reArm)
        return
    end

    if TransitionManager.isTransitioning(IMPACT_DECELERATION_TRANSITION_ID) then
        return
    end

    STATE.mode.projectile_camera.projectile = STATE.mode.projectile_camera.projectile or {}
    STATE.mode.projectile_camera.projectile.smoothedPositions = STATE.mode.projectile_camera.projectile.smoothedPositions or { camPos = nil, targetPos = nil }

    if not STATE.mode.projectile_camera.projectile.currentProjectileID then
        ProjectileCamera.selectProjectile(unitID)
        if not STATE.mode.projectile_camera.projectile.currentProjectileID then
            ProjectileCamera.handleImpactView()
            return
        end
    end

    ProjectileCamera.handleProjectileTracking(unitID, dt)
end

--------------------------------------------------------------------------------
-- Internal Update Helpers and Projectile Logic
--------------------------------------------------------------------------------
function ProjectileCamera.handleProjectileTracking(unitID, dt)
    ---@type Projectile
    local currentProjectile = ProjectileCamera.getCurrentProjectile(unitID)
    if currentProjectile and currentProjectile.position then
        STATE.mode.projectile_camera.impactPosition = {
            pos = Util.deepCopy(currentProjectile.position),
            vel = Util.deepCopy(currentProjectile.velocity)
        }
        ProjectileCamera.trackActiveProjectile(currentProjectile)
    else
        ProjectileCamera.handleImpactView()
    end
end

function ProjectileCamera.getCurrentProjectile(unitID)
    if not STATE.mode.projectile_camera.projectile or not STATE.mode.projectile_camera.projectile.currentProjectileID then
        return nil
    end
    local currentID = STATE.mode.projectile_camera.projectile.currentProjectileID
    local projectiles = ProjectileTracker.getUnitProjectiles(unitID)
    for _, proj in ipairs(projectiles) do
        if proj.id == currentID then
            return proj
        end
    end
    return nil
end

---@param currentProjectile Projectile
function ProjectileCamera.trackActiveProjectile(currentProjectile)
    if STATE.mode.projectile_camera.isHighArc and not TransitionManager.isTransitioning(HIGH_ARC_DIRECTION_TRANSITION_ID) then
        ProjectileCamera.handleHighArcProjectileTurn(currentProjectile)
    end

    if not STATE.mode.projectile_camera.isModeInitialized and not TransitionManager.isTransitioning(MODE_ENTRY_TRANSITION_ID) then
        ProjectileCamera.startModeTransition(currentProjectile)
        return
    end

    if TransitionManager.isTransitioning(MODE_ENTRY_TRANSITION_ID) then
        return
    end

    ProjectileCamera.updateCameraStateForProjectile(currentProjectile)
end

function ProjectileCamera.updateCameraStateForProjectile(currentProjectile)
    local projectilePos = currentProjectile.position
    local projectileVelocity = currentProjectile.velocity
    local camPos = ProjectileCameraUtils.calculateCameraPositionForProjectile(projectilePos, projectileVelocity, STATE.mode.projectile_camera.cameraMode, STATE.mode.projectile_camera.isHighArc)
    local targetPos = ProjectileCameraUtils.calculateIdealTargetPosition(projectilePos, projectileVelocity)

    local smoothingFactor = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING_FACTOR
    -- STATE.mode.projectile_camera.transitionFactor can be set by transitions
    smoothingFactor = STATE.mode.projectile_camera.transitionFactor or smoothingFactor

    local finalState = CameraCommons.focusOnPoint(camPos, targetPos, smoothingFactor, smoothingFactor)

    CameraTracker.updateLastKnownCameraState(finalState)
    Spring.SetCameraState(finalState, 0)
end

function ProjectileCamera.startModeTransition(currentProjectile)
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA
    local transitionFactor = cfg.ENTRY_TRANSITION_FACTOR
    local transitionDuration = cfg.ENTRY_TRANSITION_DURATION
    local finalFactor = cfg.SMOOTHING_FACTOR
    STATE.mode.projectile_camera.isModeInitialized = true
    TransitionManager.force({
        id = MODE_ENTRY_TRANSITION_ID,
        duration = transitionDuration,
        easingFn = CameraCommons.easeOut,
        respectGameSpeed = true,
        onUpdate = function(progress, easedProgress, effectiveDt)
            STATE.mode.projectile_camera.transitionFactor = CameraCommons.lerp(transitionFactor, finalFactor, easedProgress)
            STATE.mode.projectile_camera.rampUpFactor = math.max(0.5, easedProgress)
            ProjectileCamera.updateCameraStateForProjectile(currentProjectile)
        end,
        onComplete = function()
            STATE.mode.projectile_camera.rampUpFactor = 1
            STATE.mode.projectile_camera.transitionFactor = nil
        end
    })
end

---@param currentProjectile Projectile
function ProjectileCamera.handleHighArcProjectileTurn(currentProjectile)
    local projectileVelocity = currentProjectile.velocity
    local projectilePreviousVelocity = currentProjectile.previousVelocity
    if projectileVelocity.speed > MIN_PROJECTILE_SPEED_FOR_TURN_DETECT or projectilePreviousVelocity.speed > MIN_PROJECTILE_SPEED_FOR_TURN_DETECT then
        return
    end

    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA
    local ROTATION_THRESHOLD = cfg.DIRECTION_TRANSITION_THRESHOLD

    local currentDir = { x = projectileVelocity.x, y = projectileVelocity.y, z = projectileVelocity.z }
    local lastDir = { x = projectilePreviousVelocity.x, y = projectilePreviousVelocity.y, z = projectilePreviousVelocity.z }
    local currentDirXZ = { x = currentDir.x, y = 0, z = currentDir.z }
    local lastDirXZ = { x = lastDir.x, y = 0, z = lastDir.z }

    local angle = 0
    local magV1_xz = CameraCommons.vectorMagnitude(currentDirXZ)
    local magV2_xz = CameraCommons.vectorMagnitude(lastDirXZ)
    if magV1_xz > 0.01 and magV2_xz > 0.01 then
        local dot_xz = CameraCommons.dotProduct(CameraCommons.normalizeVector(currentDirXZ), CameraCommons.normalizeVector(lastDirXZ))
        dot_xz = math.max(-1.0, math.min(1.0, dot_xz))
        angle = math.acos(dot_xz)
    end


    Log.debug(angle, ROTATION_THRESHOLD, STATE.mode.projectile_camera.highArcGoingUpward)
    if angle > ROTATION_THRESHOLD and STATE.mode.projectile_camera.highArcGoingUpward then
        local highArcFactor = cfg.DIRECTION_TRANSITION_FACTOR
        local normalFactor = cfg.SMOOTHING_FACTOR
        local duration = cfg.DIRECTION_TRANSITION_DURATION


        TransitionManager.start({
            id = HIGH_ARC_DIRECTION_TRANSITION_ID,
            duration = duration,
            easingFn = CameraCommons.easeInOut,
            respectGameSpeed = true,
            onUpdate = function(progress, easedProgress)
                STATE.mode.projectile_camera.transitionFactor = CameraCommons.lerp(highArcFactor, normalFactor, easedProgress)
            end,
            onComplete = function()
                Log.debug("ProjectileCamera: TrackActiveProjectile - DirectionTransition Complete.")
                STATE.mode.projectile_camera.transitionFactor = nil
            end
        })
    end
end

function ProjectileCamera.handleImpactView()
    -- todo handle this somehow if it ever happens
    if not STATE.mode.projectile_camera.impactPosition then
        Log.warn("No impact position available!! Please report a bug")
        ModeManager.disableMode()
        return
    end
    if not TransitionManager.isTransitioning(IMPACT_DECELERATION_TRANSITION_ID) then
        ProjectileCamera.decelerateToImpactPosition()
    end
end

function ProjectileCamera.decelerateToImpactPosition()
    local vel, _, rotVel, _ = VelocityTracker.getCurrentVelocity()
    STATE.mode.projectile_camera.initialImpactVelocity = Util.deepCopy(vel)
    STATE.mode.projectile_camera.initialImpactRotVelocity = Util.deepCopy(rotVel)
    local profile = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DECELERATION_PROFILE
    TransitionManager.force({
        id = IMPACT_DECELERATION_TRANSITION_ID,
        duration = profile.DURATION,
        easingFn = CameraCommons.easeInOut,
        respectGameSpeed = true,
        onUpdate = function(progress, easedProgress, transition_dt)
            local impactWorldPos = STATE.mode.projectile_camera.impactPosition.pos
            local currentCamState = Spring.GetCameraState()

            local initialVelocity = STATE.mode.projectile_camera.initialImpactVelocity or { x = 0, y = 0, z = 0 }
            local initialRotVelocity = STATE.mode.projectile_camera.initialImpactRotVelocity or { x = 0, y = 0, z = 0 }

            local smoothedState = TransitionUtil.smoothDecelerationTransition(currentCamState, transition_dt, easedProgress, initialVelocity, initialRotVelocity, profile)

            local finalCamState
            if smoothedState then
                finalCamState = smoothedState
            else
                finalCamState = Util.deepCopy(currentCamState)
                TransitionManager.finish(IMPACT_DECELERATION_TRANSITION_ID)
                CameraTracker.updateLastKnownCameraState(finalCamState)
                Spring.SetCameraState(finalCamState, 0)
                return
            end

            local targetLookPos = ProjectileCameraUtils.calculateIdealTargetPosition(impactWorldPos, STATE.mode.projectile_camera.impactPosition.vel or { x = 0, y = 0, z = 0 })

            local focusFromPos = { x = finalCamState.px, y = finalCamState.py, z = finalCamState.pz }
            local smoothFactor = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING_FACTOR
            local targetDirState = CameraCommons.focusOnPoint(focusFromPos, targetLookPos, smoothFactor, smoothFactor)

            finalCamState.rx = CameraCommons.lerpAngle(finalCamState.rx, targetDirState.rx, easedProgress)
            finalCamState.ry = CameraCommons.lerpAngle(finalCamState.ry, targetDirState.ry, easedProgress)

            local finalDir = CameraCommons.getDirectionFromRotation(finalCamState.rx, finalCamState.ry, finalCamState.rz)
            finalCamState.dx = finalDir.x
            finalCamState.dy = finalDir.y
            finalCamState.dz = finalDir.z

            CameraTracker.updateLastKnownCameraState(finalCamState)
            Spring.SetCameraState(finalCamState, 0)
        end,
        onComplete = function()
            STATE.mode.projectile_camera.initialImpactVelocity = nil
            STATE.mode.projectile_camera.initialImpactRotVelocity = nil
            STATE.mode.projectile_camera.returnToPreviousMode = true
        end
    })
end

function ProjectileCamera.shouldUpdate()
    if STATE.mode.name ~= 'projectile_camera' then
        return false
    end
    if Util.isTurboBarCamDisabled() then
        return false
    end
    return true
end

function ProjectileCamera.validateUnit(unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then
        return false
    end
    return true
end

function ProjectileCamera.selectProjectile(unitID)
    local allProjectiles = ProjectileTracker.getUnitProjectiles(unitID)
    ---@type Projectile
    local latestValidProjectile
    local maxCreationTime = -1

    for _, p in ipairs(allProjectiles) do
        if p.creationTime > maxCreationTime then
            maxCreationTime = p.creationTime
            latestValidProjectile = p
        end
    end

    local newProjectileSelected = false
    if latestValidProjectile and (STATE.mode.projectile_camera.projectile.currentProjectileID ~= latestValidProjectile.id) then
        newProjectileSelected = true
    elseif not latestValidProjectile and STATE.mode.projectile_camera.projectile.currentProjectileID ~= nil then
        newProjectileSelected = true
    end

    if newProjectileSelected then
        TransitionManager.cancelPrefix(PROJECTILE_CAMERA_TRANSITION_PREFIX)
        STATE.mode.projectile_camera.isHighArc = false
        Log.trace("Projectile changed/lost, resetting direction transition state.") -- Original log
    end

    if latestValidProjectile and newProjectileSelected then
        STATE.mode.projectile_camera.projectile = STATE.mode.projectile_camera.projectile or {}
        STATE.mode.projectile_camera.projectile.selectedProjectileID = latestValidProjectile.id
        STATE.mode.projectile_camera.projectile.currentProjectileID = latestValidProjectile.id
        ProjectileCameraUtils.resetSmoothedPositions()
        Log.trace("ProjectileCamera: Selected projectile " .. latestValidProjectile.id) -- Original log
        STATE.mode.projectile_camera.impactPosition = nil
        STATE.mode.projectile_camera.projectile.trackingStartTime = Spring.GetTimer()

        local projectileVelocity = latestValidProjectile.velocity
        if projectileVelocity.speed > 0.01 then
            local upComponent = projectileVelocity.y
            if upComponent > HIGH_ARC_THRESHOLD then
                STATE.mode.projectile_camera.isHighArc = true
                STATE.mode.projectile_camera.highArcGoingUpward = false -- Initialize based on some criteria if needed
                Log.trace("ProjectileCamera: High Arc detected.") -- Original log
            else
                STATE.mode.projectile_camera.isHighArc = false
            end
        else
            STATE.mode.projectile_camera.isHighArc = false
            STATE.mode.projectile_camera.highArcGoingUpward = false
        end
    elseif newProjectileSelected then
        STATE.mode.projectile_camera.projectile = STATE.mode.projectile_camera.projectile or {}
        STATE.mode.projectile_camera.projectile.selectedProjectileID = nil
        STATE.mode.projectile_camera.projectile.currentProjectileID = nil
        STATE.mode.projectile_camera.projectile.trackingStartTime = nil
    end
end
--------------------------------------------------------------------------------
-- Settings and Parameters
--------------------------------------------------------------------------------
function ProjectileCamera.adjustParams(params)
    return ProjectileCameraUtils.adjustParams(params)
end

function ProjectileCamera.resetToDefaults()
    return ProjectileCameraUtils.resetToDefaults()
end

function ProjectileCamera.saveSettings(unitID)
    return ProjectileCameraUtils.saveSettings(unitID)
end

function ProjectileCamera.loadSettings(unitID)
    return ProjectileCameraUtils.loadSettings(unitID)
end

return {
    ProjectileCamera = ProjectileCamera
}