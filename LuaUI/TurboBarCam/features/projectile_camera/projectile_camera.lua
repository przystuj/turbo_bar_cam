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

--- Cycles to the next or previous projectile in the global list.
---@param direction 'forward'|'backward' The direction to cycle in.
---@param mode 'follow'|'static' The camera sub-mode to use for the next projectile.
function ProjectileCamera.cycleNextProjectile(direction, mode)
    if Utils.isTurboBarCamDisabled() then return end
    local allProjectiles = ProjectileTracker.getAllTrackedProjectiles()
    if not allProjectiles or #allProjectiles == 0 then
        Log:info("No active projectiles to cycle through.")
        return
    end

    -- Sort projectiles to ensure a consistent cycling order.
    table.sort(allProjectiles, function(a, b) return a.id < b.id end)

    local currentIndex
    local projCamState = STATE.active.mode.projectile_camera
    if STATE.active.mode.name == 'projectile_camera' and projCamState and projCamState.currentProjectileID then
        for i, p in ipairs(allProjectiles) do
            if p.id == projCamState.currentProjectileID then
                currentIndex = i
                break
            end
        end
    end

    local nextIndex
    local numProjectiles = #allProjectiles

    if not currentIndex then
        -- Not currently tracking or projectile disappeared, start from an edge.
        nextIndex = (direction == 'backward') and numProjectiles or 1
    else
        if direction == 'forward' then
            nextIndex = (currentIndex % numProjectiles) + 1
        else -- 'backward'
            nextIndex = currentIndex - 1
            if nextIndex < 1 then
                nextIndex = numProjectiles -- Wrap around to the end
            end
        end
    end

    local nextProjectile = allProjectiles[nextIndex]
    if nextProjectile then
        ProjectileCamera.startTrackingProjectile(nextProjectile.id, mode or 'follow')
    else
        Log:warn("Failed to find a projectile at the calculated next index.")
    end
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

        -- Determine the anchor unit. Use the currently tracked unit if available to preserve context.
        local anchorUnitID = ownerID
        if STATE.active.mode.unitID and Spring.ValidUnitID(STATE.active.mode.unitID) then
            anchorUnitID = STATE.active.mode.unitID
        end

        if not ModeManager.initializeMode('projectile_camera', anchorUnitID, CONSTANTS.TARGET_TYPE.UNIT) then
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

    -- If toggling the same mode for the same projectile, toggle it off
    if currentProjCamState.currentProjectileID ==  projectileID and currentProjCamState.cameraMode == subMode then
        CameraDriver.stop()
        ProjectileCamera.stopProjectileTracking()
        return
    end

    currentProjCamState.cameraMode = subMode or 'static'
    currentProjCamState.currentProjectileID = projectileID
    currentProjCamState.currentProjectileOwnerID = ownerID -- Track owner explicitly for settings
    currentProjCamState.impactTime = nil -- Reset impact view

    ProjectileCameraUtils.loadSettings(ownerID)
    Log:debug("Started tracking projectile " .. projectileID .. " in mode " .. currentProjCamState.cameraMode)
end


function ProjectileCamera.stopProjectileTracking()
    if Utils.isTurboBarCamDisabled() then return end
    if STATE.active.mode.name ~= 'projectile_camera' then return end

    local currentProjCamState = STATE.active.mode.projectile_camera
    currentProjCamState.cameraMode = nil
    currentProjCamState.currentProjectileID = nil
    ProjectileCamera.returnToPreviousMode(false) -- Explicitly don't re-arm
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
            local unitToSave = projCamState.currentProjectileOwnerID or unitToWatchForToggle
            ProjectileCameraUtils.saveSettings(unitToSave)
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
    projCamState.lastArmingTime = Spring.GetTimer()
    projCamState.currentProjectileID = nil
    ProjectileTracker.initTemporaryUnitTracking(unitID)
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

function ProjectileCamera.toggleProjectileSubMode()
    Log:debug(STATE.active.mode.projectile_camera.cameraMode)
    if STATE.active.mode.name ~= 'projectile_camera' then return end
    local projCamState = STATE.active.mode.projectile_camera
    if projCamState.cameraMode == 'follow' then
        projCamState.cameraMode = 'static'
    else
        projCamState.cameraMode = 'follow'
    end
    Log:info("Projectile camera sub-mode set to: " .. projCamState.cameraMode)
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
        if Spring.DiffTimers(p.creationTime, projCamState.lastArmingTime) > 0 then
            if not latestProjectile or Spring.DiffTimers(p.creationTime, latestProjectile.creationTime) > 0 then
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
        STATE.active.mode.projectile_camera.currentProjectileOwnerID = unitID
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

function ProjectileCamera.handleSelectNewUnit()
    ProjectileCamera.disableProjectileArming()
    ProjectileCamera.stopProjectileTracking()
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
    local projCamState = STATE.active.mode.projectile_camera
    local targetID = unitID
    if projCamState.currentProjectileOwnerID then
        targetID = projCamState.currentProjectileOwnerID
    end
    return ProjectileCameraUtils.saveSettings(targetID)
end

function ProjectileCamera.loadSettings(_, unitID)
    return ProjectileCameraUtils.loadSettings(unitID)
end

STATE.settings.loadModeSettingsFn.projectile_camera = ProjectileCamera.loadSettings
STATE.settings.saveModeSettingsFn.projectile_camera = ProjectileCamera.saveSettings

return ProjectileCamera
