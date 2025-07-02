---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CONSTANTS = ModuleManager.CONSTANTS(function(m) CONSTANTS = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "OrbitingCamera")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local WorldUtils = ModuleManager.WorldUtils(function(m) WorldUtils = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local CameraDriver = ModuleManager.CameraDriver(function(m) CameraDriver = m end)
local OrbitCameraUtils = ModuleManager.OrbitCameraUtils(function(m) OrbitCameraUtils = m end)
local OrbitPersistence = ModuleManager.OrbitPersistence(function(m) OrbitPersistence = m end)

---@class OrbitingCamera
local OrbitingCamera = {}

local function setupAngleForUnit(unitID)
    local unitX, _, unitZ = Spring.GetUnitPosition(unitID)
    local camState = Spring.GetCameraState()
    STATE.active.mode.orbit.angle = math.atan2(camState.px - unitX, camState.pz - unitZ)
end

function OrbitingCamera.toggle(unitID)
    if Utils.isTurboBarCamDisabled() then
        return
    end

    local currentTargetIsPoint = STATE.active.mode.name == CONSTANTS.MODE.ORBIT and STATE.active.mode.targetType == CONSTANTS.TARGET_TYPE.POINT

    if not unitID then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            unitID = selectedUnits[1]
        else
            if currentTargetIsPoint then
                ModeManager.disableAndStopDriver()
            end
            Log:debug("No unit selected.")
            return
        end
    end

    if not Spring.ValidUnitID(unitID) then
        if currentTargetIsPoint then
            ModeManager.disableAndStopDriver()
        end
        Log:debug("Invalid unit ID: " .. tostring(unitID))
        return
    end

    if STATE.active.mode.name == CONSTANTS.MODE.ORBIT and STATE.active.mode.unitID == unitID and STATE.active.mode.targetType == CONSTANTS.TARGET_TYPE.UNIT and
            not STATE.active.mode.optionalTargetCameraStateForModeEntry then
        ModeManager.disableAndStopDriver()
        Log:debug("Orbiting camera detached from unit " .. unitID)
        return
    end

    if ModeManager.initializeMode(CONSTANTS.MODE.ORBIT, unitID, CONSTANTS.TARGET_TYPE.UNIT) then
        STATE.active.mode.orbit.isPaused = false
        setupAngleForUnit(unitID)
        Log:debug("Orbiting camera enabled for unit " .. unitID)
    end
end

function OrbitingCamera.togglePointOrbit()
    Log:debug("toggle point");
    if Utils.isTurboBarCamDisabled() then
        return
    end

    local point = WorldUtils.getCursorWorldPosition()
    if not point then
        Log:debug("Couldn't get cursor position.");
        return
    end

    if ModeManager.initializeMode(CONSTANTS.MODE.ORBIT, point, CONSTANTS.TARGET_TYPE.POINT) then
        STATE.active.mode.orbit.isPaused = false
        local camState = Spring.GetCameraState()
        STATE.active.mode.orbit.angle = math.atan2(camState.px - point.x, camState.pz - point.z)
    end
end

function OrbitingCamera.update(dt)
    if Utils.isTurboBarCamDisabled() or STATE.active.mode.name ~= CONSTANTS.MODE.ORBIT then
        return
    end

    local targetPos = OrbitCameraUtils.getTargetPosition()
    if not targetPos then
        ModeManager.disableAndStopDriver()
        Log:debug("Target lost, disabling orbit.")
        return
    end

    if STATE.active.mode.targetType == CONSTANTS.TARGET_TYPE.POINT and STATE.active.mode.orbit.isPaused then
        -- For point targets, if paused, we let the driver settle completely.
        -- By not calling setTarget, the driver will reach its destination and stop.
        return
    end

    if not STATE.active.mode.orbit.isPaused then
        STATE.active.mode.orbit.angle = STATE.active.mode.orbit.angle + CONFIG.CAMERA_MODES.ORBIT.OFFSETS.SPEED * dt
    end

    local camPos = OrbitCameraUtils.calculateOrbitPosition(targetPos)
    local lookAtTargetData = (STATE.active.mode.targetType == CONSTANTS.TARGET_TYPE.UNIT) and STATE.active.mode.unitID or STATE.active.mode.targetPoint

    local smoothTime = CONFIG.CAMERA_MODES.ORBIT.SMOOTHING_FACTOR

    local cameraDriverJob = CameraDriver.prepare(STATE.active.mode.targetType, lookAtTargetData)
    cameraDriverJob.position = camPos
    cameraDriverJob.positionSmoothing = smoothTime
    cameraDriverJob.rotationSmoothing = smoothTime / 2 -- Faster rotation for better tracking
    cameraDriverJob.run()
end

function OrbitingCamera.pauseOrbit()
    if Utils.isTurboBarCamDisabled() or STATE.active.mode.name ~= CONSTANTS.MODE.ORBIT then
        return
    end
    if STATE.active.mode.orbit.isPaused then
        Log:trace("Orbit is already paused.");
        return
    end
    STATE.active.mode.orbit.isPaused = true
    Log:info("Orbit paused.")
end

function OrbitingCamera.resumeOrbit()
    if Utils.isTurboBarCamDisabled() or STATE.active.mode.name ~= CONSTANTS.MODE.ORBIT then
        return
    end
    if not STATE.active.mode.orbit.isPaused then
        Log:trace("Orbit is not paused.");
        return
    end
    STATE.active.mode.orbit.isPaused = false
    Log:info("Orbit resumed.")
end

function OrbitingCamera.togglePauseOrbit()
    if Utils.isTurboBarCamDisabled() or STATE.active.mode.name ~= CONSTANTS.MODE.ORBIT then
        return
    end
    if STATE.active.mode.orbit.isPaused then
        OrbitingCamera.resumeOrbit()
    else
        OrbitingCamera.pauseOrbit()
    end
end

function OrbitingCamera.saveOrbit(orbitId)
    if Utils.isTurboBarCamDisabled() or STATE.active.mode.name ~= CONSTANTS.MODE.ORBIT then
        return
    end
    if not orbitId or orbitId == "" then
        Log:warn("orbitId is required.");
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
        Log:warn("orbitId is required.");
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

    if targetTypeToUse == CONSTANTS.TARGET_TYPE.UNIT then
        if loadedData.targetID and Spring.ValidUnitID(loadedData.targetID) then
            targetToUse = loadedData.targetID
        else
            local selectedUnits = Spring.GetSelectedUnits()
            if #selectedUnits > 0 then
                targetToUse = selectedUnits[1];
                targetTypeToUse = CONSTANTS.TARGET_TYPE.UNIT
            else
                Log:warn("Invalid saved unit & no selection for load.");
                ModeManager.disableAndStopDriver()
                return
            end
        end
    elseif targetTypeToUse == CONSTANTS.TARGET_TYPE.POINT then
        if loadedData.targetPoint then
            targetToUse = TableUtils.deepCopy(loadedData.targetPoint)
        else
            Log:warn("No targetPoint data for load.");
            ModeManager.disableAndStopDriver()
            return
        end
    else
        Log:error("Unknown target type in load data: " .. tostring(targetTypeToUse));
        ModeManager.disableAndStopDriver()
        return
    end

    if STATE.active.mode.name then
        ModeManager.disableAndStopDriver()
    end

    if ModeManager.initializeMode(CONSTANTS.MODE.ORBIT, targetToUse, targetTypeToUse, false, nil) then
        STATE.active.mode.orbit.loadedAngleForEntry = loadedData.angle
        STATE.active.mode.orbit.isPaused = loadedData.isPaused or false
        Log:info("Loaded orbit ID: " .. orbitId .. (STATE.active.mode.orbit.isPaused and " (PAUSED)" or ""))
    else
        Log:error("Failed to initialize orbit for loaded data: " .. orbitId)
    end
end

function OrbitingCamera.adjustParams(params)
    OrbitCameraUtils.adjustParams(params)
end

return OrbitingCamera