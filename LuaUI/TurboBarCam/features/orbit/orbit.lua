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

    -- If no unitID provided, use the first selected unit
    if not unitID then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            unitID = selectedUnits[1]
        else
            Log.debug("No unit selected for Orbiting view")
            return
        end
    end

    -- Check if it's a valid unit
    if not Spring.ValidUnitID(unitID) then
        Log.debug("Invalid unit ID for Orbiting view")
        return
    end

    -- If we're already tracking this exact unit in Orbiting mode, turn it off
    if STATE.tracking.mode == 'orbit' and STATE.tracking.unitID == unitID then
        TrackingManager.disableTracking()
        Log.debug("Orbiting camera detached")
        return
    end

    -- Initialize the tracking system
    if TrackingManager.initializeTracking('orbit', unitID) then

        -- Initialize orbit angle based on current camera position
        local unitX, unitY, unitZ = Spring.GetUnitPosition(unitID)
        local camState = CameraManager.getCameraState("OrbitingCamera.toggle")

        -- Calculate current angle based on camera position relative to unit
        STATE.tracking.orbit.angle = math.atan2(camState.px - unitX, camState.pz - unitZ)

        Log.debug("Orbiting camera attached to unit " .. unitID)
    end

end

--- Updates the orbit camera's position and rotation
function OrbitingCamera.update()
    if STATE.tracking.mode ~= 'orbit' or not STATE.tracking.unitID then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Log.debug("Unit no longer exists")
        TrackingManager.disableTracking()
        return
    end

    -- Get unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)

    -- Update orbit angle
    STATE.tracking.orbit.angle = STATE.tracking.orbit.angle + CONFIG.CAMERA_MODES.ORBIT.SPEED

    -- Calculate camera position on the orbit circle
    local camPos = OrbitCameraUtils.calculateOrbitPosition({ x = unitX, y = unitY, z = unitZ })

    -- Create camera state looking at the unit
    local targetPos = { x = unitX, y = unitY, z = unitZ }

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
        Log.debug("[ORBIT] Using previous settings")
    else
        CONFIG.CAMERA_MODES.ORBIT.SPEED = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_SPEED
        CONFIG.CAMERA_MODES.ORBIT.DISTANCE = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_DISTANCE
        CONFIG.CAMERA_MODES.ORBIT.HEIGHT = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_HEIGHT
        Log.debug("[ORBIT] Using default settings")
    end
    OrbitCameraUtils.ensureHeightIsSet()
end

return {
    OrbitingCamera = OrbitingCamera
}