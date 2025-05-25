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
---@type ProjectileCameraPersistence
local ProjectileCameraPersistence = VFS.Include("LuaUI/TurboBarCam/features/projectile_camera/projectile_camera_persistence.lua")


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
        if currentSubMode == requestedSubMode and not isImpactDecelerating then -- Don't toggle off if decelerating
            ProjectileCamera.saveSettings(unitToWatchForToggle)
            STATE.projectileWatching.continuouslyArmedUnitID = nil
            ProjectileCamera.returnToPreviousMode(false)
            return true
        else
            return ProjectileCamera.switchCameraSubModes(requestedSubMode)
        end
    elseif isArmed then -- Armed but not yet in 'projectile_camera' mode
        if currentSubMode == requestedSubMode then
            ProjectileCamera.saveSettings(unitToWatchForToggle)
            STATE.projectileWatching.continuouslyArmedUnitID = nil
            ProjectileCamera.disableProjectileArming() -- Just disarm, don't change camera mode yet
            return true
        else
            return ProjectileCamera.switchCameraSubModes(requestedSubMode) -- Switch submode while still armed
        end
    elseif isContinuous then -- Was continuously armed, but currently not armed (e.g. after a projectile cycle)
        if currentSubMode == requestedSubMode then
            ProjectileCamera.saveSettings(unitToWatchForToggle)
            STATE.projectileWatching.continuouslyArmedUnitID = nil
            ProjectileCamera.disableProjectileArming() -- Ensure it's fully off
            return true
        else
            -- If submodes differ, re-arm with the new submode
            ProjectileCamera.loadSettings(unitToWatchForToggle)
            return ProjectileCamera.armProjectileTracking(requestedSubMode, unitToWatchForToggle)
        end
    else -- Not in projectile mode, not armed, not continuous - fresh start
        if Util.isTurboBarCamDisabled() then return false end
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

    -- Store previous mode only if not already armed or in projectile_camera mode
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
    STATE.projectileWatching.impactTimer = nil -- Reset impact timer
    STATE.projectileWatching.impactPosition = nil
    STATE.projectileWatching.isImpactDecelerating = false -- Reset deceleration state
    STATE.projectileWatching.impactDecelerationStartTime = nil
    STATE.projectileWatching.initialImpactVelocity = nil


    if STATE.tracking.projectile then
        STATE.tracking.projectile.selectedProjectileID = nil
        STATE.tracking.projectile.currentProjectileID = nil
        ProjectileCamera.resetSmoothedPositions()
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
    ProjectileCamera.resetSmoothedPositions()
    return true
end

function ProjectileCamera.returnToPreviousMode(shouldReArm)
    local prevMode = STATE.projectileWatching.previousMode
    local prevCamState = STATE.projectileWatching.previousCameraState
    local previouslyWatchedUnitID = STATE.projectileWatching.watchedUnitID
    local unitToReArmWith = STATE.projectileWatching.continuouslyArmedUnitID

    ProjectileCamera.disableProjectileArming() -- This also resets impactTimer, isImpactDecelerating etc.

    local canReArm = shouldReArm and unitToReArmWith and Spring.ValidUnitID(unitToReArmWith)

    if prevMode and prevMode ~= 'projectile_camera' then
        if TrackingManager.startModeTransition(prevMode) then
            local targetForPrevMode = nil
            local effectiveTargetUnit = previouslyWatchedUnitID
            if Util.isUnitCentricMode(prevMode) and effectiveTargetUnit and Spring.ValidUnitID(effectiveTargetUnit) then
                targetForPrevMode = effectiveTargetUnit
            elseif Util.isUnitCentricMode(prevMode) and unitToReArmWith and Spring.ValidUnitID(unitToReArmWith) then
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
        -- If we were in projectile_camera mode and are returning, disable it fully.
        TrackingManager.disableTracking()
    end

    if not canReArm then
        STATE.projectileWatching.continuouslyArmedUnitID = nil
        STATE.projectileWatching.previousMode = nil
        STATE.projectileWatching.previousCameraState = nil
    else
        -- If re-arming, set up the next watch cycle.
        ProjectileCamera.loadSettings(unitToReArmWith)
        ProjectileCamera.armProjectileTracking(STATE.projectileWatching.cameraMode, unitToReArmWith)
    end
end

--------------------------------------------------------------------------------
-- Update Loop Functions
--------------------------------------------------------------------------------

function ProjectileCamera.checkAndActivate()
    -- Check for IMPACT_TIMEOUT. This can now trigger returnToPreviousMode even during deceleration.
    if STATE.tracking.mode == 'projectile_camera' and STATE.projectileWatching.impactTimer then
        local currentTime = Spring.GetTimer()
        local elapsedImpactHold = Spring.DiffTimers(currentTime, STATE.projectileWatching.impactTimer)
        if elapsedImpactHold >= CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.IMPACT_TIMEOUT then
            Log.trace("ProjectileCamera: IMPACT_TIMEOUT reached. Returning to previous mode.")
            local unitID = STATE.projectileWatching.watchedUnitID
            local reArm = (STATE.projectileWatching.continuouslyArmedUnitID == unitID and Spring.ValidUnitID(unitID))
            if unitID and not reArm then ProjectileCamera.saveSettings(unitID) end
            ProjectileCamera.returnToPreviousMode(reArm)
            return true -- Mode changed, skip further processing in this cycle
        end
    end

    -- Logic for arming and activating projectile_camera mode when a new projectile is detected.
    if not STATE.projectileWatching.armed or STATE.tracking.mode == 'projectile_camera' then
        -- Not armed (e.g. waiting for next projectile in continuous mode, or already in projectile_camera mode)
        -- The impactTimer check above handles timeout if we are already in projectile_camera mode.
        return false
    end

    local unitID = STATE.projectileWatching.watchedUnitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.warn("ProjectileCamera: Watched unit " .. tostring(unitID) .. " became invalid. Disarming.")
        ProjectileCamera.disableProjectileArming()
        STATE.projectileWatching.continuouslyArmedUnitID = nil -- Stop continuous if unit is gone
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
        return false -- No new projectiles since arming
    end

    -- Found new projectiles, transition to 'projectile_camera' mode
    if TrackingManager.startModeTransition('projectile_camera') then
        if TrackingManager.initializeTracking('projectile_camera', unitID, STATE.TARGET_TYPES.UNIT) then
            STATE.tracking.projectile = STATE.tracking.projectile or {}
            STATE.tracking.projectile.selectedProjectileID = nil -- Will be selected in update
            STATE.tracking.projectile.currentProjectileID = nil
            ProjectileCamera.resetSmoothedPositions()
            STATE.projectileWatching.armed = false -- Consumed the "armed" state by entering the mode
            Log.trace("ProjectileCamera: Activated, tracking new projectile from unit " .. unitID)
            return true -- Mode changed
        else
            Log.warn("ProjectileCamera: Failed to initialize tracking for 'projectile_camera'. Reverting arm.")
            local reArm = (STATE.projectileWatching.continuouslyArmedUnitID == unitID)
            ProjectileCamera.returnToPreviousMode(reArm) -- This will re-arm if continuous
            return false
        end
    else
        Log.warn("ProjectileCamera: Failed to start mode transition to 'projectile_camera'. Disarming fully.")
        STATE.projectileWatching.continuouslyArmedUnitID = nil -- Stop continuous if transition fails
        ProjectileCamera.disableProjectileArming()
        return false
    end
end


function ProjectileCamera.update(dt)
    if not ProjectileCamera.shouldUpdate() then
        return
    end

    local unitID = STATE.tracking.unitID -- This is the firing unit
    if not ProjectileCamera.validateUnit(unitID) then
        local reArm = (STATE.projectileWatching.continuouslyArmedUnitID == unitID)
        if unitID and not reArm then ProjectileCamera.saveSettings(unitID) end
        ProjectileCamera.returnToPreviousMode(reArm)
        return
    end

    -- If impact deceleration is active, handle that.
    -- Note: The IMPACT_TIMEOUT is checked in checkAndActivate and can interrupt this.
    if STATE.projectileWatching.isImpactDecelerating then
        ProjectileCamera.decelerateToImpactPosition(dt)
        return
    end

    -- If impact timer is active (meaning deceleration is done, now holding view)
    -- Note: The IMPACT_TIMEOUT is checked in checkAndActivate and can interrupt this.
    if STATE.projectileWatching.impactTimer then -- This implies deceleration is finished
        ProjectileCamera.focusOnImpactPosition() -- Hold the settled impact view
        return
    end

    -- Standard projectile tracking logic
    STATE.tracking.projectile = STATE.tracking.projectile or {}
    STATE.tracking.projectile.smoothedPositions = STATE.tracking.projectile.smoothedPositions or { camPos = nil, targetPos = nil }

    if not STATE.tracking.projectile.currentProjectileID then
        ProjectileCamera.selectProjectile(unitID)
        if not STATE.tracking.projectile.currentProjectileID then
            -- No new, valid projectile found to track, initiate impact view sequence
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
    local latestValidProjectile = nil
    local maxCreationTime = -1

    for _, p in ipairs(allProjectiles) do
        if p.creationTime > maxCreationTime then
            maxCreationTime = p.creationTime
            latestValidProjectile = p
        end
    end

    if latestValidProjectile then
        if STATE.tracking.projectile.currentProjectileID ~= latestValidProjectile.id then
            STATE.tracking.projectile.selectedProjectileID = latestValidProjectile.id
            STATE.tracking.projectile.currentProjectileID = latestValidProjectile.id
            ProjectileCamera.resetSmoothedPositions()
            Log.trace("ProjectileCamera: Selected projectile " .. latestValidProjectile.id)
            -- Reset impact states as we are now tracking a new projectile
            STATE.projectileWatching.impactTimer = nil
            STATE.projectileWatching.isImpactDecelerating = false
            STATE.projectileWatching.impactPosition = nil
        end
    else
        STATE.tracking.projectile.selectedProjectileID = nil
        STATE.tracking.projectile.currentProjectileID = nil
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
        ProjectileCamera.trackActiveProjectile(currentProjectile, dt)
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

    -- This function is called when a projectile is lost or no new one is found.
    -- Start deceleration AND the impact timer here.
    if not STATE.projectileWatching.isImpactDecelerating and not STATE.projectileWatching.impactTimer then
        STATE.projectileWatching.isImpactDecelerating = true
        STATE.projectileWatching.impactDecelerationStartTime = Spring.GetTimer()
        STATE.projectileWatching.impactTimer = Spring.GetTimer() -- Start the main impact timer
        local vel, _ = CameraManager.getCurrentVelocity()
        STATE.projectileWatching.initialImpactVelocity = Util.deepCopy(vel)
        Log.trace("ProjectileCamera: Projectile lost/ended. Starting impact deceleration and timer for unit " .. unitID)
        ProjectileCamera.decelerateToImpactPosition(dt) -- Start deceleration immediately
    elseif STATE.projectileWatching.isImpactDecelerating then
        -- Already decelerating, continue. The timeout is handled in checkAndActivate.
        ProjectileCamera.decelerateToImpactPosition(dt)
    else
        -- This case should ideally not be reached if impactTimer is set when deceleration starts.
        -- If it is, it means deceleration finished and impactTimer is running (checked by checkAndActivate).
        ProjectileCamera.focusOnImpactPosition()
    end
end

--- Smoothly decelerates the camera to the impact position.
---@param dt number Delta time
function ProjectileCamera.decelerateToImpactPosition(dt)
    if not STATE.projectileWatching.impactPosition or not STATE.projectileWatching.impactPosition.pos then
        Log.warn("ProjectileCamera: decelerateToImpactPosition called without valid impactPosition.")
        STATE.projectileWatching.isImpactDecelerating = false -- Stop if no target
        ProjectileCamera.focusOnUnit(STATE.tracking.unitID) -- Fallback
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

    local initialVelocity = STATE.projectileWatching.initialImpactVelocity or {x=0,y=0,z=0}
    local newPos = TransitionUtil.decelerationTransition(camPos, dt, easedProgress, initialVelocity, profile)

    local camStatePatch = {}
    if newPos then
        camStatePatch.px = newPos.px
        camStatePatch.py = newPos.py
        camStatePatch.pz = newPos.pz
    else
        camStatePatch.px = camPos.x
        camStatePatch.py = camPos.y
        camStatePatch.pz = camPos.z
    end

    local focusFromPos = { x = camStatePatch.px, y = camStatePatch.py, z = camStatePatch.pz }
    local targetLookPos = ProjectileCamera.calculateIdealTargetPosition(impactWorldPos, STATE.projectileWatching.impactPosition.vel or {x=0,y=0,z=0})

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

    -- This condition now only marks the end of the *deceleration phase*.
    -- The overall impact view duration is handled by impactTimer in checkAndActivate.
    if linearProgress >= 1.0 then
        STATE.projectileWatching.isImpactDecelerating = false
        STATE.projectileWatching.initialImpactVelocity = nil
        -- Do NOT reset impactTimer here. It was started when deceleration began.
        Log.trace("ProjectileCamera: Finished impact deceleration phase.")
    end
end

--- Calculates the camera position for the "settled" impact view (after deceleration).
function ProjectileCamera.calculateSettledImpactCameraPosition(impactWorldPos, impactWorldVel)
    local camPosForImpact
    local impactViewCfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.IMPACT_VIEW or {}
    local followCfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.FOLLOW

    local pseudoProjectileVel = {x=0, y=-0.5, z=-0.5, speed=1}
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


--- Focuses the camera on the impact position (settled view, after deceleration is complete and impactTimer is active).
function ProjectileCamera.focusOnImpactPosition()
    if not STATE.projectileWatching.impactPosition or not STATE.projectileWatching.impactPosition.pos then
        Log.warn("ProjectileCamera: focusOnImpactPosition called without valid impactPosition.")
        ProjectileCamera.focusOnUnit(STATE.tracking.unitID)
        return
    end

    local impactWorldPos = STATE.projectileWatching.impactPosition.pos
    local impactWorldVel = STATE.projectileWatching.impactPosition.vel or {x=0,y=0,z=0}

    local currentCamState = CameraManager.getCameraState("ProjectileCamera.focusOnImpactPosition.Hold")
    local settledCamPos = { x = currentCamState.px, y = currentCamState.py, z = currentCamState.pz }

    local targetLookPos = ProjectileCamera.calculateIdealTargetPosition(impactWorldPos, impactWorldVel)

    ProjectileCamera.applyProjectileCameraState(settledCamPos, targetLookPos, "impact_view_hold")
end


function ProjectileCamera.focusOnUnit(unitID)
    local ux, uy, uz = Spring.GetUnitPosition(unitID)
    if ux then
        local currentCamState = CameraManager.getCameraState("ProjectileCamera.focusOnUnit")
        local camPos = { x = currentCamState.px, y = currentCamState.py, z = currentCamState.pz }
        local targetPos = { x = ux, y = uy + (Util.getUnitHeight(unitID) * 0.5 or 50), z = uz }
        ProjectileCamera.applyProjectileCameraState(camPos, targetPos, "unit_fallback_view")
    else
        Log.warn("ProjectileCamera: Unit " .. tostring(unitID) .. " invalid while trying to focus on it.")
        local reArm = (STATE.projectileWatching.continuouslyArmedUnitID == unitID)
        ProjectileCamera.returnToPreviousMode(reArm)
    end
end

function ProjectileCamera.trackActiveProjectile(currentProjectile, dt)
    STATE.projectileWatching.impactTimer = nil -- Clear impact timer when actively tracking a new projectile
    STATE.projectileWatching.isImpactDecelerating = false

    local projectilePos = currentProjectile.lastPosition
    local projectileVel = currentProjectile.lastVelocity

    local idealCamPos = ProjectileCamera.calculateCameraPositionForProjectile(projectilePos, projectileVel, STATE.projectileWatching.cameraMode, STATE.projectileWatching.initialCamPos)
    local idealTargetPos = ProjectileCamera.calculateIdealTargetPosition(projectilePos, projectileVel)

    ProjectileCamera.initializeSmoothedPositionsIfNil(idealCamPos, idealTargetPos)

    local smoothedCamPos = ProjectileCamera.calculateSmoothedCameraPosition(idealCamPos)
    local smoothedTargetPos = ProjectileCamera.calculateSmoothedTargetPosition(idealTargetPos)

    STATE.tracking.projectile.smoothedPositions.camPos = smoothedCamPos
    STATE.tracking.projectile.smoothedPositions.targetPos = smoothedTargetPos

    ProjectileCamera.applyProjectileCameraState(smoothedCamPos, smoothedTargetPos, "tracking_active")
end

--------------------------------------------------------------------------------
-- Camera Calculation and Smoothing Helpers
--------------------------------------------------------------------------------

function ProjectileCamera.calculateCameraPositionForProjectile(pPos, pVel, subMode, staticInitialCamPos)
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA

    if subMode == "static" then
        local camState = CameraManager.getCameraState("ProjectileCamera.calculateCameraPositionForProjectile.StaticCurrent")
        return { x = camState.px, y = camState.py, z = camState.pz }
    end

    local modeCfg = cfg.FOLLOW
    local distance = modeCfg.DISTANCE
    local height = modeCfg.HEIGHT

    local dir = CameraCommons.normalizeVector(pVel)
    if dir.x == 0 and dir.y == 0 and dir.z == 0 then
        dir = { x = 0, y = -0.5, z = -0.5 }
        dir = CameraCommons.normalizeVector(dir)
    end

    return {
        x = pPos.x - (dir.x * distance),
        y = pPos.y - (dir.y * distance) + height,
        z = pPos.z - (dir.z * distance)
    }
end


function ProjectileCamera.calculateIdealTargetPosition(projectilePos, projectileVel)
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA
    local subMode = STATE.projectileWatching.cameraMode
    local modeCfg = cfg[string.upper(subMode)] or cfg.FOLLOW

    local fwd = CameraCommons.normalizeVector(projectileVel)
    if fwd.x == 0 and fwd.y == 0 and fwd.z == 0 then
        fwd = { x = 0, y = 0, z = 1 }
    end

    local pPos = projectilePos
    local lookAhead = modeCfg.LOOK_AHEAD or 0

    local baseTarget = {
        x = pPos.x + fwd.x * lookAhead,
        y = pPos.y + fwd.y * lookAhead,
        z = pPos.z + fwd.z * lookAhead
    }

    if subMode == "static" then
        local offsetHeight = modeCfg.OFFSET_HEIGHT or 0
        local offsetSide = modeCfg.OFFSET_SIDE or 0

        if offsetHeight == 0 and offsetSide == 0 then
            return baseTarget
        end

        local worldUp = { x = 0, y = 1, z = 0 }
        local right = CameraCommons.crossProduct(fwd, worldUp)
        if CameraCommons.vectorMagnitudeSq(right) < 0.001 then
            local worldFwdTemp = { x = 0, y = 0, z = 1 }
            if math.abs(fwd.z) > 0.99 then worldFwdTemp = {x=1, y=0, z=0} end
            right = CameraCommons.crossProduct(fwd, worldFwdTemp)
        end
        right = CameraCommons.normalizeVector(right)
        local localUp = CameraCommons.normalizeVector(CameraCommons.crossProduct(right, fwd))

        return {
            x = baseTarget.x + localUp.x * offsetHeight + right.x * offsetSide,
            y = baseTarget.y + localUp.y * offsetHeight + right.y * offsetSide,
            z = baseTarget.z + localUp.z * offsetHeight + right.z * offsetSide
        }
    end
    return baseTarget
end


function ProjectileCamera.resetSmoothedPositions()
    if STATE.tracking.projectile and STATE.tracking.projectile.smoothedPositions then
        STATE.tracking.projectile.smoothedPositions.camPos = nil
        STATE.tracking.projectile.smoothedPositions.targetPos = nil
    end
end

function ProjectileCamera.initializeSmoothedPositionsIfNil(idealCamPos, idealTargetPos)
    STATE.tracking.projectile = STATE.tracking.projectile or {}
    STATE.tracking.projectile.smoothedPositions = STATE.tracking.projectile.smoothedPositions or {}

    if not STATE.tracking.projectile.smoothedPositions.camPos then
        STATE.tracking.projectile.smoothedPositions.camPos = Util.deepCopy(idealCamPos)
    end
    if not STATE.tracking.projectile.smoothedPositions.targetPos then
        STATE.tracking.projectile.smoothedPositions.targetPos = Util.deepCopy(idealTargetPos)
    end
end

function ProjectileCamera.calculateSmoothedCameraPosition(idealCamPos)
    local cfgSmoothing = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING
    local smoothFactor = cfgSmoothing.INTERPOLATION_FACTOR

    if STATE.projectileWatching.cameraMode == "static" then
        return idealCamPos
    end

    return {
        x = CameraCommons.smoothStep(STATE.tracking.projectile.smoothedPositions.camPos.x, idealCamPos.x, smoothFactor),
        y = CameraCommons.smoothStep(STATE.tracking.projectile.smoothedPositions.camPos.y, idealCamPos.y, smoothFactor),
        z = CameraCommons.smoothStep(STATE.tracking.projectile.smoothedPositions.camPos.z, idealCamPos.z, smoothFactor)
    }
end

function ProjectileCamera.calculateSmoothedTargetPosition(idealTargetPos)
    local cfgSmoothing = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING
    local smoothFactor = cfgSmoothing.INTERPOLATION_FACTOR
    return {
        x = CameraCommons.smoothStep(STATE.tracking.projectile.smoothedPositions.targetPos.x, idealTargetPos.x, smoothFactor),
        y = CameraCommons.smoothStep(STATE.tracking.projectile.smoothedPositions.targetPos.y, idealTargetPos.y, smoothFactor),
        z = CameraCommons.smoothStep(STATE.tracking.projectile.smoothedPositions.targetPos.z, idealTargetPos.z, smoothFactor)
    }
end

function ProjectileCamera.applyProjectileCameraState(camPos, targetPos, context)
    local cfgSmoothing = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING
    local posFactor = cfgSmoothing.POSITION_FACTOR
    local rotFactor = cfgSmoothing.ROTATION_FACTOR

    local actualPosFactor, actualRotFactor = CameraCommons.handleModeTransition(posFactor, rotFactor)

    local currentCamState = CameraManager.getCameraState("ProjectileCamera.applyProjectileCameraState.Context." .. context)
    local fullCamPos = {
        x = camPos.px or camPos.x or currentCamState.px,
        y = camPos.py or camPos.y or currentCamState.py,
        z = camPos.pz or camPos.z or currentCamState.pz
    }

    local directionState = CameraCommons.focusOnPoint(fullCamPos, targetPos, actualPosFactor, actualRotFactor)

    directionState.px = camPos.px or directionState.px
    directionState.py = camPos.py or directionState.py
    directionState.pz = camPos.pz or directionState.pz
    directionState.fov = currentCamState.fov

    CameraManager.setCameraState(directionState, 0, "ProjectileCamera.update." .. (context or "apply"))
    TrackingManager.updateTrackingState(directionState)
end


--------------------------------------------------------------------------------
-- Settings and Parameters
--------------------------------------------------------------------------------

function ProjectileCamera.resetToDefaults()
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA
    cfg.FOLLOW.DISTANCE = cfg.DEFAULT_FOLLOW.DISTANCE
    cfg.FOLLOW.HEIGHT = cfg.DEFAULT_FOLLOW.HEIGHT
    cfg.FOLLOW.LOOK_AHEAD = cfg.DEFAULT_FOLLOW.LOOK_AHEAD
    cfg.STATIC.LOOK_AHEAD = cfg.DEFAULT_STATIC.LOOK_AHEAD
    cfg.STATIC.OFFSET_HEIGHT = cfg.DEFAULT_STATIC.OFFSET_HEIGHT
    cfg.STATIC.OFFSET_SIDE = cfg.DEFAULT_STATIC.OFFSET_SIDE
    cfg.DECELERATION_PROFILE = Util.deepCopy(cfg.DEFAULT_DECELERATION_PROFILE)
    Log.trace("ProjectileCamera: Restored settings to defaults.")
end

function ProjectileCamera.saveSettings(unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.trace("ProjectileCamera: Cannot save settings, invalid unitID.")
        return
    end

    local unitDef = UnitDefs[Spring.GetUnitDefID(unitID)]
    if not unitDef then
        Log.warn("ProjectileCamera: Cannot save settings, failed to get unitDef.")
        return
    end
    local unitName = unitDef.name
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA

    local settingsToSave = {
        FOLLOW = {
            DISTANCE = cfg.FOLLOW.DISTANCE,
            HEIGHT = cfg.FOLLOW.HEIGHT,
            LOOK_AHEAD = cfg.FOLLOW.LOOK_AHEAD,
        },
        STATIC = {
            LOOK_AHEAD = cfg.STATIC.LOOK_AHEAD,
            OFFSET_HEIGHT = cfg.STATIC.OFFSET_HEIGHT,
            OFFSET_SIDE = cfg.STATIC.OFFSET_SIDE,
        },
        DECELERATION_PROFILE = Util.deepCopy(cfg.DECELERATION_PROFILE)
    }
    ProjectileCameraPersistence.saveSettings(unitName, settingsToSave)
end

function ProjectileCamera.loadSettings(unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.trace("ProjectileCamera: Cannot load settings, invalid unitID.")
        ProjectileCamera.resetToDefaults()
        return
    end

    local unitDef = UnitDefs[Spring.GetUnitDefID(unitID)]
    if not unitDef then
        Log.warn("ProjectileCamera: Cannot load settings, failed to get unitDef.")
        ProjectileCamera.resetToDefaults()
        return
    end
    local unitName = unitDef.name
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA
    local loadedSettings = ProjectileCameraPersistence.loadSettings(unitName)

    if loadedSettings then
        Log.trace("ProjectileCamera: Loading saved settings for " .. unitName)
        cfg.FOLLOW.DISTANCE = loadedSettings.FOLLOW and loadedSettings.FOLLOW.DISTANCE or cfg.DEFAULT_FOLLOW.DISTANCE
        cfg.FOLLOW.HEIGHT = loadedSettings.FOLLOW and loadedSettings.FOLLOW.HEIGHT or cfg.DEFAULT_FOLLOW.HEIGHT
        cfg.FOLLOW.LOOK_AHEAD = loadedSettings.FOLLOW and loadedSettings.FOLLOW.LOOK_AHEAD or cfg.DEFAULT_FOLLOW.LOOK_AHEAD
        cfg.STATIC.LOOK_AHEAD = loadedSettings.STATIC and loadedSettings.STATIC.LOOK_AHEAD or cfg.DEFAULT_STATIC.LOOK_AHEAD
        cfg.STATIC.OFFSET_HEIGHT = loadedSettings.STATIC and loadedSettings.STATIC.OFFSET_HEIGHT or cfg.DEFAULT_STATIC.OFFSET_HEIGHT
        cfg.STATIC.OFFSET_SIDE = loadedSettings.STATIC and loadedSettings.STATIC.OFFSET_SIDE or cfg.DEFAULT_STATIC.OFFSET_SIDE
        cfg.DECELERATION_PROFILE = loadedSettings.DECELERATION_PROFILE and Util.deepCopy(loadedSettings.DECELERATION_PROFILE) or Util.deepCopy(cfg.DEFAULT_DECELERATION_PROFILE)
    else
        Log.trace("ProjectileCamera: No saved settings found for " .. unitName .. ". Using defaults.")
        ProjectileCamera.resetToDefaults()
    end
end

local function getProjectileParamPrefixes()
    return {
        FOLLOW = "FOLLOW.",
        STATIC = "STATIC."
    }
end

function ProjectileCamera.adjustParams(params)
    if Util.isTurboBarCamDisabled() or STATE.tracking.mode ~= 'projectile_camera' then -- More direct check
        return
    end

    local function resetAndSave()
        ProjectileCamera.resetToDefaults()
        if STATE.tracking.unitID then -- Save for current unit if one is tracked
            ProjectileCamera.saveSettings(STATE.tracking.unitID)
        end
        Log.info("Projectile Camera settings reset to defaults" .. (STATE.tracking.unitID and " and saved for current unit type." or "."))
    end

    local currentSubmode = STATE.projectileWatching.cameraMode or "follow"
    local currentSubmodeUpper = string.upper(currentSubmode)

    Log.trace("Adjusting Projectile Camera params for submode: " .. currentSubmodeUpper)
    Util.adjustParams(params, "PROJECTILE_CAMERA", resetAndSave, currentSubmodeUpper, getProjectileParamPrefixes)

    if STATE.tracking.unitID then
        ProjectileCamera.saveSettings(STATE.tracking.unitID)
    end
end

function Util.isUnitCentricMode(mode)
    return mode == 'fps' or mode == 'unit_tracking' or mode == 'orbit' or mode == 'projectile_camera'
end

return {
    ProjectileCamera = ProjectileCamera
}