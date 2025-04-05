-- FPS Camera utils for TURBOBARCAM
-- Load modules
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CoreModules
local TurboCore = VFS.Include("LuaUI/TURBOBARCAM/core.lua")
---@type CommonModules
local TurboCommons = VFS.Include("LuaUI/TURBOBARCAM/common.lua")

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE
local Util = TurboCommons.Util
local Tracking = TurboCommons.Tracking
local CameraCommons = TurboCore.CameraCommons

---@class FPSCameraUtils
local FPSCameraUtils = {}

--- Checks if FPS camera should be updated
---@return boolean shouldUpdate Whether FPS camera should be updated
function FPSCameraUtils.shouldUpdateFPSCamera()
    if (STATE.tracking.mode ~= 'fps' and STATE.tracking.mode ~= 'fixed_point') or not STATE.tracking.unitID then
        return false
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Util.debugEcho("Unit no longer exists")
        Tracking.disableTracking()
        return false
    end

    return true
end

--- Gets unit position and vectors
---@param unitID number Unit ID
---@return table unitPos Unit position {x, y, z}
---@return table front Front vector
---@return table up Up vector
---@return table right Right vector
function FPSCameraUtils.getUnitVectors(unitID)
    local x, y, z = Spring.GetUnitPosition(unitID)
    local front, up, right = Spring.GetUnitVectors(unitID)

    -- Store unit position for smoothing calculations
    STATE.tracking.lastUnitPos = { x = x, y = y, z = z }

    return { x = x, y = y, z = z }, front, up, right
end

--- Applies FPS camera offsets to unit position
---@param unitPos table Unit position {x, y, z}
---@param front table Front vector
---@param up table Up vector
---@param right table Right vector
---@return table camPos Camera position with offsets applied
function FPSCameraUtils.applyFPSOffsets(unitPos, front, up, right)
    return CameraCommons.applyOffsets(unitPos, front, up, right, {
        height = CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT,
        forward = CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD,
        side = CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE
    })
end

--- Handles normal FPS mode camera orientation
---@param unitID number Unit ID
---@param rotFactor number Rotation smoothing factor
---@return table directionState Camera direction and rotation state
function FPSCameraUtils.handleNormalFPSMode(unitID, rotFactor)
    -- Get unit vectors
    local front, _, _ = Spring.GetUnitVectors(unitID)

    -- Extract components from the vector tables
    local frontX, frontY, frontZ = front[1], front[2], front[3]

    -- Calculate target rotations
    local targetRy = -(Spring.GetUnitHeading(unitID, true) + math.pi)

    -- Apply rotation offset
    targetRy = targetRy + CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION

    local targetRx = 1.8
    local targetRz = 0

    -- Create camera direction state with smoothed values
    local directionState = {
        dx = Util.smoothStep(STATE.tracking.lastCamDir.x, frontX, rotFactor),
        dy = Util.smoothStep(STATE.tracking.lastCamDir.y, frontY, rotFactor),
        dz = Util.smoothStep(STATE.tracking.lastCamDir.z, frontZ, rotFactor),
        rx = Util.smoothStep(STATE.tracking.lastRotation.rx, targetRx, rotFactor),
        ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, targetRy, rotFactor),
        rz = Util.smoothStep(STATE.tracking.lastRotation.rz, targetRz, rotFactor)
    }

    return directionState
end

---@see ModifiableParams
---@see UtilsModule#adjustParams
function FPSCameraUtils.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("fps") then
        return
    end

    -- Make sure we have a unit to track
    if not STATE.tracking.unitID then
        Util.debugEcho("No unit being tracked")
        return
    end

    Util.adjustParams(params, "FPS", function()
        FPSCameraUtils.resetOffsets()
    end)

    -- Update stored offsets for the current unit
    if STATE.tracking.unitID then
        if not STATE.tracking.unitOffsets[STATE.tracking.unitID] then
            STATE.tracking.unitOffsets[STATE.tracking.unitID] = {}
        end

        STATE.tracking.unitOffsets[STATE.tracking.unitID] = {
            height = CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT,
            forward = CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD,
            side = CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE,
            rotation = CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION
        }
    end
    return
end

--- Resets camera offsets to default values
---@return boolean success Whether offsets were reset successfully
function FPSCameraUtils.resetOffsets()
    if Util.isTurboBarCamDisabled() then
        return
    end

    -- If we have a tracked unit, get its height for the default height offset
    if (STATE.tracking.mode == 'fps' or STATE.tracking.mode == 'fixed_point') and
            STATE.tracking.unitID and Spring.ValidUnitID(STATE.tracking.unitID) then
        local unitHeight = Tracking.getDefaultHeightForUnitTracking(STATE.tracking.unitID)
        CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.HEIGHT = unitHeight
        CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT = unitHeight
        CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.FORWARD
        CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.SIDE
        CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.ROTATION

        -- Update stored offsets for this unit
        STATE.tracking.unitOffsets[STATE.tracking.unitID] = {
            height = CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT,
            forward = CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD,
            side = CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE,
            rotation = CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION
        }

        Util.debugEcho("Reset camera offsets for unit " .. STATE.tracking.unitID .. " to defaults")
    else
        CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.HEIGHT
        CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.FORWARD
        CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.SIDE
        CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.ROTATION
        Util.debugEcho("FPS camera offsets reset to defaults")
    end

    return true
end

--- Sets a fixed look point for the camera
---@param fixedPoint table Point to look at {x, y, z}
---@param targetUnitID number|nil Optional unit ID to track
---@return boolean success Whether fixed point was set successfully
function FPSCameraUtils.setFixedLookPoint(fixedPoint, targetUnitID)
    if Util.isTurboBarCamDisabled() then
        return
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
function FPSCameraUtils.clearFixedLookPoint()
    if Util.isTurboBarCamDisabled() then
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
function FPSCameraUtils.updateFixedPointTarget()
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

--- Determines appropriate smoothing factors based on current state
---@param isTransitioning boolean Whether we're in a mode transition
---@param smoothType string Type of smoothing ('position', 'rotation', 'direction')
---@return number smoothingFactor The smoothing factor to use
function FPSCameraUtils.getSmoothingFactor(isTransitioning, smoothType)
    if isTransitioning then
        return CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR
    end

    if smoothType == 'position' then
        return CONFIG.SMOOTHING.POSITION_FACTOR
    elseif smoothType == 'rotation' then
        return CONFIG.SMOOTHING.ROTATION_FACTOR
    end

    -- Default
    return CONFIG.SMOOTHING.POSITION_FACTOR
end

return {
    FPSCameraUtils = FPSCameraUtils
}