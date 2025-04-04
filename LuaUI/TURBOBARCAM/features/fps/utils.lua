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
    if not CameraCommons.validateUnit(STATE.tracking.unitID, "FPS") then
        Util.disableTracking()
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

--- Adjusts FPS camera offset values
---@param offsetType string Type of offset to adjust: "height", "forward", or "side"
---@param amount number Amount to adjust the offset by
---@return boolean success Whether offset was adjusted successfully
function FPSCameraUtils.adjustOffset(offsetType, amount)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("fps") then
        return
    end

    -- Make sure we have a unit to track
    if not STATE.tracking.unitID then
        Util.debugEcho("No unit being tracked")
        return false
    end

    if offsetType == "height" then
        CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT = CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT + amount
    elseif offsetType == "forward" then
        CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD = CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD + amount
    elseif offsetType == "side" then
        CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE = CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE + amount
    end

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
    return true
end

--- Adjusts the rotation offset
---@param amount number Rotation adjustment in radians
---@return boolean success Whether rotation was adjusted successfully
function FPSCameraUtils.adjustRotationOffset(amount)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("fps") then
        return
    end

    -- Make sure we have a unit to track
    if not STATE.tracking.unitID then
        Util.debugEcho("No unit being tracked")
        return false
    end

    -- Adjust rotation offset, keep between -pi and pi
    CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION = (CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION + amount) % (2 * math.pi)
    if CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION > math.pi then
        CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION = CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION - 2 * math.pi
    end

    -- Update stored offsets for the current unit
    if STATE.tracking.unitID then
        if not STATE.tracking.unitOffsets[STATE.tracking.unitID] then
            STATE.tracking.unitOffsets[STATE.tracking.unitID] = {}
        end

        STATE.tracking.unitOffsets[STATE.tracking.unitID].rotation = CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION
    end

    -- Print the updated offsets with rotation in degrees for easier understanding
    local rotationDegrees = math.floor(CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION * 180 / math.pi)
    Util.debugEcho("Camera rotation offset for unit " .. STATE.tracking.unitID .. ": " .. rotationDegrees .. "°")
    
    return true
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
        local unitHeight = Util.getUnitHeight(STATE.tracking.unitID)
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

return {
    FPSCameraUtils = FPSCameraUtils
}