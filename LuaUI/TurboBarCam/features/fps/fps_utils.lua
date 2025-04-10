---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local TrackingManager = CommonModules.TrackingManager
local CameraCommons = CommonModules.CameraCommons

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
        Log.debug("Unit no longer exists")
        TrackingManager.disableTracking()
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

    return { x = x, y = y, z = z }, front, up, right
end

--- Calculate the height if it's not set
function FPSCameraUtils.ensureHeightIsSet()
    if CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT then
        return
    end
    local unitHeight = TrackingManager.getDefaultHeightForUnitTracking(STATE.tracking.unitID) + 30
    CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT = unitHeight
end

--- Applies FPS camera offsets to unit position
---@param unitPos table Unit position {x, y, z}
---@param front table Front vector
---@param up table Up vector
---@param right table Right vector
---@return table camPos Camera position with offsets applied
function FPSCameraUtils.applyFPSOffsets(unitPos, front, up, right)
    local x, y, z = unitPos.x, unitPos.y, unitPos.z

    local offsets = {
        height = CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT,
        forward = CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD,
        side = CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE
    }

    -- Extract components from the vector tables
    local frontX, frontY, frontZ = front[1], front[2], front[3]
    local upX, upY, upZ = up[1], up[2], up[3]
    local rightX, rightY, rightZ = right[1], right[2], right[3]

    -- Apply height offset along the unit's up vector
    if offsets.height ~= 0 then
        x = x + upX * offsets.height
        y = y + upY * offsets.height
        z = z + upZ * offsets.height
    end

    -- Apply forward offset if needed
    if offsets.forward ~= 0 then
        x = x + frontX * offsets.forward
        y = y + frontY * offsets.forward
        z = z + frontZ * offsets.forward
    end

    -- Apply side offset if needed
    if offsets.side ~= 0 then
        x = x + rightX * offsets.side
        y = y + rightY * offsets.side
        z = z + rightZ * offsets.side
    end

    return { x = x, y = y, z = z }
end

--- Creates a basic camera state object with the specified position and direction
---@param position table Camera position {x, y, z}
---@param direction table Camera direction {dx, dy, dz, rx, ry, rz}
---@return table cameraState Complete camera state object
function FPSCameraUtils.createCameraState(position, direction)
    return {
        mode = 0, -- FPS camera mode
        name = "fps",

        -- Position
        px = position.x,
        py = position.y,
        pz = position.z,

        -- Direction
        dx = direction.dx,
        dy = direction.dy,
        dz = direction.dz,

        -- Rotation
        rx = direction.rx,
        ry = direction.ry,
        rz = direction.rz
    }
end

function FPSCameraUtils.clearAttackingState()
    STATE.tracking.fps.isAttacking = false
    STATE.tracking.fps.weaponPos = nil
    STATE.tracking.fps.weaponDir = nil
end

function FPSCameraUtils.chooseWeapon(unitID, unitDef)
    local bestTarget, bestWeaponNum
    -- Process each weapon
    for weaponNum, weaponData in pairs(unitDef.weapons) do
        if type(weaponNum) == "number" then
            -- Get weapon target
            local targetType, _, target = Spring.GetUnitWeaponTarget(unitID, weaponNum)

            -- Check if weapon has a proper target
            if targetType and targetType > 0 and target then
                local targetPos

                -- Unit target
                if targetType == 1 then
                    if Spring.ValidUnitID(target) then
                        local x, y, z = Spring.GetUnitPosition(target)
                        targetPos = { x = x, y = y, z = z }
                    end
                    -- Ground target
                elseif targetType == 2 then
                    targetPos = { x = target[1], y = target[2], z = target[3] }
                end

                if targetPos then
                    bestTarget = targetPos
                    bestWeaponNum = weaponNum
                    -- Found a valid target, no need to check more weapons
                    break
                end
            end
        end
    end
    return bestTarget, bestWeaponNum
end

--- Checks if unit is currently attacking a target (even without explicit command)
--- @param unitID number Unit ID to check
--- @return table|nil targetPos Position of the current attack target or nil
--- @return number|nil weaponNum The weapon number that is firing at the target
function FPSCameraUtils.getCurrentAttackTarget(unitID)
    if not Spring.ValidUnitID(unitID) then
        -- Reset attacking state when unit is invalid
        FPSCameraUtils.clearAttackingState()
        return nil, nil
    end

    local unitDefID = Spring.GetUnitDefID(unitID)
    local unitDef = UnitDefs[unitDefID]

    if not unitDef or not unitDef.weapons then
        -- Reset attacking state when unit has no weapons
        FPSCameraUtils.clearAttackingState()
        return nil, nil
    end

    local targetPos, weaponNum = FPSCameraUtils.chooseWeapon(unitID, unitDef)

    -- If no target was found, reset attacking state
    if not targetPos then
        FPSCameraUtils.clearAttackingState()
    end

    return targetPos, weaponNum
end

--- Checks if unit has a target (from any source) and returns target position if valid
--- @param unitID number Unit ID to check
--- @return table|nil targetPos Position of the target or nil if no valid target
--- @return number|nil weaponNum The weapon number that is firing at the target (if applicable)
function FPSCameraUtils.getTargetPosition(unitID)
    if not Spring.ValidUnitID(unitID) then
        return nil, nil
    end

    -- Finally check for current attack target (autonomous attack)
    local autoTarget, weaponNum = FPSCameraUtils.getCurrentAttackTarget(unitID)
    if autoTarget then
        return autoTarget, weaponNum
    end

    return nil, nil
end

--- Gets camera position for a unit, optionally using weapon position
--- @param unitID number Unit ID
--- @param weaponNum number|nil The weapon number to use for positioning (if applicable)
--- @return table camPos Camera position with offsets applied
function FPSCameraUtils.getCameraPositionForUnit(unitID, weaponNum)
    local unitPos, front, up, right = FPSCameraUtils.getUnitVectors(unitID)

    -- If a specific weapon is provided, use its position
    if weaponNum then
        local posX, posY, posZ, destX, destY, destZ = Spring.GetUnitWeaponVectors(unitID, weaponNum)

        if posX and destX then
            -- Use weapon position instead of unit center
            unitPos = { x = posX, y = posY, z = posZ }
            front = { destX, destY, destZ }

            -- Update state for tracking
            STATE.tracking.fps.isAttacking = true
            STATE.tracking.fps.weaponPos = unitPos
            STATE.tracking.fps.weaponDir = front
        else
            -- If weapon vectors couldn't be retrieved, reset state
            STATE.tracking.fps.isAttacking = false
            STATE.tracking.fps.weaponPos = nil
            STATE.tracking.fps.weaponDir = nil
        end
    else
        -- No weapon specified, reset state
        STATE.tracking.fps.isAttacking = false
        STATE.tracking.fps.weaponPos = nil
        STATE.tracking.fps.weaponDir = nil
    end

    -- Apply offsets to the position
    return FPSCameraUtils.applyFPSOffsets(unitPos, front, up, right)
end

--- Handles normal FPS mode camera orientation
--- @param unitID number Unit ID
--- @param rotFactor number Rotation smoothing factor
--- @return table directionState Camera direction and rotation state
function FPSCameraUtils.handleNormalFPSMode(unitID, rotFactor)
    -- First check if there's a target to focus on
    local targetPos, firingWeaponNum = FPSCameraUtils.getTargetPosition(unitID)

    if targetPos then
        -- Get camera position using weapon position for active weapons
        local camPos = FPSCameraUtils.getCameraPositionForUnit(unitID, firingWeaponNum)

        -- Focus on target using existing code
        return CameraCommons.focusOnPoint(camPos, targetPos, rotFactor, rotFactor)
    end

    -- Fall back to unit hull direction if no weapon direction available
    local front, _, _ = Spring.GetUnitVectors(unitID)
    local frontX, frontY, frontZ = front[1], front[2], front[3]
    local targetRy = -(Spring.GetUnitHeading(unitID, true) + math.pi) + CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION
    local targetRx = 1.8
    local targetRz = 0

    -- Create camera direction state with smoothed values
    local directionState = {
        dx = CameraCommons.smoothStep(STATE.tracking.lastCamDir.x, frontX, rotFactor),
        dy = CameraCommons.smoothStep(STATE.tracking.lastCamDir.y, frontY, rotFactor),
        dz = CameraCommons.smoothStep(STATE.tracking.lastCamDir.z, frontZ, rotFactor),
        rx = CameraCommons.smoothStep(STATE.tracking.lastRotation.rx, targetRx, rotFactor),
        ry = CameraCommons.smoothStepAngle(STATE.tracking.lastRotation.ry, targetRy, rotFactor),
        rz = CameraCommons.smoothStep(STATE.tracking.lastRotation.rz, targetRz, rotFactor)
    }

    return directionState
end

--- Sets a fixed look point for the camera
---@param fixedPoint table Point to look at {x, y, z}
---@param targetUnitID number|nil Optional unit ID to track
---@return boolean success Whether fixed point was set successfully
function FPSCameraUtils.setFixedLookPoint(fixedPoint, targetUnitID)
    if Util.isTurboBarCamDisabled() then
        return false
    end
    -- Only works if we're tracking a unit in FPS mode
    if STATE.tracking.mode ~= 'fps' and STATE.tracking.mode ~= 'fixed_point' then
        Log.debug("Fixed point tracking only works when in FPS mode")
        return false
    end
    if not STATE.tracking.unitID then
        Log.debug("No unit being tracked for fixed point camera")
        return false
    end

    -- Set the fixed point
    STATE.tracking.fps.fixedPoint = fixedPoint
    STATE.tracking.fps.targetUnitID = targetUnitID

    -- We're no longer in target selection mode
    STATE.tracking.fps.inTargetSelectionMode = false
    STATE.tracking.fps.prevFixedPoint = nil -- Clear saved previous fixed point

    -- Switch to fixed point mode
    STATE.tracking.mode = 'fixed_point'

    -- Use the previous free camera state for normal operation
    STATE.tracking.fps.inFreeCameraMode = STATE.tracking.fps.prevFreeCamState or false

    -- If not in free camera mode, enable a transition to the fixed point
    if not STATE.tracking.fps.inFreeCameraMode then
        -- Trigger a transition to smoothly move to the new view
        STATE.tracking.isModeTransitionInProgress = true
        STATE.tracking.transitionStartTime = Spring.GetTimer()
    end

    if not STATE.tracking.fps.targetUnitID then
        Log.debug("Camera will follow unit but look at fixed point")
    else
        Log.debug("Camera will follow unit but look at unit " .. STATE.tracking.fps.targetUnitID)
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
        STATE.tracking.fps.fixedPoint = nil
        STATE.tracking.fps.targetUnitID = nil  -- Clear the target unit ID
        STATE.tracking.fps.inTargetSelectionMode = false
        STATE.tracking.fps.prevFixedPoint = nil -- Clear saved previous fixed point

        -- Start a transition when changing modes
        STATE.tracking.isModeTransitionInProgress = true
        STATE.tracking.transitionStartTime = Spring.GetTimer()

        if STATE.tracking.fps.inFreeCameraMode then
            Log.debug("Fixed point tracking disabled, maintaining free camera mode")
        else
            Log.debug("Fixed point tracking disabled, returning to FPS mode")
        end
    end
end

--- Updates the fixed point if tracking a unit
---@return table|nil fixedPoint The updated fixed point or nil if not tracking a unit
function FPSCameraUtils.updateFixedPointTarget()
    if not STATE.tracking.fps.targetUnitID or not Spring.ValidUnitID(STATE.tracking.fps.targetUnitID) then
        return STATE.tracking.fps.fixedPoint
    end

    -- Get the current position of the target unit
    local targetX, targetY, targetZ = Spring.GetUnitPosition(STATE.tracking.fps.targetUnitID)
    STATE.tracking.fps.fixedPoint = {
        x = targetX,
        y = targetY,
        z = targetZ
    }
    return STATE.tracking.fps.fixedPoint
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

---@see ModifiableParams
---@see Util#adjustParams
function FPSCameraUtils.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("fps") then
        return
    end

    -- Make sure we have a unit to track
    if not STATE.tracking.unitID then
        Log.debug("No unit being tracked")
        return
    end

    Util.adjustParams(params, "FPS", function()
        FPSCameraUtils.resetOffsets()
    end)

    TrackingManager.saveModeSettings("fps", STATE.tracking.unitID)
    return
end

--- Resets camera offsets to default values
---@return boolean success Whether offsets were reset successfully
function FPSCameraUtils.resetOffsets()
    CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.HEIGHT
    CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.FORWARD
    CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.SIDE
    CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.ROTATION
    Log.debug("Restored fps camera settings to defaults")
end

return {
    FPSCameraUtils = FPSCameraUtils
}