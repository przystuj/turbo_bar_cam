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
        -- Save current orbiting settings before disabling
        STATE.orbit.unitOffsets[unitID] = {
            speed = CONFIG.CAMERA_MODES.ORBIT.SPEED
        }

        TrackingManager.disableTracking()
        Log.debug("Orbiting camera detached")
        return
    end


    -- Initialize the tracking system
    if TrackingManager.initializeTracking('orbit', unitID) then
        -- Get unit height for the default height offset
        local unitHeight = math.max(Util.getUnitHeight(unitID) + 30, 100)

        -- Check if we have stored settings for this unit
        if STATE.orbit.unitOffsets[unitID] and STATE.orbit.unitOffsets[unitID].speed then
            -- Use stored settings
            CONFIG.CAMERA_MODES.ORBIT.SPEED = STATE.orbit.unitOffsets[unitID].speed
            Log.debug("Using previous orbit speed for unit " .. unitID)
        else
            -- Use default settings
            CONFIG.CAMERA_MODES.ORBIT.SPEED = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_SPEED

            -- Initialize storage for this unit
            STATE.orbit.unitOffsets[unitID] = {
                speed = CONFIG.CAMERA_MODES.ORBIT.SPEED
            }

        end


        -- Set height based on unit height
        CONFIG.CAMERA_MODES.ORBIT.HEIGHT = unitHeight * CONFIG.CAMERA_MODES.ORBIT.HEIGHT_FACTOR

        -- Initialize orbit angle based on current camera position
        local unitX, unitY, unitZ = Spring.GetUnitPosition(unitID)
        local camState = CameraManager.getCameraState("OrbitingCamera.toggle")

        -- Calculate current angle based on camera position relative to unit
        STATE.orbit.angle = math.atan2(camState.px - unitX, camState.pz - unitZ)

        -- Initialize the last position for auto-orbit feature
        STATE.orbit.lastPosition = { x = unitX, y = unitY, z = unitZ }
        STATE.orbit.stationaryTimer = nil
        STATE.orbit.autoOrbitActive = false

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
    STATE.orbit.angle = STATE.orbit.angle + CONFIG.CAMERA_MODES.ORBIT.SPEED

    -- Calculate camera position on the orbit circle
    local camPos = OrbitCameraUtils.calculateOrbitPosition(
            { x = unitX, y = unitY, z = unitZ },
            STATE.orbit.angle,
            CONFIG.CAMERA_MODES.ORBIT.HEIGHT,
            CONFIG.CAMERA_MODES.ORBIT.DISTANCE
    )

    -- Create camera state looking at the unit
    local targetPos = { x = unitX, y = unitY, z = unitZ }

    -- Determine smoothing factor based on whether we're in a mode transition
    local smoothFactor = CONFIG.SMOOTHING.POSITION_FACTOR
    local rotFactor = CONFIG.SMOOTHING.ROTATION_FACTOR

    if STATE.tracking.modeTransition then
        -- Use a special transition factor during mode changes
        smoothFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR
        rotFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR

        -- Check if we should end the transition
        if CameraCommons.isTransitionComplete(STATE.tracking.transitionStartTime) then
            STATE.tracking.modeTransition = false
        end
    end

    local camState = CameraCommons.focusOnPoint(camPos, targetPos, smoothFactor, rotFactor)
    TrackingManager.updateTrackingState(camState)

    -- Apply camera state
    CameraManager.setCameraState(camState, 0, "OrbitingCamera.update")
end

--- Updates the auto-orbit camera
function OrbitingCamera.updateAutoOrbit()
    if not STATE.orbit.autoOrbitActive or STATE.tracking.mode ~= 'fps' or not STATE.tracking.unitID or STATE.tracking.inTargetSelectionMode or STATE.tracking.inFreeCameraMode then
        return
    end

    -- Auto-orbit uses the same update logic as manual orbit, but without changing tracking.mode
    -- Get unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)

    -- Update orbit angle
    STATE.orbit.angle = STATE.orbit.angle + CONFIG.CAMERA_MODES.ORBIT.SPEED

    -- Calculate camera position on the orbit circle
    local camPos = OrbitCameraUtils.calculateOrbitPosition(
            { x = unitX, y = unitY, z = unitZ },
            STATE.orbit.angle,
            CONFIG.CAMERA_MODES.ORBIT.HEIGHT,
            CONFIG.CAMERA_MODES.ORBIT.DISTANCE
    )

    -- Create camera state looking at the unit
    local targetPos = { x = unitX, y = unitY, z = unitZ }

    -- Determine smoothing factor - use a very smooth transition for auto-orbit
    local smoothFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR / CONFIG.CAMERA_MODES.ORBIT.AUTO_ORBIT.SMOOTHING_FACTOR
    local rotFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR / CONFIG.CAMERA_MODES.ORBIT.AUTO_ORBIT.SMOOTHING_FACTOR

    local camState = CameraCommons.focusOnPoint(camPos, targetPos, smoothFactor, rotFactor)
    TrackingManager.updateTrackingState(camState)

    -- Apply camera state
    CameraManager.setCameraState(camState, 0, "OrbitingCamera.updateAutoOrbit")
end

---@see ModifiableParams
---@see Util#adjustParams
function OrbitingCamera.adjustParams(params)
    OrbitCameraUtils.adjustParams(params)
end

--- Checks for unit movement and handles auto-orbit functionality
function OrbitingCamera.handleAutoOrbit()
    if OrbitCameraUtils.handleAutoOrbit() then
        -- State was changed, may need to update UI or other state
    end
end

return {
    OrbitingCamera = OrbitingCamera
}