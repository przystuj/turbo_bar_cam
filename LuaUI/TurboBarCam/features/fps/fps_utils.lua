---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/standalone/settings_manager.lua").SettingsManager
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
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

--- Handles normal FPS mode camera orientation
--- @param unitID number Unit ID
--- @param rotFactor number Rotation smoothing factor
--- @return table directionState Camera direction and rotation state
function FPSCameraUtils.handleNormalFPSMode(unitID, rotFactor)
    -- First check if combat mode is enabled
    if STATE.tracking.fps.combatModeEnabled then
        -- Try to get a target if the unit is actively attacking
        local targetPos, firingWeaponNum = FPSCombatMode.getTargetPosition(unitID)

        -- If there's an active target, focus on it
        if targetPos then
            local camPos = FPSCombatMode.getCameraPositionForActiveWeapon(unitID, FPSCameraUtils.applyFPSOffsets)
            return CameraCommons.focusOnPoint(camPos, targetPos, rotFactor, rotFactor, 1.8)
        end

        -- Even if no target, use weapon direction and offsets in combat mode
        -- Get weapon direction if we have a forced weapon
        if STATE.tracking.fps.forcedWeaponNumber then
            local weaponNum = STATE.tracking.fps.forcedWeaponNumber
            local posX, posY, posZ, destX, destY, destZ = Spring.GetUnitWeaponVectors(unitID, weaponNum)

            if posX and destX then
                -- Calculate weapon direction
                local dx, dy, dz = destX, destY, destZ
                local magnitude = math.sqrt(dx*dx + dy*dy + dz*dz)
                if magnitude > 0 then
                    dx, dy, dz = dx/magnitude, dy/magnitude, dz/magnitude
                end

                -- Use combat mode offsets and weapon direction
                STATE.tracking.fps.isAttacking = true  -- This ensures we use weapon offsets

                -- Store weapon position and direction for other functions
                STATE.tracking.fps.weaponPos = { x = posX, y = posY, z = posZ }
                STATE.tracking.fps.weaponDir = { dx, dy, dz }
                STATE.tracking.fps.activeWeaponNum = weaponNum

                -- Create camera direction state with weapon direction
                local directionState = {
                    dx = CameraCommons.smoothStep(STATE.tracking.lastCamDir.x, dx, rotFactor),
                    dy = CameraCommons.smoothStep(STATE.tracking.lastCamDir.y, dy, rotFactor),
                    dz = CameraCommons.smoothStep(STATE.tracking.lastCamDir.z, dz, rotFactor),
                    rx = CameraCommons.smoothStep(STATE.tracking.lastRotation.rx, 1.8, rotFactor),
                    ry = CameraCommons.smoothStepAngle(STATE.tracking.lastRotation.ry,
                            -(Spring.GetUnitHeading(unitID, true) + math.pi) +
                                    CONFIG.CAMERA_MODES.FPS.OFFSETS.WEAPON_ROTATION, rotFactor),
                    rz = CameraCommons.smoothStep(STATE.tracking.lastRotation.rz, 0, rotFactor)
                }

                return directionState
            end
        end

        -- If we don't have weapon info, fall back to unit direction but still use weapon offsets
        STATE.tracking.fps.isAttacking = true  -- Still use weapon offsets even without weapon direction
    else
        -- Not in combat mode, make sure attacking state is cleared
        STATE.tracking.fps.isAttacking = false
    end

    -- Fall back to unit hull direction for normal mode or if no weapon direction available
    local front, _, _ = Spring.GetUnitVectors(unitID)
    local frontX, frontY, frontZ = front[1], front[2], front[3]

    -- Get appropriate offsets based on mode
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
    STATE.tracking.fps.isFreeCameraActive = STATE.tracking.fps.prevFreeCamState or false

    -- If not in free camera mode, enable a transition to the fixed point
    if not STATE.tracking.fps.isFreeCameraActive then
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

        if STATE.tracking.fps.isFreeCameraActive then
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

    -- Handle reset directly
    if params == "reset" then
        FPSCameraUtils.resetOffsets()
        SettingsManager.saveModeSettings("fps", STATE.tracking.unitID)
        return
    end

    -- Determine if we're in weapon mode (attacking) or normal mode
    local isAttacking = STATE.tracking.fps.isAttacking

    -- Parse the parameter string to check what's being modified
    local commandParts = {}
    for part in string.gmatch(params, "[^;]+") do
        table.insert(commandParts, part)
    end

    -- Check if this is targeting weapon parameters or normal parameters
    local hasWeaponParam = false
    local hasNormalParam = false

    for i = 2, #commandParts do
        local paramPair = commandParts[i]
        local paramName = string.match(paramPair, "([^,]+),")

        if paramName then
            if string.find(paramName, "^WEAPON_") then
                hasWeaponParam = true
            elseif paramName == "HEIGHT" or paramName == "FORWARD" or
                    paramName == "SIDE" or paramName == "ROTATION" then
                hasNormalParam = true
            end
        end
    end

    -- Filter out calls that don't match the current state
    if isAttacking and hasNormalParam and not hasWeaponParam then
        -- In attacking mode, trying to adjust normal parameters only
        Log.trace("Ignoring normal parameter adjustment while in weapon (attacking) mode")
        return
    elseif not isAttacking and hasWeaponParam and not hasNormalParam then
        -- In normal mode, trying to adjust weapon parameters only
        Log.trace("Ignoring weapon parameter adjustment while in normal (non-attacking) mode")
        return
    end

    -- If we get here, either:
    -- 1. The parameter types match the current mode
    -- 2. We're adjusting parameters that aren't mode-specific (like MOUSE_SENSITIVITY)
    -- 3. We're adjusting both weapon and normal parameters (allow this to support hybrid adjustments)

    if isAttacking then
        Log.trace("Adjusting parameters in weapon (attacking) mode")
    else
        Log.trace("Adjusting parameters in normal (non-attacking) mode")
    end

    -- Call the original adjustParams function
    Util.adjustParams(params, "FPS", function()
        FPSCameraUtils.resetOffsets()
    end)

    SettingsManager.saveModeSettings("fps", STATE.tracking.unitID)
    return
end

--- Resets camera offsets to default values
---@return boolean success Whether offsets were reset successfully
function FPSCameraUtils.resetOffsets()
    CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.HEIGHT
    CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.FORWARD
    CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.SIDE
    CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.ROTATION
    FPSCameraUtils.ensureHeightIsSet()
    Log.debug("Restored fps camera settings to defaults")
    return true
end

return {
    FPSCameraUtils = FPSCameraUtils
}