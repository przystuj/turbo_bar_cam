-- Tracking module for TURBOBARCAM
-- Load modules
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CameraTransition
local TransitionModule = VFS.Include("LuaUI/TURBOBARCAM/core/transition.lua")
---@type Util
local UtilsModule = VFS.Include("LuaUI/TURBOBARCAM/common/utils.lua")

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE
local Util = UtilsModule.Util
local CameraTransition = TransitionModule.CameraTransition

---@class TrackingManager
local TrackingManager = {}

--- Initializes unit tracking
---@param mode string Tracking mode ('fps', 'tracking_camera', 'fixed_point', 'orbit')
---@param unitID number|nil Unit ID to track (optional)
---@return boolean success Whether tracking was initialized successfully
function TrackingManager.initializeTracking(mode, unitID)
    if not STATE.enabled then
        Util.debugEcho("Must be enabled first")
        return false
    end

    -- If no unit provided, use first selected unit
    if not unitID then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits == 0 then
            Util.debugEcho("No unit selected for " .. mode .. " view")
            return false
        end
        unitID = selectedUnits[1]
    end

    -- Check if it's a valid unit
    if not Spring.ValidUnitID(unitID) then
        Util.debugEcho("Invalid unit ID for " .. mode .. " view")
        return false
    end

    -- If we're already tracking this exact unit in the same mode, turn it off
    if STATE.tracking.mode == mode and STATE.tracking.unitID == unitID then
        -- Save current settings before disabling
        TrackingManager.saveUnitSettings(mode, unitID)
        Util.disableTracking()
        Util.debugEcho(mode .. " camera detached")
        return false
    end

    -- Begin mode transition from previous mode
    CameraTransition.startModeTransition(STATE.tracking.mode, mode)
    STATE.tracking.unitID = unitID

    -- Switch to FPS camera mode for consistent behavior
    local camStatePatch = {
        name = "fps",
        mode = 0
    }
    Spring.SetCameraState(camStatePatch, 0)

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
            Util.debugEcho("Using previous camera offsets for unit " .. unitID)
        else
            -- Get unit height for the default offset
            local unitHeight = Util.getUnitHeight(unitID)
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
            Util.debugEcho("Using new camera offsets for unit " .. unitID .. " with height: " .. unitHeight)
        end
    elseif mode == 'orbit' then
        -- Load orbit camera settings
        if STATE.orbit.unitOffsets[unitID] then
            CONFIG.CAMERA_MODES.ORBIT.SPEED = STATE.orbit.unitOffsets[unitID].speed
            Util.debugEcho("Using previous orbit speed for unit " .. unitID)
        else
            CONFIG.CAMERA_MODES.ORBIT.SPEED = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_SPEED
            STATE.orbit.unitOffsets[unitID] = {
                speed = CONFIG.CAMERA_MODES.ORBIT.SPEED
            }
        end
    end
end

--- Sets a fixed look point for the camera
---@param fixedPoint table Point to look at {x, y, z}
---@param targetUnitID number|nil Optional unit ID to track
---@return boolean success Whether fixed point was set successfully
function TrackingManager.setFixedLookPoint(fixedPoint, targetUnitID)
    if not STATE.enabled then
        Util.debugEcho("Must be enabled first")
        return false
    end

    -- Only works if we're tracking a unit in FPS mode
    if STATE.tracking.mode ~= 'fps' and STATE.tracking.mode ~= 'fixed_point' then
        Util.debugEcho("Fixed point tracking only works when in FPS mode")
        return false
    end

    if not STATE.tracking.unitID then
        Util.debugEcho("No unit being tracked for fixed point camera")
        return false
    end

    -- Set the fixed point
    STATE.tracking.fixedPoint = fixedPoint
    STATE.tracking.targetUnitID = targetUnitID

    -- We're no longer in target selection mode
    STATE.tracking.inTargetSelectionMode = false
    STATE.tracking.prevFixedPoint = nil -- Clear saved previous fixed point

    -- Switch to fixed point mode
    STATE.tracking.mode = 'fixed_point'

    -- Use the previous free camera state for normal operation
    STATE.tracking.inFreeCameraMode = STATE.tracking.prevFreeCamState or false

    -- If not in free camera mode, enable a transition to the fixed point
    if not STATE.tracking.inFreeCameraMode then
        -- Trigger a transition to smoothly move to the new view
        STATE.tracking.modeTransition = true
        STATE.tracking.transitionStartTime = Spring.GetTimer()
    end

    if not STATE.tracking.targetUnitID then
        Util.debugEcho("Camera will follow unit but look at fixed point")
    else
        Util.debugEcho("Camera will follow unit but look at unit " .. STATE.tracking.targetUnitID)
    end

    return true
end

--- Clears fixed point tracking
function TrackingManager.clearFixedLookPoint()
    if not STATE.enabled then
        Util.debugEcho("Must be enabled first")
        return
    end

    if STATE.tracking.mode == 'fixed_point' and STATE.tracking.unitID then
        -- Switch back to FPS mode
        STATE.tracking.mode = 'fps'
        STATE.tracking.fixedPoint = nil
        STATE.tracking.targetUnitID = nil  -- Clear the target unit ID
        STATE.tracking.inTargetSelectionMode = false
        STATE.tracking.prevFixedPoint = nil -- Clear saved previous fixed point

        -- Start a transition when changing modes
        STATE.tracking.modeTransition = true
        STATE.tracking.transitionStartTime = Spring.GetTimer()

        if STATE.tracking.inFreeCameraMode then
            Util.debugEcho("Fixed point tracking disabled, maintaining free camera mode")
        else
            Util.debugEcho("Fixed point tracking disabled, returning to FPS mode")
        end
    end
end

--- Updates the fixed point if tracking a unit
---@return table|nil fixedPoint The updated fixed point or nil if not tracking a unit
function TrackingManager.updateFixedPointTarget()
    if not STATE.tracking.targetUnitID or not Spring.ValidUnitID(STATE.tracking.targetUnitID) then
        return STATE.tracking.fixedPoint
    end
    
    -- Get the current position of the target unit
    local targetX, targetY, targetZ = Spring.GetUnitPosition(STATE.tracking.targetUnitID)
    STATE.tracking.fixedPoint = {
        x = targetX,
        y = targetY,
        z = targetZ
    }
    return STATE.tracking.fixedPoint
end

return {
    TrackingManager = TrackingManager
}