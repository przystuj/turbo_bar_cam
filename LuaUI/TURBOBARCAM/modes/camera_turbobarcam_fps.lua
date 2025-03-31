-- FPS Camera module for TURBOBARCAM
---@type {CONFIG: CONFIG, STATE: STATE}
local TurboConfig = VFS.Include("LuaUI/TURBOBARCAM/camera_turbobarcam_config.lua")
---@type {Util: Util}
local TurboUtils = VFS.Include("LuaUI/TURBOBARCAM/camera_turbobarcam_utils.lua")

local CONFIG = TurboConfig.CONFIG
local STATE = TurboConfig.STATE
local Util = TurboUtils.Util

local prevActiveCmd = nil

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

--- Toggles FPS camera attached to a unit
---@param unitID number|nil Optional unit ID (uses selected unit if nil)
function FPSCamera.toggle(unitID)
    if not STATE.enabled then
        Util.debugEcho("TURBOBARCAM must be enabled first")
        return
    end

    -- If no unitID provided, use the first selected unit
    if not unitID then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            unitID = selectedUnits[1]
        else
            Util.debugEcho("No unit selected for FPS view")
            return
        end
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
            height = CONFIG.FPS.HEIGHT_OFFSET,
            forward = CONFIG.FPS.FORWARD_OFFSET,
            side = CONFIG.FPS.SIDE_OFFSET,
            rotation = CONFIG.FPS.ROTATION_OFFSET
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
        CONFIG.FPS.HEIGHT_OFFSET = STATE.tracking.unitOffsets[unitID].height
        CONFIG.FPS.FORWARD_OFFSET = STATE.tracking.unitOffsets[unitID].forward
        CONFIG.FPS.SIDE_OFFSET = STATE.tracking.unitOffsets[unitID].side
        CONFIG.FPS.ROTATION_OFFSET = STATE.tracking.unitOffsets[unitID].rotation or 0 -- Add rotation

        Util.debugEcho("Using previous camera offsets for unit " .. unitID)
    else
        -- Get unit height for the default offset
        local unitHeight = Util.getUnitHeight(unitID)
        CONFIG.FPS.DEFAULT_HEIGHT_OFFSET = unitHeight
        CONFIG.FPS.HEIGHT_OFFSET = unitHeight
        CONFIG.FPS.FORWARD_OFFSET = CONFIG.FPS.DEFAULT_FORWARD_OFFSET
        CONFIG.FPS.SIDE_OFFSET = CONFIG.FPS.DEFAULT_SIDE_OFFSET
        CONFIG.FPS.ROTATION_OFFSET = CONFIG.FPS.DEFAULT_ROTATION_OFFSET -- Reset rotation

        -- Initialize storage for this unit
        STATE.tracking.unitOffsets[unitID] = {
            height = CONFIG.FPS.HEIGHT_OFFSET,
            forward = CONFIG.FPS.FORWARD_OFFSET,
            side = CONFIG.FPS.SIDE_OFFSET,
            rotation = CONFIG.FPS.ROTATION_OFFSET -- Add rotation
        }

        Util.debugEcho("Using new camera offsets for unit " .. unitID .. " with height: " .. unitHeight)
    end

    -- Begin mode transition from previous mode to FPS mode
    Util.beginModeTransition('fps')
    STATE.tracking.unitID = unitID
    STATE.tracking.inFreeCameraMode = false

    -- Switch to FPS camera mode - this will smoothly transition now
    local camStatePatch = {
        name = "fps",
        mode = 0  -- FPS camera mode
    }
    Spring.SetCameraState(camStatePatch, 0)
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

--- Updates the FPS camera position and orientation
function FPSCamera.update()
    if (STATE.tracking.mode ~= 'fps' and STATE.tracking.mode ~= 'fixed_point') or not STATE.tracking.unitID then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Util.debugEcho("Unit no longer exists, detaching FPS camera")
        Util.disableTracking()
        return
    end

    -- Get unit position and vectors
    local x, y, z = Spring.GetUnitPosition(STATE.tracking.unitID)
    local front, up, right = Spring.GetUnitVectors(STATE.tracking.unitID)

    -- Extract components from the vector tables
    local frontX, frontY, frontZ = front[1], front[2], front[3]
    local upX, upY, upZ = up[1], up[2], up[3]
    local rightX, rightY, rightZ = right[1], right[2], right[3]

    -- Store unit position for smoothing calculations
    STATE.tracking.lastUnitPos = { x = x, y = y, z = z }

    -- Apply height offset along the unit's up vector
    if CONFIG.FPS.HEIGHT_OFFSET ~= 0 then
        x = x + upX * CONFIG.FPS.HEIGHT_OFFSET
        y = y + upY * CONFIG.FPS.HEIGHT_OFFSET
        z = z + upZ * CONFIG.FPS.HEIGHT_OFFSET
    end

    -- Apply forward offset if needed
    if CONFIG.FPS.FORWARD_OFFSET ~= 0 then
        x = x + frontX * CONFIG.FPS.FORWARD_OFFSET
        y = y + frontY * CONFIG.FPS.FORWARD_OFFSET
        z = z + frontZ * CONFIG.FPS.FORWARD_OFFSET
    end

    -- Apply side offset if needed
    if CONFIG.FPS.SIDE_OFFSET ~= 0 then
        x = x + rightX * CONFIG.FPS.SIDE_OFFSET
        y = y + rightY * CONFIG.FPS.SIDE_OFFSET
        z = z + rightZ * CONFIG.FPS.SIDE_OFFSET
    end

    -- Get current camera state
    local camState = Spring.GetCameraState()

    -- Check if we're still in FPS mode
    if camState.mode ~= 0 then
        -- Force back to FPS mode
        camState.mode = 0
        camState.name = "fps"
    end

    -- Prepare camera state patch
    local camStatePatch = {
        mode = 0,
        name = "fps"
    }

    -- If this is the first update, initialize last positions
    if STATE.tracking.lastCamPos.x == 0 and STATE.tracking.lastCamPos.y == 0 and STATE.tracking.lastCamPos.z == 0 then
        STATE.tracking.lastCamPos = { x = x, y = y, z = z }
        STATE.tracking.lastCamDir = { x = frontX, y = frontY, z = frontZ }
        STATE.tracking.lastRotation = {
            rx = 1.8,
            ry = -(Spring.GetUnitHeading(STATE.tracking.unitID, true) + math.pi),
            rz = 0
        }
    end

    -- Determine smoothing factor based on whether we're in a mode transition
    local posFactor = CONFIG.SMOOTHING.FPS_FACTOR
    local rotFactor = CONFIG.SMOOTHING.ROTATION_FACTOR

    if STATE.tracking.modeTransition then
        -- Use a special transition factor during mode changes
        posFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR
        rotFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR

        -- Check if we should end the transition (after ~1 second)
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.transitionStartTime)
        if elapsed > 1.0 then
            STATE.tracking.modeTransition = false
        end
    end

    -- Smooth camera position
    camStatePatch.px = Util.smoothStep(STATE.tracking.lastCamPos.x, x, posFactor)
    camStatePatch.py = Util.smoothStep(STATE.tracking.lastCamPos.y, y, posFactor)
    camStatePatch.pz = Util.smoothStep(STATE.tracking.lastCamPos.z, z, posFactor)

    -- Handle different cases for direction and rotation
    if STATE.tracking.mode == 'fixed_point' then
        -- Update fixed point if we're tracking a unit
        if STATE.tracking.targetUnitID and Spring.ValidUnitID(STATE.tracking.targetUnitID) then
            -- Get the current position of the target unit
            local targetX, targetY, targetZ = Spring.GetUnitPosition(STATE.tracking.targetUnitID)
            STATE.tracking.fixedPoint = {
                x = targetX,
                y = targetY,
                z = targetZ
            }
        end

        -- Fixed point tracking - look at the fixed point
        local lookDir = Util.calculateLookAtPoint(
                { x = camStatePatch.px, y = camStatePatch.py, z = camStatePatch.pz },
                STATE.tracking.fixedPoint
        )

        -- Apply the look direction with smoothing
        camStatePatch.dx = Util.smoothStep(STATE.tracking.lastCamDir.x, lookDir.dx, rotFactor)
        camStatePatch.dy = Util.smoothStep(STATE.tracking.lastCamDir.y, lookDir.dy, rotFactor)
        camStatePatch.dz = Util.smoothStep(STATE.tracking.lastCamDir.z, lookDir.dz, rotFactor)

        -- Apply rotation angles with smoothing
        camStatePatch.rx = Util.smoothStep(STATE.tracking.lastRotation.rx, lookDir.rx, rotFactor)
        camStatePatch.ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, lookDir.ry, rotFactor)
        camStatePatch.rz = Util.smoothStep(STATE.tracking.lastRotation.rz, lookDir.rz, rotFactor)
    elseif not STATE.tracking.inFreeCameraMode then
        -- Normal FPS mode - follow unit orientation
        -- Smooth direction vector
        camStatePatch.dx = Util.smoothStep(STATE.tracking.lastCamDir.x, frontX, rotFactor)
        camStatePatch.dy = Util.smoothStep(STATE.tracking.lastCamDir.y, frontY, rotFactor)
        camStatePatch.dz = Util.smoothStep(STATE.tracking.lastCamDir.z, frontZ, rotFactor)

        -- Calculate target rotations
        local targetRy = -(Spring.GetUnitHeading(STATE.tracking.unitID, true) + math.pi)

        -- Apply rotation offset
        targetRy = targetRy + CONFIG.FPS.ROTATION_OFFSET

        local targetRx = 1.8
        local targetRz = 0

        -- Smooth rotations
        camStatePatch.ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, targetRy, rotFactor)
        camStatePatch.rx = Util.smoothStep(STATE.tracking.lastRotation.rx, targetRx, rotFactor)
        camStatePatch.rz = Util.smoothStep(STATE.tracking.lastRotation.rz, targetRz, rotFactor)
    else
        -- Free camera mode
        -- Get the current unit heading to detect rotation
        local unitHeading = Spring.GetUnitHeading(STATE.tracking.unitID, true)

        -- Make sure all required states are initialized
        if STATE.tracking.freeCam.lastMouseX == nil or
                STATE.tracking.freeCam.targetRx == nil or
                STATE.tracking.freeCam.targetRy == nil then
            -- Initialize with current camera rotation on first frame
            STATE.tracking.freeCam.targetRx = camState.rx
            STATE.tracking.freeCam.targetRy = camState.ry
            STATE.tracking.freeCam.lastMouseX, STATE.tracking.freeCam.lastMouseY = Spring.GetMouseState()
            STATE.tracking.freeCam.lastUnitHeading = unitHeading
        else
            -- Check if unit has changed orientation
            if STATE.tracking.freeCam.lastUnitHeading ~= nil then
                local headingDiff = unitHeading - STATE.tracking.freeCam.lastUnitHeading

                -- Only adjust if the heading difference is significant (avoid tiny adjustments)
                if math.abs(headingDiff) > 0.01 then
                    -- Calculate how much the unit has rotated
                    headingDiff = Util.normalizeAngle(headingDiff)

                    -- Invert the heading difference to rotate in the correct direction
                    -- When the unit turns right (positive heading change),
                    -- the camera needs to rotate left (negative adjustment) to maintain relative position
                    headingDiff = -headingDiff

                    -- Adjust the target rotation to maintain relative orientation to the unit
                    STATE.tracking.freeCam.targetRy = Util.normalizeAngle(STATE.tracking.freeCam.targetRy + headingDiff)
                end
            end

            -- Update the last heading for next frame
            STATE.tracking.freeCam.lastUnitHeading = unitHeading

            -- Get current mouse position
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

            -- Smoothly interpolate current camera rotation toward target rotation
            -- Add safety checks to prevent nil access
            if STATE.tracking.lastRotation and STATE.tracking.lastRotation.rx and
                    STATE.tracking.freeCam.targetRx and CONFIG.SMOOTHING.FREE_CAMERA_FACTOR then
                camStatePatch.rx = Util.smoothStep(STATE.tracking.lastRotation.rx, STATE.tracking.freeCam.targetRx, CONFIG.SMOOTHING.FREE_CAMERA_FACTOR)
            else
                camStatePatch.rx = camState.rx
            end

            if STATE.tracking.lastRotation and STATE.tracking.lastRotation.ry and
                    STATE.tracking.freeCam.targetRy and CONFIG.SMOOTHING.FREE_CAMERA_FACTOR then
                camStatePatch.ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, STATE.tracking.freeCam.targetRy, CONFIG.SMOOTHING.FREE_CAMERA_FACTOR)
            else
                camStatePatch.ry = camState.ry
            end

            -- Calculate direction vector from rotation angles
            local cosRx = math.cos(camStatePatch.rx)
            camStatePatch.dx = math.sin(camStatePatch.ry) * cosRx
            camStatePatch.dz = math.cos(camStatePatch.ry) * cosRx
            camStatePatch.dy = math.sin(camStatePatch.rx)
        end
    end

    -- Update last rotation values
    STATE.tracking.lastRotation.rx = camStatePatch.rx
    STATE.tracking.lastRotation.ry = camStatePatch.ry
    STATE.tracking.lastRotation.rz = camStatePatch.rz

    -- Update last direction values
    STATE.tracking.lastCamDir.x = camStatePatch.dx
    STATE.tracking.lastCamDir.y = camStatePatch.dy
    STATE.tracking.lastCamDir.z = camStatePatch.dz

    -- Update last camera position
    STATE.tracking.lastCamPos.x = camStatePatch.px
    STATE.tracking.lastCamPos.y = camStatePatch.py
    STATE.tracking.lastCamPos.z = camStatePatch.pz

    Spring.SetCameraState(camStatePatch, 0)
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
    CONFIG.FPS.ROTATION_OFFSET = (CONFIG.FPS.ROTATION_OFFSET + amount) % (2 * math.pi)
    if CONFIG.FPS.ROTATION_OFFSET > math.pi then
        CONFIG.FPS.ROTATION_OFFSET = CONFIG.FPS.ROTATION_OFFSET - 2 * math.pi
    end

    -- Update stored offsets for the current unit
    if STATE.tracking.unitID then
        if not STATE.tracking.unitOffsets[STATE.tracking.unitID] then
            STATE.tracking.unitOffsets[STATE.tracking.unitID] = {}
        end

        STATE.tracking.unitOffsets[STATE.tracking.unitID].rotation = CONFIG.FPS.ROTATION_OFFSET
    end

    -- Print the updated offsets with rotation in degrees for easier understanding
    local rotationDegrees = math.floor(CONFIG.FPS.ROTATION_OFFSET * 180 / math.pi)
    Util.debugEcho("Camera rotation offset for unit " .. STATE.tracking.unitID .. ": " .. rotationDegrees .. "°")
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
        CONFIG.FPS.HEIGHT_OFFSET = CONFIG.FPS.HEIGHT_OFFSET + amount
    elseif offsetType == "forward" then
        CONFIG.FPS.FORWARD_OFFSET = CONFIG.FPS.FORWARD_OFFSET + amount
    elseif offsetType == "side" then
        CONFIG.FPS.SIDE_OFFSET = CONFIG.FPS.SIDE_OFFSET + amount
    end

    -- Update stored offsets for the current unit
    if STATE.tracking.unitID then
        if not STATE.tracking.unitOffsets[STATE.tracking.unitID] then
            STATE.tracking.unitOffsets[STATE.tracking.unitID] = {}
        end

        STATE.tracking.unitOffsets[STATE.tracking.unitID] = {
            height = CONFIG.FPS.HEIGHT_OFFSET,
            forward = CONFIG.FPS.FORWARD_OFFSET,
            side = CONFIG.FPS.SIDE_OFFSET,
            rotation = CONFIG.FPS.ROTATION_OFFSET
        }
    end

    -- Print the updated offsets
    Util.debugEcho("Camera offsets for unit " .. STATE.tracking.unitID .. ":")
    Util.debugEcho("  Height: " .. CONFIG.FPS.HEIGHT_OFFSET)
    Util.debugEcho("  Forward: " .. CONFIG.FPS.FORWARD_OFFSET)
    Util.debugEcho("  Side: " .. CONFIG.FPS.SIDE_OFFSET)
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
        CONFIG.FPS.DEFAULT_HEIGHT_OFFSET = unitHeight
        CONFIG.FPS.HEIGHT_OFFSET = unitHeight
        CONFIG.FPS.FORWARD_OFFSET = CONFIG.FPS.DEFAULT_FORWARD_OFFSET
        CONFIG.FPS.SIDE_OFFSET = CONFIG.FPS.DEFAULT_SIDE_OFFSET
        CONFIG.FPS.ROTATION_OFFSET = CONFIG.FPS.DEFAULT_ROTATION_OFFSET -- Reset rotation

        -- Update stored offsets for this unit
        STATE.tracking.unitOffsets[STATE.tracking.unitID] = {
            height = CONFIG.FPS.HEIGHT_OFFSET,
            forward = CONFIG.FPS.FORWARD_OFFSET,
            side = CONFIG.FPS.SIDE_OFFSET,
            rotation = CONFIG.FPS.ROTATION_OFFSET -- Include rotation
        }

        Util.debugEcho("Reset camera offsets for unit " .. STATE.tracking.unitID .. " to defaults")
    else
        CONFIG.FPS.HEIGHT_OFFSET = CONFIG.FPS.DEFAULT_HEIGHT_OFFSET
        CONFIG.FPS.FORWARD_OFFSET = CONFIG.FPS.DEFAULT_FORWARD_OFFSET
        CONFIG.FPS.SIDE_OFFSET = CONFIG.FPS.DEFAULT_SIDE_OFFSET
        CONFIG.FPS.ROTATION_OFFSET = CONFIG.FPS.DEFAULT_ROTATION_OFFSET -- Reset rotation
        Util.debugEcho("FPS camera offsets reset to defaults")
    end
end

return {
    FPSCamera = FPSCamera
}