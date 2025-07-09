---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CONSTANTS = ModuleManager.CONSTANTS(function(m) CONSTANTS = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "ProjectileCamera")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local ProjectileTracker = ModuleManager.ProjectileTracker(function(m) ProjectileTracker = m end)
local ProjectileCameraUtils = ModuleManager.ProjectileCameraUtils(function(m) ProjectileCameraUtils = m end)
local CameraDriver = ModuleManager.CameraDriver(function(m) CameraDriver = m end)

---@class ProjectileCamera
local ProjectileCamera = {}

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

--- Starts tracking a specific projectile by its ID.
---@param projectileID number The ID of the projectile to track.
---@param subMode 'follow'|'static' The camera sub-mode to use.
function ProjectileCamera.startTrackingProjectile(projectileID, subMode)
    if Utils.isTurboBarCamDisabled() then return end
    if not projectileID then return end

    local projectile = ProjectileTracker.getProjectileByID(projectileID)
    if not projectile then
        Log:warn("Could not find projectile with ID: " .. tostring(projectileID))
        return
    end

    local ownerID = projectile.ownerID

    -- If not already in projectile camera mode, initialize it
    if STATE.active.mode.name ~= 'projectile_camera' then
        local previousMode = STATE.active.mode.name
        local previousCameraState = Spring.GetCameraState()
        local previousModeState = (previousMode and STATE.active.mode[previousMode]) and TableUtils.deepCopy(STATE.active.mode[previousMode]) or nil

        if not ModeManager.initializeMode('projectile_camera', ownerID, CONSTANTS.TARGET_TYPE.UNIT) then
            Log:error("Failed to initialize projectile camera mode.")
            return
        end

        -- ModeManager resets state, so we need to get the new reference and populate it
        local newProjCamState = STATE.active.mode.projectile_camera
        newProjCamState.previousMode = previousMode
        newProjCamState.previousCameraState = previousCameraState
        newProjCamState.previousModeState = previousModeState
    end

    -- Now that we are definitely in the correct mode, set the target projectile
    local currentProjCamState = STATE.active.mode.projectile_camera
    currentProjCamState.cameraMode = subMode or 'follow' -- Default to follow
    currentProjCamState.currentProjectileID = projectileID
    currentProjCamState.impactTime = nil -- Reset impact view
    STATE.active.mode.unitID = ownerID -- Update the mode's target unit

    ProjectileCameraUtils.loadSettings(ownerID)
    Log:debug("Started tracking projectile " .. projectileID .. " in mode " .. currentProjCamState.cameraMode)
end


function ProjectileCamera.stopProjectileTracking()
    if Utils.isTurboBarCamDisabled() then return end
    if STATE.active.mode.name ~= 'projectile_camera' then return end
    ProjectileCamera.returnToPreviousMode(false) -- Explicitly don't re-arm
end

function ProjectileCamera.toggleProjectileSubMode()
    if STATE.active.mode.name ~= 'projectile_camera' then return end
    local projCamState = STATE.active.mode.projectile_camera
    if projCamState.cameraMode == 'follow' then
        projCamState.cameraMode = 'static'
    else
        projCamState.cameraMode = 'follow'
    end
    Log:info("Projectile camera sub-mode set to: " .. projCamState.cameraMode)
end

--------------------------------------------------------------------------------
-- Core Toggling and State Management
--------------------------------------------------------------------------------

-- Handles the "select and arm" workflow
function ProjectileCamera.toggle(requestedSubMode)
    if Utils.isTurboBarCamDisabled() then return end

    local unitToWatchForToggle = Spring.GetSelectedUnits()[1] or STATE.active.mode.unitID
    if not unitToWatchForToggle then
        return false
    end

    local projCamState = STATE.active.mode.projectile_camera
    local isFollowingProjectileMode = STATE.active.mode.name == 'projectile_camera'
    local isImpactDecelerating = projCamState.impactTime ~= nil

    if isFollowingProjectileMode or isImpactDecelerating then
        if projCamState.cameraMode == requestedSubMode and not isImpactDecelerating then
            ProjectileCameraUtils.saveSettings(unitToWatchForToggle)
            projCamState.continuouslyArmedUnitID = nil
            ProjectileCamera.returnToPreviousMode(false)
            return true
        else
            return ProjectileCamera.switchCameraSubModes(requestedSubMode)
        end
    elseif projCamState.isArmed then
        if projCamState.cameraMode == requestedSubMode then
            ProjectileCameraUtils.saveSettings(unitToWatchForToggle)
            projCamState.continuouslyArmedUnitID = nil
            ProjectileCamera.disableProjectileArming()
            return true
        else
            return ProjectileCamera.switchCameraSubModes(requestedSubMode)
        end
    elseif projCamState.continuouslyArmedUnitID == unitToWatchForToggle then
        -- Handle re-arming a continuously armed unit with a different submode
        ProjectileCameraUtils.loadSettings(unitToWatchForToggle)
        return ProjectileCamera.armProjectileTracking(requestedSubMode, unitToWatchForToggle)
    else
        if not TableUtils.tableContains(CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.COMPATIBLE_MODES_FROM, STATE.active.mode.name) then
            return false
        end
        projCamState.continuouslyArmedUnitID = unitToWatchForToggle
        ProjectileCameraUtils.loadSettings(unitToWatchForToggle)
        return ProjectileCamera.armProjectileTracking(requestedSubMode, unitToWatchForToggle)
    end
end

function ProjectileCamera.armProjectileTracking(subMode, unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then return false end
    local projCamState = STATE.active.mode.projectile_camera

    if not projCamState.isArmed and STATE.active.mode.name ~= 'projectile_camera' then
        if not projCamState.previousCameraState then
            projCamState.previousMode = STATE.active.mode.name
            projCamState.previousCameraState = Spring.GetCameraState()
            projCamState.previousModeState = STATE.active.mode[STATE.active.mode.name] and TableUtils.deepCopy(STATE.active.mode[STATE.active.mode.name]) or nil
        end
    end

    projCamState.cameraMode = subMode
    projCamState.isArmed = true
    projCamState.watchedUnitID = unitID
    projCamState.lastArmingTime = Spring.GetGameSeconds()
    projCamState.currentProjectileID = nil
    ProjectileTracker.initUnitTracking(unitID)
    Log:debug("Projectile tracking ARMED for unit " .. unitID .. " in mode = " .. subMode)
    return true
end

function ProjectileCamera.disableProjectileArming()
    local projCamState = STATE.active.mode.projectile_camera
    projCamState.isArmed = false
    projCamState.watchedUnitID = nil
    Log:debug("Projectile tracking DISARMED")
end

function ProjectileCamera.switchCameraSubModes(newSubMode)
    STATE.active.mode.projectile_camera.cameraMode = newSubMode
    Log:debug("Projectile tracking switched to " .. newSubMode)
    return true
end

function ProjectileCamera.returnToPreviousMode(shouldReArm)
    local projCamState = STATE.active.mode.projectile_camera
    if not projCamState then return end

    local prevMode = projCamState.previousMode
    local prevCamState = projCamState.previousCameraState
    local prevModeState = projCamState.previousModeState
    local unitToReArmWith = projCamState.continuouslyArmedUnitID

    ProjectileCamera.disableProjectileArming()

    local canReArm = shouldReArm and unitToReArmWith and Spring.ValidUnitID(unitToReArmWith)

    if prevMode and prevMode ~= 'projectile_camera' and prevModeState then
        local targetID = prevModeState.unitID
        STATE.active.mode[prevMode] = prevModeState
        ModeManager.initializeMode(prevMode, targetID, nil, true, TableUtils.deepCopy(prevCamState))
    else
        ModeManager.disableMode()
    end

    -- After returning, check if we need to re-arm for continuous tracking
    if canReArm then
        ProjectileCameraUtils.loadSettings(unitToReArmWith)
        ProjectileCamera.armProjectileTracking(projCamState.cameraMode, unitToReArmWith)
    else
        projCamState.continuouslyArmedUnitID = nil
    end
end

--------------------------------------------------------------------------------
-- Activation and Main Update Loop
--------------------------------------------------------------------------------

-- This function activates tracking for the "select and arm" workflow.
function ProjectileCamera.checkAndActivate()
    local projCamState = STATE.active.mode.projectile_camera
    if not projCamState.isArmed or STATE.active.mode.name == 'projectile_camera' then
        return false
    end

    local unitID = projCamState.watchedUnitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        ProjectileCamera.disableProjectileArming()
        projCamState.continuouslyArmedUnitID = nil
        return false
    end

    local allProjectiles = ProjectileTracker.getUnitProjectiles(unitID)
    local latestProjectile
    for _, p in ipairs(allProjectiles) do
        if p.creationTime > projCamState.lastArmingTime then
            if not latestProjectile or p.creationTime > latestProjectile.creationTime then
                latestProjectile = p
            end
        end
    end

    if not latestProjectile then return false end

    local modeState = TableUtils.deepCopy(projCamState)
    if ModeManager.initializeMode('projectile_camera', unitID, CONSTANTS.TARGET_TYPE.UNIT) then
        -- Restore the state for projectile camera mode
        STATE.active.mode.projectile_camera = modeState
        STATE.active.mode.projectile_camera.isArmed = false -- Consume armed state
        STATE.active.mode.projectile_camera.currentProjectileID = latestProjectile.id
        Log:debug("Activated projectile camera via arm, tracking projectile " .. latestProjectile.id)
        return true
    else
        local reArm = (projCamState.continuouslyArmedUnitID == unitID)
        ProjectileCamera.returnToPreviousMode(reArm)
        return false
    end
end

function ProjectileCamera.update(dt)
    if STATE.active.mode.name ~= 'projectile_camera' or Utils.isTurboBarCamDisabled() then return end

    local projCamState = STATE.active.mode.projectile_camera

    if projCamState.impactTime then
        if Spring.DiffTimers(Spring.GetTimer(), projCamState.impactTime) >= CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.IMPACT_VIEW_DURATION then
            projCamState.impactTime = nil
            local reArm = projCamState.continuouslyArmedUnitID and Spring.ValidUnitID(projCamState.continuouslyArmedUnitID)
            ProjectileCamera.returnToPreviousMode(reArm)
        end
        return
    end

    if not projCamState.currentProjectileID then return end

    local currentProjectile = ProjectileTracker.getProjectileByID(projCamState.currentProjectileID)

    if currentProjectile then
        projCamState.impactPosition = { pos = TableUtils.deepCopy(currentProjectile.position), vel = TableUtils.deepCopy(currentProjectile.velocity) }
        ProjectileCamera.handleProjectileTracking(currentProjectile)
    else
        projCamState.currentProjectileID = nil
        if projCamState.impactPosition then
            projCamState.impactTime = Spring.GetTimer()
            local cameraDriverJob = CameraDriver.prepare(CONSTANTS.TARGET_TYPE.POINT, projCamState.impactPosition.pos)
            cameraDriverJob.decelerationProfile = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DECELERATION_PROFILE
            cameraDriverJob.run()
        else
            local reArm = projCamState.continuouslyArmedUnitID and Spring.ValidUnitID(projCamState.continuouslyArmedUnitID)
            ProjectileCamera.returnToPreviousMode(reArm)
        end
    end
end

--------------------------------------------------------------------------------
-- Internal Update Helpers
--------------------------------------------------------------------------------

function ProjectileCamera.handleProjectileTracking(currentProjectile)
    if currentProjectile and currentProjectile.position then
        ProjectileCamera.updateProjectileState(currentProjectile)
        ProjectileCamera.updateCameraStateForProjectile(currentProjectile)
    end
end

function ProjectileCamera.updateCameraStateForProjectile(currentProjectile)
    local projectilePos = currentProjectile.position
    local projectileVelocity = currentProjectile.velocity
    local camPos = ProjectileCameraUtils.calculateCameraPositionForProjectile(projectilePos, projectileVelocity, STATE.active.mode.projectile_camera.cameraMode)
    local targetPos = ProjectileCameraUtils.calculateTargetPosition(projectilePos, projectileVelocity)

    local cameraDriverJob = CameraDriver.prepare(CONSTANTS.TARGET_TYPE.POINT, targetPos)
    cameraDriverJob.position = camPos
    cameraDriverJob.positionSmoothing = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.POSITION_SMOOTHING
    cameraDriverJob.rotationSmoothing = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.ROTATION_SMOOTHING
    cameraDriverJob.run()
end

function ProjectileCamera.updateProjectileState(projectile)
    local projCamState = STATE.active.mode.projectile_camera
    local projectileVelocity = projectile.velocity
    if projectileVelocity.speed > 0.01 then
        projCamState.isHighArc = projectileVelocity.y > HIGH_ARC_THRESHOLD
    else
        projCamState.isHighArc = false
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

function ProjectileCamera.saveSettings(_, unitID)
    return ProjectileCameraUtils.saveSettings(unitID)
end

function ProjectileCamera.loadSettings(_, unitID)
    return ProjectileCameraUtils.loadSettings(unitID)
end

STATE.settings.loadModeSettingsFn.projectile_camera = ProjectileCamera.loadSettings
STATE.settings.saveModeSettingsFn.projectile_camera = ProjectileCamera.saveSettings

return ProjectileCamera
