---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons
local TrackingManager = CommonModules.TrackingManager
---@type RotationUtils
local RotationUtils = VFS.Include("LuaUI/TurboBarCam/features/overview/rotation_utils.lua").RotationUtils
---@type OverviewCameraUtils
local OverviewCameraUtils = VFS.Include("LuaUI/TurboBarCam/features/overview/overview_utils.lua").OverviewCameraUtils

---@class MovementUtils
local MovementUtils = {}

-- Calculate an appropriate distance factor based on camera height
-- to maintain a ~45-degree viewing angle
---@param height number Current camera height
---@return number distanceFactor The calculated distance factor
local function calculateDistanceFactorFromHeight(height)
    -- Base factor for a ~45-degree angle (tan(45°) = 1.0)
    local baseFactor = 1

    -- Scale slightly based on height levels (higher = further back for better overview)
    if height > 3000 then
        baseFactor = 0.85
    elseif height > 1500 then
        baseFactor = 0.82
    elseif height < 800 then
        baseFactor = 0.75
    end

    return baseFactor
end

-- New function to separate the movement logic for cleaner code organization
-- Updated function to respect targetHeight when set
function MovementUtils.startMoveToTarget(targetPoint)
    -- Cancel rotation mode if it's active
    RotationUtils.cancelRotation("movement")

    -- Get current camera state and height
    local currentCamState = CameraManager.getCameraState("MovementUtils.startMoveToTarget")

    -- Use STATE.overview.targetHeight if it's set, otherwise calculate current height
    local currentHeight
    if STATE.overview.targetHeight then
        currentHeight = STATE.overview.targetHeight
        Log.debug(string.format("Using target height: %.1f for move operation", currentHeight))
    else
        currentHeight = OverviewCameraUtils.calculateCurrentHeight()
    end

    -- Calculate base distance factor based on current height
    local baseFactor = calculateDistanceFactorFromHeight(currentHeight)

    -- Get map dimensions
    local mapX = Game.mapSizeX
    local mapZ = Game.mapSizeZ

    -- Calculate an appropriate camera position to view the target from
    local targetCamPos = OverviewCameraUtils.calculateCameraPosition(
            targetPoint,
            currentHeight,
            mapX,
            mapZ,
            currentCamState,
            baseFactor
    )

    -- Calculate movement distance
    local moveDistance = math.sqrt(
            (targetCamPos.x - currentCamState.px) ^ 2 +
                    (targetCamPos.z - currentCamState.pz) ^ 2
    )

    -- Store current camera position as starting point for transition
    STATE.overview.fixedCamPos = {
        x = currentCamState.px,
        y = currentCamState.py,
        z = currentCamState.pz
    }

    -- Store target position for smooth transition
    STATE.overview.targetCamPos = targetCamPos

    -- Store the target point
    STATE.overview.targetPoint = targetPoint

    -- IMPORTANT: Also store as lastTargetPoint for future rotation reference
    STATE.overview.lastTargetPoint = targetPoint
    Log.debug(string.format("Stored last target point at (%.1f, %.1f)", targetPoint.x, targetPoint.z))

    -- Calculate look direction
    local lookDir = CameraCommons.calculateCameraDirectionToThePoint(targetCamPos, targetPoint)

    -- Set rotation targets
    STATE.overview.targetRx = lookDir.rx
    STATE.overview.targetRy = lookDir.ry

    -- Reset user control tracking flags
    STATE.overview.userLookedAround = false

    -- Reset transition tracking variables
    STATE.overview.stuckFrameCount = 0
    STATE.overview.initialMoveDistance = moveDistance
    STATE.overview.lastTransitionDistance = moveDistance

    -- Adapt transition factor based on movement distance
    local distanceBasedFactor
    if moveDistance < 500 then
        distanceBasedFactor = CONFIG.CAMERA_MODES.OVERVIEW.TRANSITION_FACTOR * 1.5
    elseif moveDistance < 2000 then
        distanceBasedFactor = CONFIG.CAMERA_MODES.OVERVIEW.TRANSITION_FACTOR
    else
        distanceBasedFactor = CONFIG.CAMERA_MODES.OVERVIEW.TRANSITION_FACTOR * 0.7
    end
    STATE.overview.currentTransitionFactor = distanceBasedFactor

    -- Begin mode transition for smooth movement
    STATE.tracking.isModeTransitionInProgress = true
    STATE.tracking.transitionStartTime = Spring.GetTimer()

    -- Update tracking state
    TrackingManager.updateTrackingState(currentCamState)

    Log.debug(string.format("Starting move to target. Initial Distance: %.1f", moveDistance))
end

--- Checks if a transition has made enough progress or should be considered completed.
---@param currentDistance number Current distance to target position (x, z plane).
---@param initialDistance number Initial distance to target position when move started.
---@return boolean isComplete Whether the transition should be completed.
function MovementUtils.checkTransitionProgress(currentDistance, initialDistance)
    -- If initial distance was extremely small, apply a minimum transition time
    if initialDistance and initialDistance < 100 then
        -- Ensure even small movements have a minimum transition duration
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.transitionStartTime)
        if elapsed < 0.25 then  -- Minimum 0.25 seconds for small movements
            return false
        end
    end

    -- If we're very close to the target position, consider transition complete
    if currentDistance < 20 then
        -- Threshold for closeness
        Log.trace("Transition complete: Very close to target.")
        return true
    end

    -- If we've completed at least 98% of the journey, also consider it complete
    -- Ensure initialDistance is valid and positive before division
    if initialDistance and initialDistance > 0 and currentDistance < (initialDistance * 0.02) then
        Log.debug("Transition complete: Reached 98% of distance.")
        return true
    end

    -- If we're not making significant progress anymore, consider it complete
    -- This prevents getting stuck if smoothStep approaches target asymptotically
    -- Ensure lastTransitionDistance exists before comparing
    if STATE.overview.lastTransitionDistance and
            math.abs(STATE.overview.lastTransitionDistance - currentDistance) < 0.5 then
        -- Threshold for progress stall
        STATE.overview.stuckFrameCount = (STATE.overview.stuckFrameCount or 0) + 1
        if STATE.overview.stuckFrameCount > 5 then
            -- Number of frames threshold for being stuck
            Log.debug("Transition complete: Stuck (no progress).")
            return true
        end
    else
        -- Reset stuck count if progress is made
        STATE.overview.stuckFrameCount = 0
    end

    -- Note: STATE.overview.lastTransitionDistance is updated in handleModeTransition *after* this check

    return false -- Transition not yet complete
end

--- Updates the camera's position and target rotation during a movement transition.
--- Modifies STATE.overview.fixedCamPos and STATE.overview.targetRx/Ry.
---@param camState table The current camera state (used for current height).
---@param smoothFactor number The smoothing factor for position interpolation.
---@param rotFactor number The smoothing factor for rotation interpolation (unused here, handled in handleModeTransition).
---@param userControllingView boolean Whether the user is manually rotating the view.
---@return boolean success Whether updates were made.
function MovementUtils.updateTransition(camState, smoothFactor, rotFactor, userControllingView)
    -- Ensure we have a target position to move towards
    if not STATE.overview.targetCamPos then
        Log.debug("UpdateTransition called without targetCamPos")
        return false -- Indicate nothing happened
    end

    -- Smoothly interpolate position (X and Z) towards the target
    -- The source is the current STATE.overview.fixedCamPos from the previous frame
    STATE.overview.fixedCamPos.x = CameraCommons.smoothStep(
            STATE.overview.fixedCamPos.x,
            STATE.overview.targetCamPos.x,
            smoothFactor
    )
    STATE.overview.fixedCamPos.z = CameraCommons.smoothStep(
            STATE.overview.fixedCamPos.z,
            STATE.overview.targetCamPos.z,
            smoothFactor
    )
    -- Note: Y position (height) is handled separately by the zoom logic in TurboOverviewCamera.update

    -- Update rotation target ONLY if moving towards a target point and user is not interfering
    if STATE.overview.targetPoint and not userControllingView and not STATE.overview.isRotationModeActive then
        -- Calculate current look direction from the *newly calculated intermediate* position
        -- to the target point. Use the actual current camera height for the calculation.
        local currentIntermediatePos = {
            x = STATE.overview.fixedCamPos.x, -- Use the just-calculated X
            y = camState.py, -- Use current actual height from camState
            z = STATE.overview.fixedCamPos.z  -- Use the just-calculated Z
        }

        local lookDir = CameraCommons.calculateCameraDirectionToThePoint(
                currentIntermediatePos,
                STATE.overview.targetPoint
        )

        -- Update the target rotation angles. The actual smoothing/application happens in handleModeTransition.
        STATE.overview.targetRx = lookDir.rx
        STATE.overview.targetRy = lookDir.ry
    end

    return true -- Indicate that updates were made
end

function MovementUtils.moveToTarget()
    if Util.isModeDisabled("overview") then
        return false
    end

    -- Get cursor position to determine where to move
    local targetPoint = OverviewCameraUtils.getCursorWorldPosition()

    -- If targetPoint is nil, it means the click was outside the map and should be ignored
    if not targetPoint then
        Log.debug("Move target outside map boundaries - ignoring")
        return false
    end

    -- Start movement to the target point
    MovementUtils.startMoveToTarget(targetPoint)

    return true
end

return {
    MovementUtils = MovementUtils
}