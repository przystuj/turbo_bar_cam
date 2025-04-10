---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log
---@type Util
local Util = VFS.Include("LuaUI/TurboBarCam/common/utils.lua").Util

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE

---@class TrackingManager
local TrackingManager = {}

--- Initializes unit tracking
---@param mode string Tracking mode ('fps', 'unit_tracking', 'fixed_point', 'orbit')
---@param unitID number|nil Unit ID to track (optional)
---@return boolean success Whether tracking was initialized successfully
function TrackingManager.initializeTracking(mode, unitID)
    if Util.isTurboBarCamDisabled() then
        return
    end

    -- If no unit provided, use first selected unit
    if not unitID then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits == 0 then
            Log.debug("No unit selected for " .. mode .. " view")
            return false
        end
        unitID = selectedUnits[1]
    end

    -- Check if it's a valid unit
    if not Spring.ValidUnitID(unitID) then
        Log.debug("Invalid unit ID for " .. mode .. " view")
        return false
    end

    -- If we're already tracking this exact unit in the same mode, turn it off
    if STATE.tracking.mode == mode and STATE.tracking.unitID == unitID then
        -- Save current settings before disabling
        TrackingManager.saveModeSettings(mode, unitID)
        TrackingManager.disableTracking()
        Log.debug(mode .. " camera detached")
        return false
    end

    -- Begin mode transition from previous mode
    TrackingManager.startModeTransition(mode)
    STATE.tracking.unitID = unitID
    TrackingManager.loadModeSettings(mode, unitID)

    -- refresh unit command bar to add custom command
    Spring.SelectUnitArray(Spring.GetSelectedUnits())
    return true
end

-- TODO each module should implement own saveModeSettings
--- Saves custom settings
---@param mode string Camera mode
---@param unitID number Unit ID
function TrackingManager.saveModeSettings(mode, unitID)
    local identifier
    if CONFIG.PERSISTENT_UNIT_SETTINGS == "UNIT" then
        identifier = unitID
        Log.debug("Saving settings for unit " .. tostring(identifier))
    elseif CONFIG.PERSISTENT_UNIT_SETTINGS == "MODE" then
        identifier = mode
        if identifier == "fixed_point" then
            -- TODO get rid of fixed_point mode
            identifier = "fps"
        end
        Log.debug("Saving settings for mode " .. tostring(identifier))
    else
        return
    end

    if not identifier then
        return
    end

    if mode == 'fps' or mode == 'fixed_point' then
        STATE.tracking.offsets.fps[identifier] = {
            height = CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT,
            forward = CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD,
            side = CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE,
            rotation = CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION
        }
    elseif mode == 'orbit' then
        STATE.tracking.offsets.orbit[identifier] = {
            speed = CONFIG.CAMERA_MODES.ORBIT.SPEED,
            distance = CONFIG.CAMERA_MODES.ORBIT.DISTANCE,
            height = CONFIG.CAMERA_MODES.ORBIT.HEIGHT
        }
    end
end

--- Loads custom settings
---@param mode string Camera mode
---@param unitID number Unit ID
-- TODO each module should implement it's own loadModeSettings and this one should just reference it
function TrackingManager.loadModeSettings(mode, unitID)
    local identifier
    if CONFIG.PERSISTENT_UNIT_SETTINGS == "UNIT" then
        identifier = unitID
        Log.debug("Loading settings for unit " .. tostring(identifier))
    elseif CONFIG.PERSISTENT_UNIT_SETTINGS == "MODE" then
        identifier = mode
        -- TODO get rid of fixed_point mode
        if identifier == "fixed_point" then
            identifier = "fps"
        end
        Log.debug("Loading settings for mode " .. tostring(identifier))
    else
        return
    end

    if mode == 'fps' or mode == 'fixed_point' then
        if STATE.tracking.offsets.fps[identifier] then
            CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT = STATE.tracking.offsets.fps[identifier].height
            CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD = STATE.tracking.offsets.fps[identifier].forward
            CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE = STATE.tracking.offsets.fps[identifier].side
            CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION = STATE.tracking.offsets.fps[identifier].rotation
            Log.debug("Using previous settings")
        else
            CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.HEIGHT
            CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.FORWARD
            CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.SIDE
            CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.ROTATION
            Log.debug("Using default settings")
        end
    elseif mode == 'orbit' then
        -- Load orbit camera settings
        if STATE.tracking.offsets.orbit[identifier] then
            CONFIG.CAMERA_MODES.ORBIT.SPEED = STATE.tracking.offsets.orbit[identifier].speed
            CONFIG.CAMERA_MODES.ORBIT.DISTANCE = STATE.tracking.offsets.orbit[identifier].distance
            CONFIG.CAMERA_MODES.ORBIT.HEIGHT = STATE.tracking.offsets.orbit[identifier].height
            Log.debug("Using previous settings")
        else
            CONFIG.CAMERA_MODES.ORBIT.SPEED = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_SPEED
            CONFIG.CAMERA_MODES.ORBIT.DISTANCE = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_DISTANCE
            CONFIG.CAMERA_MODES.ORBIT.HEIGHT = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_HEIGHT
            Log.debug("Using default settings")
        end
    end
end

function TrackingManager.getDefaultHeightForUnitTracking(unitID)
    return math.max(Util.getUnitHeight(unitID), 100)
end

--- Updates tracking state values after applying camera state
---@param camState table Camera state that was applied
function TrackingManager.updateTrackingState(camState)
    -- Update last camera position
    STATE.tracking.lastCamPos.x = camState.px
    STATE.tracking.lastCamPos.y = camState.py
    STATE.tracking.lastCamPos.z = camState.pz

    -- Update last camera direction
    STATE.tracking.lastCamDir.x = camState.dx
    STATE.tracking.lastCamDir.y = camState.dy
    STATE.tracking.lastCamDir.z = camState.dz

    -- Update last rotation
    STATE.tracking.lastRotation.rx = camState.rx
    STATE.tracking.lastRotation.ry = camState.ry
    STATE.tracking.lastRotation.rz = camState.rz
end

--- Disables tracking and resets tracking state
function TrackingManager.disableTracking()
    TrackingManager.saveModeSettings(STATE.tracking.mode, STATE.tracking.unitID)

    if STATE.tracking.orbit and STATE.tracking.orbit.originalTransitionFactor then
        CONFIG.MODE_TRANSITION_SMOOTHING = STATE.tracking.orbit.originalTransitionFactor
        STATE.tracking.orbit.originalTransitionFactor = nil
    end

    STATE.tracking.unitID = nil
    STATE.tracking.fps.targetUnitID = nil  -- Clear the target unit ID
    STATE.tracking.fps.inFreeCameraMode = false
    STATE.tracking.graceTimer = nil
    STATE.tracking.lastUnitID = nil
   STATE.tracking.fps.fixedPoint = nil
    STATE.tracking.mode = nil

    -- Clear target selection state
    STATE.tracking.fps.inTargetSelectionMode = false
    STATE.tracking.fps.prevFreeCamState = false
    STATE.tracking.fps.prevMode = nil
    STATE.tracking.fps.prevFixedPoint = nil

    -- Reset orbit-specific states
    if STATE.tracking.orbit then
        STATE.tracking.orbit.autoOrbitActive = false
        STATE.tracking.orbit.stationaryTimer = nil
        STATE.tracking.orbit.lastPosition = nil
    end

    -- Clear freeCam state to prevent null pointer exceptions
    if STATE.tracking.freeCam then
        STATE.tracking.fps.freeCam.lastMouseX = nil
        STATE.tracking.fps.freeCam.lastMouseY = nil
        STATE.tracking.fps.freeCam.targetRx = nil
        STATE.tracking.fps.freeCam.targetRy = nil
        STATE.tracking.fps.freeCam.lastUnitHeading = nil
    end
end

--- Starts a mode transition
---@param newMode string New camera mode
---@return boolean success Whether transition started successfully
function TrackingManager.startModeTransition(newMode)
    -- Only start a transition if we're switching between different modes
    if STATE.tracking.mode == newMode then
        return false
    end

    -- Store modes
    STATE.tracking.fps.prevMode = STATE.tracking.mode
    STATE.tracking.mode = newMode

    -- Set up transition state
    STATE.tracking.isModeTransitionInProgress = true
    STATE.tracking.transitionStartState = CameraManager.getCameraState("TrackingManager.startModeTransition")
    STATE.tracking.transitionStartTime = Spring.GetTimer()

    TrackingManager.updateTrackingState(STATE.tracking.transitionStartState)
    return true
end

return {
    TrackingManager = TrackingManager
}