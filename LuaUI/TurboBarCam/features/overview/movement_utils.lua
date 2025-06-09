---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local CameraTracker = ModuleManager.CameraTracker(function(m) CameraTracker = m end)
local RotationUtils = ModuleManager.RotationUtils(function(m) RotationUtils = m end)
local OverviewCameraUtils = ModuleManager.OverviewCameraUtils(function(m) OverviewCameraUtils = m end)

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
    local currentCamState = Spring.GetCameraState()

    -- Use STATE.active.mode.overview.targetHeight if it's set, otherwise calculate current height
    local currentHeight
    if STATE.active.mode.overview.targetHeight then
        currentHeight = STATE.active.mode.overview.targetHeight
        Log:trace(string.format("Using target height: %.1f for move operation", currentHeight))
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
    STATE.active.mode.overview.fixedCamPos = {
        x = currentCamState.px,
        y = currentCamState.py,
        z = currentCamState.pz
    }

    -- Store target position for smooth transition
    STATE.active.mode.overview.targetCamPos = targetCamPos

    -- Store the target point
    STATE.active.mode.overview.targetPoint = targetPoint

    -- IMPORTANT: Also store as lastTargetPoint for future rotation reference
    STATE.active.mode.overview.lastTargetPoint = targetPoint
    Log:trace(string.format("Stored last target point at (%.1f, %.1f)", targetPoint.x, targetPoint.z))

    -- Calculate look direction
    local lookDir = CameraCommons.calculateCameraDirectionToThePoint(targetCamPos, targetPoint)

    -- Set rotation targets
    STATE.active.mode.overview.targetRx = lookDir.rx
    STATE.active.mode.overview.targetRy = lookDir.ry

    -- Reset user control tracking flags
    STATE.active.mode.overview.userLookedAround = false

    -- Reset transition tracking variables
    STATE.active.mode.overview.stuckFrameCount = 0
    STATE.active.mode.overview.initialMoveDistance = moveDistance
    STATE.active.mode.overview.lastTransitionDistance = moveDistance

    -- Adapt transition factor based on movement distance
    local distanceBasedFactor
    if moveDistance < 500 then
        distanceBasedFactor = CONFIG.CAMERA_MODES.OVERVIEW.TRANSITION_FACTOR * 1.5
    elseif moveDistance < 2000 then
        distanceBasedFactor = CONFIG.CAMERA_MODES.OVERVIEW.TRANSITION_FACTOR
    else
        distanceBasedFactor = CONFIG.CAMERA_MODES.OVERVIEW.TRANSITION_FACTOR * 0.7
    end
    STATE.active.mode.overview.currentTransitionFactor = distanceBasedFactor

    -- Begin mode transition for smooth movement
    STATE.active.mode.isModeTransitionInProgress = true
    STATE.active.mode.transitionStartTime = Spring.GetTimer()

    -- Update tracking state
    CameraTracker.updateLastKnownCameraState(currentCamState)

    Log:trace(string.format("Starting move to target. Initial Distance: %.1f", moveDistance))
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
        local elapsed = Spring.DiffTimers(now, STATE.active.mode.transitionStartTime)
        if elapsed < 0.25 then
            -- Minimum 0.25 seconds for small movements
            return false
        end
    end

    -- If we're very close to the target position, consider transition complete
    if currentDistance < 20 then
        -- Threshold for closeness
        Log:trace("Transition complete: Very close to target.")
        return true
    end

    -- If we've completed at least 98% of the journey, also consider it complete
    -- Ensure initialDistance is valid and positive before division
    if initialDistance and initialDistance > 0 and currentDistance < (initialDistance * 0.02) then
        Log:trace("Transition complete: Reached 98% of distance.")
        return true
    end

    -- If we're not making significant progress anymore, consider it complete
    -- This prevents getting stuck if smoothStep approaches target asymptotically
    -- Ensure lastTransitionDistance exists before comparing
    if STATE.active.mode.overview.lastTransitionDistance and
            math.abs(STATE.active.mode.overview.lastTransitionDistance - currentDistance) < 0.5 then
        -- Threshold for progress stall
        STATE.active.mode.overview.stuckFrameCount = (STATE.active.mode.overview.stuckFrameCount or 0) + 1
        if STATE.active.mode.overview.stuckFrameCount > 5 then
            -- Number of frames threshold for being stuck
            Log:trace("Transition complete: Stuck (no progress).")
            return true
        end
    else
        -- Reset stuck count if progress is made
        STATE.active.mode.overview.stuckFrameCount = 0
    end

    -- Note: STATE.active.mode.overview.lastTransitionDistance is updated in handleModeTransition *after* this check

    return false -- Transition not yet complete
end

--- Updates the camera's position and target rotation during a movement transition.
--- Modifies STATE.active.mode.overview.fixedCamPos and STATE.active.mode.overview.targetRx/Ry.
---@param camState table The current camera state (used for current height).
---@param smoothFactor number The smoothing factor for position interpolation.
---@param rotFactor number The smoothing factor for rotation interpolation (unused here, handled in handleModeTransition).
---@param userControllingView boolean Whether the user is manually rotating the view.
---@return boolean success Whether updates were made.
function MovementUtils.updateTransition(camState, smoothFactor, rotFactor, userControllingView)
    -- Ensure we have a target position to move towards
    if not STATE.active.mode.overview.targetCamPos then
        Log:trace("UpdateTransition called without targetCamPos")
        return false -- Indicate nothing happened
    end

    -- Smoothly interpolate position (X and Z) towards the target
    -- The source is the current STATE.active.mode.overview.fixedCamPos from the previous frame
    STATE.active.mode.overview.fixedCamPos.x = CameraCommons.lerp(
            STATE.active.mode.overview.fixedCamPos.x,
            STATE.active.mode.overview.targetCamPos.x,
            smoothFactor
    )
    STATE.active.mode.overview.fixedCamPos.z = CameraCommons.lerp(
            STATE.active.mode.overview.fixedCamPos.z,
            STATE.active.mode.overview.targetCamPos.z,
            smoothFactor
    )
    -- Note: Y position (height) is handled separately by the zoom logic in TurboOverviewCamera.update

    -- Update rotation target ONLY if moving towards a target point and user is not interfering
    if STATE.active.mode.overview.targetPoint and not userControllingView and not STATE.active.mode.overview.isRotationModeActive then
        -- Calculate current look direction from the *newly calculated intermediate* position
        -- to the target point. Use the actual current camera height for the calculation.
        local currentIntermediatePos = {
            x = STATE.active.mode.overview.fixedCamPos.x, -- Use the just-calculated X
            y = camState.py, -- Use current actual height from camState
            z = STATE.active.mode.overview.fixedCamPos.z  -- Use the just-calculated Z
        }

        local lookDir = CameraCommons.calculateCameraDirectionToThePoint(currentIntermediatePos, STATE.active.mode.overview.targetPoint)

        -- Update the target rotation angles. The actual smoothing/application happens in handleModeTransition.
        STATE.active.mode.overview.targetRx = lookDir.rx
        STATE.active.mode.overview.targetRy = lookDir.ry
    end

    return true -- Indicate that updates were made
end

function MovementUtils.moveToTarget()
    if Utils.isModeDisabled("overview") then
        return false
    end

    -- Get cursor position to determine where to move
    local targetPoint = OverviewCameraUtils.getCursorWorldPosition()

    -- If targetPoint is nil, it means the click was outside the map and should be ignored
    if not targetPoint then
        Log:trace("Move target outside map boundaries - ignoring")
        return false
    end

    -- Start movement to the target point
    MovementUtils.startMoveToTarget(targetPoint)

    return true
end

return MovementUtils