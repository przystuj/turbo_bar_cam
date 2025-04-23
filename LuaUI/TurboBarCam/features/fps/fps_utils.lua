---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/settings/settings_manager.lua").SettingsManager
---@type FPSCombatMode
local FPSCombatMode = VFS.Include("LuaUI/TurboBarCam/features/fps/fps_combat_mode.lua").FPSCombatMode

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
        Log.trace("Unit no longer exists")
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
    -- Set PEACE mode height if not set
    if not CONFIG.CAMERA_MODES.FPS.OFFSETS.PEACE.HEIGHT then
        local unitHeight = TrackingManager.getDefaultHeightForUnitTracking(STATE.tracking.unitID) + 30
        CONFIG.CAMERA_MODES.FPS.OFFSETS.PEACE.HEIGHT = unitHeight
    end

    -- Ensure COMBAT mode height is set (though it should have a default)
    if not CONFIG.CAMERA_MODES.FPS.OFFSETS.COMBAT.HEIGHT then
        CONFIG.CAMERA_MODES.FPS.OFFSETS.COMBAT.HEIGHT = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.COMBAT.HEIGHT
    end

    -- Ensure WEAPON mode height is set (though it should have a default)
    if not CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON.HEIGHT then
        CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON.HEIGHT = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.WEAPON.HEIGHT
    end
end

--- Gets appropriate offsets based on current mode
---@return table offsets The offsets to apply
function FPSCameraUtils.getAppropriateOffsets()
    -- In combat mode - check if actively attacking
    if STATE.tracking.fps.combatModeEnabled then
        if STATE.tracking.fps.isAttacking then
            -- Weapon offsets - when actively targeting something
            return CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON
        else
            -- Combat offsets - when in combat mode but not targeting
            return CONFIG.CAMERA_MODES.FPS.OFFSETS.COMBAT
        end
    else
        -- Peace mode - normal offsets
        return CONFIG.CAMERA_MODES.FPS.OFFSETS.PEACE
    end
end

-- Calculate right vector from front and up vectors
local function calculateRightVector(front, up)
    -- Cross product of front and up gives the right vector
    return {
        front[2] * up[3] - front[3] * up[2], -- y*z' - z*y'
        front[3] * up[1] - front[1] * up[3], -- z*x' - x*z'
        front[1] * up[2] - front[2] * up[1]   -- x*y' - y*x'
    }
end

--- Applies FPS camera offsets to unit position
---@param position table Unit position {x, y, z}
---@param front table Front vector
---@param up table Up vector
---@param right table Right vector
---@return table camPos Camera position with offsets applied
function FPSCameraUtils.applyFPSOffsets(position, front, up, right)
    -- Get appropriate offsets for the current state
    FPSCameraUtils.ensureHeightIsSet()
    local offsets = FPSCameraUtils.getAppropriateOffsets()

    -- Determine which vectors to use based on state
    local frontVec, upVec, rightVec

    if STATE.tracking.fps.isAttacking and STATE.tracking.fps.weaponDir then
        position = STATE.tracking.fps.weaponPos
        front = STATE.tracking.fps.weaponDir

        -- Use weapon direction when attacking
        frontVec = STATE.tracking.fps.weaponDir
        upVec = up
        rightVec = calculateRightVector(STATE.tracking.fps.weaponDir, up)
    else
        -- Use standard vectors otherwise
        frontVec = front
        upVec = up
        rightVec = right
    end

    -- Extract components from the vector tables
    local x, y, z = position.x, position.y, position.z
    local frontX, frontY, frontZ = frontVec[1], frontVec[2], frontVec[3]
    local upX, upY, upZ = upVec[1], upVec[2], upVec[3]
    local rightX, rightY, rightZ = rightVec[1], rightVec[2], rightVec[3]


    -- Apply offsets along all vectors
    if offsets.HEIGHT ~= 0 then
        x = x + upX * offsets.HEIGHT
        y = y + upY * offsets.HEIGHT
        z = z + upZ * offsets.HEIGHT
    end

    if offsets.FORWARD ~= 0 then
        x = x + frontX * offsets.FORWARD
        y = y + frontY * offsets.FORWARD
        z = z + frontZ * offsets.FORWARD
    end

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

--- Creates direction state based on unit's hull direction
--- @param unitID number Unit ID
--- @param offsets table Offsets to use
--- @param rotFactor number Rotation smoothing factor
--- @return table directionState Camera direction state
function FPSCameraUtils.createHullDirectionState(unitID, offsets, rotFactor)
    local front, _, _ = Spring.GetUnitVectors(unitID)
    local frontX, frontY, frontZ = front[1], front[2], front[3]

    local targetRy = -(Spring.GetUnitHeading(unitID, true) + math.pi) + offsets.ROTATION
    local targetRx = 1.8
    local targetRz = 0

    -- Create camera direction state with smoothed values
    return {
        dx = CameraCommons.smoothStep(STATE.tracking.lastCamDir.x, frontX, rotFactor),
        dy = CameraCommons.smoothStep(STATE.tracking.lastCamDir.y, frontY, rotFactor),
        dz = CameraCommons.smoothStep(STATE.tracking.lastCamDir.z, frontZ, rotFactor),
        rx = CameraCommons.smoothStep(STATE.tracking.lastRotation.rx, targetRx, rotFactor),
        ry = CameraCommons.smoothStepAngle(STATE.tracking.lastRotation.ry, targetRy, rotFactor),
        rz = CameraCommons.smoothStep(STATE.tracking.lastRotation.rz, targetRz, rotFactor)
    }
end

--- Creates direction state when actively firing at a target
--- @param unitID number Unit ID
--- @param targetPos table Target position
--- @param weaponNum number|nil Weapon number
--- @param rotFactor number Rotation smoothing factor
--- @return table|nil directionState Camera direction state or nil if it fails
function FPSCameraUtils.createTargetingDirectionState(unitID, targetPos, weaponNum, rotFactor)
    if not targetPos or not weaponNum then
        return nil
    end

    -- Get the weapon position if available
    local posX, posY, posZ, destX, destY, destZ = Spring.GetUnitWeaponVectors(unitID, weaponNum)
    if not posX or not destX then
        return nil
    end

    -- We have valid weapon vectors
    local weaponPos = { x = posX, y = posY, z = posZ }

    -- Calculate direction to target (not weapon direction)
    local dx = targetPos.x - posX
    local dy = targetPos.y - posY
    local dz = targetPos.z - posZ
    local magnitude = math.sqrt(dx * dx + dy * dy + dz * dz)

    if magnitude < 0.001 then
        return nil
    end

    -- Normalize direction vector
    dx, dy, dz = dx / magnitude, dy / magnitude, dz / magnitude

    -- Store position and direction for other functions
    STATE.tracking.fps.weaponPos = weaponPos
    STATE.tracking.fps.weaponDir = { dx, dy, dz }
    STATE.tracking.fps.activeWeaponNum = weaponNum

    -- Get camera position with weapon offsets
    local camPos = FPSCombatMode.getCameraPositionForActiveWeapon(unitID, FPSCameraUtils.applyFPSOffsets)

    -- Create focusing direction to look at target
    return CameraCommons.focusOnPoint(camPos, targetPos, rotFactor, rotFactor, 1.8)
end

--- Handles normal FPS mode camera orientation
--- @param unitID number Unit ID
--- @param rotFactor number Rotation smoothing factor
--- @return table directionState Camera direction and rotation state
function FPSCameraUtils.handleNormalFPSMode(unitID, rotFactor)
    -- Check if combat mode is enabled
    if STATE.tracking.fps.combatModeEnabled then
        -- Check if the unit is actively targeting something
        local targetPos, firingWeaponNum = FPSCombatMode.getTargetPosition(unitID)

        -- Try to create direction state based on targeting data
        local targetingState = FPSCameraUtils.createTargetingDirectionState(
                unitID, targetPos, firingWeaponNum, rotFactor)

        if targetingState then
            -- Successfully created targeting state, unit is attacking
            STATE.tracking.fps.isAttacking = true
            return targetingState
        else
            -- No valid target, but still in combat mode
            STATE.tracking.fps.isAttacking = false
            return FPSCameraUtils.createHullDirectionState(unitID, CONFIG.CAMERA_MODES.FPS.OFFSETS.COMBAT, rotFactor)
        end
    else
        -- Normal mode - always ensure isAttacking is false
        STATE.tracking.fps.isAttacking = false
        return FPSCameraUtils.createHullDirectionState(unitID, CONFIG.CAMERA_MODES.FPS.OFFSETS.PEACE, rotFactor)
    end
end

--- Sets a fixed look point for the camera
---@param fixedPoint table Point to look at {x, y, z}
---@param targetUnitID number|nil Optional unit ID to track
---@return boolean success Whether fixed point was set successfully
function FPSCameraUtils.setFixedLookPoint(fixedPoint, targetUnitID)
    if Util.isTurboBarCamDisabled() then
        return false
    end
    if Util.isModeDisabled("fps") then
        return false
    end
    if not STATE.tracking.unitID then
        Log.trace("No unit being tracked for fixed point camera")
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
    STATE.tracking.fps.isFreeCameraActive = STATE.tracking.fps.prevFreeCamState or false

    -- If not in free camera mode, enable a transition to the fixed point
    if not STATE.tracking.fps.isFreeCameraActive then
        -- Trigger a transition to smoothly move to the new view
        STATE.tracking.isModeTransitionInProgress = true
        STATE.tracking.transitionStartTime = Spring.GetTimer()
    end

    if not STATE.tracking.fps.targetUnitID then
        Log.trace("Camera will follow unit but look at fixed point")
    else
        Log.trace("Camera will follow unit but look at unit " .. STATE.tracking.fps.targetUnitID)
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

        if STATE.tracking.fps.isFreeCameraActive then
            Log.trace("Fixed point tracking disabled, maintaining free camera mode")
        else
            Log.trace("Fixed point tracking disabled, returning to FPS mode")
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

    -- Determine which mode we're in
    local smoothingMode
    if STATE.tracking.fps.combatModeEnabled then
        if STATE.tracking.fps.isAttacking then
            smoothingMode = "WEAPON"
        else
            smoothingMode = "COMBAT"
        end
    else
        smoothingMode = "PEACE"
    end

    -- Get the appropriate smoothing factor based on mode and type
    if smoothType == 'position' then
        return CONFIG.CAMERA_MODES.FPS.SMOOTHING[smoothingMode].POSITION_FACTOR
    elseif smoothType == 'rotation' then
        return CONFIG.CAMERA_MODES.FPS.SMOOTHING[smoothingMode].ROTATION_FACTOR
    end

    -- Default fallback (should never happen)
    return CONFIG.CAMERA_MODES.FPS.SMOOTHING.PEACE.POSITION_FACTOR
end

--- Update adjustParams to handle the new offset structure
function FPSCameraUtils.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("fps") then
        return
    end

    -- Make sure we have a unit to track
    if not STATE.tracking.unitID then
        Log.trace("No unit being tracked")
        return
    end

    -- Handle reset directly
    if params == "reset" then
        FPSCameraUtils.resetOffsets()
        SettingsManager.saveModeSettings("fps", STATE.tracking.unitID)
        return
    end

    -- Parse the parameter string to check what's being modified
    local commandParts = {}
    for part in string.gmatch(params, "[^;]+") do
        table.insert(commandParts, part)
    end

    -- Check which mode's parameters are being adjusted
    local hasPeaceParam = false
    local hasCombatParam = false
    local hasWeaponParam = false

    for i = 2, #commandParts do
        local paramPair = commandParts[i]
        local paramName = string.match(paramPair, "([^,]+),")

        if paramName then
            if string.find(paramName, "^PEACE%.") then
                hasPeaceParam = true
            elseif string.find(paramName, "^COMBAT%.") then
                hasCombatParam = true
            elseif string.find(paramName, "^WEAPON%.") then
                hasWeaponParam = true
            end
        end
    end

    -- Determine current mode
    local currentMode
    if STATE.tracking.fps.combatModeEnabled then
        if STATE.tracking.fps.isAttacking then
            currentMode = "WEAPON"
        else
            currentMode = "COMBAT"
        end
    else
        currentMode = "PEACE"
    end

    -- Filter out calls that don't match the current mode
    if currentMode == "PEACE" and (hasCombatParam or hasWeaponParam) and not hasPeaceParam then
        return
    elseif currentMode == "COMBAT" and (hasPeaceParam or hasWeaponParam) and not hasCombatParam then
        return
    elseif currentMode == "WEAPON" and (hasPeaceParam or hasCombatParam) and not hasWeaponParam then
        return
    end

    Log.trace("Adjusting " .. currentMode:lower() .. " parameters")

    -- Call the original adjustParams function
    Util.adjustParams(params, "FPS", function()
        FPSCameraUtils.resetOffsets()
    end)

    -- Save appropriate settings
    SettingsManager.saveModeSettings("fps", STATE.tracking.unitID)
    return
end

--- Resets camera offsets to default values
function FPSCameraUtils.resetOffsets()
    local function reset(mode)
        CONFIG.CAMERA_MODES.FPS.OFFSETS[mode].HEIGHT = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS[mode].HEIGHT
        CONFIG.CAMERA_MODES.FPS.OFFSETS[mode].FORWARD = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS[mode].FORWARD
        CONFIG.CAMERA_MODES.FPS.OFFSETS[mode].SIDE = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS[mode].SIDE
        CONFIG.CAMERA_MODES.FPS.OFFSETS[mode].ROTATION = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS[mode].ROTATION
    end

    reset("PEACE")
    reset("COMBAT")
    reset("WEAPON")

    FPSCameraUtils.ensureHeightIsSet()
    Log.trace("Restored fps camera settings to defaults")
    return true
end

return {
    FPSCameraUtils = FPSCameraUtils
}