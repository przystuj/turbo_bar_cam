---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type ProjectileTracker
local ProjectileTracker = VFS.Include("LuaUI/TurboBarCam/standalone/projectile_tracker.lua").ProjectileTracker
---@type TrackingManager
local TrackingManager = CommonModules.TrackingManager

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons

-- Initialize the projectile watching state in global STATE
if not STATE.projectileWatching then
    STATE.projectileWatching = {
        enabled = false,
        watchedUnitID = nil,
        previousMode = nil, -- Store previous mode to return to
        impactTimer = nil, -- Timer for impact timeout
        impactTimeout = 1.5, -- Wait x seconds after impact
        impactPosition = nil, -- Last known position for impact view
        cameraMode = "follow" -- "follow" or "static"
    }
end

---@class ProjectileCamera
local ProjectileCamera = {}

-- Toggles projectile camera mode with shared functionality between modes
---@param mode string The camera mode to use ("follow" or "static")
---@return boolean success Whether toggle was successful
function ProjectileCamera.toggle(mode)
    if Util.isTurboBarCamDisabled() then
        return false
    end

    if STATE.tracking.mode and not Util.tableContains(CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.COMPATIBLE_MODES, STATE.tracking.mode) then
        Log.info("Current mode " .. STATE.tracking.mode .. " is not compatible with projectile tracking")
        return false
    end

    -- Get the currently tracked unit ID
    local unitID = STATE.tracking.unitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.trace("No valid unit selected for projectile camera")
        return false
    end

    -- Check if we're already in projectile camera mode
    if STATE.tracking.mode == 'projectile_camera' then
        -- If requesting the same mode we're already in, turn it off
        if STATE.projectileWatching.cameraMode == mode then
            ProjectileCamera.returnToPreviousMode()
            return true
        else
            -- Switch between follow and static modes
            Log.trace("Switching from " .. STATE.projectileWatching.cameraMode .. " mode to " .. mode .. " mode")
            STATE.projectileWatching.cameraMode = mode

            -- When switching to static mode, use the originally saved camera position
            if mode == "static" and STATE.projectileWatching.previousCameraState then
                STATE.projectileWatching.initialCamPos = {
                    x = STATE.projectileWatching.previousCameraState.px,
                    y = STATE.projectileWatching.previousCameraState.py,
                    z = STATE.projectileWatching.previousCameraState.pz
                }
            end

            -- Reset smoothed positions when switching modes
            if STATE.tracking.projectile and STATE.tracking.projectile.smoothedPositions then
                STATE.tracking.projectile.smoothedPositions = {
                    camPos = nil,
                    targetPos = nil
                }
            end

            return true
        end
    else
        STATE.projectileWatching.previousMode = STATE.tracking.mode
        STATE.projectileWatching.previousCameraState = CameraManager.getCameraState("ProjectileCamera.toggle")
    end

    -- If we're already watching for projectiles, turn it off
    if STATE.projectileWatching.enabled then
        ProjectileCamera.disableProjectileCamera()
        return true
    end


    -- Set up camera mode
    STATE.projectileWatching.cameraMode = mode

    -- For static mode, store the initial camera position
    if mode == "static" then
        local camState = CameraManager.getCameraState("ProjectileCamera.toggle")
        STATE.projectileWatching.initialCamPos = {
            x = camState.px,
            y = camState.py,
            z = camState.pz
        }
        Log.trace("Static camera position set at " ..
                STATE.projectileWatching.initialCamPos.x .. ", " ..
                STATE.projectileWatching.initialCamPos.y .. ", " ..
                STATE.projectileWatching.initialCamPos.z)
    else
        STATE.projectileWatching.initialCamPos = nil
    end

    -- Start watching for projectiles from this unit
    STATE.projectileWatching.enabled = true
    STATE.projectileWatching.watchedUnitID = unitID
    STATE.projectileWatching.impactTimer = nil
    STATE.projectileWatching.impactPosition = nil

    -- Reset projectile tracking state
    if STATE.tracking.projectile then
        STATE.tracking.projectile.selectedProjectileID = nil
        STATE.tracking.projectile.currentProjectileID = nil
    end

    -- Initialize projectile tracking for this unit
    ProjectileTracker.initUnitTracking(unitID)

    Log.trace("Watching unit " .. unitID .. " for projectiles in " .. mode .. " mode (will return to " ..
            (STATE.projectileWatching.previousMode or "default") .. " mode after impact)")

    -- Try activating immediately if projectiles exist
    local activated = ProjectileCamera.checkAndActivate()
    if activated then
        Log.trace("Projectiles found, camera activated immediately in " .. mode .. " mode")
    end

    return true
end

-- Toggles projectile follow camera mode (original behavior)
---@return boolean success Whether toggle was successful
function ProjectileCamera.followProjectile()
    return ProjectileCamera.toggle("follow")
end

-- Activates static camera mode for tracking projectiles
---@return boolean success Whether activation was successful
function ProjectileCamera.trackProjectile()
    return ProjectileCamera.toggle("static")
end

function ProjectileCamera.returnToPreviousMode()
    -- Save the previous camera state and mode before disabling tracking
    local prevMode = STATE.projectileWatching.previousMode
    local prevCamState = STATE.projectileWatching.previousCameraState
    local unitID = STATE.projectileWatching.watchedUnitID

    -- Disable projectile tracking
    TrackingManager.disableTracking()

    -- Return to previous mode with saved state
    if prevMode and prevMode ~= 'projectile_camera' and unitID and Spring.ValidUnitID(unitID) then
        -- Start a proper mode transition
        TrackingManager.startModeTransition(prevMode)

        -- Initialize tracking for the previous mode
        TrackingManager.initializeTracking(prevMode, unitID)

        -- Set the transition state for the mode switch
        if prevCamState then
            -- Store current camera state as the transition start point
            STATE.tracking.transitionStartState = CameraManager.getCameraState("ProjectileCamera.returnToPreviousState")
            -- Set the transition start time to now
            STATE.tracking.transitionStartTime = Spring.GetTimer()
            -- Mark that we're in a mode transition
            STATE.tracking.isModeTransitionInProgress = true
            CameraManager.setCameraState(prevCamState, 0.3, "ProjectileCamera.restoreUnitTrackingPosition")
            Log.trace("Starting smooth transition back to " .. prevMode .. " mode")
        end
        ProjectileCamera.disableProjectileCamera()
    end
end

function ProjectileCamera.disableProjectileCamera()
    STATE.projectileWatching.enabled = false
    STATE.projectileWatching.watchedUnitID = nil
    STATE.projectileWatching.impactTimer = nil
    STATE.projectileWatching.impactPosition = nil
    STATE.projectileWatching.initialCamPos = nil
    STATE.projectileWatching.previousMode = nil
    STATE.projectileWatching.previousCameraState = nil

    -- Clear the selected projectile ID
    if STATE.tracking.projectile then
        STATE.tracking.projectile.selectedProjectileID = nil
        STATE.tracking.projectile.currentProjectileID = nil
    end

    Log.trace("Projectile tracking disabled")
end

-- Get current camera mode
function ProjectileCamera.getCameraMode()
    return STATE.projectileWatching.cameraMode
end

-- This function will be called by UpdateManager in EVERY frame
-- to check for projectiles when watching is enabled
function ProjectileCamera.checkAndActivate()
    -- Check if we're in impact timeout mode
    if STATE.tracking.mode == 'projectile_camera' and STATE.projectileWatching.impactTimer then
        Log.trace("watchedUnitID", STATE.projectileWatching.watchedUnitID)
        -- Check if timeout has elapsed
        local currentTime = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(currentTime, STATE.projectileWatching.impactTimer)

        if elapsed >= STATE.projectileWatching.impactTimeout then
            Log.trace("Impact timeout elapsed, returning to previous mode: " .. tostring(STATE.projectileWatching.previousMode))

            ProjectileCamera.returnToPreviousMode()
            ProjectileCamera.disableProjectileCamera()
        end

        return false
    end

    -- Only proceed if watching is enabled and not already in projectile mode
    if not STATE.projectileWatching.enabled or STATE.tracking.mode == 'projectile_camera' then
        return false
    end

    -- Check if current tracking mode is compatible
    if STATE.tracking.mode then
        local isCompatible = false
        for _, compatMode in ipairs(CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.COMPATIBLE_MODES) do
            if STATE.tracking.mode == compatMode then
                isCompatible = true
                break
            end
        end

        if not isCompatible then
            -- Silently fail - don't activate tracking for incompatible modes
            return false
        end
    end

    -- Check that unit is valid
    local unitID = STATE.projectileWatching.watchedUnitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.trace("Watched unit no longer valid, disabling projectile tracking")
        STATE.projectileWatching.enabled = false
        STATE.projectileWatching.watchedUnitID = nil
        STATE.projectileWatching.impactTimer = nil
        STATE.projectileWatching.impactPosition = nil
        STATE.projectileWatching.initialCamPos = nil
        return false
    end

    -- Check if there are projectiles
    local projectiles = ProjectileTracker.getUnitProjectiles(unitID)
    if #projectiles == 0 then
        -- No projectiles found, continue watching
        return false
    end

    -- Found projectiles, activate camera
    Log.debug("Projectile detected for watched unit " .. unitID .. ", activating camera")

    -- Store previous mode (if not already stored)
    if not STATE.projectileWatching.previousMode then
        STATE.projectileWatching.previousMode = STATE.tracking.mode
    end

    -- Activate projectile camera mode
    if TrackingManager.initializeTracking('projectile_camera', unitID) then
        -- Initialize projectile tracking state
        STATE.tracking.projectile = STATE.tracking.projectile or {}

        -- Important: We don't set selectedProjectileID here
        -- This will be done in the update function when it first runs
        -- to select the oldest projectile
        STATE.tracking.projectile.selectedProjectileID = nil
        STATE.tracking.projectile.currentProjectileID = nil
        STATE.projectileWatching.watchedUnitID = unitID

        Log.debug("Projectile camera activated for unit " .. unitID .. " in " .. STATE.projectileWatching.cameraMode .. " mode")
        return true
    end

    return false
end

-- Updates the projectile camera (only called when in projectile_camera mode)
function ProjectileCamera.update()
    -- Skip if not in projectile camera mode
    if STATE.tracking.mode ~= 'projectile_camera' then
        return
    end

    if Util.isTurboBarCamDisabled() or Util.isModeDisabled("projectile_camera") then
        return
    end

    -- Get unit ID and make sure it's valid
    local unitID = STATE.tracking.unitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.debug("Unit no longer exists, disabling projectile camera")
        TrackingManager.disableTracking()
        STATE.projectileWatching.enabled = false
        STATE.projectileWatching.watchedUnitID = nil
        STATE.projectileWatching.impactTimer = nil
        STATE.projectileWatching.impactPosition = nil
        STATE.projectileWatching.initialCamPos = nil
        return
    end

    -- Make sure we have projectile state initialized
    STATE.tracking.projectile = STATE.tracking.projectile or {}

    -- Initialize smoothed positions if they don't exist
    if not STATE.tracking.projectile.smoothedPositions then
        STATE.tracking.projectile.smoothedPositions = {
            camPos = nil,
            targetPos = nil
        }
    end

    -- Check if we have selected a projectile to track
    if not STATE.tracking.projectile.selectedProjectileID then
        -- We don't have a selected projectile yet, pick the oldest one
        local projectiles = ProjectileTracker.getUnitProjectiles(unitID)
        if #projectiles > 0 then
            -- Sort by creation time (oldest first)
            table.sort(projectiles, function(a, b)
                return a.creationTime < b.creationTime
            end)

            -- Take the oldest one and mark it as our selected projectile
            local selectedProjectile = projectiles[1]
            STATE.tracking.projectile.selectedProjectileID = selectedProjectile.id
            STATE.tracking.projectile.currentProjectileID = selectedProjectile.id
            Log.debug("Selected projectile for tracking: " .. selectedProjectile.id)

            -- Reset smoothed positions when tracking a new projectile
            STATE.tracking.projectile.smoothedPositions = {
                camPos = nil,
                targetPos = nil
            }

            -- Clear any impact timer when we find a new projectile
            STATE.projectileWatching.impactTimer = nil
        end
    end

    -- Get current tracked projectile
    local currentProjectile = nil
    if STATE.tracking.projectile.selectedProjectileID then
        -- Check if our selected projectile still exists
        local projectiles = ProjectileTracker.getUnitProjectiles(unitID)
        for _, proj in ipairs(projectiles) do
            if proj.id == STATE.tracking.projectile.selectedProjectileID then
                currentProjectile = proj
                STATE.tracking.projectile.currentProjectileID = proj.id
                break
            end
        end
    end

    -- If we have a projectile, update the impact position for later use
    if currentProjectile and currentProjectile.lastPosition then
        -- Store the last known position for impact view
        STATE.projectileWatching.impactPosition = {
            pos = currentProjectile.lastPosition,
            vel = currentProjectile.lastVelocity
        }
    end

    -- If our selected projectile no longer exists, start impact timer if not already started
    if (not currentProjectile or not currentProjectile.lastPosition) and STATE.tracking.projectile.selectedProjectileID then
        if not STATE.projectileWatching.impactTimer then
            Log.trace("Selected projectile no longer exists, starting impact timeout timer")
            STATE.projectileWatching.impactTimer = Spring.GetTimer()
        end

        -- If we have a saved impact position, look at it
        if STATE.projectileWatching.impactPosition then
            local impactPos = STATE.projectileWatching.impactPosition.pos
            local impactVel = STATE.projectileWatching.impactPosition.vel

            -- Determine camera position based on camera mode
            local camPos
            if STATE.projectileWatching.cameraMode == "static" and STATE.projectileWatching.initialCamPos then
                -- In static mode, use the stored initial camera position
                camPos = STATE.projectileWatching.initialCamPos
            else
                -- In follow mode, calculate position behind the projectile
                camPos = {
                    x = impactPos.x - (impactVel.x * CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DISTANCE),
                    y = impactPos.y - (impactVel.y * CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DISTANCE) + CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.HEIGHT,
                    z = impactPos.z - (impactVel.z * CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DISTANCE)
                }
            end

            -- Calculate target position (using the impact position)
            local targetPos = {
                x = impactPos.x,
                y = impactPos.y,
                z = impactPos.z
            }

            -- Create camera state
            local directionState = CameraCommons.focusOnPoint(
                    camPos,
                    targetPos,
                    CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING.POSITION_FACTOR,
                    CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING.ROTATION_FACTOR
            )

            -- Apply camera state
            CameraManager.setCameraState(directionState, 0.2, "ProjectileCamera.update.impact")
            TrackingManager.updateTrackingState(directionState)
        else
            -- If no impact position is saved, fall back to looking at the unit
            local ux, uy, uz = Spring.GetUnitPosition(unitID)
            if ux then
                local camState = CameraManager.getCameraState("ProjectileCamera.update")
                local camPos = { x = camState.px, y = camState.py, z = camState.pz }
                local targetPos = { x = ux, y = uy + 50, z = uz }  -- Look slightly above unit

                local directionState = CameraCommons.focusOnPoint(
                        camPos,
                        targetPos,
                        CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING.POSITION_FACTOR,
                        CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING.ROTATION_FACTOR
                )

                CameraManager.setCameraState(directionState, 0.2, "ProjectileCamera.update.unit")
                TrackingManager.updateTrackingState(directionState)
            end
        end
        return
    end

    -- If we don't have a selected projectile and no impact timer, just return
    -- This prevents selecting a new projectile after the initial selection
    if not STATE.tracking.projectile.selectedProjectileID and not STATE.projectileWatching.impactTimer then
        return
    end

    -- If we found a projectile and were in impact timer mode, clear the timer
    if STATE.projectileWatching.impactTimer then
        STATE.projectileWatching.impactTimer = nil
    end

    -- We have a valid projectile to track
    local projectilePos = currentProjectile.lastPosition
    local projectileVel = currentProjectile.lastVelocity

    -- Calculate camera position based on camera mode
    local idealCamPos
    if STATE.projectileWatching.cameraMode == "static" and STATE.projectileWatching.initialCamPos then
        -- In static mode, use the stored initial camera position
        idealCamPos = STATE.projectileWatching.initialCamPos
    else
        -- In follow mode, calculate position behind the projectile
        idealCamPos = {
            x = projectilePos.x - (projectileVel.x * CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DISTANCE),
            y = projectilePos.y - (projectileVel.y * CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DISTANCE) + CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.HEIGHT,
            z = projectilePos.z - (projectileVel.z * CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DISTANCE)
        }
    end

    local idealTargetPos = {
        x = projectilePos.x + (projectileVel.x * CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.LOOK_AHEAD),
        y = projectilePos.y + (projectileVel.y * CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.LOOK_AHEAD),
        z = projectilePos.z + (projectileVel.z * CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.LOOK_AHEAD)
    }

    -- Initialize smoothed positions if they don't exist
    if not STATE.tracking.projectile.smoothedPositions.camPos then
        STATE.tracking.projectile.smoothedPositions.camPos = idealCamPos
    end

    if not STATE.tracking.projectile.smoothedPositions.targetPos then
        STATE.tracking.projectile.smoothedPositions.targetPos = idealTargetPos
    end

    -- Apply position smoothing
    local smoothPos = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING.INTERPOLATION_FACTOR or 0.85

    -- Calculate smooth camera position
    local smoothedCamPos
    if STATE.projectileWatching.cameraMode == "static" and STATE.projectileWatching.initialCamPos then
        -- In static mode, camera position doesn't change
        smoothedCamPos = idealCamPos
    else
        -- In follow mode, smooth the camera movement
        smoothedCamPos = {
            x = CameraCommons.smoothStep(STATE.tracking.projectile.smoothedPositions.camPos.x, idealCamPos.x, smoothPos),
            y = CameraCommons.smoothStep(STATE.tracking.projectile.smoothedPositions.camPos.y, idealCamPos.y, smoothPos),
            z = CameraCommons.smoothStep(STATE.tracking.projectile.smoothedPositions.camPos.z, idealCamPos.z, smoothPos)
        }
    end

    -- Calculate smooth target position
    local smoothedTargetPos = {
        x = CameraCommons.smoothStep(STATE.tracking.projectile.smoothedPositions.targetPos.x, idealTargetPos.x, smoothPos),
        y = CameraCommons.smoothStep(STATE.tracking.projectile.smoothedPositions.targetPos.y, idealTargetPos.y, smoothPos),
        z = CameraCommons.smoothStep(STATE.tracking.projectile.smoothedPositions.targetPos.z, idealTargetPos.z, smoothPos)
    }

    -- Store the smoothed positions for next frame
    STATE.tracking.projectile.smoothedPositions.camPos = smoothedCamPos
    STATE.tracking.projectile.smoothedPositions.targetPos = smoothedTargetPos

    -- Determine smoothing factor based on whether we're in a mode transition
    local posFactor = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING.POSITION_FACTOR
    local rotFactor = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING.ROTATION_FACTOR

    if STATE.tracking.isModeTransitionInProgress then
        -- Use a special transition factor during mode changes
        posFactor = CONFIG.MODE_TRANSITION_SMOOTHING
        rotFactor = CONFIG.MODE_TRANSITION_SMOOTHING

        -- Check if we should end the transition
        if CameraCommons.isTransitionComplete() then
            STATE.tracking.isModeTransitionInProgress = false
        end
    end

    -- Create camera state
    local directionState = CameraCommons.focusOnPoint(smoothedCamPos, smoothedTargetPos, posFactor, rotFactor)

    CameraManager.setCameraState(directionState, 1, "ProjectileCamera.update.tracking")
    TrackingManager.updateTrackingState(directionState)
end

---@see ModifiableParams
---@see Util#adjustParams
function ProjectileCamera.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled('projectile_camera') then
        return
    end

    Util.adjustParams(params, "PROJECTILE_CAMERA", function()
        -- Reset to defaults
        CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DISTANCE = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DEFAULT_DISTANCE
        CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.HEIGHT = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DEFAULT_HEIGHT
        CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.LOOK_AHEAD = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DEFAULT_LOOK_AHEAD
    end)
end

function ProjectileCamera.saveSettings(identifier)
    STATE.tracking.offsets.projectile_camera = STATE.tracking.offsets.projectile_camera or {}
    STATE.tracking.offsets.projectile_camera[identifier] = {
        distance = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DISTANCE,
        height = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.HEIGHT,
        lookAhead = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.LOOK_AHEAD,
        cameraMode = STATE.projectileWatching.cameraMode
    }
end

function ProjectileCamera.loadSettings(identifier)
    STATE.tracking.offsets.projectile_camera = STATE.tracking.offsets.projectile_camera or {}

    if STATE.tracking.offsets.projectile_camera[identifier] then
        local settings = STATE.tracking.offsets.projectile_camera[identifier]
        CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DISTANCE = settings.distance
        CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.HEIGHT = settings.height
        CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.LOOK_AHEAD = settings.lookAhead
        if settings.cameraMode then
            STATE.projectileWatching.cameraMode = settings.cameraMode
        end
        Log.trace("[PROJECTILE_CAMERA] Using previous settings")
    else
        CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DISTANCE = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DEFAULT_DISTANCE
        CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.HEIGHT = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DEFAULT_HEIGHT
        CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.LOOK_AHEAD = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DEFAULT_LOOK_AHEAD
        STATE.projectileWatching.cameraMode = "follow"
        Log.trace("[PROJECTILE_CAMERA] Using default settings")
    end
end

-- For external use - tells if watching mode is active
function ProjectileCamera.isWatchingForProjectiles()
    return STATE.projectileWatching.enabled
end

-- For external use - gets the watched unit ID
function ProjectileCamera.getWatchedUnitID()
    return STATE.projectileWatching.watchedUnitID
end

-- For external use - gets the timeout duration for impact view
function ProjectileCamera.getImpactTimeoutDuration()
    return STATE.projectileWatching.impactTimeout
end

-- For external use - sets the timeout duration for impact view
function ProjectileCamera.setImpactTimeoutDuration(seconds)
    if type(seconds) == "number" and seconds >= 0 then
        STATE.projectileWatching.impactTimeout = seconds
    end
end

return {
    ProjectileCamera = ProjectileCamera
}