---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log

---@type FreeCam
local FreeCam = VFS.Include("LuaUI/TurboBarCam/features/fps/fps_free_camera.lua").FreeCam
---@type FPSCameraUtils
local FPSCameraUtils = VFS.Include("LuaUI/TurboBarCam/features/fps/fps_utils.lua").FPSCameraUtils
---@type FPSCombatMode
local FPSCombatMode = VFS.Include("LuaUI/TurboBarCam/features/fps/fps_combat_mode.lua").FPSCombatMode
local CameraCommons = CommonModules.CameraCommons
local TrackingManager = CommonModules.TrackingManager

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
    action = 'turbobarcam_fps_set_fixed_look_point',
}

--- Toggles FPS camera attached to a unit
function FPSCamera.toggle()
    if Util.isTurboBarCamDisabled() then
        return
    end

    local unitID
    local selectedUnits = Spring.GetSelectedUnits()

    if #selectedUnits > 0 then
        unitID = selectedUnits[1]
    else
        Log.debug("No unit selected for FPS view")
        return
    end

    -- Check if it's a valid unit
    if not Spring.ValidUnitID(unitID) then
        Log.debug("Invalid unit ID for FPS view")
        return
    end

    -- If we're already tracking this exact unit in FPS mode, turn it off
    if STATE.tracking.mode == 'fps' and STATE.tracking.unitID == unitID then
        -- Make sure fixed point tracking is cleared when turning off FPS camera
        STATE.tracking.fps.fixedPoint = nil
        STATE.tracking.fps.targetUnitID = nil
        STATE.tracking.fps.isFixedPointActive = false

        TrackingManager.disableTracking()
        Log.debug("FPS camera detached")

        -- Refresh units command bar to remove custom command
        selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            Spring.SelectUnitArray(selectedUnits)
        end

        return
    end

    -- Initialize the FPS camera
    if TrackingManager.initializeTracking('fps', unitID) then
        -- Clear any existing fixed point tracking when starting a new FPS camera
        STATE.tracking.fps.fixedPoint = nil
        STATE.tracking.fps.targetUnitID = nil
        STATE.tracking.fps.isFixedPointActive = false

        Log.debug("FPS camera attached to unit " .. unitID)
    end
end

--- Updates the FPS camera position and orientation
function FPSCamera.update()
    -- Skip update if conditions aren't met
    if not FPSCameraUtils.shouldUpdateFPSCamera() then
        return
    end

    -- Get unit position and vectors
    local unitPos, front, up, right = FPSCameraUtils.getUnitVectors(STATE.tracking.unitID)

    -- Apply offsets to get camera position
    local camPos = FPSCameraUtils.applyFPSOffsets(unitPos, front, up, right)

    -- Determine smoothing factors
    local posFactor = FPSCameraUtils.getSmoothingFactor(STATE.tracking.isModeTransitionInProgress, 'position')
    local rotFactor = FPSCameraUtils.getSmoothingFactor(STATE.tracking.isModeTransitionInProgress, 'rotation')

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
    if STATE.tracking.isModeTransitionInProgress and CameraCommons.isTransitionComplete() then
        STATE.tracking.isModeTransitionInProgress = false
    end

    -- Smooth camera position
    local smoothedPos = {
        x = CameraCommons.smoothStep(STATE.tracking.lastCamPos.x, camPos.x, posFactor),
        y = CameraCommons.smoothStep(STATE.tracking.lastCamPos.y, camPos.y, posFactor),
        z = CameraCommons.smoothStep(STATE.tracking.lastCamPos.z, camPos.z, posFactor)
    }

    -- Handle different camera orientation modes
    local directionState

    if STATE.tracking.fps.isFixedPointActive then
        -- Update fixed point if tracking a unit
        FPSCameraUtils.updateFixedPointTarget()

        -- Use base camera module to calculate direction to fixed point
        directionState = CameraCommons.focusOnPoint(
                smoothedPos,
                STATE.tracking.fps.fixedPoint,
                rotFactor,
                rotFactor,
                1.8
        )
    elseif STATE.tracking.fps.isFreeCameraActive then
        -- Free camera mode - controlled by mouse
        local rotation = FreeCam.updateMouseRotation(rotFactor)
        FreeCam.updateUnitHeadingTracking(STATE.tracking.freeCam, STATE.tracking.unitID)

        -- Create camera state for free camera mode
        directionState = FreeCam.createCameraState(
                smoothedPos,
                rotation,
                STATE.tracking.lastCamDir,
                STATE.tracking.lastRotation,
                rotFactor
        )
    else
        -- Normal FPS mode - follow unit orientation
        directionState = FPSCameraUtils.handleNormalFPSMode(STATE.tracking.unitID, rotFactor)
    end

    -- Apply camera state and update tracking for next frame
    if directionState then
        local camStatePatch = FPSCameraUtils.createCameraState(smoothedPos, directionState)
        CameraManager.setCameraState(camStatePatch, 0, "FPSCamera.update")
        TrackingManager.updateTrackingState(camStatePatch)
    end
end

--- Checks if the fixed point command has been activated
function FPSCamera.checkFixedPointCommandActivation()
    if Util.isTurboBarCamDisabled() then
        return
    end

    -- Get the current active command
    local _, activeCmd = Spring.GetActiveCommand()

    -- Check if command state has changed
    if activeCmd ~= prevActiveCmd then
        -- Case 1: Command activated - entering target selection mode
        if activeCmd == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT then
            -- Only proceed if we're in FPS mode and have a unit to track
            if STATE.tracking.mode == 'fps' and STATE.tracking.unitID then
                -- Store current state before switching to target selection mode
                STATE.tracking.fps.inTargetSelectionMode = true
                STATE.tracking.fps.prevFreeCamState = STATE.tracking.fps.isFreeCameraActive

                -- Save the previous fixed point state for later restoration if canceled
                STATE.tracking.fps.prevMode = STATE.tracking.mode
                STATE.tracking.fps.prevFixedPoint = STATE.tracking.fps.fixedPoint
                STATE.tracking.fps.prevFixedPointActive = STATE.tracking.fps.isFixedPointActive

                -- Temporarily disable fixed point during selection
                if STATE.tracking.fps.isFixedPointActive then
                    STATE.tracking.fps.isFixedPointActive = false
                    STATE.tracking.fps.fixedPoint = nil
                end

                -- Initialize free camera for target selection
                local camState = CameraManager.getCameraState("FPSCamera.checkFixedPointCommandActivation")
                STATE.tracking.fps.freeCam.targetRx = camState.rx
                STATE.tracking.fps.freeCam.targetRy = camState.ry
                STATE.tracking.fps.freeCam.lastMouseX, STATE.tracking.fps.freeCam.lastMouseY = Spring.GetMouseState()

                -- Initialize unit heading tracking
                if Spring.ValidUnitID(STATE.tracking.unitID) then
                    STATE.tracking.fps.freeCam.lastUnitHeading = Spring.GetUnitHeading(STATE.tracking.unitID, true)
                end

                -- Always enable free camera mode during target selection
                STATE.tracking.fps.isFreeCameraActive = true
                STATE.tracking.isModeTransitionInProgress = true
                STATE.tracking.transitionStartTime = Spring.GetTimer()

                Log.debug("Target selection mode activated - select a target to look at")
            end
            -- Case 2: Command deactivated - exiting target selection mode without setting a point
        elseif prevActiveCmd == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT and STATE.tracking.fps.inTargetSelectionMode then
            -- User canceled target selection, restore previous state
            STATE.tracking.fps.inTargetSelectionMode = false

            -- Restore the previous fixed point state
            if STATE.tracking.fps.prevFixedPointActive and STATE.tracking.fps.prevFixedPoint then
                STATE.tracking.fps.isFixedPointActive = true
                STATE.tracking.fps.fixedPoint = STATE.tracking.fps.prevFixedPoint
                Log.debug("Target selection canceled, returning to fixed point view")
            end

            -- Restore previous free camera state
            STATE.tracking.fps.isFreeCameraActive = STATE.tracking.fps.prevFreeCamState

            -- Start a transition to smoothly return to the previous state
            STATE.tracking.isModeTransitionInProgress = true
            STATE.tracking.transitionStartTime = Spring.GetTimer()

            if not STATE.tracking.fps.prevFixedPointActive then
                Log.debug("Target selection canceled, returning to unit view")
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
    if Util.isTurboBarCamDisabled() then
        return
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

    local x, y, z
    -- Reset target unit ID before processing new input
    STATE.tracking.fps.targetUnitID = nil

    -- Process different types of input
    if cmdParams then
        if #cmdParams == 1 then
            -- Clicked on a unit
            local unitID = cmdParams[1]
            if Spring.ValidUnitID(unitID) then
                -- Store the target unit ID for continuous tracking
                STATE.tracking.fps.targetUnitID = unitID
                x, y, z = Spring.GetUnitPosition(unitID)
                Log.debug("Camera will follow current unit but look at unit " .. unitID)
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
        Log.debug("Could not find a valid position")
        return false
    end

    local fixedPoint = {
        x = x,
        y = y,
        z = z
    }

    return FPSCameraUtils.setFixedLookPoint(fixedPoint, STATE.tracking.fps.targetUnitID)
end

--- Clears fixed point tracking
function FPSCamera.clearFixedLookPoint()
    FPSCameraUtils.clearFixedLookPoint()
end

--- Toggles free camera mode
function FPSCamera.toggleFreeCam()
    if Util.isTurboBarCamDisabled() then
        return
    end

    -- Only works if we're tracking a unit in FPS mode
    if STATE.tracking.mode ~= 'fps' or not STATE.tracking.unitID then
        Log.debug("Free camera only works when tracking a unit in FPS mode")
        return
    end

    -- Toggle free camera mode
    FreeCam.toggle()

    -- If we have a fixed point active, we need to explicitly clear it when disabling free cam
    if not STATE.tracking.fps.isFreeCameraActive and STATE.tracking.fps.isFixedPointActive then
        FPSCameraUtils.clearFixedLookPoint()
    end
end

--- Cycles through unit's weapons
function FPSCamera.nextWeapon()
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled('fps') then
        return
    end
    if not STATE.tracking.unitID or not Spring.ValidUnitID(STATE.tracking.unitID) then
        Log.debug("No unit selected.")
        return
    end
    FPSCombatMode.nextWeapon()
end

--- Clear forced weapon
function FPSCamera.clearWeaponSelection()
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled('fps') then
        return
    end
    FPSCombatMode.clearWeaponSelection()
end

---@see ModifiableParams
---@see Util#adjustParams
function FPSCamera.adjustParams(params)
    FPSCameraUtils.adjustParams(params)
end

function FPSCamera.saveSettings(identifier)
    STATE.tracking.offsets.fps[identifier] = {
        height = CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT,
        forward = CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD,
        side = CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE,
        rotation = CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION
    }
end

function FPSCamera.saveWeaponSettings(unitId)
    FPSCombatMode.saveWeaponSettings(unitId)
end

function FPSCamera.loadSettings(identifier)
    if STATE.tracking.offsets.fps[identifier] then
        CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT = STATE.tracking.offsets.fps[identifier].height
        CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD = STATE.tracking.offsets.fps[identifier].forward
        CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE = STATE.tracking.offsets.fps[identifier].side
        CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION = STATE.tracking.offsets.fps[identifier].rotation
        Log.debug("[FPS] Using previous settings")
    else
        CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.HEIGHT
        CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.FORWARD
        CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.SIDE
        CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.ROTATION
        Log.debug("[FPS] Using default settings")
    end
    FPSCameraUtils.ensureHeightIsSet()
end

return {
    FPSCamera = FPSCamera
}