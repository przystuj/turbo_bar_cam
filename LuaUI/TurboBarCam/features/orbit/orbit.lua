---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type OrbitCameraUtils
local OrbitCameraUtils = VFS.Include("LuaUI/TurboBarCam/features/orbit/orbit_utils.lua").OrbitCameraUtils
---@type OrbitPersistence
local OrbitPersistence = VFS.Include("LuaUI/TurboBarCam/features/orbit/orbit_persistence.lua").OrbitPersistence
---@type TransitionManager
local TransitionManager = VFS.Include("LuaUI/TurboBarCam/core/transition_manager.lua")
---@type CameraTracker
local CameraTracker = VFS.Include("LuaUI/TurboBarCam/standalone/camera_tracker.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons
local ModeManager = CommonModules.ModeManager

---@class OrbitingCamera
local OrbitingCamera = {}

local ORBIT_ENTRY_TRANSITION_ID = "OrbitingCamera.EntryTransition"

--- Internal: Starts a smooth LERP transition onto the orbit path.
---@param initialCamStateAtModeEntry table Camera state when mode was initialized.
local function startOrbitEntryTransition(initialCamStateAtModeEntry)
    STATE.mode.orbit.isModeInitialized = true
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
    if Util.isTurboBarCamDisabled() then
        return
    end

    local currentTargetIsPoint = STATE.mode.name == 'orbit' and STATE.mode.targetType == STATE.TARGET_TYPES.POINT

    if not unitID then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            unitID = selectedUnits[1]
        else
            if currentTargetIsPoint then
                ModeManager.disableMode()
            end
            Log.debug("[ORBIT] No unit selected.")
            return
        end
    end

    if not Spring.ValidUnitID(unitID) then
        if currentTargetIsPoint then
            ModeManager.disableMode()
        end
        Log.trace("[ORBIT] Invalid unit ID: " .. tostring(unitID))
        return
    end

    if STATE.mode.name == 'orbit' and STATE.mode.unitID == unitID and STATE.mode.targetType == STATE.TARGET_TYPES.UNIT and
            not STATE.mode.optionalTargetCameraStateForModeEntry then
        ModeManager.disableMode()
        Log.trace("[ORBIT] Orbiting camera detached from unit " .. unitID)
        return
    end

    if ModeManager.initializeMode('orbit', unitID, STATE.TARGET_TYPES.UNIT, false, nil) then
        STATE.mode.orbit.isPaused = false
        local unitX, _, unitZ = Spring.GetUnitPosition(unitID)
        local camState = Spring.GetCameraState()
        STATE.mode.orbit.angle = math.atan2(camState.px - unitX, camState.pz - unitZ)
        Log.trace("[ORBIT] Orbiting camera enabled for unit " .. unitID)
    end
end

function OrbitingCamera.togglePointOrbit(point)
    if Util.isTurboBarCamDisabled() then
        return
    end
    local MM = ModeManager or WidgetContext.ModeManager
    if not MM then
        Log.error("[ORBIT] ModeManager not available in togglePointOrbit.");
        return
    end

    if not point then
        point = Util.getCursorWorldPosition()
        if not point then
            Log.debug("[ORBIT] Couldn't get cursor position.");
            return
        end
    end

    if ModeManager.initializeMode('orbit', point, STATE.TARGET_TYPES.POINT, false, nil) then
        STATE.mode.orbit.isPaused = false
        local camState = Spring.GetCameraState()
        STATE.mode.orbit.angle = math.atan2(camState.px - point.x, camState.pz - point.z)
    end
end

function OrbitingCamera.update(dt)
    if Util.isTurboBarCamDisabled() or STATE.mode.name ~= 'orbit' then
        return
    end

    if STATE.mode.orbit and not STATE.mode.orbit.isModeInitialized then
        startOrbitEntryTransition(STATE.mode.initialCameraStateForModeEntry)
    end

    if TransitionManager.isTransitioning(ORBIT_ENTRY_TRANSITION_ID) then
        return
    end

    if STATE.mode.targetType == STATE.TARGET_TYPES.POINT and STATE.mode.orbit.isPaused then
        return
    end

    local camState = OrbitingCamera.getNewCameraState(dt)
    if camState then
        CameraTracker.updateLastKnownCameraState(camState)
        Spring.SetCameraState(camState, 0)
    end
end

function OrbitingCamera.getNewCameraState(dt, transitionFactor)
    local targetPos = OrbitCameraUtils.getTargetPosition()
    if not targetPos then
        ModeManager.disableMode()
        Log.debug("[ORBIT] Target lost, disabling orbit.")
        return
    end

    local orbitConfig = CONFIG.CAMERA_MODES.ORBIT

    if not STATE.mode.orbit.isPaused then
        STATE.mode.orbit.angle = STATE.mode.orbit.angle + orbitConfig.SPEED * dt
    end
    local smoothing = transitionFactor or orbitConfig.SMOOTHING_FACTOR

    local camPos = OrbitCameraUtils.calculateOrbitPosition(targetPos)
    return CameraCommons.focusOnPoint(camPos, targetPos, smoothing, smoothing)
end

function OrbitingCamera.pauseOrbit()
    if Util.isTurboBarCamDisabled() or STATE.mode.name ~= 'orbit' then
        return
    end
    if STATE.mode.orbit.isPaused then
        Log.trace("[ORBIT] Orbit is already paused.");
        return
    end
    STATE.mode.orbit.isPaused = true
    Log.info("[ORBIT] Orbit paused.")
end

function OrbitingCamera.resumeOrbit()
    if Util.isTurboBarCamDisabled() or STATE.mode.name ~= 'orbit' then
        return
    end
    if not STATE.mode.orbit.isPaused then
        Log.trace("[ORBIT] Orbit is not paused.");
        return
    end
    STATE.mode.orbit.isPaused = false
    Log.info("[ORBIT] Orbit resumed.")
end

function OrbitingCamera.togglePauseOrbit()
    if Util.isTurboBarCamDisabled() or STATE.mode.name ~= 'orbit' then
        return
    end
    if STATE.mode.orbit.isPaused then
        OrbitingCamera.resumeOrbit()
    else
        OrbitingCamera.pauseOrbit()
    end
end

function OrbitingCamera.saveOrbit(orbitId)
    if Util.isTurboBarCamDisabled() or STATE.mode.name ~= 'orbit' then
        return
    end
    if not orbitId or orbitId == "" then
        Log.warn("[ORBIT] orbitId is required.");
        return
    end
    local dataToSave = OrbitPersistence.serializeCurrentOrbitState()
    if dataToSave then
        OrbitPersistence.saveToFile(orbitId, dataToSave)
    end
end

function OrbitingCamera.loadOrbit(orbitId)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if not orbitId or orbitId == "" then
        Log.warn("[ORBIT] orbitId is required.");
        return
    end
    local MM = ModeManager or WidgetContext.ModeManager
    if not MM then
        Log.error("[ORBIT] ModeManager not available in loadOrbit.");
        return
    end

    local loadedData = OrbitPersistence.loadFromFile(orbitId)
    if not loadedData then
        return
    end

    CONFIG.CAMERA_MODES.ORBIT.SPEED = loadedData.speed
    CONFIG.CAMERA_MODES.ORBIT.DISTANCE = loadedData.distance
    CONFIG.CAMERA_MODES.ORBIT.HEIGHT = loadedData.height

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
                Log.warn("[ORBIT] Invalid saved unit & no selection for load.");
                ModeManager.disableMode();
                return
            end
        end
    elseif targetTypeToUse == STATE.TARGET_TYPES.POINT then
        if loadedData.targetPoint then
            targetToUse = Util.deepCopy(loadedData.targetPoint)
        else
            Log.warn("[ORBIT] No targetPoint data for load.");
            ModeManager.disableMode();
            return
        end
    else
        Log.error("[ORBIT] Unknown target type in load data: " .. tostring(targetTypeToUse));
        ModeManager.disableMode();
        return
    end

    if STATE.mode.name then
        ModeManager.disableMode()
    end

    if ModeManager.initializeMode('orbit', targetToUse, targetTypeToUse, false, nil) then
        STATE.mode.orbit.loadedAngleForEntry = loadedData.angle
        STATE.mode.orbit.isPaused = loadedData.isPaused or false
        Log.info("[ORBIT] Loaded orbit ID: " .. orbitId .. (STATE.mode.orbit.isPaused and " (PAUSED)" or ""))
    else
        Log.error("[ORBIT] Failed to initialize orbit for loaded data: " .. orbitId)
    end
end

function OrbitingCamera.adjustParams(params)
    OrbitCameraUtils.adjustParams(params)
end

function OrbitingCamera.saveSettings(identifier)
    STATE.mode.offsets.orbit[identifier] = {
        speed = CONFIG.CAMERA_MODES.ORBIT.SPEED,
        distance = CONFIG.CAMERA_MODES.ORBIT.DISTANCE,
        height = CONFIG.CAMERA_MODES.ORBIT.HEIGHT
    }
end

function OrbitingCamera.loadSettings(identifier)
    if STATE.mode.offsets.orbit[identifier] then
        CONFIG.CAMERA_MODES.ORBIT.SPEED = STATE.mode.offsets.orbit[identifier].speed
        CONFIG.CAMERA_MODES.ORBIT.DISTANCE = STATE.mode.offsets.orbit[identifier].distance
        CONFIG.CAMERA_MODES.ORBIT.HEIGHT = STATE.mode.offsets.orbit[identifier].height
    else
        CONFIG.CAMERA_MODES.ORBIT.SPEED = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_SPEED
        CONFIG.CAMERA_MODES.ORBIT.DISTANCE = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_DISTANCE
        CONFIG.CAMERA_MODES.ORBIT.HEIGHT = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_HEIGHT
    end
    OrbitCameraUtils.ensureHeightIsSet()
end

return {
    OrbitingCamera = OrbitingCamera
}