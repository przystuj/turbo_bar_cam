---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CONSTANTS = ModuleManager.CONSTANTS(function(m) CONSTANTS = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "UnitFollowCamera")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local WorldUtils = ModuleManager.WorldUtils(function(m) WorldUtils = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local CameraDriver = ModuleManager.CameraDriver(function(m) CameraDriver = m end)
local UnitFollowUtils = ModuleManager.UnitFollowUtils(function(m) UnitFollowUtils = m end)
local UnitFollowCombatMode = ModuleManager.UnitFollowCombatMode(function(m) UnitFollowCombatMode = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local ProjectileTracker = ModuleManager.ProjectileTracker(function(m) ProjectileTracker = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)

local prevActiveCmd

---@class UnitFollowCamera
local UnitFollowCamera = {}

UnitFollowCamera.COMMAND_DEFINITION = {
    id = CONFIG.COMMANDS.SET_FIXED_LOOK_POINT,
    type = CMDTYPE.ICON_UNIT_OR_MAP,
    name = 'Set Fixed Look Point',
    tooltip = 'Click on a location to focus camera on while following unit',
    cursor = 'settarget',
    action = 'turbobarcam_unit_follow_set_fixed_look_point',
}

local function disableMode()
    ModeManager.disableAndStopDriver()
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits > 0 then
        Spring.SelectUnitArray(selectedUnits)
    end
end

--- Toggles Unit Follow camera attached to a unit
function UnitFollowCamera.toggle(unitID, mode)
    if Utils.isTurboBarCamDisabled() then
        return
    end

    local previousUnitID = STATE.active.mode.unitID
    if not previousUnitID and STATE.core.selection.lastUnitID then
        local lastSelection = STATE.core.selection
        if lastSelection.lastUpdateTime and Spring.DiffTimers(Spring.GetTimer(), lastSelection.lastUpdateTime) < CONFIG.CAMERA_MODES.UNIT_FOLLOW.GRACE_PERIOD then
            previousUnitID = lastSelection.lastUnitID
        end
    end

    if not unitID then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            unitID = selectedUnits[1]
        else
            Log:debug("No unit selected for unit_follow view")
            disableMode()
            return
        end
    end

    if not Spring.ValidUnitID(unitID) then
        Log:trace("Invalid unit ID for unit_follow view: " .. tostring(unitID))
        disableMode()
        return
    end

    if STATE.active.mode.name == 'unit_follow' and STATE.active.mode.unitID == unitID and not STATE.active.mode.optionalTargetCameraStateForModeEntry then
        disableMode()
        return
    end

    if ModeManager.initializeMode('unit_follow', unitID, CONSTANTS.TARGET_TYPE.UNIT) then
        UnitFollowCamera.handleSelectNewUnit(unitID, previousUnitID)
        if mode == "combat" then
            UnitFollowCombatMode.setCombatMode(true)
        end
    end
end

--- Updates the unit_follow camera position and orientation
function UnitFollowCamera.update()
    if not UnitFollowUtils.shouldUpdateCamera() then
        CameraDriver.stop()
        return
    end

    local unitID = STATE.active.mode.unitID
    local cameraPosition
    local target, targetType

    if Spring.ValidUnitID(unitID) then
        local unitX, unitY, unitZ, front, up, right = WorldUtils.getUnitVectors(unitID)
        cameraPosition = UnitFollowUtils.applyOffsets(unitX, unitY, unitZ, front, up, right)
        target, targetType = UnitFollowCamera.getCameraDirection()
    else
        -- Unit died: use last known position/orientation for up to 5s
        local sel = STATE.core.selection
        local now = Spring.GetTimer()
        if sel.lastUpdateTime and Spring.DiffTimers(now, sel.lastUpdateTime) < CONFIG.CAMERA_MODES.UNIT_FOLLOW.GRACE_PERIOD and sel.lastUnitPosition.x then
            local lx, ly, lz = sel.lastUnitPosition.x, sel.lastUnitPosition.y, sel.lastUnitPosition.z
            local front = sel.lastUnitFront or { 0, 0, 1 }
            local up = sel.lastUnitUp or { 0, 1, 0 }
            local right = sel.lastUnitRight or { 1, 0, 0 }
            cameraPosition = UnitFollowUtils.applyOffsets(lx, ly, lz, front, up, right)
            target, targetType = { x = lx, y = ly, z = lz }, CONSTANTS.TARGET_TYPE.POINT
        else
            CameraDriver.stop()
            return
        end
    end

    local rotSmoothingOverride, posSmoothingOverride
    cameraPosition, target, targetType, rotSmoothingOverride, posSmoothingOverride = UnitFollowCamera.applyTransition(cameraPosition, target, targetType)

    local cameraDriverJob = CameraDriver.prepare(targetType, target)
    cameraDriverJob.position = cameraPosition
    cameraDriverJob.positionSmoothing = posSmoothingOverride or UnitFollowUtils.getSmoothingFactor('position')
    cameraDriverJob.rotationSmoothing = rotSmoothingOverride or UnitFollowUtils.getSmoothingFactor('rotation')
    cameraDriverJob.forceSmoothing = (posSmoothingOverride ~= nil or rotSmoothingOverride ~= nil)
    cameraDriverJob.run()
end

function UnitFollowCamera.applyTransition(cameraPosition, target, targetType)
    if not CONFIG.CAMERA_MODES.UNIT_FOLLOW.UNIT_TRANSITION_ENABLED then
        return cameraPosition, target, targetType
    end

    local unitFollowState = STATE.active.mode.unit_follow
    local initialDist2D = unitFollowState.initialDist2D or 0
    local transitionStartTime = unitFollowState.unitTransitionStartTime
    local minimalDistanceForHeightChange = 1700


    local bonusHeight = math.max(0, initialDist2D - minimalDistanceForHeightChange)

    if not transitionStartTime then
        return cameraPosition, target, targetType
    end

    local elapsed = Spring.DiffTimers(Spring.GetTimer(), transitionStartTime)
    local duration = CONFIG.CAMERA_MODES.UNIT_FOLLOW.INITIAL_TRANSITION_DURATION
    local progress = elapsed / duration

    if progress >= 1 or progress < 0 then
        unitFollowState.initialDist2D = 0
        unitFollowState.unitTransitionStartTime = nil
        unitFollowState.previousUnitID = nil
        unitFollowState.previousUnitPosition = nil
        return cameraPosition, target, targetType
    end

    -- Look at unit selection thresholds
    local secondPartStart = 0.2
    local thirdPartStart = 0.4 -- 40% of transition: switch from looking at previous to next unit
    local forthPartStart = 0.9 -- 90% of transition: switch to final follow orientation

    if progress > secondPartStart then
        bonusHeight = 0
    end

    -- 1. Apply height bonus
    if bonusHeight > 0 then
        cameraPosition = { x = cameraPosition.x, y = cameraPosition.y + bonusHeight, z = cameraPosition.z }
    end

    -- skip lookAt transition if distance is low
    if initialDist2D < 2000 then
        return cameraPosition, target, targetType
    end

    -- 2. Apply look-at override
    local usePreviousUnitLookAt = false
    if progress < thirdPartStart and initialDist2D > 4000 then
        local ux, uy, uz = Spring.GetUnitPosition(STATE.active.mode.unitID)
        if ux then
            local camX, camY, camZ = Spring.GetCameraPosition()
            local _, camRy = Spring.GetCameraRotation()

            -- Direction from camera to new unit
            local dx, dz = ux - camX, uz - camZ
            local angleToUnit = math.atan2(dx, -dz)
            local angleDiff = math.abs(CameraCommons.getAngleDiff(camRy, angleToUnit))

            -- 80 degree cone behind: angleDiff > 140 degrees (7/9 * pi)
            -- To make the cone bigger, decrease the angle threshold (e.g., 2/3 * pi for 120-degree cone)
            -- To make it smaller, increase it (e.g., 8/9 * pi for 20-degree cone)
            if angleDiff > (7 / 9) * math.pi then
                usePreviousUnitLookAt = true
            end
        end
    end

    local targetOverridden = false
    if usePreviousUnitLookAt then
        local prevPos = unitFollowState.previousUnitPosition
        if prevPos then
            TableUtils.syncTable(target, prevPos)
            targetType = CONSTANTS.TARGET_TYPE.POINT
            targetOverridden = true
        elseif unitFollowState.previousUnitID and Spring.ValidUnitID(unitFollowState.previousUnitID) then
            local pux, puy, puz = Spring.GetUnitPosition(unitFollowState.previousUnitID)
            if pux then
                target.x, target.y, target.z = pux, puy, puz
                targetType = CONSTANTS.TARGET_TYPE.POINT
                targetOverridden = true
            end
        end
    end

    if not targetOverridden and progress < forthPartStart then
        -- Look at next unit
        local ux, uy, uz = Spring.GetUnitPosition(STATE.active.mode.unitID)
        if ux then
            target.x, target.y, target.z = ux, uy, uz
            targetType = CONSTANTS.TARGET_TYPE.POINT
        end
    end

    -- 3. Calculate rotation smoothing
    local rotationSmoothing, positionSmoothing

    if progress > forthPartStart then
        rotationSmoothing = 1 -- prepare to look at the target
        positionSmoothing = 2
    elseif progress > thirdPartStart then
        rotationSmoothing = 0.5 -- look at next unit
        positionSmoothing = 1
    elseif progress > secondPartStart then
        rotationSmoothing = 1.0  -- turn towards next unit
        positionSmoothing = 3
    else
        rotationSmoothing = targetOverridden and 0.5 or 2 -- initial look at unit
        positionSmoothing = 3
    end

    return cameraPosition, target, targetType, rotationSmoothing, positionSmoothing
end

local function getFixedTargetPosition()
    local fixedTarget = STATE.active.mode.unit_follow.fixedTarget
    local fixedTargetType = STATE.active.mode.unit_follow.fixedTargetType

    if fixedTargetType == CONSTANTS.TARGET_TYPE.POINT then
        return fixedTarget, fixedTargetType
    end

    local lastFixedTargetPosition = STATE.active.mode.unit_follow.lastFixedTargetPosition
    local x, y, z

    if fixedTargetType == CONSTANTS.TARGET_TYPE.UNIT then
        x, y, z = Spring.GetUnitPosition(fixedTarget)
    elseif fixedTargetType == CONSTANTS.TARGET_TYPE.PROJECTILE then
        x, y, z = Spring.GetProjectilePosition(fixedTarget)
    end

    if x then
        lastFixedTargetPosition.x = x
        lastFixedTargetPosition.y = y
        lastFixedTargetPosition.z = z
    else
        -- look at the last known position if unit/projectile is gone
        STATE.active.mode.unit_follow.fixedTarget = lastFixedTargetPosition
        STATE.active.mode.unit_follow.fixedTargetType = CONSTANTS.TARGET_TYPE.POINT
    end

    return fixedTarget, fixedTargetType
end

function UnitFollowCamera.getCameraDirection()
    if STATE.active.mode.unit_follow.isFixedPointActive then
        return getFixedTargetPosition()
    else
        return UnitFollowUtils.handleNormalFollowMode(STATE.active.mode.unitID)
    end
end

function UnitFollowCamera.checkFixedPointCommandActivation()
    if Utils.isTurboBarCamDisabled() then
        return
    end

    local _, activeCmd = Spring.GetActiveCommand()

    if activeCmd ~= prevActiveCmd then
        if activeCmd == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT then
            if STATE.active.mode.name == 'unit_follow' and STATE.active.mode.unitID then
                STATE.active.mode.unit_follow.inTargetSelectionMode = true
                STATE.active.mode.unit_follow.prevFixedTarget = STATE.active.mode.unit_follow.fixedTarget
                STATE.active.mode.unit_follow.prevFixedPointActive = STATE.active.mode.unit_follow.isFixedPointActive

                if STATE.active.mode.unit_follow.isFixedPointActive then
                    STATE.active.mode.unit_follow.isFixedPointActive = false
                end
            end
        elseif prevActiveCmd == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT and STATE.active.mode.unit_follow.inTargetSelectionMode then
            STATE.active.mode.unit_follow.inTargetSelectionMode = false
            if STATE.active.mode.unit_follow.prevFixedPointActive and STATE.active.mode.unit_follow.prevFixedTarget then
                STATE.active.mode.unit_follow.isFixedPointActive = true
                STATE.active.mode.unit_follow.fixedTarget = STATE.active.mode.unit_follow.prevFixedTarget
            end
        end
    end
    prevActiveCmd = activeCmd
end

function UnitFollowCamera.setFixedLookPoint(targetType, cmdParams)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled("unit_follow") then
        return
    end
    if not STATE.active.mode.unitID then
        Log:debug("No unit being tracked for fixed point camera")
        return false
    end

    local x, y, z
    STATE.active.mode.unit_follow.fixedTarget = nil
    STATE.active.mode.unit_follow.fixedTargetType = targetType

    if targetType == CONSTANTS.TARGET_TYPE.UNIT then
        local unitID = tonumber(cmdParams[1])
        if Spring.ValidUnitID(unitID) then
            STATE.active.mode.unit_follow.fixedTarget = unitID
            x, y, z = Spring.GetUnitPosition(unitID)
        end
    elseif targetType == CONSTANTS.TARGET_TYPE.PROJECTILE then
        local projectileID = cmdParams[1]
        local projectile = ProjectileTracker.getProjectileByID(projectileID)
        if projectile then
            x, y, z = projectile.position.x, projectile.position.y, projectile.position.z
            STATE.active.mode.unit_follow.fixedTarget = projectileID
        end
    elseif targetType == CONSTANTS.TARGET_TYPE.POINT then
        x, y, z = cmdParams[1], cmdParams[2], cmdParams[3]
        STATE.active.mode.unit_follow.fixedTarget = { x = x, y = y, z = z }
    end

    if not x or not y or not z then
        return false
    end

    STATE.active.mode.unit_follow.isFixedPointActive = true
    STATE.active.mode.unit_follow.inTargetSelectionMode = false
    STATE.active.mode.unit_follow.prevFixedTarget = nil
end

function UnitFollowCamera.clearFixedLookPoint()
    UnitFollowUtils.clearFixedLookPoint()
end

function UnitFollowCamera.nextWeapon()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled('unit_follow') then
        return
    end
    if not STATE.active.mode.unitID or not Spring.ValidUnitID(STATE.active.mode.unitID) then
        Log:debug("No unit selected.")
        return
    end
    UnitFollowCombatMode.nextWeapon()
end

function UnitFollowCamera.resetAttackState(delay)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled('unit_follow') then
        return
    end
    if not STATE.active.mode.unitID or not Spring.ValidUnitID(STATE.active.mode.unitID) then
        Log:debug("No unit selected.")
        return
    end
    UnitFollowCombatMode.resetAttackState(delay)
end

function UnitFollowCamera.clearWeaponSelection()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled('unit_follow') then
        return
    end
    UnitFollowCombatMode.clearWeaponSelection()
end

function UnitFollowCamera.adjustParams(params, isTemporary)
    UnitFollowUtils.adjustParams(params, isTemporary)
end

function UnitFollowCamera.toggleCombatMode()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled('unit_follow') then
        return
    end
    UnitFollowCombatMode.toggleCombatMode()
end

function UnitFollowCamera.handleSelectNewUnit(unitID, previousUnitIDOverride)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled('unit_follow') then
        return
    end

    local unitFollowState = STATE.active.mode.unit_follow
    local previousUnitID = previousUnitIDOverride or STATE.active.mode.unitID

    -- Compute 2D distance between previous and next unit positions (ignore height)
    local prevUx, prevUy, prevUz = nil, nil, nil
    local lastSelectionState = STATE.core.selection
    local now = Spring.GetTimer()

    if previousUnitID and Spring.ValidUnitID(previousUnitID) then
        prevUx, prevUy, prevUz = Spring.GetUnitPosition(previousUnitID)
    elseif lastSelectionState.lastUnitID == previousUnitID and lastSelectionState.lastUpdateTime then
        local elapsed = Spring.DiffTimers(now, lastSelectionState.lastUpdateTime)
        if elapsed < CONFIG.CAMERA_MODES.UNIT_FOLLOW.GRACE_PERIOD then
            prevUx = lastSelectionState.lastUnitPosition.x
            prevUy = lastSelectionState.lastUnitPosition.y
            prevUz = lastSelectionState.lastUnitPosition.z
        end
    end

    local nextUx, nextUy, nextUz = Spring.GetUnitPosition(unitID)

    local dist2D = 0
    if prevUx and nextUx then
        local dx = (nextUx - prevUx)
        local dz = (nextUz - prevUz)
        dist2D = math.sqrt(dx * dx + dz * dz)
    else
        -- Fallback to camera-to-next 2D distance if previous unit position is unavailable
        local unitX, unitY, unitZ, front, up, right = WorldUtils.getUnitVectors(unitID)
        local cameraPosition = UnitFollowUtils.applyOffsets(unitX, unitY, unitZ, front, up, right)
        local cx, cy, cz = Spring.GetCameraPosition()
        local dx2 = cameraPosition.x - cx
        local dz2 = cameraPosition.z - cz
        dist2D = math.sqrt(dx2 * dx2 + dz2 * dz2)
    end

    unitFollowState.initialDist2D = dist2D
    unitFollowState.unitTransitionStartTime = Spring.GetTimer()
    unitFollowState.previousUnitID = previousUnitID
    if prevUx then
        unitFollowState.previousUnitPosition = { x = prevUx, y = prevUy, z = prevUz }
    else
        unitFollowState.previousUnitPosition = nil
    end

    UnitFollowCombatMode.clearAttackingState()
end

function UnitFollowCamera.setFixedLookTarget(args)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled('unit_follow') then
        return
    end
    local params = { args[2], args[3], args[4] }
    Log:debug("Looking at", args[1], args[2], args[3], args[4])
    UnitFollowCamera.setFixedLookPoint(args[1], params)
end

return UnitFollowCamera
