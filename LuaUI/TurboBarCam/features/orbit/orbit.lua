---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "OrbitingCamera")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local WorldUtils = ModuleManager.WorldUtils(function(m) WorldUtils = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local OrbitCameraUtils = ModuleManager.OrbitCameraUtils(function(m) OrbitCameraUtils = m end)
local OrbitPersistence = ModuleManager.OrbitPersistence(function(m) OrbitPersistence = m end)
local TransitionManager = ModuleManager.TransitionManager(function(m) TransitionManager = m end)
local CameraTracker = ModuleManager.CameraTracker(function(m) CameraTracker = m end)

---@class OrbitingCamera
local OrbitingCamera = {}

local ORBIT_ENTRY_TRANSITION_ID = "OrbitingCamera.EntryTransition"

local function setupAngleForUnit(unitID)
    local unitX, _, unitZ = Spring.GetUnitPosition(unitID)
    local camState = Spring.GetCameraState()
    STATE.active.mode.orbit.angle = math.atan2(camState.px - unitX, camState.pz - unitZ)
end

local function startOrbitEntryTransition()
    STATE.active.mode.orbit.isModeInitialized = true
    -- angle will be null when transitioning back from projectile camera
    if not STATE.active.mode.orbit.angle then
        setupAngleForUnit(STATE.active.mode.unitID)
    end

    TransitionManager.force({
        id = ORBIT_ENTRY_TRANSITION_ID,
        duration = CONFIG.CAMERA_MODES.ORBIT.INITIAL_TRANSITION_DURATION,
        easingFn = CameraCommons.easeOut,
        onUpdate = function(raw_progress, eased_progress, dt)
            local transitionFactor = CameraCommons.lerp(CONFIG.CAMERA_MODES.ORBIT.INITIAL_TRANSITION_FACTOR, CONFIG.CAMERA_MODES.ORBIT.SMOOTHING_FACTOR, eased_progress)
            local camStatePatch = OrbitingCamera.getNewCameraState(dt, transitionFactor)

            CameraTracker.updateLastKnownCameraState(camStatePatch)
            Spring.SetCameraState(camStatePatch, 0)
        end,
        onComplete = function()
        end
    })
end

function OrbitingCamera.toggle(unitID)
    if Utils.isTurboBarCamDisabled() then
        return
    end

    local currentTargetIsPoint = STATE.active.mode.name == 'orbit' and STATE.active.mode.targetType == STATE.TARGET_TYPES.POINT

    if not unitID then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            unitID = selectedUnits[1]
        else
            if currentTargetIsPoint then
                ModeManager.disableMode()
            end
            Log:debug("[ORBIT] No unit selected.")
            return
        end
    end

    if not Spring.ValidUnitID(unitID) then
        if currentTargetIsPoint then
            ModeManager.disableMode()
        end
        Log:trace("[ORBIT] Invalid unit ID: " .. tostring(unitID))
        return
    end

    if STATE.active.mode.name == 'orbit' and STATE.active.mode.unitID == unitID and STATE.active.mode.targetType == STATE.TARGET_TYPES.UNIT and
            not STATE.active.mode.optionalTargetCameraStateForModeEntry then
        ModeManager.disableMode()
        Log:trace("[ORBIT] Orbiting camera detached from unit " .. unitID)
        return
    end

    if ModeManager.initializeMode('orbit', unitID, STATE.TARGET_TYPES.UNIT, false, nil) then
        STATE.active.mode.orbit.isPaused = false
        setupAngleForUnit(unitID)
        Log:debug("[ORBIT] Orbiting camera enabled for unit " .. unitID)
    end
end

function OrbitingCamera.togglePointOrbit(point)
    if Utils.isTurboBarCamDisabled() then
        return
    end

    if not point then
        point = WorldUtils.getCursorWorldPosition()
        if not point then
            Log:debug("[ORBIT] Couldn't get cursor position.");
            return
        end
    end

    if ModeManager.initializeMode('orbit', point, STATE.TARGET_TYPES.POINT, false, nil) then
        STATE.active.mode.orbit.isPaused = false
        local camState = Spring.GetCameraState()
        STATE.active.mode.orbit.angle = math.atan2(camState.px - point.x, camState.pz - point.z)
    end
end

function OrbitingCamera.update(dt)
    if Utils.isTurboBarCamDisabled() or STATE.active.mode.name ~= 'orbit' then
        return
    end

    if STATE.active.mode.orbit and not STATE.active.mode.orbit.isModeInitialized then
        startOrbitEntryTransition()
    end

    if TransitionManager.isTransitioning(ORBIT_ENTRY_TRANSITION_ID) then
        return
    end

    if STATE.active.mode.targetType == STATE.TARGET_TYPES.POINT and STATE.active.mode.orbit.isPaused then
        return
    end

    local camStatePatch = OrbitingCamera.getNewCameraState(dt)
    if camStatePatch then
        CameraTracker.updateLastKnownCameraState(camStatePatch)
        Spring.SetCameraState(camStatePatch, 0)
    end
end

function OrbitingCamera.getNewCameraState(dt, transitionFactor)
    local targetPos = OrbitCameraUtils.getTargetPosition()
    if not targetPos then
        ModeManager.disableMode()
        Log:debug("[ORBIT] Target lost, disabling orbit.")
        return
    end

    if not STATE.active.mode.orbit.isPaused then
        STATE.active.mode.orbit.angle = STATE.active.mode.orbit.angle + CONFIG.CAMERA_MODES.ORBIT.OFFSETS.SPEED * dt
    end
    local smoothing = transitionFactor or CONFIG.CAMERA_MODES.ORBIT.SMOOTHING_FACTOR

    local camPos = OrbitCameraUtils.calculateOrbitPosition(targetPos)
    return CameraCommons.focusOnPoint(camPos, targetPos, smoothing, smoothing)
end

function OrbitingCamera.pauseOrbit()
    if Utils.isTurboBarCamDisabled() or STATE.active.mode.name ~= 'orbit' then
        return
    end
    if STATE.active.mode.orbit.isPaused then
        Log:trace("[ORBIT] Orbit is already paused.");
        return
    end
    STATE.active.mode.orbit.isPaused = true
    Log:info("[ORBIT] Orbit paused.")
end

function OrbitingCamera.resumeOrbit()
    if Utils.isTurboBarCamDisabled() or STATE.active.mode.name ~= 'orbit' then
        return
    end
    if not STATE.active.mode.orbit.isPaused then
        Log:trace("[ORBIT] Orbit is not paused.");
        return
    end
    STATE.active.mode.orbit.isPaused = false
    Log:info("[ORBIT] Orbit resumed.")
end

function OrbitingCamera.togglePauseOrbit()
    if Utils.isTurboBarCamDisabled() or STATE.active.mode.name ~= 'orbit' then
        return
    end
    if STATE.active.mode.orbit.isPaused then
        OrbitingCamera.resumeOrbit()
    else
        OrbitingCamera.pauseOrbit()
    end
end

function OrbitingCamera.saveOrbit(orbitId)
    if Utils.isTurboBarCamDisabled() or STATE.active.mode.name ~= 'orbit' then
        return
    end
    if not orbitId or orbitId == "" then
        Log:warn("[ORBIT] orbitId is required.");
        return
    end
    local dataToSave = OrbitPersistence.serializeCurrentOrbitState()
    if dataToSave then
        OrbitPersistence.saveToFile(orbitId, dataToSave)
    end
end

function OrbitingCamera.loadOrbit(orbitId)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if not orbitId or orbitId == "" then
        Log:warn("[ORBIT] orbitId is required.");
        return
    end

    local loadedData = OrbitPersistence.loadFromFile(orbitId)
    if not loadedData then
        return
    end

    CONFIG.CAMERA_MODES.ORBIT.OFFSETS.SPEED = loadedData.speed
    CONFIG.CAMERA_MODES.ORBIT.OFFSETS.DISTANCE = loadedData.distance
    CONFIG.CAMERA_MODES.ORBIT.OFFSETS.HEIGHT = loadedData.height

    local targetToUse
    local targetTypeToUse = loadedData.targetType

    if targetTypeToUse == STATE.TARGET_TYPES.UNIT then
        if loadedData.targetID and Spring.ValidUnitID(loadedData.targetID) then
            targetToUse = loadedData.targetID
        else
            local selectedUnits = Spring.GetSelectedUnits()
            if #selectedUnits > 0 then
                targetToUse = selectedUnits[1];
                targetTypeToUse = STATE.TARGET_TYPES.UNIT
            else
                Log:warn("[ORBIT] Invalid saved unit & no selection for load.");
                ModeManager.disableMode();
                return
            end
        end
    elseif targetTypeToUse == STATE.TARGET_TYPES.POINT then
        if loadedData.targetPoint then
            targetToUse = TableUtils.deepCopy(loadedData.targetPoint)
        else
            Log:warn("[ORBIT] No targetPoint data for load.");
            ModeManager.disableMode();
            return
        end
    else
        Log:error("[ORBIT] Unknown target type in load data: " .. tostring(targetTypeToUse));
        ModeManager.disableMode();
        return
    end

    if STATE.active.mode.name then
        ModeManager.disableMode()
    end

    if ModeManager.initializeMode('orbit', targetToUse, targetTypeToUse, false, nil) then
        STATE.active.mode.orbit.loadedAngleForEntry = loadedData.angle
        STATE.active.mode.orbit.isPaused = loadedData.isPaused or false
        Log:info("[ORBIT] Loaded orbit ID: " .. orbitId .. (STATE.active.mode.orbit.isPaused and " (PAUSED)" or ""))
    else
        Log:error("[ORBIT] Failed to initialize orbit for loaded data: " .. orbitId)
    end
end

function OrbitingCamera.adjustParams(params)
    OrbitCameraUtils.adjustParams(params)
end

return OrbitingCamera