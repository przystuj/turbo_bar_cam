-- FPS Camera module for TURBOBARCAM
-- Load modules
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CoreModules
local TurboCore = VFS.Include("LuaUI/TURBOBARCAM/core.lua")
---@type CommonModules
local TurboCommons = VFS.Include("LuaUI/TURBOBARCAM/common.lua")

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE
---@type Util
local Util = TurboCommons.Util

---@type {FPSCameraUtils: FPSCameraUtils}
local FPSUtils = VFS.Include("LuaUI/TURBOBARCAM/features/fps/utils.lua")
local CameraCommons = TurboCore.CameraCommons
local FreeCam = TurboCore.FreeCam
local TrackingManager = TurboCommons.Tracking
local FPSCameraUtils = FPSUtils.FPSCameraUtils

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

    -- Initialize the FPS camera
    if TrackingManager.initializeTracking('fps', unitID) then
        -- Clear any existing fixed point tracking when starting a new FPS camera
        STATE.tracking.fixedPoint = nil
        STATE.tracking.targetUnitID = nil

        -- Load unit settings
        TrackingManager.loadUnitSettings('fps', unitID)
        
        Util.debugEcho("FPS camera attached to unit " .. unitID)
    end
end

--- Updates the FPS camera position and orientation
function FPSCamera.update()
    -- Skip update if conditions aren't met
    if not FPSCameraUtils.shouldUpdateFPSCamera() then
        return
    end

    -- Get current camera state and ensure it's in FPS mode
    local camState = Spring.GetCameraState()
    camState = CameraCommons.ensureFPSMode(camState)

    -- Get unit position and vectors
    local unitPos, front, up, right = FPSCameraUtils.getUnitVectors(STATE.tracking.unitID)

    -- Apply offsets to get camera position
    local camPos = FPSCameraUtils.applyFPSOffsets(unitPos, front, up, right)

    -- Determine smoothing factors
    local posFactor = CameraCommons.getSmoothingFactor(STATE.tracking.modeTransition, 'position')
    local rotFactor = CameraCommons.getSmoothingFactor(STATE.tracking.modeTransition, 'rotation')

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
    if STATE.tracking.modeTransition and CameraCommons.isTransitionComplete(STATE.tracking.transitionStartTime) then
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
        TrackingManager.updateFixedPointTarget()

        -- Use base camera module to calculate direction to fixed point
        directionState = CameraCommons.focusOnPoint(
                smoothedPos,
                STATE.tracking.fixedPoint,
                STATE.tracking.lastCamDir,
                STATE.tracking.lastRotation,
                rotFactor,
                rotFactor
        )
    elseif not STATE.tracking.inFreeCameraMode then
        -- Normal FPS mode - follow unit orientation
        directionState = FPSCameraUtils.handleNormalFPSMode(STATE.tracking.unitID, rotFactor)
    else
        -- Free camera mode - controlled by mouse
        local rotation = FreeCam.updateMouseRotation(STATE.tracking.freeCam, STATE.tracking.lastRotation, rotFactor)
        FreeCam.updateUnitHeadingTracking(STATE.tracking.freeCam, STATE.tracking.unitID)
        
        -- Create camera state for free camera mode
        directionState = FreeCam.createCameraState(
            smoothedPos, 
            rotation, 
            STATE.tracking.lastCamDir, 
            STATE.tracking.lastRotation, 
            rotFactor
        )
    end

    -- Apply camera state and update tracking for next frame
    local camStatePatch = CameraCommons.createCameraState(smoothedPos, directionState)
    Spring.SetCameraState(camStatePatch, 0)
    CameraCommons.updateTrackingState(camStatePatch)
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

    local fixedPoint = {
        x = x,
        y = y,
        z = z
    }

    return TrackingManager.setFixedLookPoint(fixedPoint, STATE.tracking.targetUnitID)
end

--- Clears fixed point tracking
function FPSCamera.clearFixedLookPoint()
    TrackingManager.clearFixedLookPoint()
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

    -- Toggle free camera mode
    FreeCam.toggle(STATE.tracking, "unit")

    -- If we have a fixed point active, we need to explicitly clear it when disabling free cam
    if not STATE.tracking.inFreeCameraMode and STATE.tracking.mode == 'fixed_point' then
        FPSCamera.clearFixedLookPoint()
    end
end

--- Adjusts camera offset values
---@param offsetType string Type of offset to adjust: "height", "forward", or "side"
---@param amount number Amount to adjust the offset by
function FPSCamera.adjustOffset(offsetType, amount)
    FPSCameraUtils.adjustOffset(offsetType, amount)
end

--- Adjusts the rotation offset
---@param amount number Rotation adjustment in radians
function FPSCamera.adjustRotationOffset(amount)
    FPSCameraUtils.adjustRotationOffset(amount)
end

--- Resets camera offsets to default values
function FPSCamera.resetOffsets()
    FPSCameraUtils.resetOffsets()
end

return {
    FPSCamera = FPSCamera
}