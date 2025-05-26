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

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons
local TrackingManager = CommonModules.TrackingManager

---@class ProjectileCamera
local ProjectileCamera = {}

--------------------------------------------------------------------------------
-- Public API Functions
--------------------------------------------------------------------------------
-- Unchanged from your file
function ProjectileCamera.followProjectile()
    return ProjectileCamera.toggle("follow")
end

function ProjectileCamera.trackProjectile()
    return ProjectileCamera.toggle("static")
end
--------------------------------------------------------------------------------
-- Core Toggling and State Management (assumed mostly unchanged)
--------------------------------------------------------------------------------
-- Functions getUnitToToggle, toggle, armProjectileTracking, disableProjectileArming,
-- switchCameraSubModes, returnToPreviousMode remain unchanged from your file.
-- Key change is in selectProjectile for HighArc detection.
-- For brevity, only showing selectProjectile and trackActiveProjectile fully,
-- assuming others are as per your last uploaded version.
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
        STATE.tracking.projectileWatching.previousMode = STATE.tracking.mode
        STATE.tracking.projectileWatching.previousCameraState = CameraManager.getCameraState("ProjectileCamera.armProjectileTracking.StorePrev")
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
    Log.debug("Returning to previous mode")
    local prevMode = STATE.tracking.projectileWatching.previousMode
    local prevCamState = STATE.tracking.projectileWatching.previousCameraState
    local previouslyWatchedUnitID = STATE.tracking.projectileWatching.watchedUnitID
    local unitToReArmWith = STATE.tracking.projectileWatching.continuouslyArmedUnitID

    ProjectileCamera.disableProjectileArming() -- This clears armed, impact, etc.

    local canReArm = shouldReArm and unitToReArmWith and Spring.ValidUnitID(unitToReArmWith)

    if prevMode and prevMode ~= 'projectile_camera' then
        ProjectileCamera.cleanupBeforeSwitch(false)
        local targetForPrevMode
        local effectiveTargetUnit = previouslyWatchedUnitID
        if ProjectileCameraUtils.isUnitCentricMode(prevMode) and effectiveTargetUnit and Spring.ValidUnitID(effectiveTargetUnit) then
            targetForPrevMode = effectiveTargetUnit
        elseif ProjectileCameraUtils.isUnitCentricMode(prevMode) and unitToReArmWith and Spring.ValidUnitID(unitToReArmWith) then
            targetForPrevMode = unitToReArmWith
        end

        TrackingManager.initializeMode(prevMode, targetForPrevMode, nil, true)
        if prevCamState then
            CameraManager.setCameraState(prevCamState, 0, "ProjectileCamera.restorePreviousModeState")
        end
    elseif STATE.tracking.mode == 'projectile_camera' then
        TrackingManager.disableMode()
    end

    -- Clear previousMode ONLY if not re-arming
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
        if elapsedImpactHold >= CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.IMPACT_TIMEOUT then
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
    ProjectileCamera.cleanupBeforeSwitch()
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

    if not STATE.tracking.projectile.currentProjectileID then
        ProjectileCamera.selectProjectile(unitID) -- This will set STATE.tracking.projectileWatching.isHighArc
        if not STATE.tracking.projectile.currentProjectileID then
            ProjectileCamera.handleImpactView(unitID, dt)
            return
        end
    end

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

    -- Reset isHighArc before checking. It's set only if a new projectile is selected AND meets criteria.
    -- If no new projectile is selected, isHighArc retains its value from the previous projectile if applicable,
    -- or remains false if it was reset due to losing a projectile.
    -- For a cleaner state, always reset when we attempt to select a new one.
    if not latestValidProjectile or (STATE.tracking.projectile.currentProjectileID ~= latestValidProjectile.id) then
        STATE.tracking.projectileWatching.isHighArc = false
    end

    if latestValidProjectile then
        if STATE.tracking.projectile.currentProjectileID ~= latestValidProjectile.id then
            STATE.tracking.projectile.selectedProjectileID = latestValidProjectile.id
            STATE.tracking.projectile.currentProjectileID = latestValidProjectile.id
            ProjectileCameraUtils.resetSmoothedPositions()
            Log.trace("ProjectileCamera: Selected projectile " .. latestValidProjectile.id)
            STATE.tracking.projectileWatching.impactTimer = nil
            STATE.tracking.projectileWatching.isImpactDecelerating = false
            STATE.tracking.projectileWatching.impactPosition = nil

            -- *** HIGH ARC DETECTION LOGIC (Magnitude check removed as per user) ***
            local vel = latestValidProjectile.lastVelocity
            if not vel then
                Log.warn("[ProjectileDebug] selectProjectile: latestValidProjectile.lastVelocity is nil for projectile ID: " .. latestValidProjectile.id)
                STATE.tracking.projectileWatching.isHighArc = false -- Ensure it's false if velocity is missing
            else
                local mag = CameraCommons.vectorMagnitude(vel)
                if mag > 0.01 then
                    -- Ensure projectile has some velocity to avoid division by zero / NaN
                    local upComponent = vel.y / mag
                    local HIGH_ARC_THRESHOLD = 0.8 -- ~53 degrees
                    if upComponent > HIGH_ARC_THRESHOLD then
                        STATE.tracking.projectileWatching.isHighArc = true
                    end
                    STATE.tracking.projectileWatching.isHighArc = false -- Ensure it's false for zero/low speed
                end
            end
            -- *** END HIGH ARC DETECTION ***
        end
    else
        STATE.tracking.projectile.selectedProjectileID = nil
        STATE.tracking.projectile.currentProjectileID = nil
        STATE.tracking.projectileWatching.isHighArc = false -- No projectile, so not high arc
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
    local elapsedDecelTime = Spring.DiffTimers(Spring.GetTimer(), STATE.tracking.projectileWatching.impactDecelerationStartTime)
    local linearProgress = 1.0
    if profile.DURATION and profile.DURATION > 0 then
        linearProgress = math.min(elapsedDecelTime / profile.DURATION, 1.0)
    end
    local easedProgress = CameraCommons.easeOut(linearProgress) -- Use easing function if available

    -- 3. Get initial velocities (both positional and rotational)
    local initialVelocity = STATE.tracking.projectileWatching.initialImpactVelocity or { x = 0, y = 0, z = 0 }
    local initialRotVelocity = STATE.tracking.projectileWatching.initialImpactRotVelocity or { x = 0, y = 0, z = 0 }

    -- 4. Call the (newly enhanced) TransitionUtil
    local smoothedState = TransitionUtil.smoothDecelerationTransition(currentCamState, dt, easedProgress, initialVelocity, initialRotVelocity, profile)

    local finalCamState

    -- 5. Determine the next camera state based on transition output
    if smoothedState then
        -- If TransitionUtil returned a state, it means we're still decelerating.
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

-- This is the version from your uploaded file for this turn.
-- It does not pass `smoothedUp` to calculateCameraPositionForProjectile.
-- The logic is now self-contained in projectile_camera_utils.lua
function ProjectileCamera.trackActiveProjectile(currentProjectile)
    STATE.tracking.projectileWatching.impactTimer = nil
    STATE.tracking.projectileWatching.isImpactDecelerating = false

    local projectilePos = currentProjectile.lastPosition
    local projectileVel = currentProjectile.lastVelocity

    if not projectilePos or not projectileVel then
        Log.warn(("[ProjectileDebug] TrackActive: projectilePos (%s) or projectileVel (%s) is nil. ID: %s"):format(tostring(projectilePos), tostring(projectileVel), currentProjectile.id))
        ProjectileCamera.handleImpactView(STATE.tracking.unitID, 0) -- Pass dt=0 or handle appropriately
        return
    end

    -- calculateCameraPositionForProjectile in utils will now internally use STATE.tracking.projectileWatching.isHighArc
    local idealCamPos = ProjectileCameraUtils.calculateCameraPositionForProjectile(projectilePos, projectileVel, STATE.tracking.projectileWatching.cameraMode)
    local idealTargetPos = ProjectileCameraUtils.calculateIdealTargetPosition(projectilePos, projectileVel)

    ProjectileCameraUtils.initializeSmoothedPositionsIfNil(idealCamPos, idealTargetPos)

    local smoothedCamPos = ProjectileCameraUtils.calculateSmoothedCameraPosition(idealCamPos)
    local smoothedTargetPos = ProjectileCameraUtils.calculateSmoothedTargetPosition(idealTargetPos)

    STATE.tracking.projectile.smoothedPositions.camPos = smoothedCamPos
    STATE.tracking.projectile.smoothedPositions.targetPos = smoothedTargetPos

    ProjectileCameraUtils.applyProjectileCameraState(smoothedCamPos, smoothedTargetPos, "tracking_active")
end

--- Cleans up projectile state before switching to another mode.
--- It checks an internal flag to see if this switch is part of returning to a previous mode.
function ProjectileCamera.cleanupBeforeSwitch()
    if STATE.tracking.mode == 'projectile_camera' then
        -- Check 'projectile_camera'
        if STATE.tracking.projectileWatching then
            STATE.tracking.projectileWatching.armed = false
            STATE.tracking.projectileWatching.watchedUnitID = nil
            STATE.tracking.projectileWatching.impactTimer = nil
            STATE.tracking.projectileWatching.impactPosition = nil
            STATE.tracking.projectileWatching.initialCamPos = nil
            STATE.tracking.projectileWatching.previousMode = nil
            STATE.tracking.projectileWatching.previousCameraState = nil
        end
        if STATE.tracking.projectile then
            STATE.tracking.projectile.selectedProjectileID = nil
            STATE.tracking.projectile.currentProjectileID = nil
            STATE.tracking.projectile.smoothedPositions = nil
        end
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