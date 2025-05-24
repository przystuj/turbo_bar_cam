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
    STATE.projectileWatching.impactTimer = nil
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
    -- Do not clear continuouslyArmedUnitID here, let toggle logic manage it.
end

function ProjectileCamera.switchCameraSubModes(newSubMode)
    STATE.projectileWatching.cameraMode = newSubMode
    if newSubMode == "static" and not STATE.projectileWatching.initialCamPos then
        -- If switching to static and we are already in projectile_camera mode,
        -- capture current camera pos as the static point.
        -- Otherwise, initialCamPos would have been set during arming.
        if STATE.tracking.mode == 'projectile_camera' or STATE.projectileWatching.armed then
            local camState = CameraManager.getCameraState("ProjectileCamera.switchCameraSubModes.Static")
            STATE.projectileWatching.initialCamPos = { x = camState.px, y = camState.py, z = camState.pz }
        end
    end
    Log.debug("Projectile tracking switched to: " .. newSubMode)
    ProjectileCamera.resetSmoothedPositions()
    -- If already tracking a projectile, the view will update in the next frame.
    -- If only armed, it will use this subMode when a projectile is found.
    return true
end

function ProjectileCamera.returnToPreviousMode(shouldReArm)
    local prevMode = STATE.projectileWatching.previousMode
    local prevCamState = STATE.projectileWatching.previousCameraState
    local previouslyWatchedUnitID = STATE.projectileWatching.watchedUnitID -- The unit that fired
    local unitToReArmWith = STATE.projectileWatching.continuouslyArmedUnitID -- The unit we want to keep watching

    ProjectileCamera.disableProjectileArming() -- Full disarm of current cycle

    local canReArm = shouldReArm and unitToReArmWith and Spring.ValidUnitID(unitToReArmWith)

    if prevMode and prevMode ~= 'projectile_camera' then
        if TrackingManager.startModeTransition(prevMode) then
            local targetForPrevMode = nil
            -- When returning, the target should be the unit that was originally firing,
            -- or the unit we are continuously armed for if different and makes sense for that mode.
            -- Typically, it's the unit that was the center of action.
            local effectiveTargetUnit = previouslyWatchedUnitID
            if Util.isUnitCentricMode(prevMode) and effectiveTargetUnit and Spring.ValidUnitID(effectiveTargetUnit) then
                targetForPrevMode = effectiveTargetUnit
            elseif Util.isUnitCentricMode(prevMode) and unitToReArmWith and Spring.ValidUnitID(unitToReArmWith) then
                targetForPrevMode = unitToReArmWith -- Fallback if previouslyWatched is gone
            end

            TrackingManager.initializeTracking(prevMode, targetForPrevMode) -- Target type auto-detected
            if prevCamState then
                CameraManager.setCameraState(prevCamState, 0, "ProjectileCamera.restorePreviousModeState")
            end
        else
            Log.warn("ProjectileCamera: Failed to start transition to previous mode: " .. prevMode .. ". Disabling tracking fully.")
            TrackingManager.disableTracking()
            canReArm = false -- Cannot re-arm if mode transition failed
        end
    elseif STATE.tracking.mode == 'projectile_camera' then
        -- Was in projectile_camera, but no specific previous mode to return to (e.g., direct entry)
        TrackingManager.disableTracking()
    end

    -- Clean up projectile watching state if not re-arming
    if not canReArm then
        STATE.projectileWatching.continuouslyArmedUnitID = nil
        STATE.projectileWatching.previousMode = nil
        STATE.projectileWatching.previousCameraState = nil
    else
        -- Re-arm for the continuously tracked unit
        ProjectileCamera.loadSettings(unitToReArmWith)
        ProjectileCamera.armProjectileTracking(STATE.projectileWatching.cameraMode, unitToReArmWith)
    end
end

--------------------------------------------------------------------------------
-- Update Loop Functions
--------------------------------------------------------------------------------

function ProjectileCamera.checkAndActivate()
    -- Handle timeout for impact view (after deceleration)
    if STATE.tracking.mode == 'projectile_camera' and STATE.projectileWatching.impactTimer and not STATE.projectileWatching.isImpactDecelerating then
        local currentTime = Spring.GetTimer()
        local elapsedImpactHold = Spring.DiffTimers(currentTime, STATE.projectileWatching.impactTimer)
        if elapsedImpactHold >= CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.IMPACT_TIMEOUT then
            local unitID = STATE.projectileWatching.watchedUnitID
            local reArm = (STATE.projectileWatching.continuouslyArmedUnitID == unitID and Spring.ValidUnitID(unitID))
            if unitID and not reArm then ProjectileCamera.saveSettings(unitID) end
            ProjectileCamera.returnToPreviousMode(reArm)
            return true -- Mode changed
        end
    end

    if not STATE.projectileWatching.armed or STATE.tracking.mode == 'projectile_camera' then
        return false -- Already in mode or not armed
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
        -- Pass the unitID that fired the projectile as the target for the mode
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

    -- If impact deceleration is active, handle that exclusively
    if STATE.projectileWatching.isImpactDecelerating then
        ProjectileCamera.decelerateToImpactPosition(dt)
        return
    end

    -- If impact timer is active (meaning deceleration is done, now holding view)
    if STATE.projectileWatching.impactTimer then
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
    if Util.isTurboBarCamDisabled() then -- Removed redundant isModeDisabled check
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

--- Selects the oldest *new* projectile to track.
function ProjectileCamera.selectProjectile(unitID)
    local allProjectiles = ProjectileTracker.getUnitProjectiles(unitID)
    local latestValidProjectile = nil
    local maxCreationTime = -1

    for _, p in ipairs(allProjectiles) do
        -- We assume getUnitProjectiles only returns currently active/tracked ones.
        -- We just need to find the newest one.
        if p.creationTime > maxCreationTime then
            maxCreationTime = p.creationTime
            latestValidProjectile = p
        end
    end

    if latestValidProjectile then
        -- Select this projectile if it's different from the current one
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
        -- No valid projectiles found. Clear current selection.
        STATE.tracking.projectile.selectedProjectileID = nil
        STATE.tracking.projectile.currentProjectileID = nil
    end
end

--- Gets the currently tracked projectile's data by searching the tracked list.
---@param unitID number The ID of the firing unit (used to filter ProjectileTracker)
---@return table|nil The projectile data table or nil if not found/invalid.
function ProjectileCamera.getCurrentProjectile(unitID)
    if not STATE.tracking.projectile or not STATE.tracking.projectile.currentProjectileID then
        return nil
    end

    local currentID = STATE.tracking.projectile.currentProjectileID
    local projectiles = ProjectileTracker.getUnitProjectiles(unitID)

    for _, proj in ipairs(projectiles) do
        if proj.id == currentID then
            return proj -- Found it in the current list, so it's "valid"
        end
    end

    -- If not found in the current list, it's no longer tracked/valid.
    return nil
end


function ProjectileCamera.handleProjectileTracking(unitID, dt)
    local currentProjectile = ProjectileCamera.getCurrentProjectile(unitID) -- unitID is the firing unit

    -- Check if currentProjectile is valid (non-nil) and has a position.
    if currentProjectile and currentProjectile.lastPosition then
        -- Store the last known good position and velocity for potential impact view
        STATE.projectileWatching.impactPosition = {
            pos = Util.deepCopy(currentProjectile.lastPosition),
            vel = Util.deepCopy(currentProjectile.lastVelocity)
        }
        ProjectileCamera.trackActiveProjectile(currentProjectile, dt)
    else
        -- Projectile became invalid or disappeared (getCurrentProjectile returned nil).
        ProjectileCamera.handleImpactView(unitID, dt)
    end
end


--- Initiates the sequence for viewing the impact point.
--- This could mean starting deceleration or directly focusing if no velocity.
---@param unitID number The ID of the unit that fired the projectile.
---@param dt number Delta time.
function ProjectileCamera.handleImpactView(unitID, dt)
    if not STATE.projectileWatching.impactPosition then
        Log.trace("ProjectileCamera: No impact position available, focusing on unit " .. unitID)
        ProjectileCamera.focusOnUnit(unitID) -- Fallback if no impact data at all
        return
    end

    if not STATE.projectileWatching.isImpactDecelerating and not STATE.projectileWatching.impactTimer then
        -- This is the first time we're handling impact for this projectile
        STATE.projectileWatching.isImpactDecelerating = true
        STATE.projectileWatching.impactDecelerationStartTime = Spring.GetTimer()
        local vel, _ = CameraManager.getCurrentVelocity()
        STATE.projectileWatching.initialImpactVelocity = Util.deepCopy(vel)
        Log.trace("ProjectileCamera: Projectile lost/ended. Starting impact deceleration for unit " .. unitID)
        ProjectileCamera.decelerateToImpactPosition(dt) -- Start deceleration immediately
    elseif STATE.projectileWatching.isImpactDecelerating then
        -- Already decelerating, continue
        ProjectileCamera.decelerateToImpactPosition(dt)
    else
        -- Deceleration finished, impactTimer is running, hold view
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

    local profile = CONFIG.DECELERATION_PROFILES.PROJECTILE_IMPACT_ENTER
    local elapsedDecelTime = Spring.DiffTimers(Spring.GetTimer(), STATE.projectileWatching.impactDecelerationStartTime)
    local decelProgress = math.min(elapsedDecelTime / (profile.DURATION or 0.75), 1.0)

    local initialVelocity = STATE.projectileWatching.initialImpactVelocity or {x=0,y=0,z=0}
    local newPos = TransitionUtil.smoothDecelerationTransition(camPos, dt, decelProgress, initialVelocity, profile)

    local camStatePatch = {}
    if newPos then
        camStatePatch.px = newPos.px
        camStatePatch.py = newPos.py
        camStatePatch.pz = newPos.pz
    else
        -- Deceleration logic returned nil (e.g., velocity low or progress ended).
        -- Smoothly approach the final "settled" impact view camera position.
        local finalCamPosForImpact = ProjectileCamera.calculateSettledImpactCameraPosition(impactWorldPos, STATE.projectileWatching.impactPosition.vel)
        local approachFactor = CameraCommons.lerp(0.1, 1.0, decelProgress) -- Start gentle, ensure arrival

        camStatePatch.px = CameraCommons.smoothStep(camPos.x, finalCamPosForImpact.x, approachFactor)
        camStatePatch.py = CameraCommons.smoothStep(camPos.y, finalCamPosForImpact.y, approachFactor)
        camStatePatch.pz = CameraCommons.smoothStep(camPos.z, finalCamPosForImpact.z, approachFactor)
    end

    -- Direction and rotation should still point towards the impact.
    local targetLookPos = ProjectileCamera.calculateIdealTargetPosition(impactWorldPos, STATE.projectileWatching.impactPosition.vel or {x=0,y=0,z=0})

    -- Use general projectile camera smoothing factors for direction/rotation during this phase
    local cfgSmoothing = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING
    local dirSmoothFactor, rotSmoothFactor = CameraCommons.handleModeTransition(cfgSmoothing.POSITION_FACTOR, cfgSmoothing.ROTATION_FACTOR)

    -- Create a temporary camera state with the new position for focusOnPoint
    local tempFocusCamState = { x = camStatePatch.px, y = camStatePatch.py, z = camStatePatch.pz }
    local dirState = CameraCommons.focusOnPoint(tempFocusCamState, targetLookPos, dirSmoothFactor, rotSmoothFactor)

    local finalCamState = {
        px = camStatePatch.px, py = camStatePatch.py, pz = camStatePatch.pz,
        dx = dirState.dx, dy = dirState.dy, dz = dirState.dz,
        rx = dirState.rx, ry = dirState.ry, rz = dirState.rz,
        fov = currentCamState.fov -- Preserve FOV
    }

    CameraManager.setCameraState(finalCamState, 0, "ProjectileCamera.decelerateToImpact")
    TrackingManager.updateTrackingState(finalCamState)

    if decelProgress >= 1.0 then
        STATE.projectileWatching.isImpactDecelerating = false
        STATE.projectileWatching.initialImpactVelocity = nil
        STATE.projectileWatching.impactTimer = Spring.GetTimer() -- Start the hold timer
        Log.trace("ProjectileCamera: Finished impact deceleration. Holding view.")
    end
end

--- Calculates the camera position for the "settled" impact view (after deceleration).
function ProjectileCamera.calculateSettledImpactCameraPosition(impactWorldPos, impactWorldVel)
    local camPosForImpact
    local impactViewCfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.IMPACT_VIEW or {}
    local followCfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.FOLLOW

    -- Use a pseudo velocity to orient the camera if actual impact velocity is not useful
    local pseudoProjectileVel = {x=0, y=-0.5, z=-0.5, speed=1} -- Default: look somewhat down and forward
    if impactWorldVel and CameraCommons.vectorMagnitude(impactWorldVel) > 0.1 then
        pseudoProjectileVel = impactWorldVel
    end
    pseudoProjectileVel = CameraCommons.normalizeVector(pseudoProjectileVel) -- Ensure it's normalized

    -- Base distance and height from follow mode, then scale if impactViewCfg exists
    local baseDistance = followCfg.DISTANCE
    local baseHeight = followCfg.HEIGHT

    local viewDistance = baseDistance * (impactViewCfg.DISTANCE_SCALE or 0.5)
    local viewHeightOffset = baseHeight * (impactViewCfg.HEIGHT_SCALE or 0.75) -- This is an offset from projectile path

    camPosForImpact = {
        x = impactWorldPos.x - pseudoProjectileVel.x * viewDistance,
        y = impactWorldPos.y - pseudoProjectileVel.y * viewDistance + viewHeightOffset,
        z = impactWorldPos.z - pseudoProjectileVel.z * viewDistance
    }
    return camPosForImpact
end


--- Focuses the camera on the impact position (settled view, after deceleration).
function ProjectileCamera.focusOnImpactPosition()
    if not STATE.projectileWatching.impactPosition or not STATE.projectileWatching.impactPosition.pos then
        Log.warn("ProjectileCamera: focusOnImpactPosition called without valid impactPosition.")
        ProjectileCamera.focusOnUnit(STATE.tracking.unitID) -- Fallback
        return
    end

    local impactWorldPos = STATE.projectileWatching.impactPosition.pos
    local impactWorldVel = STATE.projectileWatching.impactPosition.vel or {x=0,y=0,z=0}

    local camPosForImpact = ProjectileCamera.calculateSettledImpactCameraPosition(impactWorldPos, impactWorldVel)
    local targetLookPos = ProjectileCamera.calculateIdealTargetPosition(impactWorldPos, impactWorldVel)

    ProjectileCamera.applyProjectileCameraState(camPosForImpact, targetLookPos, "impact_view_settled")
end


function ProjectileCamera.focusOnUnit(unitID)
    local ux, uy, uz = Spring.GetUnitPosition(unitID)
    if ux then
        local currentCamState = CameraManager.getCameraState("ProjectileCamera.focusOnUnit")
        local camPos = { x = currentCamState.px, y = currentCamState.py, z = currentCamState.pz }
        local targetPos = { x = ux, y = uy + (Util.getUnitHeight(unitID) * 0.5 or 50), z = uz } -- Look at mid-height
        ProjectileCamera.applyProjectileCameraState(camPos, targetPos, "unit_fallback_view")
    else
        Log.warn("ProjectileCamera: Unit " .. tostring(unitID) .. " invalid while trying to focus on it.")
        local reArm = (STATE.projectileWatching.continuouslyArmedUnitID == unitID)
        ProjectileCamera.returnToPreviousMode(reArm)
    end
end

function ProjectileCamera.trackActiveProjectile(currentProjectile, dt)
    STATE.projectileWatching.impactTimer = nil -- Not in impact phase if actively tracking
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
        return staticInitialCamPos or Util.deepCopy(pPos)
    end

    local modeCfg = cfg.FOLLOW
    local distance = modeCfg.DISTANCE
    local height = modeCfg.HEIGHT

    local dir = CameraCommons.normalizeVector(pVel)
    if dir.x == 0 and dir.y == 0 and dir.z == 0 then -- Fallback if velocity is zero
        dir = { x = 0, y = -0.5, z = -0.5 } -- Look somewhat down/behind
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
    local modeCfg = cfg[string.upper(subMode)] or cfg.FOLLOW -- Fallback to FOLLOW if subMode cfg missing

    local fwd = CameraCommons.normalizeVector(projectileVel)
    if fwd.x == 0 and fwd.y == 0 and fwd.z == 0 then
        fwd = { x = 0, y = 0, z = 1 } -- Default forward if no velocity
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
            if math.abs(fwd.z) > 0.99 then worldFwdTemp = {x=1, y=0, z=0} end -- if fwd is along Z, use X for cross
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
    directionState.fov = currentCamState.fov -- Preserve FOV

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
        }
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
