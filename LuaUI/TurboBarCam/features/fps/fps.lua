---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua")
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
---@type FPSTargetingSmoothing
local FPSTargetingSmoothing = VFS.Include("LuaUI/TurboBarCam/features/fps/fps_targeting_smoothing.lua").FPSTargetingSmoothing

local CameraCommons = CommonModules.CameraCommons
local ModeManager = CommonModules.ModeManager

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
        Log.trace("Invalid unit ID for FPS view")
        return
    end

    -- If we're already tracking this exact unit in FPS mode, turn it off
    if STATE.mode.name == 'fps' and STATE.mode.unitID == unitID then
        -- Make sure fixed point tracking is cleared when turning off FPS camera
        STATE.mode.fps.fixedPoint = nil
        STATE.mode.fps.targetUnitID = nil
        STATE.mode.fps.isFixedPointActive = false
        -- Clear combat mode state as well
        STATE.mode.fps.combatModeEnabled = false
        STATE.mode.fps.forcedWeaponNumber = nil

        ModeManager.disableMode()
        Log.trace("FPS camera detached")

        -- Refresh units command bar to remove custom command
        selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            Spring.SelectUnitArray(selectedUnits)
        end
        return
    end

    -- Initialize the FPS camera
    if ModeManager.initializeMode('fps', unitID) then
        -- Clear any existing fixed point tracking when starting a new FPS camera
        STATE.mode.fps.fixedPoint = nil
        STATE.mode.fps.targetUnitID = nil
        STATE.mode.fps.isFixedPointActive = false
        -- Initialize combat mode state to false
        STATE.mode.fps.combatModeEnabled = false
        STATE.mode.fps.forcedWeaponNumber = nil

        FPSTargetingSmoothing.configure({
            rotationConstraint = true,
            targetPrediction = true,
            cloudBlendFactor = 0.9,
            maxRotationRate = 0.05,
            rotationDamping = 0.9
        })

        Log.trace("FPS camera attached to unit " .. unitID)
    end
end

--- Updates the FPS camera position and orientation
function FPSCamera.update()
    -- Skip update if conditions aren't met
    if not FPSCameraUtils.shouldUpdateFPSCamera() then
        return
    end

    -- Get unit position and vectors
    local unitPos, front, up, right = Util.getUnitVectors(STATE.mode.unitID)

    -- Apply offsets to get camera position
    local camPos = FPSCameraUtils.applyFPSOffsets(unitPos, front, up, right)

    -- Determine smoothing factors
    local posFactor = FPSCameraUtils.getSmoothingFactor('position')
    local rotFactor = FPSCameraUtils.getSmoothingFactor('rotation')

    -- If this is the first update, initialize last positions
    if STATE.mode.lastCamPos.x == 0 and STATE.mode.lastCamPos.y == 0 and STATE.mode.lastCamPos.z == 0 then
        STATE.mode.lastCamPos = { x = camPos.x, y = camPos.y, z = camPos.z }
        STATE.mode.lastCamDir = { x = front[1], y = front[2], z = front[3] }
        STATE.mode.lastRotation = {
            rx = 1.8,
            ry = -(Spring.GetUnitHeading(STATE.mode.unitID, true) + math.pi),
            rz = 0
        }
    end

    CameraCommons.handleModeTransition(posFactor, rotFactor)

    -- Apply smoothing with spherical interpolation for significant direction changes
    local center = { x = unitPos.x, y = unitPos.y, z = unitPos.z }
    local smoothedPos

    if CameraCommons.shouldUseSphericalInterpolation(STATE.mode.lastCamPos, camPos, center) then
        smoothedPos = CameraCommons.sphericalInterpolate(center, STATE.mode.lastCamPos, camPos, posFactor, true)
    else
        smoothedPos = {
            x = CameraCommons.smoothStep(STATE.mode.lastCamPos.x, camPos.x, posFactor),
            y = CameraCommons.smoothStep(STATE.mode.lastCamPos.y, camPos.y, posFactor),
            z = CameraCommons.smoothStep(STATE.mode.lastCamPos.z, camPos.z, posFactor)
        }
    end

    -- Handle different camera orientation modes
    local directionState

    if STATE.mode.fps.isFixedPointActive then
        -- Update fixed point if tracking a unit
        FPSCameraUtils.updateFixedPointTarget()

        -- Use base camera module to calculate direction to fixed point
        directionState = CameraCommons.focusOnPoint(
                smoothedPos,
                STATE.mode.fps.fixedPoint,
                rotFactor,
                rotFactor,
                1.8
        )
    elseif STATE.mode.fps.isFreeCameraActive then
        -- Free camera mode - controlled by mouse
        local rotation = FreeCam.updateMouseRotation(rotFactor)
        FreeCam.updateUnitHeadingTracking(STATE.mode.unitID)

        -- Create camera state for free camera mode
        directionState = FreeCam.createCameraState(
                smoothedPos,
                rotation,
                STATE.mode.lastCamDir,
                STATE.mode.lastRotation,
                rotFactor
        )
    else
        -- Normal FPS mode - follow unit orientation
        directionState = FPSCameraUtils.handleNormalFPSMode(STATE.mode.unitID, rotFactor)
    end

    -- Apply camera state and update tracking for next frame
    if directionState then
        local camStatePatch = FPSCameraUtils.createCameraState(smoothedPos, directionState)
        CameraManager.setCameraState(camStatePatch, 0, "FPSCamera.update")
        ModeManager.updateTrackingState(camStatePatch)
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
            if STATE.mode.name == 'fps' and STATE.mode.unitID then
                -- Store current state before switching to target selection mode
                STATE.mode.fps.inTargetSelectionMode = true
                STATE.mode.fps.prevFreeCamState = STATE.mode.fps.isFreeCameraActive

                -- Save the previous fixed point state for later restoration if canceled
                STATE.mode.fps.prevMode = STATE.mode.name
                STATE.mode.fps.prevFixedPoint = STATE.mode.fps.fixedPoint
                STATE.mode.fps.prevFixedPointActive = STATE.mode.fps.isFixedPointActive

                -- Temporarily disable fixed point during selection
                if STATE.mode.fps.isFixedPointActive then
                    STATE.mode.fps.isFixedPointActive = false
                    STATE.mode.fps.fixedPoint = nil
                end

                -- Initialize free camera for target selection
                local camState = CameraManager.getCameraState("FPSCamera.checkFixedPointCommandActivation")
                STATE.mode.fps.freeCam.targetRx = camState.rx
                STATE.mode.fps.freeCam.targetRy = camState.ry
                STATE.mode.fps.freeCam.lastMouseX, STATE.mode.fps.freeCam.lastMouseY = Spring.GetMouseState()

                -- Initialize unit heading tracking
                if Spring.ValidUnitID(STATE.mode.unitID) then
                    STATE.mode.fps.freeCam.lastUnitHeading = Spring.GetUnitHeading(STATE.mode.unitID, true)
                end

                -- Always enable free camera mode during target selection
                STATE.mode.fps.isFreeCameraActive = true
                STATE.mode.isModeTransitionInProgress = true
                STATE.mode.transitionStartTime = Spring.GetTimer()

                Log.trace("Target selection mode activated - select a target to look at")
            end
            -- Case 2: Command deactivated - exiting target selection mode without setting a point
        elseif prevActiveCmd == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT and STATE.mode.fps.inTargetSelectionMode then
            -- User canceled target selection, restore previous state
            STATE.mode.fps.inTargetSelectionMode = false

            -- Restore the previous fixed point state
            if STATE.mode.fps.prevFixedPointActive and STATE.mode.fps.prevFixedPoint then
                STATE.mode.fps.isFixedPointActive = true
                STATE.mode.fps.fixedPoint = STATE.mode.fps.prevFixedPoint
                Log.trace("Target selection canceled, returning to fixed point view")
            end

            -- Restore previous free camera state
            STATE.mode.fps.isFreeCameraActive = STATE.mode.fps.prevFreeCamState

            -- Start a transition to smoothly return to the previous state
            STATE.mode.isModeTransitionInProgress = true
            STATE.mode.transitionStartTime = Spring.GetTimer()

            if not STATE.mode.fps.prevFixedPointActive then
                Log.trace("Target selection canceled, returning to unit view")
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
    if Util.isModeDisabled("fps") then
        return
    end
    if not STATE.mode.unitID then
        Log.debug("No unit being tracked for fixed point camera")
        return false
    end

    local x, y, z
    -- Reset target unit ID before processing new input
    STATE.mode.fps.targetUnitID = nil

    -- Process different types of input
    if cmdParams then
        if #cmdParams == 1 then
            -- Clicked on a unit
            local unitID = cmdParams[1]
            if Spring.ValidUnitID(unitID) then
                -- Store the target unit ID for continuous tracking
                STATE.mode.fps.targetUnitID = unitID
                x, y, z = Spring.GetUnitPosition(unitID)
                Log.trace("Camera will follow current unit but look at unit " .. unitID)
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
        Log.trace("Could not find a valid position")
        return false
    end

    local fixedPoint = {
        x = x,
        y = y,
        z = z
    }

    return FPSCameraUtils.setFixedLookPoint(fixedPoint, STATE.mode.fps.targetUnitID)
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
    if STATE.mode.name ~= 'fps' or not STATE.mode.unitID then
        Log.debug("Free camera only works when tracking a unit in FPS mode")
        return
    end

    -- Toggle free camera mode
    FreeCam.toggle()

    -- If we have a fixed point active, we need to explicitly clear it when disabling free cam
    if not STATE.mode.fps.isFreeCameraActive and STATE.mode.fps.isFixedPointActive then
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
    if not STATE.mode.unitID or not Spring.ValidUnitID(STATE.mode.unitID) then
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

function FPSCamera.toggleCombatMode()
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled('fps') then
        return
    end

    FPSCombatMode.toggleCombatMode()
end

function FPSCamera.handleSelectNewUnit()
    FPSCombatMode.clearAttackingState()
end

return {
    FPSCamera = FPSCamera
}