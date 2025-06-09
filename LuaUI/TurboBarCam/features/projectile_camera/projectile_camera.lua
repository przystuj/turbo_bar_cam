---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local VelocityTracker = ModuleManager.VelocityTracker(function(m) VelocityTracker = m end)
local ProjectileTracker = ModuleManager.ProjectileTracker(function(m) ProjectileTracker = m end)
local TransitionUtil = ModuleManager.TransitionUtil(function(m) TransitionUtil = m end)
local ProjectileCameraUtils = ModuleManager.ProjectileCameraUtils(function(m) ProjectileCameraUtils = m end)
local TransitionManager = ModuleManager.TransitionManager(function(m) TransitionManager = m end)
local CameraTracker = ModuleManager.CameraTracker(function(m) CameraTracker = m end)

---@class ProjectileCamera
local ProjectileCamera = {}

local PROJECTILE_CAMERA_TRANSITION_PREFIX = "ProjectileCamera."
local MODE_ENTRY_TRANSITION_ID = PROJECTILE_CAMERA_TRANSITION_PREFIX .. "MODE_ENTRY_TRANSITION_ID"
local HIGH_ARC_DIRECTION_TRANSITION_ID = PROJECTILE_CAMERA_TRANSITION_PREFIX .. "HIGH_ARC_DIRECTION_TRANSITION_ID"
local IMPACT_DECELERATION_TRANSITION_ID = PROJECTILE_CAMERA_TRANSITION_PREFIX .. "IMPACT_DECELERATION_TRANSITION_ID"
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
    local isImpactDecelerating = TransitionManager.isTransitioning(IMPACT_DECELERATION_TRANSITION_ID)

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
    STATE.active.mode.projectile_camera.initialImpactVelocity = nil
    STATE.active.mode.projectile_camera.initialImpactRotVelocity = nil
    STATE.active.mode.projectile_camera.isHighArc = false
    STATE.active.mode.projectile_camera.highArcDirectionChangeCompleted = false

    TransitionManager.cancelPrefix(PROJECTILE_CAMERA_TRANSITION_PREFIX)

    if STATE.active.mode.projectile_camera.projectile then
        STATE.active.mode.projectile_camera.projectile.selectedProjectileID = nil
        STATE.active.mode.projectile_camera.projectile.currentProjectileID = nil
        ProjectileCameraUtils.resetSmoothedPositions()
    end

    ProjectileTracker.initUnitTracking(unitID)
    Log:debug("Projectile tracking enabled in mode = " .. subMode)
    return true
end

function ProjectileCamera.disableProjectileArming()
    STATE.active.mode.projectile_camera.armed = false
    STATE.active.mode.projectile_camera.impactPosition = nil
    STATE.active.mode.projectile_camera.initialImpactVelocity = nil
    STATE.active.mode.projectile_camera.initialImpactRotVelocity = nil
    STATE.active.mode.projectile_camera.isHighArc = false

    TransitionManager.cancelPrefix(HIGH_ARC_DIRECTION_TRANSITION_ID)

    if STATE.active.mode.projectile_camera.projectile then
        STATE.active.mode.projectile_camera.projectile.selectedProjectileID = nil
        STATE.active.mode.projectile_camera.projectile.currentProjectileID = nil
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
    ProjectileCameraUtils.resetSmoothedPositions()
    return true
end

function ProjectileCamera.returnToPreviousMode(shouldReArm)
    local prevMode = STATE.active.mode.projectile_camera.previousMode
    local prevCamState = STATE.active.mode.projectile_camera.previousCameraState
    local previouslyWatchedUnitID = STATE.active.mode.projectile_camera.watchedUnitID
    local unitToReArmWith = STATE.active.mode.projectile_camera.continuouslyArmedUnitID

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
        ProjectileCamera.armProjectileTracking(STATE.active.mode.projectile_camera.cameraMode, unitToReArmWith)
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
    for _, p in ipairs(allProjectiles) do
        if p.creationTime > STATE.active.mode.projectile_camera.lastArmingTime then
            table.insert(newProjectiles, p)
        end
    end

    if #newProjectiles == 0 then
        return false
    end

    local modeState = STATE.active.mode.projectile_camera
    if ModeManager.initializeMode('projectile_camera', unitID, STATE.TARGET_TYPES.UNIT) then
        STATE.active.mode.projectile_camera = modeState
        STATE.active.mode.projectile_camera.armed = false -- Consume armed state
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
    -- mode initialization is handled inside trackActiveProjectile because it has to select projectile first

    local unitID = STATE.active.mode.unitID
    if not ProjectileCamera.validateUnit(unitID) then
        local reArm = (STATE.active.mode.projectile_camera.continuouslyArmedUnitID == unitID)
        if unitID and not reArm then
            ProjectileCameraUtils.saveSettings(unitID)
        end
        ProjectileCamera.returnToPreviousMode(reArm)
        return
    end

    if TransitionManager.isTransitioning(IMPACT_DECELERATION_TRANSITION_ID) then
        return
    end

    STATE.active.mode.projectile_camera.projectile = STATE.active.mode.projectile_camera.projectile or {}
    STATE.active.mode.projectile_camera.projectile.smoothedPositions = STATE.active.mode.projectile_camera.projectile.smoothedPositions or { camPos = nil, targetPos = nil }

    if not STATE.active.mode.projectile_camera.projectile.currentProjectileID then
        ProjectileCamera.selectProjectile(unitID)
        if not STATE.active.mode.projectile_camera.projectile.currentProjectileID then
            ProjectileCamera.handleImpactView()
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
        ProjectileCamera.trackActiveProjectile(currentProjectile)
    else
        ProjectileCamera.handleImpactView()
    end
end

function ProjectileCamera.getCurrentProjectile(unitID)
    if not STATE.active.mode.projectile_camera.projectile or not STATE.active.mode.projectile_camera.projectile.currentProjectileID then
        return nil
    end
    local currentID = STATE.active.mode.projectile_camera.projectile.currentProjectileID
    local projectiles = ProjectileTracker.getUnitProjectiles(unitID)
    for _, proj in ipairs(projectiles) do
        if proj.id == currentID then
            return proj
        end
    end
    return nil
end

---@param currentProjectile Projectile
function ProjectileCamera.trackActiveProjectile(currentProjectile)
    if not STATE.active.mode.projectile_camera.isModeInitialized and not TransitionManager.isTransitioning(MODE_ENTRY_TRANSITION_ID) then
        ProjectileCamera.startModeTransition(currentProjectile)
        return
    end

    if STATE.active.mode.projectile_camera.isHighArc and not TransitionManager.isTransitioning(HIGH_ARC_DIRECTION_TRANSITION_ID) then
        ProjectileCamera.handleHighArcProjectileTurn(currentProjectile)
    end

    if TransitionManager.isTransitioning(MODE_ENTRY_TRANSITION_ID) or TransitionManager.isTransitioning(HIGH_ARC_DIRECTION_TRANSITION_ID) then
        return
    end

    ProjectileCamera.updateCameraStateForProjectile(currentProjectile)
end

function ProjectileCamera.updateCameraStateForProjectile(currentProjectile, posFactorMultiplier, rotFactorMultiplier)
    posFactorMultiplier = posFactorMultiplier or 1
    rotFactorMultiplier = rotFactorMultiplier or 1
    local projectilePos = currentProjectile.position
    local projectileVelocity = currentProjectile.velocity
    local camPos = ProjectileCameraUtils.calculateCameraPositionForProjectile(projectilePos, projectileVelocity, STATE.active.mode.projectile_camera.cameraMode, STATE.active.mode.projectile_camera.isHighArc)
    local targetPos = ProjectileCameraUtils.calculateIdealTargetPosition(projectilePos, projectileVelocity)

    local defaultFactor = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING_FACTOR
    local posFactor = defaultFactor * posFactorMultiplier
    local rotFactor = defaultFactor * rotFactorMultiplier

    local finalState = CameraCommons.focusOnPoint(camPos, targetPos, posFactor, rotFactor)

    CameraTracker.updateLastKnownCameraState(finalState)
    Spring.SetCameraState(finalState, 0)
end

function ProjectileCamera.startModeTransition(currentProjectile)
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA
    local transitionDuration = cfg.ENTRY_TRANSITION_DURATION
    STATE.active.mode.projectile_camera.isModeInitialized = true
    TransitionManager.force({
        id = MODE_ENTRY_TRANSITION_ID,
        duration = transitionDuration,
        respectGameSpeed = true,
        onUpdate = function(progress, _, effectiveDt)
            local rotFactorMultiplier = 1
            if STATE.active.mode.projectile_camera.cameraMode == "follow" then
                rotFactorMultiplier = CameraCommons.lerp(2, 1, CameraCommons.easeIn(progress))
            end
            local posFactorMultiplier = CameraCommons.easeInOut(progress)
            STATE.active.mode.projectile_camera.rampUpFactor = CameraCommons.easeOut(progress)
            ProjectileCamera.updateCameraStateForProjectile(currentProjectile, posFactorMultiplier, rotFactorMultiplier)
        end,
        onComplete = function()
            STATE.active.mode.projectile_camera.rampUpFactor = 1
        end
    })
end

---@param currentProjectile Projectile
function ProjectileCamera.handleHighArcProjectileTurn(currentProjectile)
    local projectileVelocity = currentProjectile.velocity
    local projectilePreviousVelocity = currentProjectile.previousVelocity
    if projectileVelocity.speed < MIN_PROJECTILE_SPEED_FOR_TURN_DETECT or projectilePreviousVelocity.speed < MIN_PROJECTILE_SPEED_FOR_TURN_DETECT then
        return
    end

    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA
    local ROTATION_THRESHOLD = cfg.DIRECTION_TRANSITION_THRESHOLD

    local currentDir = { x = projectileVelocity.x, y = projectileVelocity.y, z = projectileVelocity.z }
    local lastDir = { x = projectilePreviousVelocity.x, y = projectilePreviousVelocity.y, z = projectilePreviousVelocity.z }
    local currentDirXZ = { x = currentDir.x, y = 0, z = currentDir.z }
    local lastDirXZ = { x = lastDir.x, y = 0, z = lastDir.z }

    local angle = 0
    local currentMagnitude = CameraCommons.vectorMagnitude(currentDirXZ)
    local previousMagnitude = CameraCommons.vectorMagnitude(lastDirXZ)
    if currentMagnitude > 0.01 and previousMagnitude > 0.01 then
        local dot_xz = CameraCommons.dotProduct(CameraCommons.normalizeVector(currentDirXZ), CameraCommons.normalizeVector(lastDirXZ))
        dot_xz = math.max(-1.0, math.min(1.0, dot_xz))
        angle = math.acos(dot_xz)
    end

    if angle > ROTATION_THRESHOLD and not STATE.active.mode.projectile_camera.highArcDirectionChangeCompleted then
        TransitionManager.start({
            id = HIGH_ARC_DIRECTION_TRANSITION_ID,
            duration = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DIRECTION_TRANSITION_DURATION,
            easingFn = function(t)
                return CameraCommons.dipAndReturn(t, 0.5)
            end,
            respectGameSpeed = true,
            onUpdate = function(progress, easedProgress)
                ProjectileCamera.updateCameraStateForProjectile(currentProjectile, easedProgress)
            end,
            onComplete = function()
                STATE.active.mode.projectile_camera.highArcDirectionChangeCompleted = true
            end
        })
    end
end

function ProjectileCamera.handleImpactView()
    -- todo handle this somehow if it ever happens
    if not STATE.active.mode.projectile_camera.impactPosition then
        Log:warn("No impact position available!! Please report a bug")
        ModeManager.disableMode()
        return
    end
    if not TransitionManager.isTransitioning(IMPACT_DECELERATION_TRANSITION_ID) then
        ProjectileCamera.decelerateToImpactPosition()
    end
end

function ProjectileCamera.decelerateToImpactPosition()
    local vel, _, rotVel, _ = VelocityTracker.getCurrentVelocity()
    STATE.active.mode.projectile_camera.initialImpactVelocity = TableUtils.deepCopy(vel)
    STATE.active.mode.projectile_camera.initialImpactRotVelocity = TableUtils.deepCopy(rotVel)
    local profile = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.DECELERATION_PROFILE
    TransitionManager.force({
        id = IMPACT_DECELERATION_TRANSITION_ID,
        duration = profile.DURATION,
        easingFn = CameraCommons.easeOut,
        respectGameSpeed = true,
        onUpdate = function(progress, easedProgress, transition_dt)
            local currentCamState = Spring.GetCameraState()

            local initialVelocity = STATE.active.mode.projectile_camera.initialImpactVelocity or { x = 0, y = 0, z = 0 }
            local initialRotVelocity = STATE.active.mode.projectile_camera.initialImpactRotVelocity or { x = 0, y = 0, z = 0 }

            local smoothedState = TransitionUtil.smoothDecelerationTransition(currentCamState, transition_dt, easedProgress, initialVelocity, initialRotVelocity, profile)

            local finalCamState
            if smoothedState then
                finalCamState = smoothedState
            else
                finalCamState = TableUtils.deepCopy(currentCamState)
                TransitionManager.finish(IMPACT_DECELERATION_TRANSITION_ID)
                CameraTracker.updateLastKnownCameraState(finalCamState)
                Spring.SetCameraState(finalCamState, 0)
                return
            end

            -- point camera back towards the impact site
            local impactWorldPos = STATE.active.mode.projectile_camera.impactPosition.pos
            local targetLookPos = ProjectileCameraUtils.calculateIdealTargetPosition(impactWorldPos, STATE.active.mode.projectile_camera.impactPosition.vel or { x = 0, y = 0, z = 0 })

            local focusFromPos = { x = finalCamState.px, y = finalCamState.py, z = finalCamState.pz }
            local smoothFactor = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.SMOOTHING_FACTOR

            local targetDirState = CameraCommons.calculateCameraDirectionToThePoint(focusFromPos, targetLookPos)

            finalCamState.rx = CameraCommons.lerpAngle(finalCamState.rx, targetDirState.rx, smoothFactor / 10)
            finalCamState.ry = CameraCommons.lerpAngle(finalCamState.ry, targetDirState.ry, smoothFactor / 10)

            local finalDir = CameraCommons.getDirectionFromRotation(finalCamState.rx, finalCamState.ry, finalCamState.rz)
            finalCamState.dx = finalDir.x
            finalCamState.dy = finalDir.y
            finalCamState.dz = finalDir.z

            CameraTracker.updateLastKnownCameraState(finalCamState)
            Spring.SetCameraState(finalCamState, 0)
        end,
        onComplete = function()
            STATE.active.mode.projectile_camera.initialImpactVelocity = nil
            STATE.active.mode.projectile_camera.initialImpactRotVelocity = nil
            STATE.active.mode.projectile_camera.returnToPreviousMode = true
        end
    })
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
    if latestValidProjectile and (STATE.active.mode.projectile_camera.projectile.currentProjectileID ~= latestValidProjectile.id) then
        newProjectileSelected = true
    elseif not latestValidProjectile and STATE.active.mode.projectile_camera.projectile.currentProjectileID ~= nil then
        newProjectileSelected = true
    end

    if newProjectileSelected then
        TransitionManager.cancelPrefix(PROJECTILE_CAMERA_TRANSITION_PREFIX)
        STATE.active.mode.projectile_camera.isHighArc = false
        Log:trace("Projectile changed/lost, resetting direction transition state.") -- Original log
    end

    if latestValidProjectile and newProjectileSelected then
        STATE.active.mode.projectile_camera.projectile = STATE.active.mode.projectile_camera.projectile or {}
        STATE.active.mode.projectile_camera.projectile.selectedProjectileID = latestValidProjectile.id
        STATE.active.mode.projectile_camera.projectile.currentProjectileID = latestValidProjectile.id
        ProjectileCameraUtils.resetSmoothedPositions()
        Log:trace("ProjectileCamera: Selected projectile " .. latestValidProjectile.id) -- Original log
        STATE.active.mode.projectile_camera.impactPosition = nil
        STATE.active.mode.projectile_camera.projectile.trackingStartTime = Spring.GetTimer()

        local projectileVelocity = latestValidProjectile.velocity
        if projectileVelocity.speed > 0.01 then
            local upComponent = projectileVelocity.y
            if upComponent > HIGH_ARC_THRESHOLD then
                STATE.active.mode.projectile_camera.isHighArc = true
                STATE.active.mode.projectile_camera.highArcDirectionChangeCompleted = false -- Initialize based on some criteria if needed
                Log:trace("ProjectileCamera: High Arc detected.") -- Original log
            else
                STATE.active.mode.projectile_camera.isHighArc = false
            end
        else
            STATE.active.mode.projectile_camera.isHighArc = false
            STATE.active.mode.projectile_camera.highArcDirectionChangeCompleted = false
        end
    elseif newProjectileSelected then
        STATE.active.mode.projectile_camera.projectile = STATE.active.mode.projectile_camera.projectile or {}
        STATE.active.mode.projectile_camera.projectile.selectedProjectileID = nil
        STATE.active.mode.projectile_camera.projectile.currentProjectileID = nil
        STATE.active.mode.projectile_camera.projectile.trackingStartTime = nil
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