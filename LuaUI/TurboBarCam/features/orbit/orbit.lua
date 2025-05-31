---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type OrbitCameraUtils
local OrbitCameraUtils = VFS.Include("LuaUI/TurboBarCam/features/orbit/orbit_utils.lua").OrbitCameraUtils
---@type OrbitPersistence
local OrbitPersistence = VFS.Include("LuaUI/TurboBarCam/features/orbit/orbit_persistence.lua").OrbitPersistence
---@type TransitionManager
local TransitionManager = VFS.Include("LuaUI/TurboBarCam/standalone/transition_manager.lua").TransitionManager

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons
local ModeManager = CommonModules.ModeManager

---@class OrbitingCamera
local OrbitingCamera = {}

local ORBIT_ENTRY_TRANSITION_ID = "OrbitingCamera.EntryTransition"
local ORBIT_ENTRY_TRANSITION_DURATION = 0.75

--- Internal: Starts a smooth LERP transition onto the orbit path.
---@param targetPosActual table The actual current target position {x,y,z}.
---@param initialCamStateAtModeEntry table Camera state when mode was initialized.
local function startOrbitEntryTransition(targetPosActual, initialCamStateAtModeEntry)
    local desiredInitialAngle
    if STATE.mode.orbit.loadedAngleForEntry ~= nil then
        desiredInitialAngle = STATE.mode.orbit.loadedAngleForEntry
        STATE.mode.orbit.loadedAngleForEntry = nil -- Consume the loaded angle
        Log.trace("[ORBIT] Using loaded angle for entry transition: " .. desiredInitialAngle)
    else
        desiredInitialAngle = math.atan2(initialCamStateAtModeEntry.px - targetPosActual.x, initialCamStateAtModeEntry.pz - targetPosActual.z)
    end

    local targetCamPosOnOrbit = OrbitCameraUtils.calculateOrbitPositionWithAngle(targetPosActual, desiredInitialAngle)
    local targetCamStateOnOrbit = CameraCommons.calculateCameraDirectionToThePoint(targetCamPosOnOrbit, targetPosActual)
    targetCamStateOnOrbit.px = targetCamPosOnOrbit.x
    targetCamStateOnOrbit.py = targetCamPosOnOrbit.y
    targetCamStateOnOrbit.pz = targetCamPosOnOrbit.z
    targetCamStateOnOrbit.fov = initialCamStateAtModeEntry.fov -- Keep FOV from before transition

    TransitionManager.force({
        id = ORBIT_ENTRY_TRANSITION_ID,
        duration = ORBIT_ENTRY_TRANSITION_DURATION,
        easingFn = CameraCommons.easeInOut,
        onUpdate = function(progress, easedProgress, dt)
            local camStatePatch = {
                px = CameraCommons.lerp(initialCamStateAtModeEntry.px, targetCamStateOnOrbit.px, easedProgress),
                py = CameraCommons.lerp(initialCamStateAtModeEntry.py, targetCamStateOnOrbit.py, easedProgress),
                pz = CameraCommons.lerp(initialCamStateAtModeEntry.pz, targetCamStateOnOrbit.pz, easedProgress),
                rx = CameraCommons.smoothStepAngle(initialCamStateAtModeEntry.rx, targetCamStateOnOrbit.rx, easedProgress),
                ry = CameraCommons.smoothStepAngle(initialCamStateAtModeEntry.ry, targetCamStateOnOrbit.ry, easedProgress),
                fov = CameraCommons.lerp(initialCamStateAtModeEntry.fov or 45, targetCamStateOnOrbit.fov or 45, easedProgress)
            }
            local finalDir = CameraCommons.getDirectionFromRotation(camStatePatch.rx, camStatePatch.ry, 0)
            camStatePatch.dx, camStatePatch.dy, camStatePatch.dz = finalDir.x, finalDir.y, finalDir.z
            camStatePatch.rz = 0
            if ModeManager and ModeManager.updateTrackingState then
                ModeManager.updateTrackingState(camStatePatch)
            end
            Spring.SetCameraState(camStatePatch, 0)
        end,
        onComplete = function()
            Log.trace("[ORBIT] Smooth entry transition finished.")
            STATE.mode.orbit.angle = desiredInitialAngle

            -- FIX for slight jump: Set camera to the exact end state of transition
            local finalTargetPosOnComplete = OrbitCameraUtils.getTargetPosition() -- Re-fetch in case unit moved
            if finalTargetPosOnComplete then
                OrbitCameraUtils.ensureHeightIsSet()
                local finalCamPos = OrbitCameraUtils.calculateOrbitPositionWithAngle(finalTargetPosOnComplete, STATE.mode.orbit.angle)
                local finalCamState = CameraCommons.calculateCameraDirectionToThePoint(finalCamPos, finalTargetPosOnComplete)
                finalCamState.px, finalCamState.py, finalCamState.pz = finalCamPos.x, finalCamPos.y, finalCamPos.z
                finalCamState.fov = targetCamStateOnOrbit.fov -- Use the FOV we transitioned to

                local MM = ModeManager or WidgetContext.ModeManager
                if MM and ModeManager.updateTrackingState then
                    ModeManager.updateTrackingState(finalCamState)
                end
                Spring.SetCameraState(finalCamState, 0)
            end
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
        Log.trace(string.format("[ORBIT] Orbiting camera enabled for point (%.1f, %.1f, %.1f)", point.x, point.y, point.z))
    end
end

function OrbitingCamera.update(dt)
    if Util.isTurboBarCamDisabled() or STATE.mode.name ~= 'orbit' then
        return
    end
    local MM = ModeManager or WidgetContext.ModeManager

    local targetPos = OrbitCameraUtils.getTargetPosition()
    if not targetPos then
        if MM and ModeManager.disableMode then
            ModeManager.disableMode()
        end
        Log.debug("[ORBIT] Target lost, disabling orbit.")
        return
    end

    if STATE.mode.orbit and not STATE.mode.orbit.isModeInitialized then
        STATE.mode.orbit.isModeInitialized = true
        local initialCamState = STATE.mode.initialCameraStateForModeEntry
        startOrbitEntryTransition(targetPos, initialCamState)
    end

    if TransitionManager.isTransitioning(ORBIT_ENTRY_TRANSITION_ID) then
        return
    end

    if STATE.mode.targetType == STATE.TARGET_TYPES.POINT and STATE.mode.orbit.isPaused then
        return
    end

    if not STATE.mode.orbit.isPaused then
        local speed = CONFIG.CAMERA_MODES.ORBIT.SPEED
        local validDt = (type(dt) == "number" and dt > 0) and dt or (1 / 60)
        STATE.mode.orbit.angle = (STATE.mode.orbit.angle or 0) + speed * validDt
    end

    OrbitCameraUtils.ensureHeightIsSet() -- Uses STATE for context
    local posSmoothFactor = CONFIG.CAMERA_MODES.ORBIT.SMOOTHING.POSITION_FACTOR
    local rotSmoothFactor = CONFIG.CAMERA_MODES.ORBIT.SMOOTHING.ROTATION_FACTOR
    local camPos = OrbitCameraUtils.calculateOrbitPosition(targetPos)
    local camStatePatch = CameraCommons.focusOnPoint(camPos, targetPos, posSmoothFactor, rotSmoothFactor)

    if MM and ModeManager.updateTrackingState then
        ModeManager.updateTrackingState(camStatePatch)
    end
    Spring.SetCameraState(camStatePatch, 0)
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
        STATE.mode.orbit.loadedAngleForEntry = loadedData.angle -- Store for entry transition
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
    OrbitCameraUtils.ensureHeightIsSet() -- Recalculate based on current target after loading/defaulting
end

return {
    OrbitingCamera = OrbitingCamera
}