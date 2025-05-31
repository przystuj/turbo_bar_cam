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

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons
local ModeManager = CommonModules.ModeManager

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
    local unitToWatch = STATE.mode.unitID
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
    local unitToWatchForToggle = STATE.mode.unitID
    if not unitToWatchForToggle then
        return false
    end

    local currentActualMode = STATE.mode.name
    local isArmed = STATE.mode.projectile_camera.armed
    local isFollowingProjectileMode = currentActualMode == 'projectile_camera'
    local currentSubMode = STATE.mode.projectile_camera.cameraMode
    local isContinuous = (STATE.mode.projectile_camera.continuouslyArmedUnitID == unitToWatchForToggle)
    local isImpactDecelerating = STATE.mode.projectile_camera.isImpactDecelerating

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
            Log.warn("ProjectileCamera: Cannot arm from current mode: " .. tostring(currentActualMode))
            return false
        end

        STATE.mode.projectile_camera.continuouslyArmedUnitID = unitToWatchForToggle
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
    STATE.mode.projectile_camera.impactTimer = nil
    STATE.mode.projectile_camera.impactPosition = nil
    STATE.mode.projectile_camera.isImpactDecelerating = false
    STATE.mode.projectile_camera.impactDecelerationStartTime = nil
    STATE.mode.projectile_camera.initialImpactVelocity = nil
    STATE.mode.projectile_camera.isHighArc = false -- Reset flag

    -- Reset Direction Transition State
    TransitionManager.cancel(DIRECTION_TRANSITION_ID)
    STATE.mode.projectile_camera.transitioningDirection = false
    STATE.mode.projectile_camera.projectile.lastProjectileVel = nil
    STATE.mode.projectile_camera.currentFactor = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING.ROTATION_FACTOR -- Set to default


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
    STATE.mode.projectile_camera.impactTimer = nil
    STATE.mode.projectile_camera.impactPosition = nil
    STATE.mode.projectile_camera.isImpactDecelerating = false
    STATE.mode.projectile_camera.impactDecelerationStartTime = nil
    STATE.mode.projectile_camera.initialImpactVelocity = nil
    STATE.mode.projectile_camera.isHighArc = false

    -- Reset Direction Transition State
    TransitionManager.cancel(DIRECTION_TRANSITION_ID)
    STATE.mode.projectile_camera.transitioningDirection = false
    STATE.mode.projectile_camera.projectile.lastProjectileVel = nil

    if STATE.mode.projectile_camera.projectile then
        STATE.mode.projectile_camera.projectile.selectedProjectileID = nil
        STATE.mode.projectile_camera.projectile.currentProjectileID = nil
    end
    Log.debug("Projectile tracking disabled")
end

function ProjectileCamera.switchCameraSubModes(newSubMode)
    STATE.mode.projectile_camera.cameraMode = newSubMode
    if newSubMode == "static" and not STATE.mode.projectile_camera.initialCamPos then
        if STATE.mode.name == 'projectile_camera' or STATE.mode.projectile_camera.armed then
            local camState = Spring.GetCameraState()
            STATE.mode.projectile_camera.initialCamPos = { x = camState.px, y = camState.py, z = camState.pz }
        end
    end
    Log.debug("Projectile tracking switched to: " .. newSubMode)
    ProjectileCameraUtils.resetSmoothedPositions()
    return true
end

function ProjectileCamera.returnToPreviousMode(shouldReArm)
    local prevMode = STATE.mode.projectile_camera.previousMode
    local prevCamState = STATE.mode.projectile_camera.previousCameraState
    local previouslyWatchedUnitID = STATE.mode.projectile_camera.watchedUnitID
    local unitToReArmWith = STATE.mode.projectile_camera.continuouslyArmedUnitID

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
-- Update Loop Functions
--------------------------------------------------------------------------------
function ProjectileCamera.checkAndActivate()
    if STATE.mode.name == 'projectile_camera' and STATE.mode.projectile_camera.impactTimer then
        local currentTime = Spring.GetTimer()
        local elapsedImpactHold = Spring.DiffTimers(currentTime, STATE.mode.projectile_camera.impactTimer)
        local _, gameSpeed = Spring.GetGameSpeed()
        if elapsedImpactHold * gameSpeed >= CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.IMPACT_TIMEOUT then
            Log.trace("ProjectileCamera: IMPACT_TIMEOUT reached. Returning to previous mode.")
            local unitID = STATE.mode.projectile_camera.watchedUnitID
            local reArm = (STATE.mode.projectile_camera.continuouslyArmedUnitID == unitID and Spring.ValidUnitID(unitID))
            if unitID and not reArm then
                ProjectileCamera.saveSettings(unitID)
            end
            ProjectileCamera.returnToPreviousMode(reArm)
            return true
        end
    end

    if not STATE.mode.projectile_camera.armed or STATE.mode.name == 'projectile_camera' then
        return false
    end

    local unitID = STATE.mode.projectile_camera.watchedUnitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.warn("ProjectileCamera: Watched unit " .. tostring(unitID) .. " became invalid. Disarming.")
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

    if ModeManager.startModeTransition('projectile_camera') then
        if ModeManager.initializeMode('projectile_camera', unitID, STATE.TARGET_TYPES.UNIT) then
            STATE.mode.projectile_camera.projectile = STATE.mode.projectile_camera.projectile or {}
            STATE.mode.projectile_camera.projectile.selectedProjectileID = nil
            STATE.mode.projectile_camera.projectile.currentProjectileID = nil
            ProjectileCameraUtils.resetSmoothedPositions()
            STATE.mode.projectile_camera.armed = false
            Log.trace("ProjectileCamera: Activated, tracking new projectile from unit " .. unitID)
            return true
        else
            Log.warn("ProjectileCamera: Failed to initialize tracking for 'projectile_camera'. Reverting arm.")
            local reArm = (STATE.mode.projectile_camera.continuouslyArmedUnitID == unitID)
            ProjectileCamera.returnToPreviousMode(reArm)
            return false
        end
    else
        Log.warn("ProjectileCamera: Failed to start mode transition to 'projectile_camera'. Disarming fully.")
        STATE.mode.projectile_camera.continuouslyArmedUnitID = nil
        ProjectileCamera.disableProjectileArming()
        return false
    end
end

function ProjectileCamera.update(dt)
    if not ProjectileCamera.shouldUpdate() then
        return
    end

    local unitID = STATE.mode.unitID
    if not ProjectileCamera.validateUnit(unitID) then
        local reArm = (STATE.mode.projectile_camera.continuouslyArmedUnitID == unitID)
        if unitID and not reArm then
            ProjectileCamera.saveSettings(unitID)
        end
        ProjectileCamera.returnToPreviousMode(reArm)
        return
    end

    if STATE.mode.projectile_camera.isImpactDecelerating then
        ProjectileCamera.decelerateToImpactPosition(dt)
        return
    end

    if STATE.mode.projectile_camera.impactTimer then
        ProjectileCamera.focusOnImpactPosition()
        return
    end

    STATE.mode.projectile_camera.projectile = STATE.mode.projectile_camera.projectile or {}
    STATE.mode.projectile_camera.projectile.smoothedPositions = STATE.mode.projectile_camera.projectile.smoothedPositions or { camPos = nil, targetPos = nil }

    -- Select projectile (if needed)
    if not STATE.mode.projectile_camera.projectile.currentProjectileID then
        ProjectileCamera.selectProjectile(unitID) -- This will set STATE.mode.projectile_camera.isHighArc
        if not STATE.mode.projectile_camera.projectile.currentProjectileID then
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
        newProjectileSelected = true -- Projectile lost
    end

    if newProjectileSelected then
        -- Cancel any existing transition when projectile changes
        TransitionManager.cancel(DIRECTION_TRANSITION_ID)
        STATE.mode.projectile_camera.transitioningDirection = false
        STATE.mode.projectile_camera.projectile.lastProjectileVel = nil
        STATE.mode.projectile_camera.isHighArc = false
        Log.trace("Projectile changed/lost, resetting direction transition state.")
    end

    if latestValidProjectile then
        if newProjectileSelected then
            STATE.mode.projectile_camera.projectile = STATE.mode.projectile_camera.projectile or {}
            STATE.mode.projectile_camera.projectile.selectedProjectileID = latestValidProjectile.id
            STATE.mode.projectile_camera.projectile.currentProjectileID = latestValidProjectile.id
            ProjectileCameraUtils.resetSmoothedPositions()
            Log.trace("ProjectileCamera: Selected projectile " .. latestValidProjectile.id)
            STATE.mode.projectile_camera.impactTimer = nil
            STATE.mode.projectile_camera.isImpactDecelerating = false
            STATE.mode.projectile_camera.impactPosition = nil
            STATE.mode.projectile_camera.projectile.trackingStartTime = Spring.GetTimer()

            local vel = latestValidProjectile.lastVelocity
            if not vel then
                STATE.mode.projectile_camera.isHighArc = false
            else
                -- lastVelocity from tracker is {x,y,z,speed} where x,y,z is normalized
                if vel.y and vel.speed and vel.speed > 0.01 then
                    -- Check speed for valid direction
                    local upComponent = vel.y -- Since x,y,z is normalized, vel.y is effectively (vy/mag) if mag is considered 1
                    if upComponent > HIGH_ARC_THRESHOLD then
                        STATE.mode.projectile_camera.isHighArc = true
                        STATE.mode.projectile_camera.highArcGoingUpward = false
                        Log.trace("ProjectileCamera: High Arc detected.")
                    end
                else
                    STATE.mode.projectile_camera.isHighArc = false
                    STATE.mode.projectile_camera.highArcGoingUpward = false
                end
            end
        end
    elseif newProjectileSelected then
        -- Projectile was lost, clear state
        STATE.mode.projectile_camera.projectile = STATE.mode.projectile_camera.projectile or {}
        STATE.mode.projectile_camera.projectile.selectedProjectileID = nil
        STATE.mode.projectile_camera.projectile.currentProjectileID = nil
        STATE.mode.projectile_camera.projectile.trackingStartTime = nil
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

function ProjectileCamera.handleProjectileTracking(unitID, dt)
    local currentProjectile = ProjectileCamera.getCurrentProjectile(unitID)
    if currentProjectile and currentProjectile.lastPosition then
        STATE.mode.projectile_camera.impactPosition = {
            pos = Util.deepCopy(currentProjectile.lastPosition),
            vel = Util.deepCopy(currentProjectile.lastVelocity)
        }
        ProjectileCamera.trackActiveProjectile(currentProjectile)
    else
        ProjectileCamera.handleImpactView(unitID, dt)
    end
end

function ProjectileCamera.handleImpactView(unitID, dt)
    if not STATE.mode.projectile_camera.impactPosition then
        Log.trace("ProjectileCamera: No impact position available, focusing on unit " .. unitID)
        ProjectileCamera.focusOnUnit(unitID)
        return
    end
    if not STATE.mode.projectile_camera.isImpactDecelerating and not STATE.mode.projectile_camera.impactTimer then
        STATE.mode.projectile_camera.isImpactDecelerating = true
        STATE.mode.projectile_camera.impactDecelerationStartTime = Spring.GetTimer()
        STATE.mode.projectile_camera.impactTimer = Spring.GetTimer()
        local vel, _, rotVel, _ = VelocityTracker.getCurrentVelocity()
        STATE.mode.projectile_camera.initialImpactVelocity = Util.deepCopy(vel)
        STATE.mode.projectile_camera.initialImpactRotVelocity = Util.deepCopy(rotVel)
        Log.trace("ProjectileCamera: Projectile lost. Starting impact deceleration.")
        ProjectileCamera.decelerateToImpactPosition(dt)
    elseif STATE.mode.projectile_camera.isImpactDecelerating then
        ProjectileCamera.decelerateToImpactPosition(dt)
    else
        ProjectileCamera.focusOnImpactPosition()
    end
end

function ProjectileCamera.decelerateToImpactPosition(dt)
    -- 1. Check for valid impact position
    if not STATE.mode.projectile_camera.impactPosition or not STATE.mode.projectile_camera.impactPosition.pos then
        Log.warn("ProjectileCamera: decelerateToImpactPosition called without valid impactPosition.")
        STATE.mode.projectile_camera.isImpactDecelerating = false
        ProjectileCamera.focusOnUnit(STATE.mode.unitID) -- Fallback to unit
        return
    end

    local impactWorldPos = STATE.mode.projectile_camera.impactPosition.pos
    local currentCamState = Spring.GetCameraState()
    local profile = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DECELERATION_PROFILE

    -- 2. Calculate progress (0.0 to 1.0)
    local _, gameSpeed = Spring.GetGameSpeed()
    local elapsedDecelTime = Spring.DiffTimers(Spring.GetTimer(), STATE.mode.projectile_camera.impactDecelerationStartTime)
    -- shorten the transition if gameSpeed is higher
    local linearProgress = math.min(elapsedDecelTime / profile.DURATION / gameSpeed, 1.0)
    local easedProgress = CameraCommons.easeOut(linearProgress)

    -- 3. Get initial velocities (both positional and rotational)
    local initialVelocity = STATE.mode.projectile_camera.initialImpactVelocity or { x = 0, y = 0, z = 0 }
    local initialRotVelocity = STATE.mode.projectile_camera.initialImpactRotVelocity or { x = 0, y = 0, z = 0 }

    -- Call the TransitionUtil
    local smoothedState = TransitionUtil.smoothDecelerationTransition(currentCamState, dt, easedProgress, initialVelocity, initialRotVelocity, profile)

    local finalCamState
    if smoothedState then
        finalCamState = smoothedState
    else
        -- If TransitionUtil returned nil, it means deceleration is finished.
        -- We hold the current state and mark deceleration as complete.
        finalCamState = Util.deepCopy(currentCamState)
        if STATE.mode.projectile_camera.isImpactDecelerating then
            STATE.mode.projectile_camera.isImpactDecelerating = false
            STATE.mode.projectile_camera.initialImpactVelocity = nil
            STATE.mode.projectile_camera.initialImpactRotVelocity = nil
            Log.trace("ProjectileCamera: Finished impact deceleration phase (TransitionUtil returned nil).")
        end
    end

    -- 6. Calculate where the camera *should* be looking
    local targetLookPos = ProjectileCameraUtils.calculateIdealTargetPosition(impactWorldPos, STATE.mode.projectile_camera.impactPosition.vel or { x = 0, y = 0, z = 0 })

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
    Spring.SetCameraState(finalCamState, 0)
    ModeManager.updateTrackingState(finalCamState)

    -- 11. Final check if duration ended, in case TransitionUtil didn't return nil yet.
    if linearProgress >= 1.0 and STATE.mode.projectile_camera.isImpactDecelerating then
        STATE.mode.projectile_camera.isImpactDecelerating = false
        STATE.mode.projectile_camera.initialImpactVelocity = nil
        STATE.mode.projectile_camera.initialImpactRotVelocity = nil
        Log.trace("ProjectileCamera: Finished impact deceleration phase (Progress >= 1.0).")
    end
end

function ProjectileCamera.focusOnImpactPosition()
    if not STATE.mode.projectile_camera.impactPosition or not STATE.mode.projectile_camera.impactPosition.pos then
        Log.warn("ProjectileCamera: focusOnImpactPosition called without valid impactPosition.")
        ProjectileCamera.focusOnUnit(STATE.mode.unitID)
        return
    end
    local impactWorldPos = STATE.mode.projectile_camera.impactPosition.pos
    local impactWorldVel = STATE.mode.projectile_camera.impactPosition.vel or { x = 0, y = 0, z = 0 }
    local currentCamState = Spring.GetCameraState()
    local settledCamPos = { x = currentCamState.px, y = currentCamState.py, z = currentCamState.pz }
    local targetLookPos = ProjectileCameraUtils.calculateIdealTargetPosition(impactWorldPos, impactWorldVel)
    ProjectileCameraUtils.applyProjectileCameraState(settledCamPos, targetLookPos, "impact_view_hold")
end

function ProjectileCamera.focusOnUnit(unitID)
    local ux, uy, uz = Spring.GetUnitPosition(unitID)
    if ux then
        local currentCamState = Spring.GetCameraState()
        local camPos = { x = currentCamState.px, y = currentCamState.py, z = currentCamState.pz }
        local targetPos = { x = ux, y = uy + (Util.getUnitHeight(unitID) * 0.5 or 50), z = uz }
        ProjectileCameraUtils.applyProjectileCameraState(camPos, targetPos, "unit_fallback_view")
    else
        Log.warn("ProjectileCamera: Unit " .. tostring(unitID) .. " invalid while trying to focus on it.")
        local reArm = (STATE.mode.projectile_camera.continuouslyArmedUnitID == unitID)
        ProjectileCamera.returnToPreviousMode(reArm)
    end
end

function ProjectileCamera.trackActiveProjectile(currentProjectile)
    STATE.mode.projectile_camera.impactTimer = nil
    STATE.mode.projectile_camera.isImpactDecelerating = false

    local projectilePos = currentProjectile.lastPosition
    local projectileVel = currentProjectile.lastVelocity -- This is {x_norm, y_norm, z_norm, speed=actual_speed}

    if not projectilePos or not projectileVel then
        ProjectileCamera.handleImpactView(STATE.mode.unitID, 0)
        return
    end

    local lastVel = STATE.mode.projectile_camera.projectile.lastProjectileVel
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA
    local ROTATION_THRESHOLD = cfg.DIRECTION_TRANSITION_THRESHOLD

    -- Only perform angle check and potentially transition if in High Arc mode and not already transitioning
    if STATE.mode.projectile_camera.isHighArc and
            not STATE.mode.projectile_camera.transitioningDirection and
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
        if angle > ROTATION_THRESHOLD and STATE.mode.projectile_camera.highArcGoingUpward then
            local highArcFactor = cfg.DIRECTION_TRANSITION_FACTOR
            local normalFactor = cfg.SMOOTHING.ROTATION_FACTOR
            local duration = cfg.DIRECTION_TRANSITION_DURATION

            Log.debug("ProjectileCamera: Starting direction transition (High Arc XZ Angle Trigger). Angle: " .. angle)
            STATE.mode.projectile_camera.transitioningDirection = true

            TransitionManager.start({
                id = DIRECTION_TRANSITION_ID,
                duration = duration,
                easingFn = CameraCommons.easeInOut,
                onUpdate = function(progress, easedProgress)
                    local current = CameraCommons.lerp(highArcFactor, normalFactor, easedProgress)
                    STATE.mode.projectile_camera.currentFactor = current
                end,
                onComplete = function()
                    STATE.mode.projectile_camera.transitioningDirection = false
                    STATE.mode.projectile_camera.currentFactor = normalFactor
                    Log.debug("ProjectileCamera: Direction transition finished.")
                end
            })
        end
    end
    -- Store the full velocity object (which includes the speed component)
    if projectileVel then
        STATE.mode.projectile_camera.projectile.lastProjectileVel = Util.deepCopy(projectileVel)
    end


    -- calculateCameraPositionForProjectile in utils will now internally use STATE.mode.projectile_camera.isHighArc
    local idealCamPos = ProjectileCameraUtils.calculateCameraPositionForProjectile(projectilePos, projectileVel, STATE.mode.projectile_camera.cameraMode)
    local idealTargetPos = ProjectileCameraUtils.calculateIdealTargetPosition(projectilePos, projectileVel)

    ProjectileCameraUtils.initializeSmoothedPositionsIfNil(idealCamPos, idealTargetPos)

    local smoothedCamPos = ProjectileCameraUtils.calculateSmoothedCameraPosition(idealCamPos)
    local smoothedTargetPos = ProjectileCameraUtils.calculateSmoothedTargetPosition(idealTargetPos)

    STATE.mode.projectile_camera.projectile.smoothedPositions.camPos = smoothedCamPos
    STATE.mode.projectile_camera.projectile.smoothedPositions.targetPos = smoothedTargetPos

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