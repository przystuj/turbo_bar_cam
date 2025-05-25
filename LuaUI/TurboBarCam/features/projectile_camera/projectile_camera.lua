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

-- Logging Helper
local function formatVec(v)
    if not v then
        return "nil"
    end
    return string.format("{x=%.1f, y=%.1f, z=%.1f}", v.x or 0, v.y or 0, v.z or 0)
end


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
    local unitToWatchForToggle = getUnitToToggle()
    if not unitToWatchForToggle then
        Log.warn("ProjectileCamera: No unit selected or tracked to initiate/toggle projectile watching.")
        return false
    end

    local currentActualMode = STATE.tracking.mode
    local isArmed = STATE.projectileWatching.armed
    local isFollowingProjectileMode = (currentActualMode == 'projectile_camera')
    local currentSubMode = STATE.projectileWatching.cameraMode
    local isContinuous = (STATE.projectileWatching.continuouslyArmedUnitID == unitToWatchForToggle)
    local isImpactDecelerating = STATE.projectileWatching.isImpactDecelerating

    if isFollowingProjectileMode or isImpactDecelerating then
        if currentSubMode == requestedSubMode and not isImpactDecelerating then
            ProjectileCamera.saveSettings(unitToWatchForToggle)
            STATE.projectileWatching.continuouslyArmedUnitID = nil
            ProjectileCamera.returnToPreviousMode(false)
            return true
        else
            return ProjectileCamera.switchCameraSubModes(requestedSubMode)
        end
    elseif isArmed then
        if currentSubMode == requestedSubMode then
            ProjectileCamera.saveSettings(unitToWatchForToggle)
            STATE.projectileWatching.continuouslyArmedUnitID = nil
            ProjectileCamera.disableProjectileArming()
            return true
        else
            return ProjectileCamera.switchCameraSubModes(requestedSubMode)
        end
    elseif isContinuous then
        if currentSubMode == requestedSubMode then
            ProjectileCamera.saveSettings(unitToWatchForToggle)
            STATE.projectileWatching.continuouslyArmedUnitID = nil
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
        if currentActualMode and not Util.tableContains(CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.COMPATIBLE_MODES_FROM, currentActualMode) then
            Log.warn("ProjectileCamera: Cannot arm from current mode: " .. currentActualMode)
            return false
        end

        STATE.projectileWatching.continuouslyArmedUnitID = unitToWatchForToggle
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

    if not STATE.projectileWatching.armed and STATE.tracking.mode ~= 'projectile_camera' then
        STATE.projectileWatching.previousMode = STATE.tracking.mode
        STATE.projectileWatching.previousCameraState = CameraManager.getCameraState("ProjectileCamera.armProjectileTracking.StorePrev")
    end

    STATE.projectileWatching.cameraMode = subMode

    if subMode == "static" then
        local camState = CameraManager.getCameraState("ProjectileCamera.armProjectileTracking.StaticInitialPos")
        STATE.projectileWatching.initialCamPos = { x = camState.px, y = camState.py, z = camState.pz }
    else
        STATE.projectileWatching.initialCamPos = nil
    end

    STATE.projectileWatching.armed = true
    STATE.projectileWatching.watchedUnitID = unitID
    STATE.projectileWatching.lastArmingTime = Spring.GetGameSeconds()
    STATE.projectileWatching.impactTimer = nil
    STATE.projectileWatching.impactPosition = nil
    STATE.projectileWatching.isImpactDecelerating = false
    STATE.projectileWatching.impactDecelerationStartTime = nil
    STATE.projectileWatching.initialImpactVelocity = nil
    STATE.projectileWatching.isHighArc = false -- Reset flag

    if STATE.tracking.projectile then
        STATE.tracking.projectile.selectedProjectileID = nil
        STATE.tracking.projectile.currentProjectileID = nil
        ProjectileCameraUtils.resetSmoothedPositions()
    end

    ProjectileTracker.initUnitTracking(unitID)
    return true
end

function ProjectileCamera.disableProjectileArming()
    STATE.projectileWatching.armed = false
    STATE.projectileWatching.impactTimer = nil
    STATE.projectileWatching.impactPosition = nil
    STATE.projectileWatching.isImpactDecelerating = false
    STATE.projectileWatching.impactDecelerationStartTime = nil
    STATE.projectileWatching.initialImpactVelocity = nil
    STATE.projectileWatching.isHighArc = false

    if STATE.tracking.projectile then
        STATE.tracking.projectile.selectedProjectileID = nil
        STATE.tracking.projectile.currentProjectileID = nil
    end
end

function ProjectileCamera.switchCameraSubModes(newSubMode)
    STATE.projectileWatching.cameraMode = newSubMode
    if newSubMode == "static" and not STATE.projectileWatching.initialCamPos then
        if STATE.tracking.mode == 'projectile_camera' or STATE.projectileWatching.armed then
            local camState = CameraManager.getCameraState("ProjectileCamera.switchCameraSubModes.Static")
            STATE.projectileWatching.initialCamPos = { x = camState.px, y = camState.py, z = camState.pz }
        end
    end
    Log.debug("Projectile tracking switched to: " .. newSubMode)
    ProjectileCameraUtils.resetSmoothedPositions()
    return true
end

function ProjectileCamera.returnToPreviousMode(shouldReArm)
    local prevMode = STATE.projectileWatching.previousMode
    local prevCamState = STATE.projectileWatching.previousCameraState
    local previouslyWatchedUnitID = STATE.projectileWatching.watchedUnitID
    local unitToReArmWith = STATE.projectileWatching.continuouslyArmedUnitID

    ProjectileCamera.disableProjectileArming()

    local canReArm = shouldReArm and unitToReArmWith and Spring.ValidUnitID(unitToReArmWith)

    if prevMode and prevMode ~= 'projectile_camera' then
        if TrackingManager.startModeTransition(prevMode) then
            local targetForPrevMode
            local effectiveTargetUnit = previouslyWatchedUnitID
            if ProjectileCameraUtils.isUnitCentricMode(prevMode) and effectiveTargetUnit and Spring.ValidUnitID(effectiveTargetUnit) then
                targetForPrevMode = effectiveTargetUnit
            elseif ProjectileCameraUtils.isUnitCentricMode(prevMode) and unitToReArmWith and Spring.ValidUnitID(unitToReArmWith) then
                targetForPrevMode = unitToReArmWith
            end

            TrackingManager.initializeTracking(prevMode, targetForPrevMode)
            if prevCamState then
                CameraManager.setCameraState(prevCamState, 0, "ProjectileCamera.restorePreviousModeState")
            end
        else
            Log.warn("ProjectileCamera: Failed to start transition to previous mode: " .. prevMode .. ". Disabling tracking fully.")
            TrackingManager.disableTracking()
            canReArm = false
        end
    elseif STATE.tracking.mode == 'projectile_camera' then
        TrackingManager.disableTracking()
    end

    if not canReArm then
        STATE.projectileWatching.continuouslyArmedUnitID = nil
        STATE.projectileWatching.previousMode = nil
        STATE.projectileWatching.previousCameraState = nil
    else
        ProjectileCamera.loadSettings(unitToReArmWith)
        ProjectileCamera.armProjectileTracking(STATE.projectileWatching.cameraMode, unitToReArmWith)
    end
end
--------------------------------------------------------------------------------
-- Update Loop Functions
--------------------------------------------------------------------------------
function ProjectileCamera.checkAndActivate()
    if STATE.tracking.mode == 'projectile_camera' and STATE.projectileWatching.impactTimer then
        local currentTime = Spring.GetTimer()
        local elapsedImpactHold = Spring.DiffTimers(currentTime, STATE.projectileWatching.impactTimer)
        if elapsedImpactHold >= CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.IMPACT_TIMEOUT then
            Log.trace("ProjectileCamera: IMPACT_TIMEOUT reached. Returning to previous mode.")
            local unitID = STATE.projectileWatching.watchedUnitID
            local reArm = (STATE.projectileWatching.continuouslyArmedUnitID == unitID and Spring.ValidUnitID(unitID))
            if unitID and not reArm then
                ProjectileCamera.saveSettings(unitID)
            end
            ProjectileCamera.returnToPreviousMode(reArm)
            return true
        end
    end

    if not STATE.projectileWatching.armed or STATE.tracking.mode == 'projectile_camera' then
        return false
    end

    local unitID = STATE.projectileWatching.watchedUnitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.warn("ProjectileCamera: Watched unit " .. tostring(unitID) .. " became invalid. Disarming.")
        ProjectileCamera.disableProjectileArming()
        STATE.projectileWatching.continuouslyArmedUnitID = nil
        return false
    end

    local allProjectiles = ProjectileTracker.getUnitProjectiles(unitID)
    local newProjectiles = {}
    for _, p in ipairs(allProjectiles) do
        if p.creationTime > STATE.projectileWatching.lastArmingTime then
            table.insert(newProjectiles, p)
        end
    end

    if #newProjectiles == 0 then
        return false
    end

    if TrackingManager.startModeTransition('projectile_camera') then
        if TrackingManager.initializeTracking('projectile_camera', unitID, STATE.TARGET_TYPES.UNIT) then
            STATE.tracking.projectile = STATE.tracking.projectile or {}
            STATE.tracking.projectile.selectedProjectileID = nil
            STATE.tracking.projectile.currentProjectileID = nil
            ProjectileCameraUtils.resetSmoothedPositions()
            STATE.projectileWatching.armed = false
            Log.trace("ProjectileCamera: Activated, tracking new projectile from unit " .. unitID)
            return true
        else
            Log.warn("ProjectileCamera: Failed to initialize tracking for 'projectile_camera'. Reverting arm.")
            local reArm = (STATE.projectileWatching.continuouslyArmedUnitID == unitID)
            ProjectileCamera.returnToPreviousMode(reArm)
            return false
        end
    else
        Log.warn("ProjectileCamera: Failed to start mode transition to 'projectile_camera'. Disarming fully.")
        STATE.projectileWatching.continuouslyArmedUnitID = nil
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
        local reArm = (STATE.projectileWatching.continuouslyArmedUnitID == unitID)
        if unitID and not reArm then
            ProjectileCamera.saveSettings(unitID)
        end
        ProjectileCamera.returnToPreviousMode(reArm)
        return
    end

    if STATE.projectileWatching.isImpactDecelerating then
        ProjectileCamera.decelerateToImpactPosition(dt)
        return
    end

    if STATE.projectileWatching.impactTimer then
        ProjectileCamera.focusOnImpactPosition()
        return
    end

    STATE.tracking.projectile = STATE.tracking.projectile or {}
    STATE.tracking.projectile.smoothedPositions = STATE.tracking.projectile.smoothedPositions or { camPos = nil, targetPos = nil }

    if not STATE.tracking.projectile.currentProjectileID then
        ProjectileCamera.selectProjectile(unitID) -- This will set STATE.projectileWatching.isHighArc
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
        STATE.projectileWatching.isHighArc = false
    end

    if latestValidProjectile then
        if STATE.tracking.projectile.currentProjectileID ~= latestValidProjectile.id then
            STATE.tracking.projectile.selectedProjectileID = latestValidProjectile.id
            STATE.tracking.projectile.currentProjectileID = latestValidProjectile.id
            ProjectileCameraUtils.resetSmoothedPositions()
            Log.trace("ProjectileCamera: Selected projectile " .. latestValidProjectile.id)
            STATE.projectileWatching.impactTimer = nil
            STATE.projectileWatching.isImpactDecelerating = false
            STATE.projectileWatching.impactPosition = nil

            -- *** HIGH ARC DETECTION LOGIC (Magnitude check removed as per user) ***
            local vel = latestValidProjectile.lastVelocity
            if not vel then
                Log.warn("[ProjectileDebug] selectProjectile: latestValidProjectile.lastVelocity is nil for projectile ID: " .. latestValidProjectile.id)
                STATE.projectileWatching.isHighArc = false -- Ensure it's false if velocity is missing
            else
                local mag = CameraCommons.vectorMagnitude(vel)
                if mag > 0.01 then
                    -- Ensure projectile has some velocity to avoid division by zero / NaN
                    local upComponent = vel.y / mag
                    local HIGH_ARC_THRESHOLD = 0.8 -- ~53 degrees
                    if upComponent > HIGH_ARC_THRESHOLD then
                        STATE.projectileWatching.isHighArc = true
                        Log.debug(("[ProjectileDebug] High arc trajectory DETECTED. Vel: %s UpComp: %.2f Mag: %.2f"):format(formatVec(vel), upComponent, mag))
                    else
                        Log.debug(("[ProjectileDebug] High arc trajectory NOT detected (Low Angle). Vel: %s UpComp: %.2f Mag: %.2f"):format(formatVec(vel), upComponent, mag))
                    end
                else
                    Log.debug(("[ProjectileDebug] High arc trajectory NOT detected (Zero/Low Speed). Vel: %s Mag: %.2f"):format(formatVec(vel), mag))
                    STATE.projectileWatching.isHighArc = false -- Ensure it's false for zero/low speed
                end
            end
            -- *** END HIGH ARC DETECTION ***
        end
    else
        STATE.tracking.projectile.selectedProjectileID = nil
        STATE.tracking.projectile.currentProjectileID = nil
        STATE.projectileWatching.isHighArc = false -- No projectile, so not high arc
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
        STATE.projectileWatching.impactPosition = {
            pos = Util.deepCopy(currentProjectile.lastPosition),
            vel = Util.deepCopy(currentProjectile.lastVelocity)
        }
        ProjectileCamera.trackActiveProjectile(currentProjectile)
    else
        ProjectileCamera.handleImpactView(unitID, dt)
    end
end

function ProjectileCamera.handleImpactView(unitID, dt)
    if not STATE.projectileWatching.impactPosition then
        Log.trace("ProjectileCamera: No impact position available, focusing on unit " .. unitID)
        ProjectileCamera.focusOnUnit(unitID)
        return
    end
    if not STATE.projectileWatching.isImpactDecelerating and not STATE.projectileWatching.impactTimer then
        STATE.projectileWatching.isImpactDecelerating = true
        STATE.projectileWatching.impactDecelerationStartTime = Spring.GetTimer()
        STATE.projectileWatching.impactTimer = Spring.GetTimer()
        local vel, _ = CameraManager.getCurrentVelocity()
        STATE.projectileWatching.initialImpactVelocity = Util.deepCopy(vel)
        Log.trace("ProjectileCamera: Projectile lost/ended. Starting impact deceleration and timer for unit " .. unitID)
        ProjectileCamera.decelerateToImpactPosition(dt)
    elseif STATE.projectileWatching.isImpactDecelerating then
        ProjectileCamera.decelerateToImpactPosition(dt)
    else
        ProjectileCamera.focusOnImpactPosition()
    end
end

function ProjectileCamera.decelerateToImpactPosition(dt)
    if not STATE.projectileWatching.impactPosition or not STATE.projectileWatching.impactPosition.pos then
        Log.warn("ProjectileCamera: decelerateToImpactPosition called without valid impactPosition.")
        STATE.projectileWatching.isImpactDecelerating = false
        ProjectileCamera.focusOnUnit(STATE.tracking.unitID)
        return
    end
    local impactWorldPos = STATE.projectileWatching.impactPosition.pos
    local currentCamState = CameraManager.getCameraState("ProjectileCamera.decelerateToImpactPosition")
    local camPos = { x = currentCamState.px, y = currentCamState.py, z = currentCamState.pz }
    local profile = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DECELERATION_PROFILE
    local elapsedDecelTime = Spring.DiffTimers(Spring.GetTimer(), STATE.projectileWatching.impactDecelerationStartTime)
    local linearProgress = 1.0
    if profile.DURATION and profile.DURATION > 0 then
        linearProgress = math.min(elapsedDecelTime / profile.DURATION, 1.0)
    end
    local easedProgress = CameraCommons.easeOut(linearProgress)
    local initialVelocity = STATE.projectileWatching.initialImpactVelocity or { x = 0, y = 0, z = 0 }
    local newPos = TransitionUtil.decelerationTransition(camPos, dt, easedProgress, initialVelocity, profile)
    local camStatePatch = {}
    if newPos then
        camStatePatch.px = newPos.px;
        camStatePatch.py = newPos.py;
        camStatePatch.pz = newPos.pz
    else
        camStatePatch.px = camPos.x;
        camStatePatch.py = camPos.y;
        camStatePatch.pz = camPos.z
    end
    local focusFromPos = { x = camStatePatch.px, y = camStatePatch.py, z = camStatePatch.pz }
    local targetLookPos = ProjectileCameraUtils.calculateIdealTargetPosition(impactWorldPos, STATE.projectileWatching.impactPosition.vel or { x = 0, y = 0, z = 0 })
    local cfgSmoothing = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING
    local dirSmoothFactor = cfgSmoothing.ROTATION_FACTOR
    local rotSmoothFactor = cfgSmoothing.ROTATION_FACTOR
    local dirState = CameraCommons.focusOnPoint(focusFromPos, targetLookPos, dirSmoothFactor, rotSmoothFactor)
    local finalCamState = {
        px = camStatePatch.px, py = camStatePatch.py, pz = camStatePatch.pz,
        dx = dirState.dx, dy = dirState.dy, dz = dirState.dz,
        rx = dirState.rx, ry = dirState.ry, rz = dirState.rz,
        fov = currentCamState.fov
    }
    CameraManager.setCameraState(finalCamState, 0, "ProjectileCamera.decelerateToImpact")
    TrackingManager.updateTrackingState(finalCamState)
    if linearProgress >= 1.0 then
        STATE.projectileWatching.isImpactDecelerating = false
        STATE.projectileWatching.initialImpactVelocity = nil
        Log.trace("ProjectileCamera: Finished impact deceleration phase.")
    end
end

function ProjectileCamera.calculateSettledImpactCameraPosition(impactWorldPos, impactWorldVel)
    local camPosForImpact
    local impactViewCfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.IMPACT_VIEW or {}
    local followCfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.FOLLOW
    local pseudoProjectileVel = { x = 0, y = -0.5, z = -0.5, speed = 1 }
    if impactWorldVel and CameraCommons.vectorMagnitude(impactWorldVel) > 0.1 then
        pseudoProjectileVel = impactWorldVel
    end
    pseudoProjectileVel = CameraCommons.normalizeVector(pseudoProjectileVel)
    local baseDistance = followCfg.DISTANCE
    local baseHeight = followCfg.HEIGHT
    local viewDistance = baseDistance * (impactViewCfg.DISTANCE_SCALE or 0.5)
    local viewHeightOffset = baseHeight * (impactViewCfg.HEIGHT_SCALE or 0.75)
    camPosForImpact = {
        x = impactWorldPos.x - pseudoProjectileVel.x * viewDistance,
        y = impactWorldPos.y - pseudoProjectileVel.y * viewDistance + viewHeightOffset,
        z = impactWorldPos.z - pseudoProjectileVel.z * viewDistance
    }
    return camPosForImpact
end

function ProjectileCamera.focusOnImpactPosition()
    if not STATE.projectileWatching.impactPosition or not STATE.projectileWatching.impactPosition.pos then
        Log.warn("ProjectileCamera: focusOnImpactPosition called without valid impactPosition.")
        ProjectileCamera.focusOnUnit(STATE.tracking.unitID)
        return
    end
    local impactWorldPos = STATE.projectileWatching.impactPosition.pos
    local impactWorldVel = STATE.projectileWatching.impactPosition.vel or { x = 0, y = 0, z = 0 }
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
        local reArm = (STATE.projectileWatching.continuouslyArmedUnitID == unitID)
        ProjectileCamera.returnToPreviousMode(reArm)
    end
end

-- This is the version from your uploaded file for this turn.
-- It does not pass `smoothedUp` to calculateCameraPositionForProjectile.
-- The logic is now self-contained in projectile_camera_utils.lua
function ProjectileCamera.trackActiveProjectile(currentProjectile)
    STATE.projectileWatching.impactTimer = nil
    STATE.projectileWatching.isImpactDecelerating = false

    local projectilePos = currentProjectile.lastPosition
    local projectileVel = currentProjectile.lastVelocity

    if not projectilePos or not projectileVel then
        Log.warn(("[ProjectileDebug] TrackActive: projectilePos (%s) or projectileVel (%s) is nil. ID: %s"):format(tostring(projectilePos), tostring(projectileVel), currentProjectile.id))
        ProjectileCamera.handleImpactView(STATE.tracking.unitID, 0) -- Pass dt=0 or handle appropriately
        return
    end

    -- calculateCameraPositionForProjectile in utils will now internally use STATE.projectileWatching.isHighArc
    local idealCamPos = ProjectileCameraUtils.calculateCameraPositionForProjectile(projectilePos, projectileVel, STATE.projectileWatching.cameraMode)
    local idealTargetPos = ProjectileCameraUtils.calculateIdealTargetPosition(projectilePos, projectileVel)

    ProjectileCameraUtils.initializeSmoothedPositionsIfNil(idealCamPos, idealTargetPos)

    local smoothedCamPos = ProjectileCameraUtils.calculateSmoothedCameraPosition(idealCamPos)
    local smoothedTargetPos = ProjectileCameraUtils.calculateSmoothedTargetPosition(idealTargetPos)

    STATE.tracking.projectile.smoothedPositions.camPos = smoothedCamPos
    STATE.tracking.projectile.smoothedPositions.targetPos = smoothedTargetPos

    Log.staggeredLog(("[ProjectileDebug] Track Loop. ProjPos: %s | ProjVel: %s | HighArc: %s | Mode: %s"):format(
            formatVec(projectilePos), formatVec(projectileVel), tostring(STATE.projectileWatching.isHighArc), STATE.projectileWatching.cameraMode
    ))
    Log.staggeredLog(("[ProjectileDebug] Track Loop. IdealCam: %s | SmoothedCam: %s"):format(
            formatVec(idealCamPos), formatVec(smoothedCamPos)
    ))

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