---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CONSTANTS = ModuleManager.CONSTANTS(function(m) CONSTANTS = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "ProjectileCamera")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local MathUtils = ModuleManager.MathUtils(function(m) MathUtils = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local ProjectileTracker = ModuleManager.ProjectileTracker(function(m) ProjectileTracker = m end)
local ProjectileCameraUtils = ModuleManager.ProjectileCameraUtils(function(m) ProjectileCameraUtils = m end)
local CameraDriver = ModuleManager.CameraDriver(function(m) CameraDriver = m end)

---@class ProjectileCamera
local ProjectileCamera = {}

local MIN_PROJECTILE_SPEED_FOR_TURN_DETECT = 1.0
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
function ProjectileCamera.toggle(requestedSubMode)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    local unitToWatchForToggle = STATE.active.mode.unitID
    if not unitToWatchForToggle then
        return false
    end

    local currentActualMode = STATE.active.mode.name
    local isArmed = STATE.active.mode.projectile_camera.armed
    local isFollowingProjectileMode = currentActualMode == 'projectile_camera'
    local currentSubMode = STATE.active.mode.projectile_camera.cameraMode
    local isContinuous = (STATE.active.mode.projectile_camera.continuouslyArmedUnitID == unitToWatchForToggle)
    local isImpactDecelerating = STATE.active.mode.projectile_camera.impactTime ~= nil

    if isFollowingProjectileMode or isImpactDecelerating then
        if currentSubMode == requestedSubMode and not isImpactDecelerating then
            ProjectileCameraUtils.saveSettings(unitToWatchForToggle)
            STATE.active.mode.projectile_camera.continuouslyArmedUnitID = nil
            ProjectileCamera.returnToPreviousMode(false)
            return true
        else
            return ProjectileCamera.switchCameraSubModes(requestedSubMode)
        end
    elseif isArmed then
        if currentSubMode == requestedSubMode then
            ProjectileCameraUtils.saveSettings(unitToWatchForToggle)
            STATE.active.mode.projectile_camera.continuouslyArmedUnitID = nil
            ProjectileCamera.disableProjectileArming()
            return true
        else
            return ProjectileCamera.switchCameraSubModes(requestedSubMode)
        end
    elseif isContinuous then
        if currentSubMode == requestedSubMode then
            ProjectileCameraUtils.saveSettings(unitToWatchForToggle)
            STATE.active.mode.projectile_camera.continuouslyArmedUnitID = nil
            ProjectileCamera.disableProjectileArming()
            return true
        else
            ProjectileCameraUtils.loadSettings(unitToWatchForToggle)
            return ProjectileCamera.armProjectileTracking(requestedSubMode, unitToWatchForToggle)
        end
    else
        if Utils.isTurboBarCamDisabled() then
            return false
        end
        if not currentActualMode or not TableUtils.tableContains(CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.COMPATIBLE_MODES_FROM, currentActualMode) then
            return false
        end

        STATE.active.mode.projectile_camera.continuouslyArmedUnitID = unitToWatchForToggle
        ProjectileCameraUtils.loadSettings(unitToWatchForToggle)
        return ProjectileCamera.armProjectileTracking(requestedSubMode, unitToWatchForToggle)
    end
end

function ProjectileCamera.armProjectileTracking(subMode, unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then
        return false
    end

    if not STATE.active.mode.projectile_camera.armed and STATE.active.mode.name ~= 'projectile_camera' then
        if not STATE.active.mode.projectile_camera.previousCameraState then
            STATE.active.mode.projectile_camera.previousMode = STATE.active.mode.name
            STATE.active.mode.projectile_camera.previousCameraState = Spring.GetCameraState()
        end
    end

    STATE.active.mode.projectile_camera.cameraMode = subMode

    if subMode == "static" then
        local camState = Spring.GetCameraState()
        STATE.active.mode.projectile_camera.initialCamPos = { x = camState.px, y = camState.py, z = camState.pz }
    else
        STATE.active.mode.projectile_camera.initialCamPos = nil
    end

    STATE.active.mode.projectile_camera.armed = true
    STATE.active.mode.projectile_camera.watchedUnitID = unitID
    STATE.active.mode.projectile_camera.lastArmingTime = Spring.GetGameSeconds()
    STATE.active.mode.projectile_camera.impactPosition = nil
    STATE.active.mode.projectile_camera.isHighArc = false
    STATE.active.mode.projectile_camera.currentProjectileID = nil

    ProjectileTracker.initUnitTracking(unitID)
    Log:debug("Projectile tracking enabled in mode = " .. subMode)
    return true
end

function ProjectileCamera.disableProjectileArming()
    STATE.active.mode.projectile_camera.armed = false
    STATE.active.mode.projectile_camera.impactPosition = nil
    STATE.active.mode.projectile_camera.isHighArc = false

    if STATE.active.mode.projectile_camera.projectile then
        STATE.active.mode.projectile_camera.currentProjectileID = nil
    end
    Log:debug("Projectile tracking disabled") -- This was an original log message
end

function ProjectileCamera.switchCameraSubModes(newSubMode)
    STATE.active.mode.projectile_camera.cameraMode = newSubMode
    if newSubMode == "static" and not STATE.active.mode.projectile_camera.initialCamPos then
        if STATE.active.mode.name == 'projectile_camera' or STATE.active.mode.projectile_camera.armed then
            local camState = Spring.GetCameraState()
            STATE.active.mode.projectile_camera.initialCamPos = { x = camState.px, y = camState.py, z = camState.pz }
        end
    end
    Log:debug("Projectile tracking switched to " .. newSubMode)
    return true
end

function ProjectileCamera.returnToPreviousMode(shouldReArm)
    local prevMode = STATE.active.mode.projectile_camera.previousMode
    local prevCamState = STATE.active.mode.projectile_camera.previousCameraState
    local previouslyWatchedUnitID = STATE.active.mode.projectile_camera.watchedUnitID
    local unitToReArmWith = STATE.active.mode.projectile_camera.continuouslyArmedUnitID

    local currentCameraMode = STATE.active.mode.projectile_camera.cameraMode
    local prevCamStateCopy = TableUtils.deepCopy(prevCamState)
    ProjectileCamera.disableProjectileArming()

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

    elseif STATE.active.mode.name == 'projectile_camera' then
        ModeManager.disableMode()
    end

    if not canReArm then
        STATE.active.mode.projectile_camera.continuouslyArmedUnitID = nil
        STATE.active.mode.projectile_camera.previousMode = nil
        STATE.active.mode.projectile_camera.previousCameraState = nil
    else
        ProjectileCameraUtils.loadSettings(unitToReArmWith)
        ProjectileCamera.armProjectileTracking(currentCameraMode, unitToReArmWith)
    end
end

--------------------------------------------------------------------------------
-- Activation and Main Update Loop
--------------------------------------------------------------------------------
function ProjectileCamera.checkAndActivate()
    if STATE.active.mode.name == 'projectile_camera' and STATE.active.mode.projectile_camera.returnToPreviousMode then
        local unitID = STATE.active.mode.projectile_camera.watchedUnitID
        local reArm = (STATE.active.mode.projectile_camera.continuouslyArmedUnitID == unitID and Spring.ValidUnitID(unitID))
        if unitID and not reArm then
            ProjectileCameraUtils.saveSettings(unitID)
        end
        ProjectileCamera.returnToPreviousMode(reArm)
        STATE.active.mode.projectile_camera.returnToPreviousMode = false
        return true
    end

    if not STATE.active.mode.projectile_camera.armed or STATE.active.mode.name == 'projectile_camera' then
        return false
    end

    local unitID = STATE.active.mode.projectile_camera.watchedUnitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        ProjectileCamera.disableProjectileArming()
        STATE.active.mode.projectile_camera.continuouslyArmedUnitID = nil
        return false
    end

    local allProjectiles = ProjectileTracker.getUnitProjectiles(unitID)
    local newProjectiles = {}
    local latestProjectile
    for _, p in ipairs(allProjectiles) do
        if p.creationTime > STATE.active.mode.projectile_camera.lastArmingTime then
            table.insert(newProjectiles, p)
            if not latestProjectile or p.creationTime > latestProjectile.creationTime then
                latestProjectile = p
            end
        end
    end

    if #newProjectiles == 0 then
        return false
    end

    local modeState = TableUtils.deepCopy(STATE.active.mode.projectile_camera)
    if ModeManager.initializeMode('projectile_camera', unitID, CONSTANTS.TARGET_TYPE.UNIT) then
        STATE.active.mode.projectile_camera = modeState
        STATE.active.mode.projectile_camera.armed = false -- Consume armed state
        if latestProjectile and latestProjectile.position then
            STATE.active.mode.projectile_camera.impactPosition = {
                pos = TableUtils.deepCopy(latestProjectile.position),
                vel = TableUtils.deepCopy(latestProjectile.velocity)
            }
        end
        Log:trace("ProjectileCamera: CheckAndActivate - Activated, tracking new projectile from unit", unitID, "(Original log trace)")
        return true
    else
        local reArm = (STATE.active.mode.projectile_camera.continuouslyArmedUnitID == unitID)
        ProjectileCamera.returnToPreviousMode(reArm)
        return false
    end
end

function ProjectileCamera.update(dt)
    if not ProjectileCamera.shouldUpdate() then
        return
    end

    local impactTime = STATE.active.mode.projectile_camera.impactTime
    if impactTime then
        local impactViewDuration = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.IMPACT_VIEW_DURATION
        if Spring.DiffTimers(Spring.GetTimer(), impactTime) >= impactViewDuration then
            STATE.active.mode.projectile_camera.impactTime = nil
            STATE.active.mode.projectile_camera.returnToPreviousMode = true
        end
        return
    end

    local unitID = STATE.active.mode.unitID
    if not ProjectileCamera.validateUnit(unitID) then
        local reArm = (STATE.active.mode.projectile_camera.continuouslyArmedUnitID == unitID)
        if unitID and not reArm then
            ProjectileCameraUtils.saveSettings(unitID)
        end
        ProjectileCamera.returnToPreviousMode(reArm)
        return
    end

    STATE.active.mode.projectile_camera.projectile = STATE.active.mode.projectile_camera.projectile or {}
    STATE.active.mode.projectile_camera.projectile.smoothedPositions = STATE.active.mode.projectile_camera.projectile.smoothedPositions or { camPos = nil, targetPos = nil }

    if not STATE.active.mode.projectile_camera.currentProjectileID then
        ProjectileCamera.selectProjectile(unitID)
        if not STATE.active.mode.projectile_camera.currentProjectileID then
            if not STATE.active.mode.projectile_camera.impactTime then
                STATE.active.mode.projectile_camera.impactTime = Spring.GetTimer()
            end
            return
        end
    end

    ProjectileCamera.handleProjectileTracking(unitID, dt)
end

--------------------------------------------------------------------------------
-- Internal Update Helpers and Projectile Logic
--------------------------------------------------------------------------------
function ProjectileCamera.handleProjectileTracking(unitID, dt)
    ---@type Projectile
    local currentProjectile = ProjectileCamera.getCurrentProjectile(unitID)
    if currentProjectile and currentProjectile.position then
        STATE.active.mode.projectile_camera.impactPosition = {
            pos = TableUtils.deepCopy(currentProjectile.position),
            vel = TableUtils.deepCopy(currentProjectile.velocity)
        }
        ProjectileCamera.updateCameraStateForProjectile(currentProjectile)
    end
end

function ProjectileCamera.getCurrentProjectile(unitID)
    if not STATE.active.mode.projectile_camera.projectile or not STATE.active.mode.projectile_camera.currentProjectileID then
        return nil
    end
    local currentID = STATE.active.mode.projectile_camera.currentProjectileID
    local projectiles = ProjectileTracker.getUnitProjectiles(unitID)
    for _, proj in ipairs(projectiles) do
        if proj.id == currentID then
            return proj
        end
    end
    return nil
end

---@param currentProjectile Projectile
function ProjectileCamera.updateCameraStateForProjectile(currentProjectile)
    local projectilePos = currentProjectile.position
    local projectileVelocity = currentProjectile.velocity
    local camPos = ProjectileCameraUtils.calculateCameraPositionForProjectile(projectilePos, projectileVelocity, STATE.active.mode.projectile_camera.cameraMode, STATE.active.mode.projectile_camera.isHighArc)
    local targetPos = ProjectileCameraUtils.calculateTargetPosition(projectilePos, projectileVelocity)

    local cameraDriverJob = CameraDriver.prepare(CONSTANTS.TARGET_TYPE.POINT, targetPos)
    cameraDriverJob.position = camPos
    cameraDriverJob.positionSmoothing = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.POSITION_SMOOTHING
    cameraDriverJob.rotationSmoothing = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.ROTATION_SMOOTHING
    cameraDriverJob.run()
end

---@param currentProjectile Projectile
function ProjectileCamera.handleHighArcProjectileTurn(currentProjectile)
    local projectileVelocity = currentProjectile.velocity
    local projectilePreviousVelocity = currentProjectile.previousVelocity
    if projectileVelocity.speed < MIN_PROJECTILE_SPEED_FOR_TURN_DETECT or projectilePreviousVelocity.speed < MIN_PROJECTILE_SPEED_FOR_TURN_DETECT then
        return
    end

    local currentDir = { x = projectileVelocity.x, y = projectileVelocity.y, z = projectileVelocity.z }
    local lastDir = { x = projectilePreviousVelocity.x, y = projectilePreviousVelocity.y, z = projectilePreviousVelocity.z }
    local currentDirXZ = { x = currentDir.x, y = 0, z = currentDir.z }
    local lastDirXZ = { x = lastDir.x, y = 0, z = lastDir.z }

    local angle = 0
    local currentMagnitude = MathUtils.vector.magnitude(currentDirXZ)
    local previousMagnitude = MathUtils.vector.magnitude(lastDirXZ)
    if currentMagnitude > 0.01 and previousMagnitude > 0.01 then
        local dot_xz = MathUtils.vector.dot(MathUtils.vector.normalize(currentDirXZ), MathUtils.vector.normalize(lastDirXZ))
        dot_xz = math.max(-1.0, math.min(1.0, dot_xz))
        angle = math.acos(dot_xz)
    end
end

function ProjectileCamera.shouldUpdate()
    if STATE.active.mode.name ~= 'projectile_camera' then
        return false
    end
    if Utils.isTurboBarCamDisabled() then
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
    ---@type Projectile
    local latestValidProjectile
    local maxCreationTime = -1

    for _, p in ipairs(allProjectiles) do
        if p.creationTime > maxCreationTime then
            maxCreationTime = p.creationTime
            latestValidProjectile = p
        end
    end

    local newProjectileSelected = false
    if latestValidProjectile and (STATE.active.mode.projectile_camera.currentProjectileID ~= latestValidProjectile.id) then
        newProjectileSelected = true
    elseif not latestValidProjectile and STATE.active.mode.projectile_camera.currentProjectileID ~= nil then
        newProjectileSelected = true
    end

    if newProjectileSelected then
        STATE.active.mode.projectile_camera.isHighArc = false
        Log:trace("Projectile changed/lost, resetting direction transition state.") -- Original log
    end

    if latestValidProjectile and newProjectileSelected then
        STATE.active.mode.projectile_camera.projectile = STATE.active.mode.projectile_camera.projectile or {}
        STATE.active.mode.projectile_camera.currentProjectileID = latestValidProjectile.id
        Log:trace("ProjectileCamera: Selected projectile " .. latestValidProjectile.id) -- Original log

        local projectileVelocity = latestValidProjectile.velocity
        if projectileVelocity.speed > 0.01 then
            local upComponent = projectileVelocity.y
            if upComponent > HIGH_ARC_THRESHOLD then
                STATE.active.mode.projectile_camera.isHighArc = true
                Log:trace("ProjectileCamera: High Arc detected.") -- Original log
            else
                STATE.active.mode.projectile_camera.isHighArc = false
            end
        else
            STATE.active.mode.projectile_camera.isHighArc = false
        end
    elseif newProjectileSelected then
        STATE.active.mode.projectile_camera.projectile = STATE.active.mode.projectile_camera.projectile or {}
        STATE.active.mode.projectile_camera.currentProjectileID = nil
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