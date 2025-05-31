---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type MouseManager
local MouseManager = VFS.Include("LuaUI/TurboBarCam/standalone/mouse_manager.lua")
---@type OverviewCameraUtils
local OverviewCameraUtils = VFS.Include("LuaUI/TurboBarCam/features/overview/overview_utils.lua").OverviewCameraUtils
---@type RotationUtils
local RotationUtils = VFS.Include("LuaUI/TurboBarCam/features/overview/rotation_utils.lua").RotationUtils
---@type MovementUtils
local MovementUtils = VFS.Include("LuaUI/TurboBarCam/features/overview/movement_utils.lua").MovementUtils
---@type Scheduler
local Scheduler = VFS.Include("LuaUI/TurboBarCam/standalone/scheduler.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local ModeManager = CommonModules.ModeManager
local CameraCommons = CommonModules.CameraCommons

---@class TurboOverviewCamera
local TurboOverviewCamera = {}

--- Helper function to complete a transition
---@param finalCamState table The camera state at the moment the transition is completed.
---@param userControllingView boolean Whether the user was controlling view during transition.
local function completeTransition(finalCamState, userControllingView)
    -- Calculate any movement velocity at the time of transition completion
    local movementVelocity = {
        x = 0,
        z = 0
    }

    -- If we have both position information, calculate velocity
    if STATE.mode.overview.targetCamPos and STATE.mode.overview.lastTransitionDistance then
        local moveVector = {
            x = STATE.mode.overview.targetCamPos.x - finalCamState.px,
            z = STATE.mode.overview.targetCamPos.z - finalCamState.pz
        }

        -- Normalize and scale based on current transition speed
        local distance = math.sqrt(moveVector.x ^ 2 + moveVector.z ^ 2)
        if distance > 0.001 then
            -- Avoid division by very small numbers
            -- Calculate velocity based on smoothing factor and remaining distance
            local factor = STATE.mode.overview.currentTransitionFactor or CONFIG.MODE_TRANSITION_SMOOTHING
            movementVelocity = {
                x = (moveVector.x / distance) * factor * STATE.mode.overview.lastTransitionDistance * 0.5,
                z = (moveVector.z / distance) * factor * STATE.mode.overview.lastTransitionDistance * 0.5
            }
        end
    end

    -- Store velocity for continued motion
    STATE.mode.overview.movementVelocity = movementVelocity
    STATE.mode.overview.velocityDecay = 0.95 -- How quickly the velocity decays each frame

    -- Log the final camera position for debugging
    Log.trace(string.format("[DEBUG-ROTATION] Transition complete. Final position: (%.2f, %.2f, %.2f)",
            finalCamState.px, finalCamState.py, finalCamState.pz))

    if STATE.mode.overview.targetCamPos then
        Log.trace(string.format("[DEBUG-ROTATION] Target position was: (%.2f, %.2f, %.2f), distance=%.2f",
                STATE.mode.overview.targetCamPos.x, STATE.mode.overview.targetCamPos.y or 0, STATE.mode.overview.targetCamPos.z,
                math.sqrt((finalCamState.px - STATE.mode.overview.targetCamPos.x) ^ 2 + (finalCamState.pz - STATE.mode.overview.targetCamPos.z) ^ 2)))
    end

    -- *** Special handling for rotation transition - IMPROVED ***
    if STATE.mode.overview.enableRotationAfterToggle then
        Log.trace("[DEBUG-ROTATION] Transition complete - enabling rotation mode")

        -- Store the EXACT final camera position and rotation
        STATE.mode.overview.exactFinalPosition = {
            x = finalCamState.px,
            y = finalCamState.py,
            z = finalCamState.pz,
            rx = finalCamState.rx,
            ry = finalCamState.ry
        }

        -- CRITICAL: Recalculate the exact rotation angle based on final position
        -- This ensures proper continuity from movement end to rotation start
        local angle = math.atan2(
                finalCamState.px - STATE.mode.overview.rotationCenter.x,
                finalCamState.pz - STATE.mode.overview.rotationCenter.z
        )
        STATE.mode.overview.rotationAngle = angle

        -- Recalculate the exact distance based on final position
        STATE.mode.overview.rotationDistance = math.sqrt(
                (finalCamState.px - STATE.mode.overview.rotationCenter.x) ^ 2 +
                        (finalCamState.pz - STATE.mode.overview.rotationCenter.z) ^ 2
        )

        -- Activate rotation mode after the camera has reached its position
        STATE.mode.overview.isRotationModeActive = true
        STATE.mode.overview.rotationParametersInitialized = true

        -- CRITICAL: Make sure fixed camera position exactly matches finalCamState
        STATE.mode.overview.fixedCamPos = {
            x = finalCamState.px,
            z = finalCamState.pz
        }

        Log.trace(string.format("[DEBUG-ROTATION] Fixed camera position set to (%.2f, %.2f)",
                STATE.mode.overview.fixedCamPos.x, STATE.mode.overview.fixedCamPos.z))

        Log.trace(string.format("[DEBUG-ROTATION] Rotation activated around (%.2f, %.2f) at distance %.2f",
                STATE.mode.overview.rotationCenter.x, STATE.mode.overview.rotationCenter.z,
                STATE.mode.overview.rotationDistance))
    end

    -- End the transition flag
    STATE.mode.isModeTransitionInProgress = false

    -- Clear transition state variables but preserve velocity
    STATE.mode.overview.currentTransitionFactor = nil
    STATE.mode.overview.userLookedAround = nil -- Reset user looked around flag after transition
    STATE.mode.overview.initialMoveDistance = nil
    STATE.mode.overview.lastTransitionDistance = nil
    STATE.mode.overview.stuckFrameCount = 0
    STATE.mode.overview.targetPoint = nil -- Clear the look-at target point
    STATE.mode.overview.enableRotationAfterMove = nil -- Clear the rotation flag
    STATE.mode.overview.enableRotationAfterToggle = nil -- Clear the toggle transition flag

    -- Use the final camera state's rotation values directly
    STATE.mode.overview.targetRx = finalCamState.rx
    STATE.mode.overview.targetRy = finalCamState.ry

    -- Set fixed camera position from the final state of the transition
    -- Done again for emphasis and clarity
    STATE.mode.overview.fixedCamPos = {
        x = finalCamState.px,
        -- y = finalCamState.py, -- Y is managed by height/zoom logic, not fixed here
        z = finalCamState.pz
    }

    -- Clear the target position since we've reached it (or are close enough)
    -- But preserve for debugging
    -- STATE.mode.overview.targetCamPos = nil

    -- Update tracking state one last time with the final state using the manager's function
    ModeManager.updateTrackingState(finalCamState)

    Log.trace("[DEBUG-ROTATION] Overview camera transition complete")
end

--- Handles the camera update logic during a mode transition (e.g., movement).
--- Calculates the intermediate state and applies it to the camera.
---@param camState table Current camera state
---@param currentHeight number The target or current height (potentially changing due to zoom).
---@param userControllingView boolean Whether the user is manually controlling rotation.
local function handleModeTransition(camState, currentHeight, userControllingView)
    -- Determine smoothing factor for this frame
    local smoothFactor = STATE.mode.overview.currentTransitionFactor or CONFIG.MODE_TRANSITION_SMOOTHING
    -- Use the same factor for rotation smoothing during movement
    local rotFactor = smoothFactor

    -- Update interpolated position (STATE.mode.overview.fixedCamPos) and target rotation (STATE.mode.overview.targetRx/Ry)
    MovementUtils.updateTransition(camState, smoothFactor, rotFactor, userControllingView)

    -- *** Apply the interpolated state to the camera ***
    local interpolatedPos = STATE.mode.overview.fixedCamPos -- This now holds the position for *this* frame
    local targetRx = STATE.mode.overview.targetRx          -- Use the potentially updated target rotation
    local targetRy = STATE.mode.overview.targetRy

    -- Smoothly interpolate rotation angles towards the target for this frame
    -- Use the last known rotation from the tracking state as the source
    local rx = CameraCommons.smoothStep(STATE.mode.lastRotation.rx, targetRx, rotFactor)
    local ry = CameraCommons.smoothStepAngle(STATE.mode.lastRotation.ry, targetRy, rotFactor)

    -- Calculate direction vector from smoothed rotation angles
    local cosRx = math.cos(rx)
    local dx = math.sin(ry) * cosRx
    local dy = math.sin(rx)
    local dz = math.cos(ry) * cosRx

    -- Prepare camera state patch using interpolated position and rotation
    local camStatePatch = {
        px = interpolatedPos.x,
        py = currentHeight, -- Use the potentially zooming height calculated in update()
        pz = interpolatedPos.z,
        dx = dx,
        dy = dy,
        dz = dz,
        rx = rx,
        ry = ry,
        rz = 0
    }

    -- Apply the intermediate camera state for this frame
    Spring.SetCameraState(camStatePatch, 0)

    -- Update tracking state with the state we just applied, so the next frame interpolates correctly
    -- Use the manager's function
    ModeManager.updateTrackingState(camStatePatch)

    -- Check if we should end the transition based on distance and progress
    local currentDistance = 0
    if STATE.mode.overview.targetCamPos then
        -- Calculate distance based on the *applied* position for this frame
        currentDistance = math.sqrt(
                (camStatePatch.px - STATE.mode.overview.targetCamPos.x) ^ 2 +
                        (camStatePatch.pz - STATE.mode.overview.targetCamPos.z) ^ 2
        )
    end

    -- Use the progress check helper. Pass the initial distance stored when the move started.
    local transitionComplete = MovementUtils.checkTransitionProgress(currentDistance, STATE.mode.overview.initialMoveDistance)

    -- Also check the generic transition completion condition (e.g., time-based)
    if transitionComplete or CameraCommons.isTransitionComplete() then
        -- Pass the *final applied state* (camStatePatch) to completeTransition
        completeTransition(camStatePatch, userControllingView)
    else
        -- Store the current distance for the *next* frame's progress check
        -- This happens *after* checkTransitionProgress uses the *previous* frame's last distance
        STATE.mode.overview.lastTransitionDistance = currentDistance
    end
end

local function updateRotationMode(currentHeight)
    -- For the very first rotation frame, use the exact final position from the transition
    if STATE.mode.overview.exactFinalPosition then
        -- Use the stored exact final position
        local exactPos = STATE.mode.overview.exactFinalPosition

        -- IMPORTANT: The camera should stay EXACTLY at this position on the first frame
        -- We don't want any sudden jumps in position or rotation!
        local exactCamState = {
            px = exactPos.x,
            py = currentHeight, -- Use current height (may have changed)
            pz = exactPos.z,
            rx = exactPos.rx,
            ry = exactPos.ry,
            rz = 0
        }

        -- Calculate direction vector from rotation angles for consistency
        local cosRx = math.cos(exactPos.rx)
        local dx = math.sin(exactPos.ry) * cosRx
        local dy = math.sin(exactPos.rx)
        local dz = math.cos(exactPos.ry) * cosRx

        -- Add direction vectors to ensure consistency
        exactCamState.dx = dx
        exactCamState.dy = dy
        exactCamState.dz = dz

        -- Log the exact state being applied
        Log.trace(string.format("[FIXED-ROTATION] Using exact final position for first rotation frame: (%.2f, %.2f)",
                exactPos.x, exactPos.z))

        -- Apply camera state DIRECTLY to ensure exact match with transition end
        Spring.SetCameraState(exactCamState, 0)

        -- Update tracking state
        ModeManager.updateTrackingState(exactCamState)

        -- Update fixed camera position to match exact position
        STATE.mode.overview.fixedCamPos = {
            x = exactPos.x,
            z = exactPos.z
        }

        -- Clear the stored position to use normal rotation updates after first frame
        STATE.mode.overview.exactFinalPosition = nil

        -- Add a flag to indicate this is the first frame (for next rotation update)
        STATE.mode.overview.firstRotationFrame = true

        return -- Skip normal rotation update for first frame
    end

    -- For the second rotation frame (first actual rotation),
    -- we'll make a VERY tiny adjustment to avoid a sudden jump
    if STATE.mode.overview.firstRotationFrame then
        -- Ensure we have rotation parameters for safety
        if not STATE.mode.overview.rotationCenter or not STATE.mode.overview.rotationDistance or not STATE.mode.overview.rotationAngle then
            Log.trace("Missing rotation parameters on first rotate frame - canceling rotation")
            RotationUtils.cancelRotation("missing parameters on first rotation frame")
            return
        end

        -- Use a very tiny rotation step (barely noticeable)
        local tinyRotationStep = 0.001
        STATE.mode.overview.rotationAngle = STATE.mode.overview.rotationAngle + tinyRotationStep

        -- Calculate new position with this tiny adjustment
        local sinAngle = math.sin(STATE.mode.overview.rotationAngle)
        local cosAngle = math.cos(STATE.mode.overview.rotationAngle)

        -- Calculate new camera position based on rotation parameters
        local newCamPos = {
            x = STATE.mode.overview.rotationCenter.x + STATE.mode.overview.rotationDistance * sinAngle,
            y = currentHeight,
            z = STATE.mode.overview.rotationCenter.z + STATE.mode.overview.rotationDistance * cosAngle
        }

        -- Update fixed camera position with this tiny change
        STATE.mode.overview.fixedCamPos.x = newCamPos.x
        STATE.mode.overview.fixedCamPos.z = newCamPos.z

        -- Calculate look direction to the rotation center
        local lookDir = CameraCommons.calculateCameraDirectionToThePoint(
                newCamPos,
                STATE.mode.overview.rotationCenter
        )

        -- Apply the camera state with this tiny change
        local camStatePatch = {
            px = newCamPos.x,
            py = newCamPos.y,
            pz = newCamPos.z,
            dx = lookDir.dx,
            dy = lookDir.dy,
            dz = lookDir.dz,
            rx = lookDir.rx,
            ry = lookDir.ry,
            rz = 0
        }

        -- Apply camera state
        Spring.SetCameraState(camStatePatch, 0)

        -- Update tracking state
        ModeManager.updateTrackingState(camStatePatch)

        -- Clear the first frame flag
        STATE.mode.overview.firstRotationFrame = nil

        Log.trace(string.format("[FIXED-ROTATION] First actual rotation step (tiny adjustment): angle=%.4f", STATE.mode.overview.rotationAngle))

        return
    end

    -- Normal rotation update for subsequent frames
    if not RotationUtils.updateRotation() then
        return -- Exit early if rotation update failed
    end

    -- Use the fixed camera position that was updated in RotationUtils.updateRotation
    local newCamPos = {
        x = STATE.mode.overview.fixedCamPos.x,
        y = currentHeight, -- Use the current height passed to this function
        z = STATE.mode.overview.fixedCamPos.z
    }

    -- Calculate look direction to the rotation center
    local lookDir = CameraCommons.calculateCameraDirectionToThePoint(
            newCamPos,
            STATE.mode.overview.rotationCenter
    )

    -- Apply the rotation directly without smoothing when in rotation mode
    local camStatePatch = {
        px = newCamPos.x,
        py = newCamPos.y,
        pz = newCamPos.z,
        dx = lookDir.dx,
        dy = lookDir.dy,
        dz = lookDir.dz,
        rx = lookDir.rx,
        ry = lookDir.ry,
        rz = 0
    }

    -- Apply camera state DIRECTLY to ensure immediate effect
    Spring.SetCameraState(camStatePatch, 0)

    -- Update tracking state AFTER applying (important order!)
    ModeManager.updateTrackingState(camStatePatch)
end

-- Update camera in normal overview mode (Assumed mostly correct, ensure it uses currentHeight)
local function updateNormalMode(camState, currentHeight)
    -- Apply any remaining movement velocity
    if STATE.mode.overview.movementVelocity and (
            math.abs(STATE.mode.overview.movementVelocity.x) > 0.01 or
                    math.abs(STATE.mode.overview.movementVelocity.z) > 0.01
    ) then
        -- Update position based on velocity
        STATE.mode.overview.fixedCamPos.x = STATE.mode.overview.fixedCamPos.x + STATE.mode.overview.movementVelocity.x
        STATE.mode.overview.fixedCamPos.z = STATE.mode.overview.fixedCamPos.z + STATE.mode.overview.movementVelocity.z

        -- Decay velocity
        STATE.mode.overview.movementVelocity.x = STATE.mode.overview.movementVelocity.x * STATE.mode.overview.velocityDecay
        STATE.mode.overview.movementVelocity.z = STATE.mode.overview.movementVelocity.z * STATE.mode.overview.velocityDecay

        -- If velocity becomes very small, clear it
        if math.abs(STATE.mode.overview.movementVelocity.x) < 0.01 and
                math.abs(STATE.mode.overview.movementVelocity.z) < 0.01 then
            STATE.mode.overview.movementVelocity = nil
        end
    end

    -- Get camera position - use the fixed position which only changes via moveToTarget transitions
    local camPos = {
        x = STATE.mode.overview.fixedCamPos.x,
        y = currentHeight, -- Apply the current (potentially zooming) height
        z = STATE.mode.overview.fixedCamPos.z
    }

    -- Normal rotation interpolation towards targetRx/Ry
    local rotationFactor = CONFIG.CAMERA_MODES.OVERVIEW.SMOOTHING.FREE_CAMERA_FACTOR
    local rx = CameraCommons.smoothStep(STATE.mode.lastRotation.rx, STATE.mode.overview.targetRx, rotationFactor)
    local ry = CameraCommons.smoothStepAngle(STATE.mode.lastRotation.ry, STATE.mode.overview.targetRy, rotationFactor)

    -- Calculate direction vector from rotation angles
    local cosRx = math.cos(rx)
    local dx = math.sin(ry) * cosRx
    local dy = math.sin(rx)
    local dz = math.cos(ry) * cosRx

    -- Prepare camera state patch
    local camStatePatch = {
        px = camPos.x, py = camPos.y, pz = camPos.z, -- Use fixed position + current height
        dx = dx, dy = dy, dz = dz,
        rx = rx, ry = ry, rz = 0
    }

    -- Update tracking state using the manager's function
    ModeManager.updateTrackingState(camStatePatch)

    -- Apply camera state
    Spring.SetCameraState(camStatePatch, 0)
end

--- Main update loop for the overview camera.
function TurboOverviewCamera.update()
    if STATE.mode.name ~= 'overview' then
        -- Unregister handlers if mode changed externally (optional cleanup)
        -- MouseManager.unregisterMode('overview')
        return
    end

    -- Handle delayed rotation mode activation (existing logic)
    if not STATE.mode.isModeTransitionInProgress and STATE.mode.overview.enableRotationAfterToggle then
        STATE.mode.overview.enableRotationAfterToggle = nil
        Log.trace("Overview mode fully enabled, now toggling rotation mode")
        RotationUtils.toggleRotation()
    end

    -- Get current camera state *once* per frame
    local camState = Spring.GetCameraState()

    -- Ensure we're intended to be in FPS mode for overview camera control
    if camState.mode ~= 0 then
        ModeManager.disableMode()
        return
    end

    -- Handle smooth zoom height transitions independently
    local currentActualHeight = camState.py
    local targetHeight = STATE.mode.overview.targetHeight or OverviewCameraUtils.calculateCurrentHeight()
    local heightForThisFrame = currentActualHeight -- Start with actual height

    if math.abs(currentActualHeight - targetHeight) > 1 then
        -- Height difference threshold
        -- Interpolate height for this frame
        heightForThisFrame = CameraCommons.smoothStep(currentActualHeight, targetHeight, CONFIG.CAMERA_MODES.OVERVIEW.ZOOM_TRANSITION_FACTOR)
    else
        -- Snap to target height if close enough
        heightForThisFrame = targetHeight
        -- Ensure targetHeight state matches if we snapped
        if STATE.mode.overview.targetHeight ~= targetHeight then
            STATE.mode.overview.targetHeight = targetHeight
        end
    end

    -- Track if user is controlling the camera view rotation via mouse drag
    local userControllingView = (STATE.mouse and STATE.mouse.isMiddleMouseDown) or STATE.mode.overview.userLookedAround

    -- === Main Logic Branching ===

    -- Handle mode transitions (like movement from moveToTarget)
    if STATE.mode.isModeTransitionInProgress then
        -- This function now handles calculating AND applying the intermediate state
        handleModeTransition(camState, heightForThisFrame, userControllingView)
        -- The rest of the update logic is skipped because the transition handler applied the state
        return
    end

    -- If not in a mode transition, handle normal or rotation mode updates

    -- Initialize tracking state if this is the very first update after enabling
    if STATE.mode.lastCamPos.x == 0 and STATE.mode.lastCamPos.y == 0 and STATE.mode.lastCamPos.z == 0 then
        Log.trace("First update: Initializing tracking state and fixed position.")
        -- Use the manager's function to initialize tracking state fully
        ModeManager.updateTrackingState(camState)
        -- Initialize fixed camera position from current state
        STATE.mode.overview.fixedCamPos = { x = camState.px, z = camState.pz }
        -- Ensure target rotations match current state initially
        STATE.mode.overview.targetRx = camState.rx
        STATE.mode.overview.targetRy = camState.ry
    end

    -- Handle different camera modes (Rotation vs Normal Free Look)
    if STATE.mode.overview.isRotationModeActive then
        updateRotationMode(heightForThisFrame)
    else
        updateNormalMode(camState, heightForThisFrame)
    end
end

-- Add the toggle function here for completeness if it wasn't included before
function TurboOverviewCamera.toggle()
    if Util.isTurboBarCamDisabled() then
        return
    end
    -- disable previous mode
    ModeManager.disableMode()

    local mapX = Game.mapSizeX
    local mapZ = Game.mapSizeZ
    local mapDiagonal = math.sqrt(mapX * mapX + mapZ * mapZ)

    STATE.mode.overview.heightLevel = CONFIG.CAMERA_MODES.OVERVIEW.DEFAULT_HEIGHT_LEVEL
    STATE.mode.overview.maxRotationSpeed = CONFIG.CAMERA_MODES.OVERVIEW.MAX_ROTATION_SPEED
    STATE.mode.overview.edgeRotationMultiplier = CONFIG.CAMERA_MODES.OVERVIEW.EDGE_ROTATION_MULTIPLIER
    STATE.mode.overview.maxAngularVelocity = CONFIG.CAMERA_MODES.OVERVIEW.MAX_ANGULAR_VELOCITY
    STATE.mode.overview.angularDamping = CONFIG.CAMERA_MODES.OVERVIEW.ANGULAR_DAMPING
    STATE.mode.overview.forwardVelocity = CONFIG.CAMERA_MODES.OVERVIEW.FORWARD_VELOCITY
    STATE.mode.overview.minDistanceToTarget = CONFIG.CAMERA_MODES.OVERVIEW.MIN_DISTANCE
    STATE.mode.overview.movementTransitionFactor = CONFIG.CAMERA_MODES.OVERVIEW.TRANSITION_FACTOR
    STATE.mode.overview.mouseMoveSensitivity = CONFIG.CAMERA_MODES.OVERVIEW.MOUSE_MOVE_SENSITIVITY
    STATE.mode.overview.userLookedAround = false
    STATE.mode.overview.movingToTarget = false
    STATE.mode.overview.inMovementTransition = false
    STATE.mode.overview.angularVelocity = 0
    STATE.mode.overview.movementAngle = 0
    STATE.mode.overview.distanceToTarget = CONFIG.CAMERA_MODES.OVERVIEW.MIN_DISTANCE
    STATE.mode.overview.height = math.max(math.max(mapDiagonal * CONFIG.CAMERA_MODES.OVERVIEW.HEIGHT_FACTOR, 2500), 500)

    -- Add new movement velocity tracking
    STATE.mode.overview.movementVelocity = nil
    STATE.mode.overview.velocityDecay = 0.95

    local currentCamState = Spring.GetCameraState()
    local targetPoint, targetCamPos
    local selectedUnits = Spring.GetSelectedUnits()

    -- Start with current height - we'll determine the best height level to maintain this as closely as possible
    local currentHeight = currentCamState.py

    if #selectedUnits > 0 then
        -- Handle case when units are selected - use the first selected unit as target
        local unitID = selectedUnits[1]
        local unitX, unitY, unitZ = Spring.GetUnitPosition(unitID)
        if unitX and unitZ then
            targetPoint = { x = unitX, y = unitY, z = unitZ }
            STATE.mode.overview.heightLevel = CONFIG.CAMERA_MODES.OVERVIEW.HEIGHT_CONTROL_GRANULARITY / 2
            targetCamPos = OverviewCameraUtils.calculateCameraPosition(
                    targetPoint,
                    OverviewCameraUtils.calculateCurrentHeight(),
                    mapX,
                    mapZ
            )
            Log.trace("Setting target position to look at selected unit " .. unitID)
        else
            Log.trace("Could not get selected unit position, using default positioning")
            targetCamPos = { x = currentCamState.px, z = currentCamState.pz }
        end
    else
        -- NEW: When no unit is selected, use cursor position instead of map center
        local cursorPos = OverviewCameraUtils.getCursorWorldPosition()

        if cursorPos then
            -- Valid cursor position on the map
            targetPoint = cursorPos
            Log.trace(string.format("Using cursor position as target: (%.1f, %.1f)", cursorPos.x, cursorPos.z))
        else
            -- Fallback to map center if cursor is outside the map
            targetPoint = { x = mapX / 2, y = 0, z = mapZ / 2 }
            Log.trace("Cursor outside map - using map center as fallback target")
        end

        -- Find the height level that would give us the closest height to what we had before
        -- First, store current default height level
        local origHeightLevel = STATE.mode.overview.heightLevel

        -- Find the closest height level
        local closestDiff = math.huge
        local closestLevel = CONFIG.CAMERA_MODES.OVERVIEW.DEFAULT_HEIGHT_LEVEL
        local granularity = CONFIG.CAMERA_MODES.OVERVIEW.HEIGHT_CONTROL_GRANULARITY

        for level = 1, granularity do
            -- Temporarily set this level
            STATE.mode.overview.heightLevel = level
            local levelHeight = OverviewCameraUtils.calculateCurrentHeight()
            local diff = math.abs(levelHeight - currentHeight)

            if diff < closestDiff then
                closestDiff = diff
                closestLevel = level
            end
        end

        -- Set the height level that best matches the current height
        STATE.mode.overview.heightLevel = closestLevel
        Log.trace(string.format("Selected height level %d (closest to previous height %.1f)",
                closestLevel, currentHeight))

        -- Calculate camera position using the target point
        targetCamPos = OverviewCameraUtils.calculateCameraPosition(
                targetPoint,
                OverviewCameraUtils.calculateCurrentHeight(),
                mapX,
                mapZ
        )
    end

    -- Use the target height or calculated best height
    local targetHeight = OverviewCameraUtils.calculateCurrentHeight()
    STATE.mode.overview.targetHeight = targetHeight
    targetCamPos.y = targetHeight -- Set target height

    -- Store current camera position as starting point for transition
    STATE.mode.overview.fixedCamPos = { x = currentCamState.px, y = currentCamState.py, z = currentCamState.pz }
    STATE.mode.overview.targetCamPos = targetCamPos

    -- Calculate look direction
    local lookDir = CameraCommons.calculateCameraDirectionToThePoint(targetCamPos, targetPoint)
    STATE.mode.overview.targetRy = lookDir.ry

    -- For map center (fallback), look more downwards, otherwise use calculated look dir
    if targetPoint.x == mapX / 2 and targetPoint.z == mapZ / 2 and #selectedUnits == 0 then
        STATE.mode.overview.targetRx = math.pi * 0.75 -- Look more downwards for map center
    else
        STATE.mode.overview.targetRx = lookDir.rx
    end

    -- IMPORTANT: Store as lastTargetPoint for future rotation reference
    STATE.mode.overview.lastTargetPoint = targetPoint
    Log.trace(string.format("Stored last target point at (%.1f, %.1f)", targetPoint.x, targetPoint.z))

    -- Use manager's function to initialize tracking state for the transition
    ModeManager.updateTrackingState(currentCamState)

    TurboOverviewCamera.registerMouseHandlers()
    ModeManager.startModeTransition('overview')

    Log.trace(string.format("Turbo Overview camera enabled (Target Height: %.1f units, Level: %d)",
            targetHeight, STATE.mode.overview.heightLevel))
end

function TurboOverviewCamera.registerMouseHandlers()
    MouseManager.registerMode('overview')

    -- MMB click - move to point
    MouseManager.onMMB('overview', function(x, y)
        MovementUtils.moveToTarget()

        -- Moving cancels rotation
        RotationUtils.cancelRotation("movement")
    end)

    -- MMB hold - look around
    MouseManager.onDragStartMMB('overview', function(startX, startY, currentX, currentY)
        RotationUtils.initCursorRotation(startX, startY)

        -- Looking around cancels rotation
        RotationUtils.cancelRotation("looking around")
    end)

    MouseManager.onDragMMB('overview', function(dx, dy, x, y)
        if RotationUtils.updateCursorRotation(dx, dy) then
            STATE.mode.overview.userLookedAround = true
        end
    end)

    MouseManager.onReleaseMMB('overview', function(x, y)
        RotationUtils.resetCursorRotation()
    end)

    -- RMB hold - toggle rotation mode
    MouseManager.onHoldRMB('overview', function(x, y, holdTime)
        -- If the user just holds RMB and doesn't drag, toggle rotation mode after a threshold
        if holdTime > STATE.mouse.dragTimeThreshold then
            if not STATE.mode.overview.isRotationModeActive and not STATE.mode.isModeTransitionInProgress then
                -- Only enable rotation if we have a previous target point and not already transitioning
                if STATE.mode.overview.lastTargetPoint then
                    RotationUtils.toggleRotation()
                    -- Set a flag to track that we're in RMB hold rotation mode
                    STATE.mode.overview.isRmbHoldRotation = true
                else
                    Log.info("Cannot enable rotation: No target point available. Use MMB first")
                end
            elseif STATE.mode.overview.isRotationModeActive then
                -- Update rotation speed based on cursor position while holding RMB
                RotationUtils.updateRotationSpeed(x, y)
            end
        end
    end)

    -- RMB drag - update rotation speed
    MouseManager.onDragRMB('overview', function(dx, dy, x, y)
        if STATE.mode.overview.isRotationModeActive then
            -- Update rotation speed based on current cursor position
            RotationUtils.updateRotationSpeed(x, y)
            -- We're dragging, so this isn't just a hold anymore
            STATE.mode.overview.isRmbHoldRotation = false
        end
    end)

    -- RMB release - cleanup
    MouseManager.onReleaseRMB('overview', function(x, y, wasDoubleClick, wasDragging, holdTime)
        -- If rotation was activated via RMB hold without dragging, disable it when released
        if STATE.mode.overview.isRotationModeActive and STATE.mode.overview.isRmbHoldRotation then
            RotationUtils.cancelRotation("RMB hold released")
            STATE.mode.overview.isRmbHoldRotation = false
            -- If rotation is active but RMB was just a brief click (not dragging),
            -- we should disable rotation mode
        elseif STATE.mode.overview.isRotationModeActive and not wasDragging and holdTime < STATE.mouse.dragTimeThreshold then
            RotationUtils.cancelRotation("brief click release")
        elseif STATE.mode.overview.isRotationModeActive then
            RotationUtils.applyMomentum()
            Scheduler.schedule(function()
                RotationUtils.cancelRotation("RMB released")
            end, 0.5, "Overview_RMB_released")
        end

        -- Clear the moveButtonPressed flag that was used in the old system
        STATE.mode.overview.moveButtonPressed = false

        -- Always clear this flag when RMB is released
        STATE.mode.overview.isRmbHoldRotation = false
    end)
end

-- Simple height change function that updates height and triggers move to target
function TurboOverviewCamera.changeHeightAndMove(amount)
    if Util.isModeDisabled("overview") then
        return
    end

    local granularity = CONFIG.CAMERA_MODES.OVERVIEW.HEIGHT_CONTROL_GRANULARITY
    if not STATE.mode.overview.heightLevel then
        STATE.mode.overview.heightLevel = CONFIG.CAMERA_MODES.OVERVIEW.DEFAULT_HEIGHT_LEVEL
    end

    -- Calculate the new height level
    local newHeightLevel = STATE.mode.overview.heightLevel + amount

    -- Check if the new height level is within valid range
    if newHeightLevel >= 1 and newHeightLevel <= granularity then
        -- Store the previous height level to check if there was a change
        local previousHeightLevel = STATE.mode.overview.heightLevel

        -- Update the height level
        STATE.mode.overview.heightLevel = newHeightLevel

        -- Calculate the new target height
        local newTargetHeight = OverviewCameraUtils.calculateCurrentHeight()

        -- Only proceed with move-to-target if height actually changed
        if previousHeightLevel ~= newHeightLevel then
            -- Set the target height for the move operation
            STATE.mode.overview.targetHeight = newTargetHeight

            -- Call the standard move to target function which uses cursor position
            MovementUtils.moveToTarget()

            Log.trace("Height changed to level " .. STATE.mode.overview.heightLevel ..
                    " (target height: " .. math.floor(newTargetHeight) .. " units)")
        else
            Log.trace("Height level unchanged: " .. STATE.mode.overview.heightLevel)
        end
    else
        Log.info("Cannot change height level: would exceed valid range (1-" .. granularity .. ")")
    end
end

return {
    TurboOverviewCamera = TurboOverviewCamera
}
