---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TURBOBARCAM/standalone/camera_manager.lua").CameraManager
---@type Log
local Log = VFS.Include("LuaUI/TURBOBARCAM/common/log.lua").Log
---@type Util
local Util = VFS.Include("LuaUI/TURBOBARCAM/common/utils.lua").Util

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE

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
        TrackingManager.saveUnitSettings(mode, unitID)
        TrackingManager.disableTracking()
        Log.debug(mode .. " camera detached")
        return false
    end

    -- Begin mode transition from previous mode
    TrackingManager.startModeTransition(mode)
    STATE.tracking.unitID = unitID

    -- refresh unit command bar to add custom command
    Spring.SelectUnitArray(Spring.GetSelectedUnits())
    return true
end

--- Saves unit-specific settings
---@param mode string Camera mode
---@param unitID number Unit ID
function TrackingManager.saveUnitSettings(mode, unitID)
    if not unitID then return end

    if mode == 'fps' or mode == 'fixed_point' then
        -- Save FPS camera offsets
        STATE.tracking.unitOffsets[unitID] = {
            height = CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT,
            forward = CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD,
            side = CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE,
            rotation = CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION
        }
    elseif mode == 'orbit' then
        -- Save orbit camera settings
        if not STATE.orbit.unitOffsets[unitID] then
            STATE.orbit.unitOffsets[unitID] = {}
        end
        STATE.orbit.unitOffsets[unitID].speed = CONFIG.CAMERA_MODES.ORBIT.SPEED
    end
end


function TrackingManager.getDefaultHeightForUnitTracking(unitID)
    return math.max(Util.getUnitHeight(unitID) + 30, 100)
end

--- Loads unit-specific settings
---@param mode string Camera mode
---@param unitID number Unit ID
function TrackingManager.loadUnitSettings(mode, unitID)
    if not unitID then return end

    if mode == 'fps' or mode == 'fixed_point' then
        -- Load FPS camera offsets
        if STATE.tracking.unitOffsets[unitID] then
            CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT = STATE.tracking.unitOffsets[unitID].height
            CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD = STATE.tracking.unitOffsets[unitID].forward
            CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE = STATE.tracking.unitOffsets[unitID].side
            CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION = STATE.tracking.unitOffsets[unitID].rotation or 0
            Log.debug("Using previous camera offsets for unit " .. unitID)
        else
            -- Get unit height for the default offset
            local unitHeight = TrackingManager.getDefaultHeightForUnitTracking(unitID)
            CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.HEIGHT = unitHeight
            CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT = unitHeight
            CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.FORWARD
            CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.SIDE
            CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.ROTATION

            -- Initialize storage for this unit
            STATE.tracking.unitOffsets[unitID] = {
                height = CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT,
                forward = CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD,
                side = CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE,
                rotation = CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION
            }
            Log.debug("Using new camera offsets for unit " .. unitID .. " with height: " .. unitHeight)
        end
    elseif mode == 'orbit' then
        -- Load orbit camera settings
        if STATE.orbit.unitOffsets[unitID] then
            CONFIG.CAMERA_MODES.ORBIT.SPEED = STATE.orbit.unitOffsets[unitID].speed
            Log.debug("Using previous orbit speed for unit " .. unitID)
        else
            CONFIG.CAMERA_MODES.ORBIT.SPEED = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_SPEED
            STATE.orbit.unitOffsets[unitID] = {
                speed = CONFIG.CAMERA_MODES.ORBIT.SPEED
            }
        end
    end
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
    -- Restore original transition factor if needed
    if STATE.orbit and STATE.orbit.originalTransitionFactor then
        CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR = STATE.orbit.originalTransitionFactor
        STATE.orbit.originalTransitionFactor = nil
    end

    STATE.tracking.unitID = nil
    STATE.tracking.targetUnitID = nil  -- Clear the target unit ID
    STATE.tracking.inFreeCameraMode = false
    STATE.tracking.graceTimer = nil
    STATE.tracking.lastUnitID = nil
    STATE.tracking.fixedPoint = nil
    STATE.tracking.mode = nil

    -- Clear target selection state
    STATE.tracking.inTargetSelectionMode = false
    STATE.tracking.prevFreeCamState = false
    STATE.tracking.prevMode = nil
    STATE.tracking.prevFixedPoint = nil

    -- Reset orbit-specific states
    if STATE.orbit then
        STATE.orbit.autoOrbitActive = false
        STATE.orbit.stationaryTimer = nil
        STATE.orbit.lastPosition = nil
    end

    -- Clear freeCam state to prevent null pointer exceptions
    if STATE.tracking.freeCam then
        STATE.tracking.freeCam.lastMouseX = nil
        STATE.tracking.freeCam.lastMouseY = nil
        STATE.tracking.freeCam.targetRx = nil
        STATE.tracking.freeCam.targetRy = nil
        STATE.tracking.freeCam.lastUnitHeading = nil
    end
end

--- Starts a mode transition
---@param prevMode string Previous camera mode
---@param newMode string New camera mode
---@return boolean success Whether transition started successfully
function TrackingManager.startModeTransition(newMode)
    -- Only start a transition if we're switching between different modes
    if STATE.tracking.mode == newMode then
        return false
    end

    -- Store modes
    STATE.tracking.prevMode = STATE.tracking.mode
    STATE.tracking.mode = newMode

    -- Set up transition state
    STATE.tracking.modeTransition = true
    STATE.tracking.transitionStartState = CameraManager.getCameraState("TrackingManager.startModeTransition")
    STATE.tracking.transitionStartTime = Spring.GetTimer()

    TrackingManager.updateTrackingState(STATE.tracking.transitionStartState)
    return true
end

return {
    TrackingManager = TrackingManager
}