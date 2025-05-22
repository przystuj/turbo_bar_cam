---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type OrbitCameraUtils
local OrbitCameraUtils = VFS.Include("LuaUI/TurboBarCam/features/orbit/orbit_utils.lua").OrbitCameraUtils
---@type OrbitPersistence
local OrbitPersistence = VFS.Include("LuaUI/TurboBarCam/features/orbit/orbit_persistence.lua").OrbitPersistence

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons
local TrackingManager = CommonModules.TrackingManager

---@class OrbitingCamera
local OrbitingCamera = {}

-- Initialize isPaused in STATE.tracking.orbit if it's not there
if STATE.tracking.orbit and STATE.tracking.orbit.isPaused == nil then
    STATE.tracking.orbit.isPaused = false
end

--- Toggles orbiting camera mode
---@param unitID number|nil Optional unit ID (uses selected unit if nil)
function OrbitingCamera.toggle(unitID)
    if Util.isTurboBarCamDisabled() then
        return
    end

    local pointTrackingEnabled = false
    if STATE.tracking.mode == 'orbit' and STATE.tracking.targetType == STATE.TARGET_TYPES.POINT then
        pointTrackingEnabled = true
    end

    if not unitID then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            unitID = selectedUnits[1]
        else
            Log.debug("[ORBIT] No unit selected for Orbiting view")
            if pointTrackingEnabled then
                TrackingManager.disableTracking()
            end
            return
        end
    end

    if not Spring.ValidUnitID(unitID) then
        Log.trace("[ORBIT] Invalid unit ID for Orbiting view")
        if pointTrackingEnabled then
            TrackingManager.disableTracking()
        end
        return
    end

    if STATE.tracking.mode == 'orbit' and STATE.tracking.unitID == unitID and STATE.tracking.targetType == STATE.TARGET_TYPES.UNIT then
        TrackingManager.disableTracking()
        Log.trace("[ORBIT] Orbiting camera detached")
        return
    end

    if TrackingManager.initializeTracking('orbit', unitID, STATE.TARGET_TYPES.UNIT) then
        local unitX, unitY, unitZ = Spring.GetUnitPosition(unitID)
        local camState = CameraManager.getCameraState("OrbitingCamera.toggle")
        STATE.tracking.orbit.angle = math.atan2(camState.px - unitX, camState.pz - unitZ)
        STATE.tracking.orbit.isPaused = false -- Ensure not paused on new toggle
        Log.trace("[ORBIT] Orbiting camera attached to unit " .. unitID)
    end
end

--- Toggles orbiting camera mode around a point
---@param point table|nil Optional position {x,y,z} to orbit around
function OrbitingCamera.togglePointOrbit(point)
    if Util.isTurboBarCamDisabled() then
        return
    end

    if not point then
        point = Util.getCursorWorldPosition()
        if not point then
            Log.debug("[ORBIT] Couldn't get cursor position for Orbiting view")
            return
        end
    end

    if TrackingManager.initializeTracking('orbit', point, STATE.TARGET_TYPES.POINT) then
        local camState = CameraManager.getCameraState("OrbitingCamera.togglePointOrbit")
        STATE.tracking.orbit.angle = math.atan2(camState.px - point.x, camState.pz - point.z)
        STATE.tracking.orbit.isPaused = false -- Ensure not paused on new toggle
        Log.trace(string.format("[ORBIT] Orbiting camera attached to point at (%.1f, %.1f, %.1f)",
                point.x, point.y, point.z))
    end
end

--- Updates the orbit camera's position and rotation
function OrbitingCamera.update(dt)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("orbit") then
        return
    end

    local targetPos = OrbitCameraUtils.getTargetPosition()
    if not targetPos then
        TrackingManager.disableTracking() -- Target lost (e.g. unit destroyed)
        Log.debug("[ORBIT] Target lost, disabling orbit.")
        return
    end

    if STATE.tracking.targetType == STATE.TARGET_TYPES.POINT and STATE.tracking.orbit.isPaused then
        return
    end

    if not STATE.tracking.orbit.isPaused then
        STATE.tracking.orbit.angle = STATE.tracking.orbit.angle + CONFIG.CAMERA_MODES.ORBIT.SPEED * dt
    end

    local orbitSmoothingFactors = CONFIG.CAMERA_MODES.ORBIT.SMOOTHING
    local posSmoothFactor, rotSmoothFactor = CameraCommons.handleModeTransition(orbitSmoothingFactors.POSITION_FACTOR, orbitSmoothingFactors.ROTATION_FACTOR)

    local camPos = OrbitCameraUtils.calculateOrbitPosition(targetPos)
    local camState = CameraCommons.focusOnPoint(camPos, targetPos, posSmoothFactor, rotSmoothFactor)
    TrackingManager.updateTrackingState(camState)
    CameraManager.setCameraState(camState, 0, "OrbitingCamera.update")
end

--- Pauses the current orbit if active.
function OrbitingCamera.pauseOrbit()
    if Util.isTurboBarCamDisabled() or STATE.tracking.mode ~= 'orbit' then
        return
    end
    if STATE.tracking.orbit.isPaused then
        Log.trace("[ORBIT] Orbit is already paused.")
        return
    end
    STATE.tracking.orbit.isPaused = true
    Log.info("[ORBIT] Orbit paused.")
end

--- Resumes the current orbit if paused.
function OrbitingCamera.resumeOrbit()
    if Util.isTurboBarCamDisabled() or STATE.tracking.mode ~= 'orbit' then
        return
    end
    if not STATE.tracking.orbit.isPaused then
        Log.trace("[ORBIT] Orbit is not paused.")
        return
    end
    STATE.tracking.orbit.isPaused = false
    Log.info("[ORBIT] Orbit resumed.")
end

--- Toggles pause/resume state of the orbit.
function OrbitingCamera.togglePauseOrbit()
    if Util.isTurboBarCamDisabled() or STATE.tracking.mode ~= 'orbit' then
        return
    end
    if STATE.tracking.orbit.isPaused then
        OrbitingCamera.resumeOrbit()
    else
        OrbitingCamera.pauseOrbit()
    end
end

--- Saves the current orbit state to a named slot for the current map.
---@param orbitId string The identifier for this saved orbit state (e.g., "orbit_1").
function OrbitingCamera.saveOrbit(orbitId)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if STATE.tracking.mode ~= 'orbit' then
        return
    end
    if not orbitId or orbitId == "" then
        Log.warn("[ORBIT] orbitSetId is required to save orbit state.")
        return
    end

    local dataToSave = OrbitPersistence.serializeCurrentOrbitState()
    if dataToSave then
        OrbitPersistence.saveToFile(orbitId, dataToSave)
    else
        Log.error("[ORBIT] Failed to serialize orbit state for saving.")
    end
end

--- Loads an orbit state from a named slot for the current map and starts orbiting.
---@param orbitId string The identifier of the orbit state to load.
function OrbitingCamera.loadOrbit(orbitId)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if not orbitId or orbitId == "" then
        Log.warn("[ORBIT] orbitSetId is required to load orbit state.")
        return
    end

    local loadedData = OrbitPersistence.loadFromFile(orbitId)
    if not loadedData then
        Log.warn("[ORBIT] Failed to load orbit data for ID: " .. orbitId)
        return
    end

    -- Apply loaded settings to CONFIG (these are used by OrbitCameraUtils)
    CONFIG.CAMERA_MODES.ORBIT.SPEED = loadedData.speed
    CONFIG.CAMERA_MODES.ORBIT.DISTANCE = loadedData.distance
    CONFIG.CAMERA_MODES.ORBIT.HEIGHT = loadedData.height
    OrbitCameraUtils.ensureHeightIsSet() -- Recalculate height if it was based on unit type

    local targetToUse
    local targetTypeToUse = loadedData.targetType
    local unitUsedForHeight = nil

    if targetTypeToUse == STATE.TARGET_TYPES.UNIT then
        if loadedData.targetID and Spring.ValidUnitID(loadedData.targetID) then
            targetToUse = loadedData.targetID
            unitUsedForHeight = targetToUse
            Log.info("[ORBIT] Loading orbit for saved UnitID: " .. targetToUse)
        else
            Log.warn("[ORBIT] Saved UnitID " .. (loadedData.targetID or "nil") .. " is invalid.")
            local selectedUnits = Spring.GetSelectedUnits()
            if #selectedUnits > 0 then
                targetToUse = selectedUnits[1]
                unitUsedForHeight = targetToUse
                targetTypeToUse = STATE.TARGET_TYPES.UNIT -- Ensure target type is unit
                Log.info("[ORBIT] Using selected UnitID: " .. targetToUse .. " as fallback.")
            else
                Log.warn("[ORBIT] No valid saved unit and no unit selected. Cannot load orbit.")
                TrackingManager.disableTracking()
                return
            end
        end
    elseif targetTypeToUse == STATE.TARGET_TYPES.POINT then
        if loadedData.targetPoint then
            targetToUse = Util.deepCopy(loadedData.targetPoint)
            Log.info(string.format("[ORBIT] Loading orbit for saved Point: (%.1f, %.1f, %.1f)", targetToUse.x, targetToUse.y, targetToUse.z))
        else
            Log.warn("[ORBIT] Saved target type is POINT, but no targetPoint data found. Cannot load orbit.")
            TrackingManager.disableTracking()
            return
        end
    else
        Log.error("[ORBIT] Unknown target type in loaded data: " .. (targetTypeToUse or "nil"))
        TrackingManager.disableTracking()
        return
    end

    -- Stop any current camera mode before starting the new loaded orbit
    if STATE.tracking.mode then
        TrackingManager.disableTracking()
    end

    -- Initialize tracking with the determined target
    if TrackingManager.initializeTracking('orbit', targetToUse, targetTypeToUse) then
        -- Crucially, set the loaded angle *after* initializeTracking
        STATE.tracking.orbit.angle = loadedData.angle
        -- Set paused state from loaded data
        STATE.tracking.orbit.isPaused = loadedData.isPaused or false

        Log.info("[ORBIT] Successfully loaded and started orbit ID: " .. orbitId ..
                (STATE.tracking.orbit.isPaused and " (loaded as PAUSED)" or ""))
    else
        Log.error("[ORBIT] Failed to initialize tracking for loaded orbit ID: " .. orbitId)
    end
end

---@see ModifiableParams
---@see Util#adjustParams
function OrbitingCamera.adjustParams(params)
    OrbitCameraUtils.adjustParams(params)
end

function OrbitingCamera.saveSettings(identifier)
    STATE.tracking.offsets.orbit[identifier] = {
        speed = CONFIG.CAMERA_MODES.ORBIT.SPEED,
        distance = CONFIG.CAMERA_MODES.ORBIT.DISTANCE,
        height = CONFIG.CAMERA_MODES.ORBIT.HEIGHT
    }
end

function OrbitingCamera.loadSettings(identifier)
    if STATE.tracking.offsets.orbit[identifier] then
        CONFIG.CAMERA_MODES.ORBIT.SPEED = STATE.tracking.offsets.orbit[identifier].speed
        CONFIG.CAMERA_MODES.ORBIT.DISTANCE = STATE.tracking.offsets.orbit[identifier].distance
        CONFIG.CAMERA_MODES.ORBIT.HEIGHT = STATE.tracking.offsets.orbit[identifier].height
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
