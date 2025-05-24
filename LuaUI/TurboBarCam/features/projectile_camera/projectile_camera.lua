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
---@type ProjectileCameraPersistence
local ProjectileCameraPersistence = VFS.Include("LuaUI/TurboBarCam/features/projectile_camera/projectile_camera_persistence.lua").ProjectileCameraPersistence


local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons

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

--- Determines the unit to target for toggling.
---@return number|nil unitID or nil
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

--- Internal toggle logic. Manages continuous arming.
---@param requestedSubMode string "follow" or "static"
---@return boolean success
function ProjectileCamera.toggle(requestedSubMode)
    local unitToWatchForToggle = getUnitToToggle()
    if not unitToWatchForToggle then
        Log.warn("ProjectileCamera: No unit selected or tracked to initiate/toggle projectile watching.")
        return false
    end

    local currentActualMode = STATE.tracking.mode
    local isArmed = STATE.projectileWatching.armed
    local isFollowing = (currentActualMode == 'projectile_camera')
    local currentSubMode = STATE.projectileWatching.cameraMode
    local isContinuous = (STATE.projectileWatching.continuouslyArmedUnitID == unitToWatchForToggle)

    if isFollowing then
        if currentSubMode == requestedSubMode then
            ProjectileCamera.saveSettings(unitToWatchForToggle) -- Save on exit
            STATE.projectileWatching.continuouslyArmedUnitID = nil
            ProjectileCamera.returnToPreviousMode(false)
            return true
        else
            return ProjectileCamera.switchCameraSubModes(requestedSubMode)
        end
    elseif isArmed then
        if currentSubMode == requestedSubMode then
            ProjectileCamera.saveSettings(unitToWatchForToggle) -- Save on exit
            STATE.projectileWatching.continuouslyArmedUnitID = nil
            ProjectileCamera.disableProjectileArming()
            return true
        else
            return ProjectileCamera.switchCameraSubModes(requestedSubMode)
        end
    elseif isContinuous then
        if currentSubMode == requestedSubMode then
            ProjectileCamera.saveSettings(unitToWatchForToggle) -- Save on exit
            STATE.projectileWatching.continuouslyArmedUnitID = nil
            ProjectileCamera.disableProjectileArming()
            return true
        else
            return ProjectileCamera.switchCameraSubModes(requestedSubMode)
        end
    else
        if Util.isTurboBarCamDisabled() then return false end
        if currentActualMode and not Util.tableContains(CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.COMPATIBLE_MODES_FROM, currentActualMode) then return false end

        STATE.projectileWatching.continuouslyArmedUnitID = unitToWatchForToggle
        Log.debug("Projectile tracking: " .. requestedSubMode)
        ProjectileCamera.loadSettings(unitToWatchForToggle) -- Load on entry
        return ProjectileCamera.armProjectileTracking(requestedSubMode, unitToWatchForToggle)
    end
end


--- Arms the system to watch for the next projectile from a unit.
---@param subMode string "follow" or "static"
---@param unitID number The ID of the unit to watch.
---@return boolean success
function ProjectileCamera.armProjectileTracking(subMode, unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.warn("ProjectileCamera: Invalid unitID (" .. tostring(unitID) .. ") for armProjectileTracking.")
        return false
    end

    if not STATE.projectileWatching.armed and STATE.tracking.mode ~= 'projectile_camera' then
        STATE.projectileWatching.previousMode = STATE.tracking.mode
        STATE.projectileWatching.previousCameraState = CameraManager.getCameraState("ProjectileCamera.armProjectileTracking")
    end

    STATE.projectileWatching.cameraMode = subMode

    if subMode == "static" then
        local camState = CameraManager.getCameraState("ProjectileCamera.armProjectileTracking.Static")
        STATE.projectileWatching.initialCamPos = { x = camState.px, y = camState.py, z = camState.pz }
    else
        STATE.projectileWatching.initialCamPos = nil
    end

    STATE.projectileWatching.armed = true
    STATE.projectileWatching.watchedUnitID = unitID
    STATE.projectileWatching.lastArmingTime = Spring.GetGameSeconds()
    STATE.projectileWatching.impactTimer = nil
    STATE.projectileWatching.impactPosition = nil

    if STATE.tracking.projectile then
        STATE.tracking.projectile.selectedProjectileID = nil
        STATE.tracking.projectile.currentProjectileID = nil
    end

    ProjectileTracker.initUnitTracking(unitID)
    return true
end

--- Disarms the *current* cycle of projectile watching. Does not affect continuous state.
function ProjectileCamera.disableProjectileArming()
    STATE.projectileWatching.armed = false
    STATE.projectileWatching.impactTimer = nil
    STATE.projectileWatching.impactPosition = nil

    if STATE.tracking.projectile then
        STATE.tracking.projectile.selectedProjectileID = nil
        STATE.tracking.projectile.currentProjectileID = nil
    end
end

--- Switches sub-modes ("follow" or "static").
---@param newSubMode string The new sub-mode.
---@return boolean success
function ProjectileCamera.switchCameraSubModes(newSubMode)
    STATE.projectileWatching.cameraMode = newSubMode
    if newSubMode == "static" and not STATE.projectileWatching.initialCamPos then
        local camState = CameraManager.getCameraState("ProjectileCamera.switchCameraSubModes")
        STATE.projectileWatching.initialCamPos = { x = camState.px, y = camState.py, z = camState.pz }
    end
    Log.debug("Projectile tracking: " .. newSubMode)
    ProjectileCamera.resetSmoothedPositions()
    return true
end

--- Returns the camera to the previous mode and optionally re-arms.
---@param shouldReArm boolean If true, attempts to re-arm for the continuously tracked unit.
function ProjectileCamera.returnToPreviousMode(shouldReArm)
    local prevMode = STATE.projectileWatching.previousMode
    local prevCamState = STATE.projectileWatching.previousCameraState
    local previouslyWatchedUnitID = STATE.projectileWatching.watchedUnitID
    local unitToReArm = STATE.projectileWatching.continuouslyArmedUnitID

    ProjectileCamera.disableProjectileArming()

    local canReArm = shouldReArm and unitToReArm and Spring.ValidUnitID(unitToReArm)

    if prevMode and prevMode ~= 'projectile_camera' then
        if TrackingManager.startModeTransition(prevMode) then
            local targetForPrevMode = nil
            if Util.isUnitCentricMode(prevMode) and previouslyWatchedUnitID and Spring.ValidUnitID(previouslyWatchedUnitID) then
                targetForPrevMode = previouslyWatchedUnitID
            end
            TrackingManager.initializeTracking(prevMode, targetForPrevMode)
            if prevCamState then
                CameraManager.setCameraState(prevCamState, 0, "ProjectileCamera.restorePreviousCameraState")
            end
        else
            Log.warn("ProjectileCamera: Failed to start transition to previous mode: " .. prevMode .. ". Disabling tracking.")
            TrackingManager.disableTracking()
            canReArm = false
        end
    elseif STATE.tracking.mode == 'projectile_camera' then
        TrackingManager.disableTracking()
    end

    if canReArm then
        ProjectileCamera.loadSettings(unitToReArm) -- Load settings before re-arming
        ProjectileCamera.armProjectileTracking(STATE.projectileWatching.cameraMode, unitToReArm)
    else
        STATE.projectileWatching.continuouslyArmedUnitID = nil
    end
end

--------------------------------------------------------------------------------
-- Update Loop Functions (Called by UpdateManager)
--------------------------------------------------------------------------------

--- Checks if armed and if new projectiles exist to activate 'projectile_camera' mode.
function ProjectileCamera.checkAndActivate()
    if STATE.tracking.mode == 'projectile_camera' and STATE.projectileWatching.impactTimer then
        local currentTime = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(currentTime, STATE.projectileWatching.impactTimer)
        if elapsed >= CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.IMPACT_TIMEOUT then
            local unitID = STATE.projectileWatching.watchedUnitID
            local reArm = (STATE.projectileWatching.continuouslyArmedUnitID == unitID and Spring.ValidUnitID(unitID))
            if unitID and not reArm then ProjectileCamera.saveSettings(unitID) end -- Save before exit if not rearming
            ProjectileCamera.returnToPreviousMode(reArm)
            return true
        end
    end

    if not STATE.projectileWatching.armed or STATE.tracking.mode == 'projectile_camera' then
        return false
    end

    local unitID = STATE.projectileWatching.watchedUnitID
    if not unitID or not Spring.ValidUnitID(unitID) then
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
        if TrackingManager.initializeTracking('projectile_camera', unitID) then
            STATE.tracking.projectile = STATE.tracking.projectile or {}
            STATE.tracking.projectile.selectedProjectileID = nil
            STATE.tracking.projectile.currentProjectileID = nil
            return true
        else
            Log.warn("ProjectileCamera: Failed to initialize tracking for 'projectile_camera'. Reverting.")
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


--- Updates the camera when 'projectile_camera' mode is active.
function ProjectileCamera.update()
    if not ProjectileCamera.shouldUpdate() then
        return
    end

    local unitID = STATE.tracking.unitID
    if not ProjectileCamera.validateUnit(unitID) then
        local reArm = (STATE.projectileWatching.continuouslyArmedUnitID == unitID)
        if unitID and not reArm then ProjectileCamera.saveSettings(unitID) end -- Save before exit
        ProjectileCamera.returnToPreviousMode(reArm)
        return
    end

    if STATE.projectileWatching.impactTimer then
        if STATE.projectileWatching.impactPosition then
            ProjectileCamera.focusOnImpactPosition()
        else
            ProjectileCamera.focusOnUnit(unitID)
        end
        return
    end

    STATE.tracking.projectile = STATE.tracking.projectile or {}
    STATE.tracking.projectile.smoothedPositions = STATE.tracking.projectile.smoothedPositions or { camPos = nil, targetPos = nil }

    if not STATE.tracking.projectile.selectedProjectileID then
        ProjectileCamera.selectProjectile(unitID)
        if not STATE.tracking.projectile.selectedProjectileID then
            ProjectileCamera.handleImpactView(unitID)
            return
        end
    end
    ProjectileCamera.handleProjectileTracking(unitID)
end

--------------------------------------------------------------------------------
-- Internal Update Helpers
--------------------------------------------------------------------------------

function ProjectileCamera.shouldUpdate()
    if STATE.tracking.mode ~= 'projectile_camera' then
        return false
    end
    if Util.isTurboBarCamDisabled() or Util.isModeDisabled('projectile_camera') then
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
    local newProjectiles = {}
    for _, p in ipairs(allProjectiles) do
        if p.creationTime > STATE.projectileWatching.lastArmingTime then
            table.insert(newProjectiles, p)
        end
    end

    if #newProjectiles > 0 then
        table.sort(newProjectiles, function(a, b)
            return a.creationTime < b.creationTime
        end)
        local selectedProjectile = newProjectiles[1]
        STATE.tracking.projectile.selectedProjectileID = selectedProjectile.id
        STATE.tracking.projectile.currentProjectileID = selectedProjectile.id
        ProjectileCamera.resetSmoothedPositions()
        if not STATE.tracking.isModeTransitionInProgress then
            STATE.tracking.isModeTransitionInProgress = true
            STATE.tracking.transitionStartTime = Spring.GetTimer()
        end
        STATE.projectileWatching.impactTimer = nil
    end
end

function ProjectileCamera.handleProjectileTracking(unitID)
    local currentProjectile = ProjectileCamera.getCurrentProjectile(unitID)
    if currentProjectile and currentProjectile.lastPosition then
        STATE.projectileWatching.impactPosition = {
            pos = currentProjectile.lastPosition,
            vel = currentProjectile.lastVelocity
        }
        ProjectileCamera.trackActiveProjectile(currentProjectile)
    else
        ProjectileCamera.handleImpactView(unitID)
    end
end

function ProjectileCamera.getCurrentProjectile(unitID)
    if not STATE.tracking.projectile or not STATE.tracking.projectile.selectedProjectileID then
        return nil
    end
    local projectiles = ProjectileTracker.getUnitProjectiles(unitID)
    for _, proj in ipairs(projectiles) do
        if proj.id == STATE.tracking.projectile.selectedProjectileID then
            STATE.tracking.projectile.currentProjectileID = proj.id
            return proj
        end
    end
    return nil
end

function ProjectileCamera.handleImpactView(unitID)
    if not STATE.projectileWatching.impactTimer then
        STATE.projectileWatching.impactTimer = Spring.GetTimer()
    end
    if STATE.projectileWatching.impactPosition then
        ProjectileCamera.focusOnImpactPosition()
    else
        ProjectileCamera.focusOnUnit(unitID)
    end
end

function ProjectileCamera.focusOnImpactPosition()
    local impactPos = STATE.projectileWatching.impactPosition.pos
    local impactVel = STATE.projectileWatching.impactPosition.vel
    local camPos = ProjectileCamera.calculateCameraPositionForProjectile(impactPos, impactVel, STATE.projectileWatching.cameraMode, STATE.projectileWatching.initialCamPos)
    local targetPos = { x = impactPos.x, y = impactPos.y, z = impactPos.z }
    ProjectileCamera.applyProjectileCameraState(camPos, targetPos, "impact_view")
end

function ProjectileCamera.focusOnUnit(unitID)
    local ux, uy, uz = Spring.GetUnitPosition(unitID)
    if ux then
        local currentCamState = CameraManager.getCameraState("ProjectileCamera.focusOnUnit")
        local camPos = { x = currentCamState.px, y = currentCamState.py, z = currentCamState.pz }
        local targetPos = { x = ux, y = uy + 50, z = uz }
        ProjectileCamera.applyProjectileCameraState(camPos, targetPos, "unit_fallback_view")
    else
        Log.warn("ProjectileCamera: Unit " .. unitID .. " invalid while trying to focus on it.")
        local reArm = (STATE.projectileWatching.continuouslyArmedUnitID == unitID)
        ProjectileCamera.returnToPreviousMode(reArm)
    end
end

function ProjectileCamera.trackActiveProjectile(currentProjectile)
    STATE.projectileWatching.impactTimer = nil
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
    local modeCfg = cfg[string.upper(subMode)]

    if subMode == "static" and staticInitialCamPos then
        return staticInitialCamPos
    else
        local distance = modeCfg.DISTANCE
        local height = modeCfg.HEIGHT

        local dirX, dirY, dirZ = pVel.x, pVel.y, pVel.z
        if pVel.speed and pVel.speed > 0.001 then
            dirX = pVel.x / pVel.speed
            dirY = pVel.y / pVel.speed
            dirZ = pVel.z / pVel.speed
        else -- Fallback if velocity is zero
            dirX, dirY, dirZ = 0, -1, 0
        end

        return {
            x = pPos.x - (dirX * distance),
            y = pPos.y - (dirY * distance) + height,
            z = pPos.z - (dirZ * distance)
        }
    end
end


function ProjectileCamera.calculateIdealTargetPosition(projectilePos, projectileVel)
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA
    local subMode = STATE.projectileWatching.cameraMode
    local modeCfg = cfg[string.upper(subMode)]
    local lookAhead = modeCfg.LOOK_AHEAD

    local dirX, dirY, dirZ = projectileVel.x, projectileVel.y, projectileVel.z
    if projectileVel.speed and projectileVel.speed > 0.001 then
        dirX = projectileVel.x / projectileVel.speed
        dirY = projectileVel.y / projectileVel.speed
        dirZ = projectileVel.z / projectileVel.speed
    else -- Fallback if velocity is zero
        dirX, dirY, dirZ = 0, 0, 1 -- Look slightly 'forward'
    end

    return {
        x = projectilePos.x + (dirX * lookAhead),
        y = projectilePos.y + (dirY * lookAhead),
        z = projectilePos.z + (dirZ * lookAhead)
    }
end


function ProjectileCamera.resetSmoothedPositions()
    if STATE.tracking.projectile and STATE.tracking.projectile.smoothedPositions then
        STATE.tracking.projectile.smoothedPositions.camPos = nil
        STATE.tracking.projectile.smoothedPositions.targetPos = nil
    end
end

function ProjectileCamera.initializeSmoothedPositionsIfNil(idealCamPos, idealTargetPos)
    if not STATE.tracking.projectile then
        STATE.tracking.projectile = {}
    end
    if not STATE.tracking.projectile.smoothedPositions then
        STATE.tracking.projectile.smoothedPositions = {}
    end
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
    local posFactor, rotFactor = ProjectileCamera.getSmoothingFactors()
    local directionState = CameraCommons.focusOnPoint(camPos, targetPos, posFactor, rotFactor)
    if STATE.projectileWatching.cameraMode == "static" then
        local camState = CameraManager.getCameraState("ProjectileCamera.armProjectileTracking.Static")
        STATE.projectileWatching.initialCamPos = { x = camState.px, y = camState.py, z = camState.pz }
    end
    CameraManager.setCameraState(directionState, 0, "ProjectileCamera.update." .. (context or "apply"))
    TrackingManager.updateTrackingState(directionState)
end

function ProjectileCamera.getSmoothingFactors()
    local cfgSmoothing = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING
    local posFactor = cfgSmoothing.POSITION_FACTOR
    local rotFactor = cfgSmoothing.ROTATION_FACTOR
    return CameraCommons.handleModeTransition(posFactor, rotFactor)
end

--------------------------------------------------------------------------------
-- Settings and Parameters
--------------------------------------------------------------------------------

--- Resets projectile camera settings to default values.
function ProjectileCamera.resetToDefaults()
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA
    cfg.FOLLOW.DISTANCE = cfg.DEFAULT_FOLLOW.DISTANCE
    cfg.FOLLOW.HEIGHT = cfg.DEFAULT_FOLLOW.HEIGHT
    cfg.FOLLOW.LOOK_AHEAD = cfg.DEFAULT_FOLLOW.LOOK_AHEAD
    cfg.STATIC.DISTANCE = cfg.DEFAULT_STATIC.DISTANCE -- Though not used by calc, reset for consistency
    cfg.STATIC.HEIGHT = cfg.DEFAULT_STATIC.HEIGHT   -- Though not used by calc, reset for consistency
    cfg.STATIC.LOOK_AHEAD = cfg.DEFAULT_STATIC.LOOK_AHEAD
    Log.trace("ProjectileCamera: Restored settings to defaults.")
end

--- Saves current projectile camera settings for the given unit ID's type.
---@param unitID number The unit ID.
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
            DISTANCE = cfg.STATIC.DISTANCE,
            HEIGHT = cfg.STATIC.HEIGHT,
            LOOK_AHEAD = cfg.STATIC.LOOK_AHEAD,
        }
        -- cameraMode is a runtime state, not saved per unit type here.
        -- It's restored based on last use or default when arming.
    }

    ProjectileCameraPersistence.saveSettings(unitName, settingsToSave)
end

--- Loads projectile camera settings for the given unit ID's type.
---@param unitID number The unit ID.
function ProjectileCamera.loadSettings(unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log.trace("ProjectileCamera: Cannot load settings, invalid unitID.")
        ProjectileCamera.resetToDefaults() -- Reset if unit is invalid
        return
    end

    local unitDef = UnitDefs[Spring.GetUnitDefID(unitID)]
    if not unitDef then
        Log.warn("ProjectileCamera: Cannot load settings, failed to get unitDef.")
        ProjectileCamera.resetToDefaults() -- Reset if no unitdef
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
        cfg.STATIC.DISTANCE = loadedSettings.STATIC and loadedSettings.STATIC.DISTANCE or cfg.DEFAULT_STATIC.DISTANCE
        cfg.STATIC.HEIGHT = loadedSettings.STATIC and loadedSettings.STATIC.HEIGHT or cfg.DEFAULT_STATIC.HEIGHT
        cfg.STATIC.LOOK_AHEAD = loadedSettings.STATIC and loadedSettings.STATIC.LOOK_AHEAD or cfg.DEFAULT_STATIC.LOOK_AHEAD
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

--- Adjusts projectile camera parameters.
---@param params string Parameters to adjust.
function ProjectileCamera.adjustParams(params)
    if Util.isTurboBarCamDisabled() or Util.isModeDisabled('projectile_camera') then
        return
    end

    -- Define the reset function first
    local function resetAndSave()
        ProjectileCamera.resetToDefaults()
        if STATE.tracking.unitID then
            ProjectileCamera.saveSettings(STATE.tracking.unitID)
        end
        Log.info("Projectile Camera settings reset to defaults and saved.")
    end

    -- Determine the current submode (Follow or Static).
    -- Use 'follow' as a fallback if the state isn't set.
    local currentSubmode = STATE.projectileWatching.cameraMode or "follow"
    local currentSubmodeUpper = string.upper(currentSubmode)

    Log.trace("Adjusting Projectile Camera params for submode: " .. currentSubmodeUpper)

    -- Call the generic Util.adjustParams with submode filtering
    Util.adjustParams(params, "PROJECTILE_CAMERA", resetAndSave, currentSubmodeUpper, getProjectileParamPrefixes)

    -- Save settings after adjustment
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