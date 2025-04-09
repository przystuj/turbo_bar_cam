---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local TrackingManager = CommonModules.TrackingManager

---@class OrbitCameraUtils
local OrbitCameraUtils = {}

--- Calculates camera position on orbit path
---@param unitPos table Unit position {x, y, z}
---@return table camPos Camera position {x, y, z}
function OrbitCameraUtils.calculateOrbitPosition(unitPos)
    return {
        x = unitPos.x + CONFIG.CAMERA_MODES.ORBIT.DISTANCE * math.sin(STATE.tracking.orbit.angle),
        y = unitPos.y + CONFIG.CAMERA_MODES.ORBIT.HEIGHT,
        z = unitPos.z + CONFIG.CAMERA_MODES.ORBIT.DISTANCE * math.cos(STATE.tracking.orbit.angle)
    }
end

--- Checks for unit movement and handles auto-orbit functionality
---@return boolean stateChanged Whether the auto orbit state has changed
function OrbitCameraUtils.handleAutoOrbit()
    -- Only check if we're in FPS mode with a valid unit and auto-orbit is enabled
    if STATE.tracking.mode ~= 'fps' or not STATE.tracking.unitID or not CONFIG.CAMERA_MODES.ORBIT.AUTO_ORBIT.ENABLED then
        return false
    end

    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Log.debug("[handleAutoOrbit] Unit no longer exists")
        TrackingManager.disableTracking()
        return
    end

    -- Get current unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)
    local currentPos = { x = unitX, y = unitY, z = unitZ }

    -- Get current camera state
    local camState = CameraManager.getCameraState("OrbitCameraUtils.handleAutoOrbit")
    local currentCamPos = { x = camState.px, y = camState.py, z = camState.pz }
    local currentCamRot = { rx = camState.rx, ry = camState.ry, rz = camState.rz }

    -- If this is the first check, just store the positions
    if not STATE.tracking.orbit.lastPosition then
        STATE.tracking.orbit.lastPosition = currentPos
        STATE.tracking.orbit.lastCamPos = currentCamPos
        STATE.tracking.orbit.lastCamRot = currentCamRot
        return false
    end

    -- Check if unit has moved
    local epsilon = 0.1  -- Small threshold to account for floating point precision
    local hasMoved = math.abs(currentPos.x - STATE.tracking.orbit.lastPosition.x) > epsilon or
            math.abs(currentPos.y - STATE.tracking.orbit.lastPosition.y) > epsilon or
            math.abs(currentPos.z - STATE.tracking.orbit.lastPosition.z) > epsilon

    -- Check if camera has moved (user interaction)
    local camEpsilon = 0.5  -- Slightly larger threshold for camera movement
    local rotEpsilon = 0.01  -- Threshold for rotation changes

    -- Only check camera position/rotation if we have previous values
    local hasCamMoved = false
    if STATE.tracking.orbit.autoOrbitActive then
        hasCamMoved = false
    elseif STATE.tracking.orbit.lastCamPos and STATE.tracking.orbit.lastCamRot then
        hasCamMoved = math.abs(currentCamPos.x - STATE.tracking.orbit.lastCamPos.x) > camEpsilon or
                math.abs(currentCamPos.y - STATE.tracking.orbit.lastCamPos.y) > camEpsilon or
                math.abs(currentCamPos.z - STATE.tracking.orbit.lastCamPos.z) > camEpsilon or
                math.abs(currentCamRot.rx - STATE.tracking.orbit.lastCamRot.rx) > rotEpsilon or
                math.abs(currentCamRot.ry - STATE.tracking.orbit.lastCamRot.ry) > rotEpsilon
    end

    local stateChanged = false

    -- Consider either unit movement or camera movement as activity
    if hasMoved or hasCamMoved then
        -- Unit or camera is moving, reset timer
        STATE.tracking.orbit.stationaryTimer = nil

        -- If auto-orbit is active, transition back to FPS
        if STATE.tracking.orbit.autoOrbitActive then
            STATE.tracking.orbit.autoOrbitActive = false
            stateChanged = true

            -- Begin transition from orbit back to FPS mode
            -- We need to do this manually as we're already in "fps" tracking mode
            STATE.tracking.isModeTransitionInProgress = true
            STATE.tracking.transitionStartTime = Spring.GetTimer()

            -- Restore original transition factor
            if STATE.tracking.orbit.originalTransitionFactor then
                CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR = STATE.tracking.orbit.originalTransitionFactor
                STATE.tracking.orbit.originalTransitionFactor = nil
            end

            -- Store current camera position as last position to smooth from
            TrackingManager.updateTrackingState(camState)
        end
    else
        -- Unit and camera are stationary
        if not STATE.tracking.orbit.stationaryTimer then
            -- Start timer
            STATE.tracking.orbit.stationaryTimer = Spring.GetTimer()
        else
            -- Check if we've been stationary long enough
            local now = Spring.GetTimer()
            local elapsed = Spring.DiffTimers(now, STATE.tracking.orbit.stationaryTimer)

            if elapsed > CONFIG.CAMERA_MODES.ORBIT.AUTO_ORBIT.DELAY and not STATE.tracking.orbit.autoOrbitActive then
                -- Transition to auto-orbit
                STATE.tracking.orbit.autoOrbitActive = true
                stateChanged = true

                -- Initialize orbit settings with default values
                TrackingManager.loadModeSettings("orbit", STATE.tracking.unitID)
                OrbitCameraUtils.ensureHeightIsSet()

                -- Initialize orbit angle based on current camera position
                STATE.tracking.orbit.angle = math.atan2(camState.px - unitX, camState.pz - unitZ)

                -- Begin transition from FPS to orbit
                -- We need to do this manually as we're already in "fps" tracking mode
                STATE.tracking.isModeTransitionInProgress = true
                STATE.tracking.transitionStartTime = Spring.GetTimer()

                -- Store current camera position as last position to smooth from
                TrackingManager.updateTrackingState(camState)

                -- Store original transition factor and use a more delayed transition
                STATE.tracking.orbit.originalTransitionFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR
                CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR / CONFIG.CAMERA_MODES.ORBIT.AUTO_ORBIT.SMOOTHING_FACTOR
            end
        end
    end

    -- Update last positions
    STATE.tracking.orbit.lastPosition = currentPos
    STATE.tracking.orbit.lastCamPos = currentCamPos
    STATE.tracking.orbit.lastCamRot = currentCamRot

    return stateChanged
end

function OrbitCameraUtils.ensureHeightIsSet()
    if CONFIG.CAMERA_MODES.ORBIT.HEIGHT then
        return
    end
    local unitHeight = TrackingManager.getDefaultHeightForUnitTracking(STATE.tracking.unitID)
    CONFIG.CAMERA_MODES.ORBIT.HEIGHT = unitHeight * CONFIG.CAMERA_MODES.ORBIT.HEIGHT_FACTOR
end

---@see ModifiableParams
---@see Util#adjustParams
function OrbitCameraUtils.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("orbit") then
        return
    end
    -- Make sure we have a unit to orbit around
    if not STATE.tracking.unitID then
        Log.debug("No unit is being orbited")
        return
    end

    Util.adjustParams(params, "ORBIT", function() OrbitCameraUtils.resetSettings() end)
    TrackingManager.saveModeSettings(STATE.tracking.mode, STATE.tracking.unitID)
end

--- Resets orbit settings to defaults
---@return boolean success Whether settings were reset successfully
function OrbitCameraUtils.resetSettings()
    CONFIG.CAMERA_MODES.ORBIT.SPEED = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_SPEED
    CONFIG.CAMERA_MODES.ORBIT.DISTANCE = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_DISTANCE
    CONFIG.CAMERA_MODES.ORBIT.HEIGHT = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_HEIGHT
    Log.debug("Restored orbit camera settings to defaults")
end

return {
    OrbitCameraUtils = OrbitCameraUtils
}