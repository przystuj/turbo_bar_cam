-- FPS Camera module for TURBOBARCAM
---@type {CONFIG: CONFIG, STATE: STATE}
local TurboConfig = VFS.Include("LuaUI/TURBOBARCAM/camera_turbobarcam_config.lua")
---@type {Util: Util}
local TurboUtils = VFS.Include("LuaUI/TURBOBARCAM/camera_turbobarcam_utils.lua")
---@type {BaseCameraMode: BaseCameraMode}
local BaseCameraModule = VFS.Include("LuaUI/TURBOBARCAM/camera_turbobarcam_base.lua")

local CONFIG = TurboConfig.CONFIG
local STATE = TurboConfig.STATE
local Util = TurboUtils.Util
local BaseCameraMode = BaseCameraModule.BaseCameraMode
local prevActiveCmd

---@class FPSCamera
local FPSCamera = {}

--- Command definition for Set Fixed Look Point
---@type table
FPSCamera.COMMAND_DEFINITION = {
    id = CONFIG.COMMANDS.SET_FIXED_LOOK_POINT,
    type = CMDTYPE.ICON_UNIT_OR_MAP,
    name = 'Set Fixed Look Point',
    tooltip = 'Click on a location to focus camera on while following unit',
    cursor = 'settarget',
    action = 'set_fixed_look_point',
}

--- Checks if FPS camera should be updated
---@return boolean shouldUpdate Whether FPS camera should be updated
local function shouldUpdateFPSCamera()
    if (STATE.tracking.mode ~= 'fps' and STATE.tracking.mode ~= 'fixed_point') or not STATE.tracking.unitID then
        return false
    end

    -- Check if unit still exists
    if not BaseCameraMode.validateUnit(STATE.tracking.unitID, "FPS") then
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
local function getUnitVectors(unitID)
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
local function applyFPSOffsets(unitPos, front, up, right)
    return BaseCameraMode.applyOffsets(unitPos, front, up, right, {
        height = CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT,
        forward = CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD,
        side = CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE
    })
end

--- Updates fixed point if tracking a unit
---@return table|nil fixedPoint The updated fixed point or nil if not tracking a unit
local function updateFixedPointTarget()
    if STATE.tracking.targetUnitID and Spring.ValidUnitID(STATE.tracking.targetUnitID) then
        -- Get the current position of the target unit
        local targetX, targetY, targetZ = Spring.GetUnitPosition(STATE.tracking.targetUnitID)
        STATE.tracking.fixedPoint = {
            x = targetX,
            y = targetY,
            z = targetZ
        }
        return STATE.tracking.fixedPoint
    end
    return STATE.tracking.fixedPoint
end

--- Handles normal FPS mode camera orientation
---@param unitID number Unit ID
---@param rotFactor number Rotation smoothing factor
---@return table directionState Camera direction and rotation state
local function handleNormalFPSMode(unitID, rotFactor)
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

--- Handles free camera mode
---@param unitID number Unit ID
---@return table directionState Camera direction and rotation state
local function handleFreeCameraMode(unitID)
    -- Get the current unit heading to detect rotation
    local unitHeading = Spring.GetUnitHeading(unitID, true)
    local camState = Spring.GetCameraState()

    -- Initialize free camera state if needed
    if STATE.tracking.freeCam.lastMouseX == nil or
            STATE.tracking.freeCam.targetRx == nil or
            STATE.tracking.freeCam.targetRy == nil then
        -- Initialize with current camera rotation on first frame
        STATE.tracking.freeCam.targetRx = camState.rx
        STATE.tracking.freeCam.targetRy = camState.ry
        STATE.tracking.freeCam.lastMouseX, STATE.tracking.freeCam.lastMouseY = Spring.GetMouseState()
        STATE.tracking.freeCam.lastUnitHeading = unitHeading
    else
        -- Handle unit rotation
        if STATE.tracking.freeCam.lastUnitHeading ~= nil then
            local headingDiff = unitHeading - STATE.tracking.freeCam.lastUnitHeading

            -- Only adjust if the heading difference is significant
            if math.abs(headingDiff) > 0.01 then
                -- Calculate how much the unit has rotated
                headingDiff = Util.normalizeAngle(headingDiff)

                -- Invert the heading difference for correct rotation
                headingDiff = -headingDiff

                -- Adjust the target rotation to maintain relative orientation
                STATE.tracking.freeCam.targetRy = Util.normalizeAngle(STATE.tracking.freeCam.targetRy + headingDiff)
            end
        end

        -- Update the last heading for next frame
        STATE.tracking.freeCam.lastUnitHeading = unitHeading

        -- Process mouse movement
        local mouseX, mouseY = Spring.GetMouseState()

        -- Only update if mouse has moved
        if mouseX ~= STATE.tracking.freeCam.lastMouseX or mouseY ~= STATE.tracking.freeCam.lastMouseY then
            -- Calculate delta movement
            local deltaX = mouseX - STATE.tracking.freeCam.lastMouseX
            local deltaY = mouseY - STATE.tracking.freeCam.lastMouseY

            -- Update target rotations based on mouse movement
            STATE.tracking.freeCam.targetRy = STATE.tracking.freeCam.targetRy + deltaX * STATE.tracking.freeCam.mouseMoveSensitivity
            STATE.tracking.freeCam.targetRx = STATE.tracking.freeCam.targetRx - deltaY * STATE.tracking.freeCam.mouseMoveSensitivity

            -- Normalize yaw angle
            STATE.tracking.freeCam.targetRy = Util.normalizeAngle(STATE.tracking.freeCam.targetRy)

            -- Remember mouse position for next frame
            STATE.tracking.freeCam.lastMouseX = mouseX
            STATE.tracking.freeCam.lastMouseY = mouseY
        end
    end

    -- Create smoothed camera direction state
    local smoothFactor = CONFIG.SMOOTHING.FREE_CAMERA_FACTOR
    local rx = Util.smoothStep(STATE.tracking.lastRotation.rx, STATE.tracking.freeCam.targetRx, smoothFactor)
    local ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, STATE.tracking.freeCam.targetRy, smoothFactor)

    -- Calculate direction vector from rotation angles
    local cosRx = math.cos(rx)
    local dx = math.sin(ry) * cosRx
    local dz = math.cos(ry) * cosRx
    local dy = math.sin(rx)

    -- Create camera direction state
    local directionState = {
        dx = dx,
        dy = dy,
        dz = dz,
        rx = rx,
        ry = ry,
        rz = 0
    }

    return directionState
end

--- Applies the camera state and updates tracking state
---@param camPos table Camera position {x, y, z}
---@param directionState table Camera direction and rotation state
local function applyCameraState(camPos, directionState)
    -- Create complete camera state
    local camStatePatch = BaseCameraMode.createCameraState(camPos, directionState)

    -- Apply the camera state
    Spring.SetCameraState(camStatePatch, 0)

    -- Update tracking state for next frame
    BaseCameraMode.updateTrackingState(camStatePatch)
end

--- Toggles FPS camera attached to a unit
function FPSCamera.toggle()
    if not STATE.enabled then
        Util.debugEcho("TURBOBARCAM must be enabled first")
        return
    end

    local unitID
    local selectedUnits = Spring.GetSelectedUnits()

    if #selectedUnits > 0 then
        unitID = selectedUnits[1]
    else
        Util.debugEcho("No unit selected for FPS view")
        return
    end

    -- Check if it's a valid unit
    if not Spring.ValidUnitID(unitID) then
        Util.debugEcho("Invalid unit ID for FPS view")
        return
    end

    -- If we're already tracking this exact unit in FPS mode or fixed point mode, turn it off
    if (STATE.tracking.mode == 'fps' or STATE.tracking.mode == 'fixed_point') and STATE.tracking.unitID == unitID then
        -- Save current offsets before disabling
        STATE.tracking.unitOffsets[unitID] = {
            height = CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT,
            forward = CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD,
            side = CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE,
            rotation = CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION
        }

        -- Make sure fixed point tracking is cleared when turning off FPS camera
        STATE.tracking.fixedPoint = nil
        STATE.tracking.targetUnitID = nil

        Util.disableTracking()
        Util.debugEcho("FPS camera detached")
        return
    end

    -- Otherwise we're either starting fresh or switching units
    Util.debugEcho("FPS camera attached to unit " .. unitID)

    -- Clear any existing fixed point tracking when starting a new FPS camera
    STATE.tracking.fixedPoint = nil
    STATE.tracking.targetUnitID = nil

    -- Check if we have stored offsets for this unit
    if STATE.tracking.unitOffsets[unitID] then
        -- Use stored offsets
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

    -- Begin mode transition from previous mode to FPS mode
    BaseCameraMode.beginModeTransition(STATE.tracking.mode, 'fps')
    STATE.tracking.unitID = unitID
    STATE.tracking.inFreeCameraMode = false

    -- Switch to FPS camera mode - this will smoothly transition now
    local camStatePatch = {
        name = "fps",
        mode = 0  -- FPS camera mode
    }

    -- Select unit again to reload its commands
    Spring.SelectUnitArray({unitID})
    Spring.SetCameraState(camStatePatch, 0)
end

--- Updates the FPS camera position and orientation
function FPSCamera.update()
    -- Skip update if conditions aren't met
    if not shouldUpdateFPSCamera() then
        return
    end

    -- Get current camera state and ensure it's in FPS mode
    local camState = Spring.GetCameraState()
    camState = BaseCameraMode.ensureFPSMode(camState)

    -- Get unit position and vectors
    local unitPos, front, up, right = getUnitVectors(STATE.tracking.unitID)

    -- Apply offsets to get camera position
    local camPos = applyFPSOffsets(unitPos, front, up, right)

    -- Determine smoothing factors
    local posFactor = BaseCameraMode.getSmoothingFactor(STATE.tracking.modeTransition, 'position')
    local rotFactor = BaseCameraMode.getSmoothingFactor(STATE.tracking.modeTransition, 'rotation')

    -- If this is the first update, initialize last positions
    if STATE.tracking.lastCamPos.x == 0 and STATE.tracking.lastCamPos.y == 0 and STATE.tracking.lastCamPos.z == 0 then
        STATE.tracking.lastCamPos = { x = camPos.x, y = camPos.y, z = camPos.z }
        STATE.tracking.lastCamDir = { x = front[1], y = front[2], z = front[3] }
        STATE.tracking.lastRotation = {
            rx = 1.8,
            ry = -(Spring.GetUnitHeading(STATE.tracking.unitID, true) + math.pi),
            rz = 0
        }
    end

    -- Check for mode transition completion
    if STATE.tracking.modeTransition and BaseCameraMode.isTransitionComplete(STATE.tracking.transitionStartTime) then
        STATE.tracking.modeTransition = false
    end

    -- Smooth camera position
    local smoothedPos = {
        x = Util.smoothStep(STATE.tracking.lastCamPos.x, camPos.x, posFactor),
        y = Util.smoothStep(STATE.tracking.lastCamPos.y, camPos.y, posFactor),
        z = Util.smoothStep(STATE.tracking.lastCamPos.z, camPos.z, posFactor)
    }

    -- Handle different camera orientation modes
    local directionState

    if STATE.tracking.mode == 'fixed_point' then
        -- Update fixed point if tracking a unit
        updateFixedPointTarget()

        -- Use base camera module to calculate direction to fixed point
        directionState = BaseCameraMode.focusOnPoint(
                smoothedPos,
                STATE.tracking.fixedPoint,
                STATE.tracking.lastCamDir,
                STATE.tracking.lastRotation,
                rotFactor,
                rotFactor
        )
    elseif not STATE.tracking.inFreeCameraMode then
        -- Normal FPS mode - follow unit orientation
        directionState = handleNormalFPSMode(STATE.tracking.unitID, rotFactor)
    else
        -- Free camera mode - controlled by mouse
        directionState = handleFreeCameraMode(STATE.tracking.unitID)
    end

    -- Apply camera state and update tracking for next frame
    applyCameraState(smoothedPos, directionState)
end

--- Checks if the fixed point command has been activated
function FPSCamera.checkFixedPointCommandActivation()
    if not STATE.enabled then
        return
    end

    -- Get the current active command
    local _, activeCmd = Spring.GetActiveCommand()

    -- Check if command state has changed
    if activeCmd ~= prevActiveCmd then
        -- Case 1: Command activated - entering target selection mode
        if activeCmd == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT then
            -- Only proceed if we're in FPS or fixed_point mode and have a unit to track
            if (STATE.tracking.mode == 'fps' or STATE.tracking.mode == 'fixed_point') and STATE.tracking.unitID then
                -- Store current state before switching to target selection mode
                STATE.tracking.inTargetSelectionMode = true
                STATE.tracking.prevFreeCamState = STATE.tracking.inFreeCameraMode

                -- Save the previous mode and fixed point for later restoration if canceled
                STATE.tracking.prevMode = STATE.tracking.mode
                STATE.tracking.prevFixedPoint = STATE.tracking.fixedPoint

                -- Temporarily switch to FPS mode during selection
                if STATE.tracking.mode == 'fixed_point' then
                    STATE.tracking.mode = 'fps'
                    STATE.tracking.fixedPoint = nil
                end

                -- Initialize free camera for target selection
                local camState = Spring.GetCameraState()
                STATE.tracking.freeCam.targetRx = camState.rx
                STATE.tracking.freeCam.targetRy = camState.ry
                STATE.tracking.freeCam.lastMouseX, STATE.tracking.freeCam.lastMouseY = Spring.GetMouseState()

                -- Initialize unit heading tracking
                if Spring.ValidUnitID(STATE.tracking.unitID) then
                    STATE.tracking.freeCam.lastUnitHeading = Spring.GetUnitHeading(STATE.tracking.unitID, true)
                end

                -- Always enable free camera mode during target selection
                STATE.tracking.inFreeCameraMode = true
                STATE.tracking.modeTransition = true
                STATE.tracking.transitionStartTime = Spring.GetTimer()

                Util.debugEcho("Target selection mode activated - select a target to look at")
            end
            -- Case 2: Command deactivated - exiting target selection mode without setting a point
        elseif prevActiveCmd == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT and STATE.tracking.inTargetSelectionMode then
            -- User canceled target selection, restore previous state
            STATE.tracking.inTargetSelectionMode = false

            -- Restore the previous mode and fixed point
            if STATE.tracking.prevMode == 'fixed_point' and STATE.tracking.prevFixedPoint then
                STATE.tracking.mode = 'fixed_point'
                STATE.tracking.fixedPoint = STATE.tracking.prevFixedPoint
                Util.debugEcho("Target selection canceled, returning to fixed point view")
            end

            -- Restore previous free camera state
            STATE.tracking.inFreeCameraMode = STATE.tracking.prevFreeCamState

            -- Start a transition to smoothly return to the previous state
            STATE.tracking.modeTransition = true
            STATE.tracking.transitionStartTime = Spring.GetTimer()

            if STATE.tracking.prevMode == 'fps' then
                Util.debugEcho("Target selection canceled, returning to unit view")
            end
        end
    end

    -- Store the current command for the next frame
    prevActiveCmd = activeCmd
end

--- Sets a fixed look point for the camera when following a unit
---@param cmdParams table|nil Command parameters
---@return boolean success Whether fixed point was set successfully
function FPSCamera.setFixedLookPoint(cmdParams)
    if not STATE.enabled then
        Util.debugEcho("TURBOBARCAM must be enabled first")
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

    local x, y, z
    -- Reset target unit ID before processing new input
    STATE.tracking.targetUnitID = nil

    -- Process different types of input
    if cmdParams then
        if #cmdParams == 1 then
            -- Clicked on a unit
            local unitID = cmdParams[1]
            if Spring.ValidUnitID(unitID) then
                -- Store the target unit ID for continuous tracking
                STATE.tracking.targetUnitID = unitID
                x, y, z = Spring.GetUnitPosition(unitID)
                Util.debugEcho("Camera will follow current unit but look at unit " .. unitID)
            end
        elseif #cmdParams == 3 then
            -- Clicked on ground/feature
            x, y, z = cmdParams[1], cmdParams[2], cmdParams[3]
        end
    else
        -- Legacy behavior - use current mouse position
        local _, pos = Spring.TraceScreenRay(Spring.GetMouseState(), true)
        if pos then
            x, y, z = pos[1], pos[2], pos[3]
        end
    end

    if not x or not y or not z then
        Util.debugEcho("Could not find a valid position")
        return false
    end

    -- Set the fixed point (always overrides previous point)
    STATE.tracking.fixedPoint = {
        x = x,
        y = y,
        z = z
    }

    -- We're no longer in target selection mode
    STATE.tracking.inTargetSelectionMode = false
    STATE.tracking.prevFixedPoint = nil -- Clear saved previous fixed point

    -- Switch to fixed point mode
    STATE.tracking.mode = 'fixed_point'

    -- Use the previous free camera state for normal operation
    STATE.tracking.inFreeCameraMode = STATE.tracking.prevFreeCamState

    -- If not in free camera mode, enable a transition to the fixed point
    if not STATE.tracking.inFreeCameraMode then
        -- Trigger a transition to smoothly move to the new view
        STATE.tracking.modeTransition = true
        STATE.tracking.transitionStartTime = Spring.GetTimer()
    end

    if not STATE.tracking.targetUnitID then
        Util.debugEcho("Camera will follow unit but look at fixed point")
    end

    return true
end

--- Clears fixed point tracking
function FPSCamera.clearFixedLookPoint()
    if not STATE.enabled then
        Util.debugEcho("TURBOBARCAM must be enabled first")
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

--- Toggles free camera mode
function FPSCamera.toggleFreeCam()
    if not STATE.enabled then
        Util.debugEcho("TURBOBARCAM must be enabled first")
        return
    end

    -- Only works if we're tracking a unit in FPS mode
    if (STATE.tracking.mode ~= 'fps' and STATE.tracking.mode ~= 'fixed_point') or not STATE.tracking.unitID then
        Util.debugEcho("Free camera only works when tracking a unit in FPS mode")
        return
    end

    -- Start a transition when toggling free camera
    STATE.tracking.modeTransition = true
    STATE.tracking.transitionStartTime = Spring.GetTimer()

    -- Toggle free camera mode
    STATE.tracking.inFreeCameraMode = not STATE.tracking.inFreeCameraMode

    -- If entering free cam mode and we have a fixed point, keep using the fixed point
    if STATE.tracking.inFreeCameraMode then
        -- Initialize with current camera state
        local camState = Spring.GetCameraState()
        STATE.tracking.freeCam.targetRx = camState.rx
        STATE.tracking.freeCam.targetRy = camState.ry
        STATE.tracking.freeCam.lastMouseX, STATE.tracking.freeCam.lastMouseY = Spring.GetMouseState()

        -- Initialize unit heading tracking
        if STATE.tracking.unitID and Spring.ValidUnitID(STATE.tracking.unitID) then
            STATE.tracking.freeCam.lastUnitHeading = Spring.GetUnitHeading(STATE.tracking.unitID, true)
        end

        Util.debugEcho("Free camera mode enabled - use mouse to rotate view")
    else
        -- Clear tracking data when disabling
        STATE.tracking.freeCam.lastMouseX = nil
        STATE.tracking.freeCam.lastMouseY = nil
        STATE.tracking.freeCam.targetRx = nil
        STATE.tracking.freeCam.targetRy = nil
        STATE.tracking.freeCam.lastUnitHeading = nil

        -- If we have a fixed point active, we need to explicitly clear it when disabling free cam
        if STATE.tracking.mode == 'fixed_point' then
            FPSCamera.clearFixedLookPoint()
        end

        Util.debugEcho("Free camera mode disabled - view follows unit orientation")
    end
end

--- Adjusts camera offset values
---@param offsetType string Type of offset to adjust: "height", "forward", or "side"
---@param amount number Amount to adjust the offset by
function FPSCamera.adjustOffset(offsetType, amount)
    if not STATE.enabled then
        Util.debugEcho("TURBOBARCAM must be enabled first")
        return
    end

    -- Make sure we have a unit to track
    if not STATE.tracking.unitID then
        Util.debugEcho("No unit being tracked")
        return
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

    -- Print the updated offsets
    Util.debugEcho("Camera offsets for unit " .. STATE.tracking.unitID .. ":")
    Util.debugEcho("  Height: " .. CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT)
    Util.debugEcho("  Forward: " .. CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD)
    Util.debugEcho("  Side: " .. CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE)
end

--- Adjusts the rotation offset
---@param amount number Rotation adjustment in radians
function FPSCamera.adjustRotationOffset(amount)
    if not STATE.enabled then
        Util.debugEcho("TURBOBARCAM must be enabled first")
        return
    end

    -- Make sure we have a unit to track
    if not STATE.tracking.unitID then
        Util.debugEcho("No unit being tracked")
        return
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
end

--- Resets camera offsets to default values
function FPSCamera.resetOffsets()
    if not STATE.enabled then
        Util.debugEcho("TURBOBARCAM must be enabled first")
        return
    end

    -- If we have a tracked unit, get its height for the default height offset
    if (STATE.tracking.mode == 'fps' or STATE.tracking.mode == 'fixed_point') and STATE.tracking.unitID and Spring.ValidUnitID(STATE.tracking.unitID) then
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
end

return {
    FPSCamera = FPSCamera
}