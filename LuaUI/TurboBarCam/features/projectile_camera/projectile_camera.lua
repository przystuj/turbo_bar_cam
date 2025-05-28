---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua")
---@type ProjectileTracker
local ProjectileTracker = VFS.Include("LuaUI/TurboBarCam/standalone/projectile_tracker.lua")
---@type TransitionUtil
local TransitionUtil = VFS.Include("LuaUI/TurboBarCam/standalone/transition_util.lua")
---@type ProjectileCameraUtils
local ProjectileCameraUtils = VFS.Include("LuaUI/TurboBarCam/features/projectile_camera/projectile_camera_utils.lua")
---@type TransitionManager
local TransitionManager = VFS.Include("LuaUI/TurboBarCam/standalone/transition_manager.lua").TransitionManager

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons
local TrackingManager = CommonModules.TrackingManager

---@class ProjectileCamera
local ProjectileCamera = {}

local DIRECTION_TRANSITION_ID = "ProjectileCamera.projectileDirectionTransition"
local MIN_PROJECTILE_SPEED_FOR_TURN_DETECT = 1.0 -- Minimum speed for rotation detection to be active
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
local function getUnitToToggle()
    local unitToWatch = STATE.tracking.unitID
    if not unitToWatch or not Spring.ValidUnitID(unitToWatch) then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            unitToWatch = selectedUnits[1]
        end
    end
    return unitToWatch
end

function ProjectileCamera.toggle(requestedSubMode)
    if Util.isTurboBarCamDisabled() then
        return
    end
    local unitToWatchForToggle = STATE.tracking.unitID
    if not unitToWatchForToggle then
        return false
    end

    local currentActualMode = STATE.tracking.mode
    local isArmed = STATE.tracking.projectileWatching.armed
    local isFollowingProjectileMode = currentActualMode == 'projectile_camera'
    local currentSubMode = STATE.tracking.projectileWatching.cameraMode
    local isContinuous = (STATE.tracking.projectileWatching.continuouslyArmedUnitID == unitToWatchForToggle)
    local isImpactDecelerating = STATE.tracking.projectileWatching.isImpactDecelerating

    if isFollowingProjectileMode or isImpactDecelerating then
        if currentSubMode == requestedSubMode and not isImpactDecelerating then
            ProjectileCamera.saveSettings(unitToWatchForToggle)
            STATE.tracking.projectileWatching.continuouslyArmedUnitID = nil
            ProjectileCamera.returnToPreviousMode(false)
            return true
        else
            return ProjectileCamera.switchCameraSubModes(requestedSubMode)
        end
    elseif isArmed then
        if currentSubMode == requestedSubMode then
            ProjectileCamera.saveSettings(unitToWatchForToggle)
            STATE.tracking.projectileWatching.continuouslyArmedUnitID = nil
            ProjectileCamera.disableProjectileArming()
            return true
        else
            return ProjectileCamera.switchCameraSubModes(requestedSubMode)
        end
    elseif isContinuous then
        if currentSubMode == requestedSubMode then
            ProjectileCamera.saveSettings(unitToWatchForToggle)
            STATE.tracking.projectileWatching.continuouslyArmedUnitID = nil
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
            Log.warn("ProjectileCamera: Cannot arm from current mode: " .. tostring(currentActualMode))
            return false
        end

        STATE.tracking.projectileWatching.continuouslyArmedUnitID = unitToWatchForToggle
        Log.debug("Projectile tracking armed: " .. requestedSubMode)
        ProjectileCamera.loadSettings(unitToWatchForToggle)
        return ProjectileCamera.armProjectileTracking(requestedSubMode, unitToWatchForToggle)
    end
end

function ProjectileCamera.armProjectileTracking(subMode, unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.warn("ProjectileCamera: Invalid unitID (" .. tostring(unitID) .. ") for armProjectileTracking.")
        return false
    end

    if not STATE.tracking.projectileWatching.armed and STATE.tracking.mode ~= 'projectile_camera' then
        if not STATE.tracking.projectileWatching.previousCameraState then
            STATE.tracking.projectileWatching.previousMode = STATE.tracking.mode
            STATE.tracking.projectileWatching.previousCameraState = CameraManager.getCameraState("ProjectileCamera.armProjectileTracking.StorePrev")
        end
    end

    STATE.tracking.projectileWatching.cameraMode = subMode

    if subMode == "static" then
        local camState = CameraManager.getCameraState("ProjectileCamera.armProjectileTracking.StaticInitialPos")
        STATE.tracking.projectileWatching.initialCamPos = { x = camState.px, y = camState.py, z = camState.pz }
    else
        STATE.tracking.projectileWatching.initialCamPos = nil
    end

    STATE.tracking.projectileWatching.armed = true
    STATE.tracking.projectileWatching.watchedUnitID = unitID
    STATE.tracking.projectileWatching.lastArmingTime = Spring.GetGameSeconds()
    STATE.tracking.projectileWatching.impactTimer = nil
    STATE.tracking.projectileWatching.impactPosition = nil
    STATE.tracking.projectileWatching.isImpactDecelerating = false
    STATE.tracking.projectileWatching.impactDecelerationStartTime = nil
    STATE.tracking.projectileWatching.initialImpactVelocity = nil
    STATE.tracking.projectileWatching.isHighArc = false -- Reset flag

    -- Reset Direction Transition State
    TransitionManager.cancel(DIRECTION_TRANSITION_ID)
    STATE.tracking.projectileWatching.transitioningDirection = false
    STATE.tracking.projectile.lastProjectileVel = nil
    STATE.tracking.projectileWatching.currentFactor = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING.ROTATION_FACTOR -- Set to default


    if STATE.tracking.projectile then
        STATE.tracking.projectile.selectedProjectileID = nil
        STATE.tracking.projectile.currentProjectileID = nil
        ProjectileCameraUtils.resetSmoothedPositions()
    end

    ProjectileTracker.initUnitTracking(unitID)
    return true
end

function ProjectileCamera.disableProjectileArming()
    STATE.tracking.projectileWatching.armed = false
    STATE.tracking.projectileWatching.impactTimer = nil
    STATE.tracking.projectileWatching.impactPosition = nil
    STATE.tracking.projectileWatching.isImpactDecelerating = false
    STATE.tracking.projectileWatching.impactDecelerationStartTime = nil
    STATE.tracking.projectileWatching.initialImpactVelocity = nil
    STATE.tracking.projectileWatching.isHighArc = false

    -- Reset Direction Transition State
    TransitionManager.cancel(DIRECTION_TRANSITION_ID)
    STATE.tracking.projectileWatching.transitioningDirection = false
    STATE.tracking.projectile.lastProjectileVel = nil

    if STATE.tracking.projectile then
        STATE.tracking.projectile.selectedProjectileID = nil
        STATE.tracking.projectile.currentProjectileID = nil
    end
    Log.debug("Projectile tracking disabled")
end

function ProjectileCamera.switchCameraSubModes(newSubMode)
    STATE.tracking.projectileWatching.cameraMode = newSubMode
    if newSubMode == "static" and not STATE.tracking.projectileWatching.initialCamPos then
        if STATE.tracking.mode == 'projectile_camera' or STATE.tracking.projectileWatching.armed then
            local camState = CameraManager.getCameraState("ProjectileCamera.switchCameraSubModes.Static")
            STATE.tracking.projectileWatching.initialCamPos = { x = camState.px, y = camState.py, z = camState.pz }
        end
    end
    Log.debug("Projectile tracking switched to: " .. newSubMode)
    ProjectileCameraUtils.resetSmoothedPositions()
    return true
end

function ProjectileCamera.returnToPreviousMode(shouldReArm)
    local prevMode = STATE.tracking.projectileWatching.previousMode
    local prevCamState = STATE.tracking.projectileWatching.previousCameraState
    local previouslyWatchedUnitID = STATE.tracking.projectileWatching.watchedUnitID
    local unitToReArmWith = STATE.tracking.projectileWatching.continuouslyArmedUnitID

    local prevCamStateCopy = Util.deepCopy(prevCamState)
    ProjectileCamera.disableProjectileArming() -- This clears armed, impact, etc.

    local canReArm = shouldReArm and unitToReArmWith and Spring.ValidUnitID(unitToReArmWith)

    if prevMode and prevMode ~= 'projectile_camera' then
        local targetForPrevMode
        local effectiveTargetUnit = previouslyWatchedUnitID
        if ProjectileCameraUtils.isUnitCentricMode(prevMode) and effectiveTargetUnit and Spring.ValidUnitID(effectiveTargetUnit) then
            targetForPrevMode = effectiveTargetUnit
        elseif ProjectileCameraUtils.isUnitCentricMode(prevMode) and unitToReArmWith and Spring.ValidUnitID(unitToReArmWith) then
            targetForPrevMode = unitToReArmWith
        end

        TrackingManager.initializeMode(prevMode, targetForPrevMode, nil, true, prevCamStateCopy)

    elseif STATE.tracking.mode == 'projectile_camera' then
        TrackingManager.disableMode()
    end

    if not canReArm then
        STATE.tracking.projectileWatching.continuouslyArmedUnitID = nil
        STATE.tracking.projectileWatching.previousMode = nil
        STATE.tracking.projectileWatching.previousCameraState = nil
    else
        ProjectileCamera.loadSettings(unitToReArmWith)
        ProjectileCamera.armProjectileTracking(STATE.tracking.projectileWatching.cameraMode, unitToReArmWith)
    end
end

--------------------------------------------------------------------------------
-- Update Loop Functions
--------------------------------------------------------------------------------
function ProjectileCamera.checkAndActivate()
    if STATE.tracking.mode == 'projectile_camera' and STATE.tracking.projectileWatching.impactTimer then
        local currentTime = Spring.GetTimer()
        local elapsedImpactHold = Spring.DiffTimers(currentTime, STATE.tracking.projectileWatching.impactTimer)
        local _, gameSpeed = Spring.GetGameSpeed()
        if elapsedImpactHold * gameSpeed >= CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.IMPACT_TIMEOUT then
            Log.trace("ProjectileCamera: IMPACT_TIMEOUT reached. Returning to previous mode.")
            local unitID = STATE.tracking.projectileWatching.watchedUnitID
            local reArm = (STATE.tracking.projectileWatching.continuouslyArmedUnitID == unitID and Spring.ValidUnitID(unitID))
            if unitID and not reArm then
                ProjectileCamera.saveSettings(unitID)
            end
            ProjectileCamera.returnToPreviousMode(reArm)
            return true
        end
    end

    if not STATE.tracking.projectileWatching.armed or STATE.tracking.mode == 'projectile_camera' then
        return false
    end

    local unitID = STATE.tracking.projectileWatching.watchedUnitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.warn("ProjectileCamera: Watched unit " .. tostring(unitID) .. " became invalid. Disarming.")
        ProjectileCamera.disableProjectileArming()
        STATE.tracking.projectileWatching.continuouslyArmedUnitID = nil
        return false
    end

    local allProjectiles = ProjectileTracker.getUnitProjectiles(unitID)
    local newProjectiles = {}
    for _, p in ipairs(allProjectiles) do
        if p.creationTime > STATE.tracking.projectileWatching.lastArmingTime then
            table.insert(newProjectiles, p)
        end
    end

    if #newProjectiles == 0 then
        return false
    end

    if TrackingManager.startModeTransition('projectile_camera') then
        if TrackingManager.initializeMode('projectile_camera', unitID, STATE.TARGET_TYPES.UNIT) then
            STATE.tracking.projectile = STATE.tracking.projectile or {}
            STATE.tracking.projectile.selectedProjectileID = nil
            STATE.tracking.projectile.currentProjectileID = nil
            ProjectileCameraUtils.resetSmoothedPositions()
            STATE.tracking.projectileWatching.armed = false
            Log.trace("ProjectileCamera: Activated, tracking new projectile from unit " .. unitID)
            return true
        else
            Log.warn("ProjectileCamera: Failed to initialize tracking for 'projectile_camera'. Reverting arm.")
            local reArm = (STATE.tracking.projectileWatching.continuouslyArmedUnitID == unitID)
            ProjectileCamera.returnToPreviousMode(reArm)
            return false
        end
    else
        Log.warn("ProjectileCamera: Failed to start mode transition to 'projectile_camera'. Disarming fully.")
        STATE.tracking.projectileWatching.continuouslyArmedUnitID = nil
        ProjectileCamera.disableProjectileArming()
        return false
    end
end

function ProjectileCamera.update(dt)
    if not ProjectileCamera.shouldUpdate() then
        return
    end

    local unitID = STATE.tracking.unitID
    if not ProjectileCamera.validateUnit(unitID) then
        local reArm = (STATE.tracking.projectileWatching.continuouslyArmedUnitID == unitID)
        if unitID and not reArm then
            ProjectileCamera.saveSettings(unitID)
        end
        ProjectileCamera.returnToPreviousMode(reArm)
        return
    end

    if STATE.tracking.projectileWatching.isImpactDecelerating then
        ProjectileCamera.decelerateToImpactPosition(dt)
        return
    end

    if STATE.tracking.projectileWatching.impactTimer then
        ProjectileCamera.focusOnImpactPosition()
        return
    end

    STATE.tracking.projectile = STATE.tracking.projectile or {}
    STATE.tracking.projectile.smoothedPositions = STATE.tracking.projectile.smoothedPositions or { camPos = nil, targetPos = nil }

    -- Select projectile (if needed)
    if not STATE.tracking.projectile.currentProjectileID then
        ProjectileCamera.selectProjectile(unitID) -- This will set STATE.tracking.projectileWatching.isHighArc
        if not STATE.tracking.projectile.currentProjectileID then
            ProjectileCamera.handleImpactView(unitID, dt)
            return
        end
    end

    -- Handle tracking (calls trackActiveProjectile)
    ProjectileCamera.handleProjectileTracking(unitID, dt)
end
--------------------------------------------------------------------------------
-- Internal Update Helpers
--------------------------------------------------------------------------------
function ProjectileCamera.shouldUpdate()
    if STATE.tracking.mode ~= 'projectile_camera' then
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
    local latestValidProjectile
    local maxCreationTime = -1

    for _, p in ipairs(allProjectiles) do
        if p.creationTime > maxCreationTime then
            maxCreationTime = p.creationTime
            latestValidProjectile = p
        end
    end

    local newProjectileSelected = false
    if latestValidProjectile and (STATE.tracking.projectile.currentProjectileID ~= latestValidProjectile.id) then
        newProjectileSelected = true
    elseif not latestValidProjectile and STATE.tracking.projectile.currentProjectileID ~= nil then
        newProjectileSelected = true -- Projectile lost
    end

    if newProjectileSelected then
        -- Cancel any existing transition when projectile changes
        TransitionManager.cancel(DIRECTION_TRANSITION_ID)
        STATE.tracking.projectileWatching.transitioningDirection = false
        STATE.tracking.projectile.lastProjectileVel = nil
        STATE.tracking.projectileWatching.isHighArc = false
        Log.trace("Projectile changed/lost, resetting direction transition state.")
    end

    if latestValidProjectile then
        if newProjectileSelected then
            STATE.tracking.projectile = STATE.tracking.projectile or {}
            STATE.tracking.projectile.selectedProjectileID = latestValidProjectile.id
            STATE.tracking.projectile.currentProjectileID = latestValidProjectile.id
            ProjectileCameraUtils.resetSmoothedPositions()
            Log.trace("ProjectileCamera: Selected projectile " .. latestValidProjectile.id)
            STATE.tracking.projectileWatching.impactTimer = nil
            STATE.tracking.projectileWatching.isImpactDecelerating = false
            STATE.tracking.projectileWatching.impactPosition = nil
            STATE.tracking.projectile.trackingStartTime = Spring.GetTimer()

            local vel = latestValidProjectile.lastVelocity
            if not vel then
                STATE.tracking.projectileWatching.isHighArc = false
            else
                -- lastVelocity from tracker is {x,y,z,speed} where x,y,z is normalized
                if vel.y and vel.speed and vel.speed > 0.01 then
                    -- Check speed for valid direction
                    local upComponent = vel.y -- Since x,y,z is normalized, vel.y is effectively (vy/mag) if mag is considered 1
                    if upComponent > HIGH_ARC_THRESHOLD then
                        STATE.tracking.projectileWatching.isHighArc = true
                        STATE.tracking.projectileWatching.highArcGoingUpward = false
                        Log.trace("ProjectileCamera: High Arc detected.")
                    end
                else
                    STATE.tracking.projectileWatching.isHighArc = false
                    STATE.tracking.projectileWatching.highArcGoingUpward = false
                end
            end
        end
    elseif newProjectileSelected then
        -- Projectile was lost, clear state
        STATE.tracking.projectile = STATE.tracking.projectile or {}
        STATE.tracking.projectile.selectedProjectileID = nil
        STATE.tracking.projectile.currentProjectileID = nil
        STATE.tracking.projectile.trackingStartTime = nil
    end
end

function ProjectileCamera.getCurrentProjectile(unitID)
    if not STATE.tracking.projectile or not STATE.tracking.projectile.currentProjectileID then
        return nil
    end
    local currentID = STATE.tracking.projectile.currentProjectileID
    local projectiles = ProjectileTracker.getUnitProjectiles(unitID)
    for _, proj in ipairs(projectiles) do
        if proj.id == currentID then
            return proj
        end
    end
    return nil
end

function ProjectileCamera.handleProjectileTracking(unitID, dt)
    local currentProjectile = ProjectileCamera.getCurrentProjectile(unitID)
    if currentProjectile and currentProjectile.lastPosition then
        STATE.tracking.projectileWatching.impactPosition = {
            pos = Util.deepCopy(currentProjectile.lastPosition),
            vel = Util.deepCopy(currentProjectile.lastVelocity)
        }
        ProjectileCamera.trackActiveProjectile(currentProjectile)
    else
        ProjectileCamera.handleImpactView(unitID, dt)
    end
end

function ProjectileCamera.handleImpactView(unitID, dt)
    if not STATE.tracking.projectileWatching.impactPosition then
        Log.trace("ProjectileCamera: No impact position available, focusing on unit " .. unitID)
        ProjectileCamera.focusOnUnit(unitID)
        return
    end
    if not STATE.tracking.projectileWatching.isImpactDecelerating and not STATE.tracking.projectileWatching.impactTimer then
        STATE.tracking.projectileWatching.isImpactDecelerating = true
        STATE.tracking.projectileWatching.impactDecelerationStartTime = Spring.GetTimer()
        STATE.tracking.projectileWatching.impactTimer = Spring.GetTimer()
        local vel, _, rotVel, _ = CameraManager.getCurrentVelocity()
        STATE.tracking.projectileWatching.initialImpactVelocity = Util.deepCopy(vel)
        STATE.tracking.projectileWatching.initialImpactRotVelocity = Util.deepCopy(rotVel)
        Log.trace("ProjectileCamera: Projectile lost. Starting impact deceleration.")
        ProjectileCamera.decelerateToImpactPosition(dt)
    elseif STATE.tracking.projectileWatching.isImpactDecelerating then
        ProjectileCamera.decelerateToImpactPosition(dt)
    else
        ProjectileCamera.focusOnImpactPosition()
    end
end

function ProjectileCamera.decelerateToImpactPosition(dt)
    -- 1. Check for valid impact position
    if not STATE.tracking.projectileWatching.impactPosition or not STATE.tracking.projectileWatching.impactPosition.pos then
        Log.warn("ProjectileCamera: decelerateToImpactPosition called without valid impactPosition.")
        STATE.tracking.projectileWatching.isImpactDecelerating = false
        ProjectileCamera.focusOnUnit(STATE.tracking.unitID) -- Fallback to unit
        return
    end

    local impactWorldPos = STATE.tracking.projectileWatching.impactPosition.pos
    local currentCamState = CameraManager.getCameraState("ProjectileCamera.decelerateToImpactPosition")
    local profile = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DECELERATION_PROFILE

    -- 2. Calculate progress (0.0 to 1.0)
    local _, gameSpeed = Spring.GetGameSpeed()
    local elapsedDecelTime = Spring.DiffTimers(Spring.GetTimer(), STATE.tracking.projectileWatching.impactDecelerationStartTime)
    -- shorten the transition if gameSpeed is higher
    local linearProgress = math.min(elapsedDecelTime / profile.DURATION / gameSpeed, 1.0)
    local easedProgress = CameraCommons.easeOut(linearProgress)

    -- 3. Get initial velocities (both positional and rotational)
    local initialVelocity = STATE.tracking.projectileWatching.initialImpactVelocity or { x = 0, y = 0, z = 0 }
    local initialRotVelocity = STATE.tracking.projectileWatching.initialImpactRotVelocity or { x = 0, y = 0, z = 0 }

    -- Call the TransitionUtil
    local smoothedState = TransitionUtil.smoothDecelerationTransition(currentCamState, dt, easedProgress, initialVelocity, initialRotVelocity, profile)

    local finalCamState
    if smoothedState then
        finalCamState = smoothedState
    else
        -- If TransitionUtil returned nil, it means deceleration is finished.
        -- We hold the current state and mark deceleration as complete.
        finalCamState = Util.deepCopy(currentCamState)
        if STATE.tracking.projectileWatching.isImpactDecelerating then
            STATE.tracking.projectileWatching.isImpactDecelerating = false
            STATE.tracking.projectileWatching.initialImpactVelocity = nil
            STATE.tracking.projectileWatching.initialImpactRotVelocity = nil
            Log.trace("ProjectileCamera: Finished impact deceleration phase (TransitionUtil returned nil).")
        end
    end

    -- 6. Calculate where the camera *should* be looking
    local targetLookPos = ProjectileCameraUtils.calculateIdealTargetPosition(impactWorldPos, STATE.tracking.projectileWatching.impactPosition.vel or { x = 0, y = 0, z = 0 })

    -- 7. Calculate the *ideal* rotation to look at the target (without smoothing)
    local focusFromPos = { x = finalCamState.px, y = finalCamState.py, z = finalCamState.pz }
    local dirSmoothFactor = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING.ROTATION_FACTOR
    local rotSmoothFactor = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING.ROTATION_FACTOR
    local targetDirState = CameraCommons.focusOnPoint(focusFromPos, targetLookPos, dirSmoothFactor, rotSmoothFactor)

    -- 8. Smoothly interpolate the *current* rotation towards the *ideal* rotation.
    finalCamState.rx = CameraCommons.smoothStepAngle(finalCamState.rx, targetDirState.rx, rotSmoothFactor)
    finalCamState.ry = CameraCommons.smoothStepAngle(finalCamState.ry, targetDirState.ry, rotSmoothFactor)
    finalCamState.rz = CameraCommons.smoothStepAngle(finalCamState.rz, targetDirState.rz, rotSmoothFactor)

    -- 9. Update direction vectors based on the new final rotation
    local finalDir = CameraCommons.getDirectionFromRotation(finalCamState.rx, finalCamState.ry, finalCamState.rz)
    finalCamState.dx = finalDir.x
    finalCamState.dy = finalDir.y
    finalCamState.dz = finalDir.z

    -- 10. Set the final camera state
    CameraManager.setCameraState(finalCamState, 0, "ProjectileCamera.decelerateToImpact")
    TrackingManager.updateTrackingState(finalCamState)

    -- 11. Final check if duration ended, in case TransitionUtil didn't return nil yet.
    if linearProgress >= 1.0 and STATE.tracking.projectileWatching.isImpactDecelerating then
        STATE.tracking.projectileWatching.isImpactDecelerating = false
        STATE.tracking.projectileWatching.initialImpactVelocity = nil
        STATE.tracking.projectileWatching.initialImpactRotVelocity = nil
        Log.trace("ProjectileCamera: Finished impact deceleration phase (Progress >= 1.0).")
    end
end

function ProjectileCamera.focusOnImpactPosition()
    if not STATE.tracking.projectileWatching.impactPosition or not STATE.tracking.projectileWatching.impactPosition.pos then
        Log.warn("ProjectileCamera: focusOnImpactPosition called without valid impactPosition.")
        ProjectileCamera.focusOnUnit(STATE.tracking.unitID)
        return
    end
    local impactWorldPos = STATE.tracking.projectileWatching.impactPosition.pos
    local impactWorldVel = STATE.tracking.projectileWatching.impactPosition.vel or { x = 0, y = 0, z = 0 }
    local currentCamState = CameraManager.getCameraState("ProjectileCamera.focusOnImpactPosition.Hold")
    local settledCamPos = { x = currentCamState.px, y = currentCamState.py, z = currentCamState.pz }
    local targetLookPos = ProjectileCameraUtils.calculateIdealTargetPosition(impactWorldPos, impactWorldVel)
    ProjectileCameraUtils.applyProjectileCameraState(settledCamPos, targetLookPos, "impact_view_hold")
end

function ProjectileCamera.focusOnUnit(unitID)
    local ux, uy, uz = Spring.GetUnitPosition(unitID)
    if ux then
        local currentCamState = CameraManager.getCameraState("ProjectileCamera.focusOnUnit")
        local camPos = { x = currentCamState.px, y = currentCamState.py, z = currentCamState.pz }
        local targetPos = { x = ux, y = uy + (Util.getUnitHeight(unitID) * 0.5 or 50), z = uz }
        ProjectileCameraUtils.applyProjectileCameraState(camPos, targetPos, "unit_fallback_view")
    else
        Log.warn("ProjectileCamera: Unit " .. tostring(unitID) .. " invalid while trying to focus on it.")
        local reArm = (STATE.tracking.projectileWatching.continuouslyArmedUnitID == unitID)
        ProjectileCamera.returnToPreviousMode(reArm)
    end
end

function ProjectileCamera.trackActiveProjectile(currentProjectile)
    STATE.tracking.projectileWatching.impactTimer = nil
    STATE.tracking.projectileWatching.isImpactDecelerating = false

    local projectilePos = currentProjectile.lastPosition
    local projectileVel = currentProjectile.lastVelocity -- This is {x_norm, y_norm, z_norm, speed=actual_speed}

    if not projectilePos or not projectileVel then
        ProjectileCamera.handleImpactView(STATE.tracking.unitID, 0)
        return
    end

    local lastVel = STATE.tracking.projectile.lastProjectileVel
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA
    local ROTATION_THRESHOLD = cfg.DIRECTION_TRANSITION_THRESHOLD

    -- Only perform angle check and potentially transition if in High Arc mode and not already transitioning
    if STATE.tracking.projectileWatching.isHighArc and
            not STATE.tracking.projectileWatching.transitioningDirection and
            projectileVel and projectileVel.speed and
            lastVel and lastVel.speed and
            projectileVel.speed > MIN_PROJECTILE_SPEED_FOR_TURN_DETECT and
            lastVel.speed > MIN_PROJECTILE_SPEED_FOR_TURN_DETECT then

        local currentDir = { x = projectileVel.x, y = projectileVel.y, z = projectileVel.z }
        local lastDir = { x = lastVel.x, y = lastVel.y, z = lastVel.z }


        -- Calculate angle based *only* on XZ components since we are in High Arc.
        -- This prevents the vertical flip at the apex from triggering.
        local currentDirXZ = { x = currentDir.x, y = 0, z = currentDir.z }
        local lastDirXZ = { x = lastDir.x, y = 0, z = lastDir.z }

        local currentDirXY = { x = currentDir.x, y = currentDir.y, z = 0 }
        local lastDirXY = { x = lastDir.x, y = lastDir.y, z = 0 }

        local currentDirYZ = { x = 0, y = currentDir.y, z = currentDir.z }
        local lastDirYZ = { x = 0, y = lastDir.y, z = lastDir.z }

        local function getAngle(v1, v2)
            local magV1 = CameraCommons.vectorMagnitude(v1)
            local magV2 = CameraCommons.vectorMagnitude(v2)
            if magV1 <= 0.01 or magV2 <= 0.01 then
                return 0
            end
            local dot = CameraCommons.dotProduct(v1, v2)
            dot = math.max(-1.0, math.min(1.0, dot)) -- Clamp for safety
            return math.acos(dot), magV1
        end

        --local dot = CameraCommons.dotProduct(currentDirXZ, lastDirXZ)
        --dot = math.max(-1.0, math.min(1.0, dot)) -- Clamp for safety
        local angle = getAngle(currentDirXZ, lastDirXZ)

        local a1, b1 = getAngle(currentDir, lastDir)
        local a2, b2 = getAngle(currentDirXZ, lastDirXZ)
        local a3, b3 = getAngle(currentDirXY, lastDirXY)
        local a4, b4 = getAngle(currentDirYZ, lastDirYZ)


        Log.debug(
                "angleXYZ", a1, b1,
                "angleXZ", a2, b2,
                "angleXY", a3, b3,
                "angleYZ", a4, b4,
                "angle", angle,
                "isTransitioning", TransitionManager.isTransitioning(DIRECTION_TRANSITION_ID)
        )

        -- Check if this XZ angle warrants a transition
        if angle > ROTATION_THRESHOLD and STATE.tracking.projectileWatching.highArcGoingUpward then
            local highArcFactor = cfg.DIRECTION_TRANSITION_FACTOR
            local normalFactor = cfg.SMOOTHING.ROTATION_FACTOR
            local duration = cfg.DIRECTION_TRANSITION_DURATION

            Log.debug("ProjectileCamera: Starting direction transition (High Arc XZ Angle Trigger). Angle: " .. angle)
            STATE.tracking.projectileWatching.transitioningDirection = true

            TransitionManager.start({
                id = DIRECTION_TRANSITION_ID,
                duration = duration,
                easingFn = CameraCommons.easeInOut,
                onUpdate = function(progress, easedProgress)
                    local current = CameraCommons.lerp(highArcFactor, normalFactor, easedProgress)
                    STATE.tracking.projectileWatching.currentFactor = current
                end,
                onComplete = function()
                    STATE.tracking.projectileWatching.transitioningDirection = false
                    STATE.tracking.projectileWatching.currentFactor = normalFactor
                    Log.debug("ProjectileCamera: Direction transition finished.")
                end
            })
        end
    end
    -- Store the full velocity object (which includes the speed component)
    if projectileVel then
        STATE.tracking.projectile.lastProjectileVel = Util.deepCopy(projectileVel)
    end


    -- calculateCameraPositionForProjectile in utils will now internally use STATE.tracking.projectileWatching.isHighArc
    local idealCamPos = ProjectileCameraUtils.calculateCameraPositionForProjectile(projectilePos, projectileVel, STATE.tracking.projectileWatching.cameraMode)
    local idealTargetPos = ProjectileCameraUtils.calculateIdealTargetPosition(projectilePos, projectileVel)

    ProjectileCameraUtils.initializeSmoothedPositionsIfNil(idealCamPos, idealTargetPos)

    local smoothedCamPos = ProjectileCameraUtils.calculateSmoothedCameraPosition(idealCamPos)
    local smoothedTargetPos = ProjectileCameraUtils.calculateSmoothedTargetPosition(idealTargetPos)

    STATE.tracking.projectile.smoothedPositions.camPos = smoothedCamPos
    STATE.tracking.projectile.smoothedPositions.targetPos = smoothedTargetPos

    -- Pass the currently calculated rotation factor
    ProjectileCameraUtils.applyProjectileCameraState(smoothedCamPos, smoothedTargetPos, "tracking_active")
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