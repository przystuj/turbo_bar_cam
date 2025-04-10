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
    if STATE.tracking.mode ~= 'fps' or not STATE.tracking.unitID then
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

--- Gets appropriate offsets based on whether the unit is attacking and which weapon is active
---@return table offsets The offsets to apply
function FPSCameraUtils.getAppropriateOffsets()
    if STATE.tracking.fps.isAttacking then
        return {
            HEIGHT = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_HEIGHT,
            FORWARD = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_FORWARD,
            SIDE = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_SIDE,
            ROTATION = CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_ROTATION
        }
    else
        return {
            HEIGHT = CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT,
            FORWARD = CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD,
            SIDE = CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE,
            ROTATION = CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION
        }
    end

end

--- Applies FPS camera offsets to unit position
---@param unitPos table Unit position {x, y, z}
---@param front table Front vector
---@param up table Up vector
---@param right table Right vector
---@return table camPos Camera position with offsets applied
function FPSCameraUtils.applyFPSOffsets(unitPos, front, up, right)
    local x, y, z = unitPos.x, unitPos.y, unitPos.z

    -- Get appropriate offsets for the current state
    local offsets = FPSCameraUtils.getAppropriateOffsets()

    -- Extract components from the vector tables
    local frontX, frontY, frontZ = front[1], front[2], front[3]
    local upX, upY, upZ = up[1], up[2], up[3]
    local rightX, rightY, rightZ = right[1], right[2], right[3]

    -- Apply height offset along the unit's up vector
    if offsets.HEIGHT ~= 0 then
        x = x + upX * offsets.HEIGHT
        y = y + upY * offsets.HEIGHT
        z = z + upZ * offsets.HEIGHT
    end

    -- Apply forward offset if needed
    if offsets.FORWARD ~= 0 then
        x = x + frontX * offsets.FORWARD
        y = y + frontY * offsets.FORWARD
        z = z + frontZ * offsets.FORWARD
    end

    -- Apply side offset if needed
    if offsets.SIDE ~= 0 then
        x = x + rightX * offsets.SIDE
        y = y + rightY * offsets.SIDE
        z = z + rightZ * offsets.SIDE
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
    if not STATE.tracking.fps.isAttacking then
        return
    end
    STATE.tracking.fps.isAttacking = false
    STATE.tracking.fps.weaponPos = nil
    STATE.tracking.fps.weaponDir = nil
    STATE.tracking.fps.activeWeaponNum = nil
    STATE.tracking.fps.forcedWeaponNumber = nil
    TrackingManager.loadModeSettings("fps", STATE.tracking.unitID)
end

function FPSCameraUtils.nextWeapon()
    local unitDefID = Spring.GetUnitDefID(STATE.tracking.unitID)
    local unitDef = UnitDefs[unitDefID]

    if not unitDef or not unitDef.weapons then
        Log.info("Unit has no weapons")
        return
    end

    -- Collect all valid weapon numbers in order
    local weaponNumbers = {}
    for weaponNum, weaponData in pairs(unitDef.weapons) do
        -- ignoring low range weapons because they probably aren't real weapons
        if type(weaponNum) == "number" and WeaponDefs[weaponData.weaponDef].range > 100 then
            table.insert(weaponNumbers, weaponNum)
        end
    end

    -- Sort them (since pairs() iteration order is not guaranteed)
    table.sort(weaponNumbers)

    if #weaponNumbers == 0 then
        Log.info("Unit has no usable weapons")
        return
    end

    local currentWeapon = STATE.tracking.fps.forcedWeaponNumber or weaponNumbers[1]

    -- Find the index of the current weapon in our ordered list
    local currentIndex = 1
    for i, num in ipairs(weaponNumbers) do
        if num == currentWeapon then
            currentIndex = i
            break
        end
    end

    -- Move to the next weapon or wrap around to the first
    local nextIndex = currentIndex % #weaponNumbers + 1
    STATE.tracking.fps.forcedWeaponNumber = weaponNumbers[nextIndex]

    Log.info("Current weapon: " .. tostring(STATE.tracking.fps.forcedWeaponNumber) .. " (" .. unitDef.wDefs[STATE.tracking.fps.forcedWeaponNumber].name .. ")")
end

--- Extracts target position from a weapon target
---@param unitID number The unit ID
---@param weaponNum number The weapon number
---@return table|nil targetPos The target position or nil if no valid target
function FPSCameraUtils.getWeaponTargetPosition(unitID, weaponNum)
    -- Get weapon target
    local targetType, _, target = Spring.GetUnitWeaponTarget(unitID, weaponNum)

    -- Check if weapon has a proper target
    if not (targetType and targetType > 0 and target) then
        return nil
    end

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

    return targetPos
end

function FPSCameraUtils.chooseWeapon(unitID, unitDef)
    local bestTarget, bestWeaponNum

    -- If we have a forced weapon number, only check that specific weapon
    if STATE.tracking.fps.forcedWeaponNumber then
        local weaponNum = STATE.tracking.fps.forcedWeaponNumber

        -- Verify that this weapon exists for the unit
        if unitDef.weapons[weaponNum] then
            -- Get target for forced weapon
            local targetPos = FPSCameraUtils.getWeaponTargetPosition(unitID, weaponNum)

            if targetPos then
                return targetPos, weaponNum
            end

            -- If we get here with a forced weapon but no target, we still return the forced weapon number
            -- This allows the camera to stay on the forced weapon even when not targeting
            return nil, weaponNum
        end
    end

    -- If no forced weapon, or forced weapon had no valid target, process all weapons
    for weaponNum, weaponData in pairs(unitDef.weapons) do
        -- ignoring low range weapons because they probably aren't real weapons
        if type(weaponNum) == "number" and WeaponDefs[weaponData.weaponDef].range > 100 then
            local targetPos = FPSCameraUtils.getWeaponTargetPosition(unitID, weaponNum)

            if targetPos then
                bestTarget = targetPos
                bestWeaponNum = weaponNum
                -- Found a valid target, no need to check more weapons
                break
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
    else
        -- Store the active weapon number for later use
        STATE.tracking.fps.activeWeaponNum = weaponNum
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

    -- Check for current attack target (autonomous attack)
    local autoTarget, weaponNum = FPSCameraUtils.getCurrentAttackTarget(unitID)
    if autoTarget then
        return autoTarget, weaponNum
    end

    return nil, nil
end

--- Gets camera position for a unit, optionally using weapon position
--- @param unitID number Unit ID
--- @return table camPos Camera position with offsets applied
function FPSCameraUtils.getCameraPositionForUnit(unitID)
    local unitPos, front, up, right = FPSCameraUtils.getUnitVectors(unitID)
    local weaponNum = STATE.tracking.fps.activeWeaponNum

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
            STATE.tracking.fps.activeWeaponNum = weaponNum
        else
            -- If weapon vectors couldn't be retrieved, reset state
            STATE.tracking.fps.isAttacking = false
            STATE.tracking.fps.weaponPos = nil
            STATE.tracking.fps.weaponDir = nil
            STATE.tracking.fps.activeWeaponNum = nil
        end
    else
        -- No weapon specified, reset state
        STATE.tracking.fps.isAttacking = false
        STATE.tracking.fps.weaponPos = nil
        STATE.tracking.fps.weaponDir = nil
        STATE.tracking.fps.activeWeaponNum = nil
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

    -- Get appropriate offsets
    local offsets = FPSCameraUtils.getAppropriateOffsets()

    local targetRy = -(Spring.GetUnitHeading(unitID, true) + math.pi) + offsets.ROTATION
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
    if STATE.tracking.mode ~= 'fps' then
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
    STATE.tracking.fps.isFixedPointActive = true

    -- We're no longer in target selection mode
    STATE.tracking.fps.inTargetSelectionMode = false
    STATE.tracking.fps.prevFixedPoint = nil -- Clear saved previous fixed point

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

    if STATE.tracking.fps.isFixedPointActive and STATE.tracking.unitID then
        -- Disable fixed point tracking
        STATE.tracking.fps.isFixedPointActive = false
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
        return CONFIG.MODE_TRANSITION_SMOOTHING
    end

    local multiplier = 1
    if STATE.tracking.fps.isAttacking then
        multiplier = 5
    end

    if smoothType == 'position' then
        return CONFIG.CAMERA_MODES.FPS.SMOOTHING.POSITION_FACTOR * multiplier
    elseif smoothType == 'rotation' then
        return CONFIG.CAMERA_MODES.FPS.SMOOTHING.ROTATION_FACTOR * multiplier
    end

    -- Default
    return CONFIG.CAMERA_MODES.FPS.SMOOTHING.POSITION_FACTOR * multiplier
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

    --CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_HEIGHT = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.WEAPON_HEIGHT
    --CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_FORWARD = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.WEAPON_FORWARD
    --CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_SIDE = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.WEAPON_SIDE
    --CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_ROTATION = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.WEAPON_ROTATION
    Log.debug("Restored fps camera settings to defaults")
    return true

end

return {
    FPSCameraUtils = FPSCameraUtils
}