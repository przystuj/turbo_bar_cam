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
local CameraCommons = CommonModules.CameraCommons
local TrackingManager = CommonModules.TrackingManager

---@class UnitTrackingCamera
local UnitTrackingCamera = {}

--- Toggles tracking camera mode
---@return boolean success Always returns true for widget handler
function UnitTrackingCamera.toggle()
    if Util.isTurboBarCamDisabled() then
        return
    end

    -- Get the selected unit
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits == 0 then
        -- If no unit is selected and tracking is currently on, turn it off
        if STATE.tracking.mode == 'unit_tracking' then
            TrackingManager.disableTracking()
            Log.trace("Tracking Camera disabled")
        else
            Log.trace("No unit selected for Tracking Camera")
        end
        return
    end

    local selectedUnitID = selectedUnits[1]

    -- If we're already tracking this exact unit in tracking camera mode, turn it off
    if STATE.tracking.mode == 'unit_tracking' and STATE.tracking.unitID == selectedUnitID then
        TrackingManager.disableTracking()
        Log.trace("Tracking Camera disabled")
        return
    end

    -- Initialize the tracking system
    if TrackingManager.initializeTracking('unit_tracking', selectedUnitID) then
        -- Initialize velocity tracking for smooth deceleration
        UnitTrackingCamera.initializeVelocityTracking()
        Log.trace("Tracking Camera enabled. Camera will track unit " .. selectedUnitID)
    end
end

--- Initializes velocity tracking for smooth deceleration
function UnitTrackingCamera.initializeVelocityTracking()
    local currentState = CameraManager.getCameraState("UnitTrackingCamera.initializeVelocityTracking")

    -- Initialize velocity tracking state
    if not STATE.tracking.unitTracking then
        STATE.tracking.unitTracking = {}
    end

    STATE.tracking.unitTracking.lastPosition = {
        x = currentState.px,
        y = currentState.py,
        z = currentState.pz
    }

    STATE.tracking.unitTracking.velocity = { x = 0, y = 0, z = 0 }
    STATE.tracking.unitTracking.lastUpdateTime = Spring.GetTimer()
end

--- Calculates and updates camera velocity for smooth deceleration
function UnitTrackingCamera.updateVelocityTracking()
    if not STATE.tracking.unitTracking then
        return
    end

    local currentState = CameraManager.getCameraState("UnitTrackingCamera.updateVelocityTracking")
    local currentTime = Spring.GetTimer()
    local lastTime = STATE.tracking.unitTracking.lastUpdateTime or currentTime
    local deltaTime = Spring.DiffTimers(currentTime, lastTime)

    if deltaTime > 0 then
        local lastPos = STATE.tracking.unitTracking.lastPosition
        local currentPos = { x = currentState.px, y = currentState.py, z = currentState.pz }

        -- Calculate velocity
        STATE.tracking.unitTracking.velocity = {
            x = (currentPos.x - lastPos.x) / deltaTime,
            y = (currentPos.y - lastPos.y) / deltaTime,
            z = (currentPos.z - lastPos.z) / deltaTime
        }

        -- Update last position and time
        STATE.tracking.unitTracking.lastPosition = currentPos
        STATE.tracking.unitTracking.lastUpdateTime = currentTime
    end
end

--- Applies velocity decay during transition period
---@param currentPos table Current camera position
---@param transitionProgress number Transition progress (0-1)
---@return table decayedPos Position with velocity decay applied
function UnitTrackingCamera.applyVelocityDecay(currentPos, transitionProgress)
    if not STATE.tracking.unitTracking or not STATE.tracking.unitTracking.velocity then
        return currentPos
    end

    local velocity = STATE.tracking.unitTracking.velocity
    local deltaTime = Spring.DiffTimers(Spring.GetTimer(), STATE.tracking.unitTracking.lastUpdateTime or Spring.GetTimer())

    if deltaTime <= 0 then
        return currentPos
    end

    -- Calculate decay factor based on transition progress
    -- As transition progresses (0->1), we want more decay
    local decayFactor = 0.1 + (transitionProgress * 0.9) -- 0.1 to 1.0
    local decayRate = 0.1 * decayFactor -- Adjustable decay rate

    -- Apply exponential decay to velocity
    local decayMultiplier = math.exp(-decayRate * deltaTime)

    local decayedVelocity = {
        x = velocity.x * decayMultiplier,
        y = velocity.y * decayMultiplier,
        z = velocity.z * decayMultiplier
    }

    -- Apply the decayed velocity to position
    local decayedPos = {
        x = currentPos.x + (decayedVelocity.x * deltaTime),
        y = currentPos.y + (decayedVelocity.y * deltaTime),
        z = currentPos.z + (decayedVelocity.z * deltaTime)
    }

    -- Update velocity for next frame
    STATE.tracking.unitTracking.velocity = decayedVelocity

    return decayedPos
end

--- Updates tracking camera to point at the tracked unit
function UnitTrackingCamera.update()
    if STATE.tracking.mode ~= 'unit_tracking' or not STATE.tracking.unitID then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Log.trace("Tracked unit no longer exists, disabling Tracking Camera")
        TrackingManager.disableTracking()
        return
    end

    local currentState = CameraManager.getCameraState("UnitTrackingCamera.update")

    -- Get unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)

    -- Apply the target height offset from config
    local targetPos = {
        x = unitX,
        y = unitY + CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT,
        z = unitZ
    }

    -- Get current camera position
    local camPos = { x = currentState.px, y = currentState.py, z = currentState.pz }

    -- Determine smoothing factor based on whether we're in a mode transition
    local dirFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.TRACKING_FACTOR
    local rotFactor = CONFIG.CAMERA_MODES.UNIT_TRACKING.SMOOTHING.ROTATION_FACTOR

    dirFactor, rotFactor = CameraCommons.handleModeTransition(dirFactor, rotFactor)

    -- Initialize last values if needed
    if STATE.tracking.lastCamDir.x == 0 and STATE.tracking.lastCamDir.y == 0 and STATE.tracking.lastCamDir.z == 0 then
        local initialLookDir = CameraCommons.calculateCameraDirectionToThePoint(camPos, targetPos)
        STATE.tracking.lastCamDir = { x = initialLookDir.dx, y = initialLookDir.dy, z = initialLookDir.dz }
        STATE.tracking.lastRotation = { rx = initialLookDir.rx, ry = initialLookDir.ry, rz = 0 }
    end

    -- Use the focusOnPoint method to get camera direction state
    local camStatePatch = CameraCommons.focusOnPoint(camPos, targetPos, dirFactor, rotFactor)

    -- Handle position control based on transition state
    if STATE.tracking.isModeTransitionInProgress then
        -- During transition, gradually reduce position control and apply velocity decay
        local transitionProgress = CameraCommons.getTransitionProgress()

        Log.debug(transitionProgress)

        -- Update velocity tracking
        UnitTrackingCamera.updateVelocityTracking()

        -- Calculate position smoothing that decreases as transition progresses
        -- Start with normal smoothing, end with very low smoothing
        local positionSmoothingFactor = dirFactor * (1.0 - transitionProgress * 0.95) -- Keep 5% minimum

        -- Apply velocity decay to current position
        local decayedPos = UnitTrackingCamera.applyVelocityDecay(camPos, transitionProgress)

        -- Apply position smoothing between decayed position and current position
        camStatePatch.px = CameraCommons.smoothStep(decayedPos.x, camPos.x, positionSmoothingFactor)
        camStatePatch.py = CameraCommons.smoothStep(decayedPos.y, camPos.y, positionSmoothingFactor)
        camStatePatch.pz = CameraCommons.smoothStep(decayedPos.z, camPos.z, positionSmoothingFactor)

        -- Log transition progress occasionally
        if transitionProgress > 0 and math.random() < 0.05 then -- 5% chance to log
            Log.trace(string.format("Unit tracking transition: %.1f%% complete, pos_smooth=%.3f",
                    transitionProgress * 100, positionSmoothingFactor))
        end
    else
        -- After transition is complete, remove position updates to allow free camera movement
        camStatePatch.px, camStatePatch.py, camStatePatch.pz = nil, nil, nil

        -- Clean up velocity tracking state
        if STATE.tracking.unitTracking then
            STATE.tracking.unitTracking.velocity = nil
            STATE.tracking.unitTracking.lastPosition = nil
            STATE.tracking.unitTracking.lastUpdateTime = nil
        end
    end

    TrackingManager.updateTrackingState(camStatePatch)

    -- Apply camera state
    CameraManager.setCameraState(camStatePatch, 1, "UnitTrackingCamera.update")
end

---@see ModifiableParams
---@see Util#adjustParams
function UnitTrackingCamera.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("unit_tracking") then
        return
    end
    -- Make sure we have a unit to track
    if not STATE.tracking.unitID then
        Log.trace("No unit is tracked")
        return
    end

    Util.adjustParams(params, "UNIT_TRACKING", function() CONFIG.CAMERA_MODES.UNIT_TRACKING.HEIGHT = 0 end)
end

return {
    UnitTrackingCamera = UnitTrackingCamera
}