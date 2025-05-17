---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type {OrbitCameraUtils: OrbitCameraUtils}
local OrbitUtils = VFS.Include("LuaUI/TurboBarCam/features/orbit/orbit_utils.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons
local TrackingManager = CommonModules.TrackingManager
local OrbitCameraUtils = OrbitUtils.OrbitCameraUtils

---@class OrbitingCamera
local OrbitingCamera = {}

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

    -- If no unitID provided, use the first selected unit
    if not unitID then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            unitID = selectedUnits[1]
        else
            Log.debug("No unit selected for Orbiting view")
            if pointTrackingEnabled then
                TrackingManager.disableTracking()
            end
            return
        end
    end

    -- Check if it's a valid unit
    if not Spring.ValidUnitID(unitID) then
        Log.trace("Invalid unit ID for Orbiting view")
        if pointTrackingEnabled then
            TrackingManager.disableTracking()
        end
        return
    end

    -- If we're already tracking this exact unit in Orbiting mode, turn it off
    if STATE.tracking.mode == 'orbit' and STATE.tracking.unitID == unitID and STATE.tracking.targetType == STATE.TARGET_TYPES.UNIT then
        TrackingManager.disableTracking()
        Log.trace("Orbiting camera detached")
        return
    end

    -- Initialize the tracking system
    if TrackingManager.initializeTracking('orbit', unitID) then

        -- Initialize orbit angle based on current camera position
        local unitX, unitY, unitZ = Spring.GetUnitPosition(unitID)
        local camState = CameraManager.getCameraState("OrbitingCamera.toggle")

        -- Calculate current angle based on camera position relative to unit
        STATE.tracking.orbit.angle = math.atan2(camState.px - unitX, camState.pz - unitZ)

        Log.trace("Orbiting camera attached to unit " .. unitID)
    end

end

--- Toggles orbiting camera mode around a point
---@param point table|nil Optional position {x,y,z} to orbit around
function OrbitingCamera.togglePointOrbit(point)
    if Util.isTurboBarCamDisabled() then
        return
    end

    -- If no point provided, use cursor position
    if not point then
        point = Util.getCursorWorldPosition()
        if not point then
            Log.debug("Couldn't get cursor position for Orbiting view")
            return
        end
    end

    -- Initialize the tracking system
    if TrackingManager.initializeTracking('orbit', point, STATE.TARGET_TYPES.POINT) then
        -- Initialize orbit angle based on current camera position
        local camState = CameraManager.getCameraState("OrbitingCamera.togglePointOrbit")

        -- Calculate current angle based on camera position relative to point
        STATE.tracking.orbit.angle = math.atan2(camState.px - point.x, camState.pz - point.z)

        Log.trace(string.format("Orbiting camera attached to point at (%.1f, %.1f, %.1f)",
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

    -- Get target position based on target type
    local targetPos = OrbitCameraUtils.getTargetPosition()

    STATE.tracking.orbit.angle = STATE.tracking.orbit.angle + CONFIG.CAMERA_MODES.ORBIT.SPEED * dt

    -- Calculate camera position on the orbit circle
    local camPos = OrbitCameraUtils.calculateOrbitPosition(targetPos)

    -- Determine smoothing factor based on whether we're in a mode transition
    local smoothFactor = CONFIG.CAMERA_MODES.ORBIT.SMOOTHING.POSITION_FACTOR
    local rotFactor = CONFIG.CAMERA_MODES.ORBIT.SMOOTHING.ROTATION_FACTOR

    if STATE.tracking.isModeTransitionInProgress then
        -- Use a special transition factor during mode changes
        smoothFactor = CONFIG.MODE_TRANSITION_SMOOTHING
        rotFactor = CONFIG.MODE_TRANSITION_SMOOTHING

        -- Check if we should end the transition
        if CameraCommons.isTransitionComplete() then
            STATE.tracking.isModeTransitionInProgress = false
        end
    end

    local camState = CameraCommons.focusOnPoint(camPos, targetPos, smoothFactor, rotFactor)

    TrackingManager.updateTrackingState(camState)

    -- Apply camera state
    CameraManager.setCameraState(camState, 0, "OrbitingCamera.update")
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
        Log.trace("[ORBIT] Using previous settings")
    else
        CONFIG.CAMERA_MODES.ORBIT.SPEED = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_SPEED
        CONFIG.CAMERA_MODES.ORBIT.DISTANCE = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_DISTANCE
        CONFIG.CAMERA_MODES.ORBIT.HEIGHT = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_HEIGHT
        Log.trace("[ORBIT] Using default settings")
    end
    OrbitCameraUtils.ensureHeightIsSet()
end

return {
    OrbitingCamera = OrbitingCamera
}