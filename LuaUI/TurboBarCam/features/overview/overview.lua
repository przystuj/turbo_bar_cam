---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type MouseManager
local MouseManager = VFS.Include("LuaUI/TurboBarCam/standalone/mouse_manager.lua").MouseManager

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local TrackingManager = CommonModules.TrackingManager
local CameraCommons = CommonModules.CameraCommons

---@type OverviewCameraUtils
local OverviewCameraUtils = VFS.Include("LuaUI/TurboBarCam/features/overview/overview_utils.lua").OverviewCameraUtils
---@type RotationUtils
local RotationUtils = VFS.Include("LuaUI/TurboBarCam/features/overview/rotation_utils.lua").RotationUtils
---@type MovementUtils
local MovementUtils = VFS.Include("LuaUI/TurboBarCam/features/overview/movement_utils.lua").MovementUtils

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
    if STATE.overview.targetCamPos and STATE.overview.lastTransitionDistance then
        local moveVector = {
            x = STATE.overview.targetCamPos.x - finalCamState.px,
            z = STATE.overview.targetCamPos.z - finalCamState.pz
        }

        -- Normalize and scale based on current transition speed
        local distance = math.sqrt(moveVector.x ^ 2 + moveVector.z ^ 2)
        if distance > 0.001 then
            -- Avoid division by very small numbers
            -- Calculate velocity based on smoothing factor and remaining distance
            local factor = STATE.overview.currentTransitionFactor or CONFIG.MODE_TRANSITION_SMOOTHING
            movementVelocity = {
                x = (moveVector.x / distance) * factor * STATE.overview.lastTransitionDistance * 0.5,
                z = (moveVector.z / distance) * factor * STATE.overview.lastTransitionDistance * 0.5
            }
        end
    end

    -- Store velocity for continued motion
    STATE.overview.movementVelocity = movementVelocity
    STATE.overview.velocityDecay = 0.95 -- How quickly the velocity decays each frame

    -- Check if we should enable rotation after move completion
    if (STATE.overview.moveButtonPressed or STATE.overview.enableRotationAfterMove) and STATE.overview.lastTargetPoint then
        -- Automatically enable rotation
        Log.debug("Move transition complete - enabling rotation mode")

        -- Calculate the rotation parameters using the last target point
        local targetPoint = STATE.overview.lastTargetPoint

        -- Calculate distance
        local distance = math.sqrt(
                (finalCamState.px - targetPoint.x) ^ 2 +
                        (finalCamState.pz - targetPoint.z) ^ 2
        )

        -- Calculate angle
        local angle = math.atan2(
                finalCamState.px - targetPoint.x,
                finalCamState.pz - targetPoint.z
        )

        -- Set up rotation state directly
        STATE.overview.isRotationModeActive = true
        STATE.overview.rotationCenter = {
            x = targetPoint.x,
            y = targetPoint.y or Spring.GetGroundHeight(targetPoint.x, targetPoint.z) or 0,
            z = targetPoint.z
        }
        STATE.overview.rotationDistance = distance
        STATE.overview.rotationAngle = angle

        Log.debug(string.format("Rotation activated around (%.1f, %.1f) at distance %.1f",
                targetPoint.x, targetPoint.z, distance))
    end

    -- End the transition flag
    STATE.tracking.isModeTransitionInProgress = false

    -- Clear transition state variables but preserve velocity
    STATE.overview.currentTransitionFactor = nil
    STATE.overview.userLookedAround = nil -- Reset user looked around flag after transition
    STATE.overview.initialMoveDistance = nil
    STATE.overview.lastTransitionDistance = nil
    STATE.overview.stuckFrameCount = 0
    STATE.overview.targetPoint = nil -- Clear the look-at target point
    STATE.overview.enableRotationAfterMove = nil -- Clear the rotation flag

    -- Use the final camera state's rotation values directly
    STATE.overview.targetRx = finalCamState.rx
    STATE.overview.targetRy = finalCamState.ry

    -- Set fixed camera position from the final state of the transition
    STATE.overview.fixedCamPos = {
        x = finalCamState.px,
        -- y = finalCamState.py, -- Y is managed by height/zoom logic, not fixed here
        z = finalCamState.pz
    }

    -- Clear the target position since we've reached it (or are close enough)
    STATE.overview.targetCamPos = nil

    -- Update tracking state one last time with the final state using the manager's function
    TrackingManager.updateTrackingState(finalCamState)

    Log.trace("Overview camera transition complete with preserved momentum.")
end

--- Handles the camera update logic during a mode transition (e.g., movement).
--- Calculates the intermediate state and applies it to the camera.
---@param camState table Current camera state from CameraManager.
---@param currentHeight number The target or current height (potentially changing due to zoom).
---@param userControllingView boolean Whether the user is manually controlling rotation.
local function handleModeTransition(camState, currentHeight, userControllingView)
    -- Determine smoothing factor for this frame
    local smoothFactor = STATE.overview.currentTransitionFactor or CONFIG.MODE_TRANSITION_SMOOTHING
    -- Use the same factor for rotation smoothing during movement
    local rotFactor = smoothFactor

    -- Update interpolated position (STATE.overview.fixedCamPos) and target rotation (STATE.overview.targetRx/Ry)
    MovementUtils.updateTransition(camState, smoothFactor, rotFactor, userControllingView)

    -- *** Apply the interpolated state to the camera ***
    local interpolatedPos = STATE.overview.fixedCamPos -- This now holds the position for *this* frame
    local targetRx = STATE.overview.targetRx          -- Use the potentially updated target rotation
    local targetRy = STATE.overview.targetRy

    -- Smoothly interpolate rotation angles towards the target for this frame
    -- Use the last known rotation from the tracking state as the source
    local rx = CameraCommons.smoothStep(STATE.tracking.lastRotation.rx, targetRx, rotFactor)
    local ry = CameraCommons.smoothStepAngle(STATE.tracking.lastRotation.ry, targetRy, rotFactor)

    -- Calculate direction vector from smoothed rotation angles
    local cosRx = math.cos(rx)
    local dx = math.sin(ry) * cosRx
    local dy = math.sin(rx)
    local dz = math.cos(ry) * cosRx

    -- Prepare camera state patch using interpolated position and rotation
    local camStatePatch = {
        mode = 0, -- Ensure FPS mode
        name = "fps",
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
    CameraManager.setCameraState(camStatePatch, 0, "TurboOverviewCamera.handleModeTransition")

    -- Update tracking state with the state we just applied, so the next frame interpolates correctly
    -- Use the manager's function
    TrackingManager.updateTrackingState(camStatePatch)

    -- Check if we should end the transition based on distance and progress
    local currentDistance = 0
    if STATE.overview.targetCamPos then
        -- Calculate distance based on the *applied* position for this frame
        currentDistance = math.sqrt(
                (camStatePatch.px - STATE.overview.targetCamPos.x) ^ 2 +
                        (camStatePatch.pz - STATE.overview.targetCamPos.z) ^ 2
        )
    end

    -- Use the progress check helper. Pass the initial distance stored when the move started.
    local transitionComplete = MovementUtils.checkTransitionProgress(currentDistance, STATE.overview.initialMoveDistance)

    -- Also check the generic transition completion condition (e.g., time-based)
    if transitionComplete or CameraCommons.isTransitionComplete() then
        -- Pass the *final applied state* (camStatePatch) to completeTransition
        completeTransition(camStatePatch, userControllingView)
    else
        -- Store the current distance for the *next* frame's progress check
        -- This happens *after* checkTransitionProgress uses the *previous* frame's last distance
        STATE.overview.lastTransitionDistance = currentDistance
    end
end

local function updateRotationMode(currentHeight)
    -- Update rotation based on current state
    if not RotationUtils.updateRotation() then
        return -- Exit early if rotation update failed
    end

    -- Use the fixed camera position that was updated in RotationUtils.updateRotation
    local newCamPos = {
        x = STATE.overview.fixedCamPos.x,
        y = currentHeight, -- Use the current height passed to this function
        z = STATE.overview.fixedCamPos.z
    }

    -- Calculate look direction to the rotation center
    local lookDir = CameraCommons.calculateCameraDirectionToThePoint(
            newCamPos,
            STATE.overview.rotationCenter
    )

    -- Apply the rotation directly without smoothing when in rotation mode
    local camStatePatch = {
        mode = 0,
        name = "fps",
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

    -- Log the actual camera state being applied
    Log.trace(string.format("Applying rotation camera: pos=(%.1f, %.1f, %.1f), rot=(%.2f, %.2f)",
            camStatePatch.px, camStatePatch.py, camStatePatch.pz,
            camStatePatch.rx, camStatePatch.ry))

    -- Apply camera state DIRECTLY to ensure immediate effect
    CameraManager.setCameraState(camStatePatch, 0, "TurboOverviewCamera.updateRotationMode")

    -- Update tracking state AFTER applying (important order!)
    TrackingManager.updateTrackingState(camStatePatch)

end


-- Update camera in normal overview mode (Assumed mostly correct, ensure it uses currentHeight)
local function updateNormalMode(camState, currentHeight)
    -- Apply any remaining movement velocity
    if STATE.overview.movementVelocity and (
            math.abs(STATE.overview.movementVelocity.x) > 0.01 or
                    math.abs(STATE.overview.movementVelocity.z) > 0.01
    ) then
        -- Update position based on velocity
        STATE.overview.fixedCamPos.x = STATE.overview.fixedCamPos.x + STATE.overview.movementVelocity.x
        STATE.overview.fixedCamPos.z = STATE.overview.fixedCamPos.z + STATE.overview.movementVelocity.z

        -- Decay velocity
        STATE.overview.movementVelocity.x = STATE.overview.movementVelocity.x * STATE.overview.velocityDecay
        STATE.overview.movementVelocity.z = STATE.overview.movementVelocity.z * STATE.overview.velocityDecay

        -- If velocity becomes very small, clear it
        if math.abs(STATE.overview.movementVelocity.x) < 0.01 and
                math.abs(STATE.overview.movementVelocity.z) < 0.01 then
            STATE.overview.movementVelocity = nil
        end
    end

    -- Get camera position - use the fixed position which only changes via moveToTarget transitions
    local camPos = {
        x = STATE.overview.fixedCamPos.x,
        y = currentHeight, -- Apply the current (potentially zooming) height
        z = STATE.overview.fixedCamPos.z
    }

    -- Normal rotation interpolation towards targetRx/Ry
    local rotationFactor = CONFIG.CAMERA_MODES.OVERVIEW.SMOOTHING.FREE_CAMERA_FACTOR
    local rx = CameraCommons.smoothStep(STATE.tracking.lastRotation.rx, STATE.overview.targetRx, rotationFactor)
    local ry = CameraCommons.smoothStepAngle(STATE.tracking.lastRotation.ry, STATE.overview.targetRy, rotationFactor)

    -- Calculate direction vector from rotation angles
    local cosRx = math.cos(rx)
    local dx = math.sin(ry) * cosRx
    local dy = math.sin(rx)
    local dz = math.cos(ry) * cosRx

    -- Prepare camera state patch
    local camStatePatch = {
        mode = 0, name = "fps",
        px = camPos.x, py = camPos.y, pz = camPos.z, -- Use fixed position + current height
        dx = dx, dy = dy, dz = dz,
        rx = rx, ry = ry, rz = 0
    }

    -- Update tracking state using the manager's function
    TrackingManager.updateTrackingState(camStatePatch)

    -- Apply camera state
    CameraManager.setCameraState(camStatePatch, 0, "TurboOverviewCamera.update")
end

--- Main update loop for the overview camera.
function TurboOverviewCamera.update()
    if STATE.tracking.mode ~= 'overview' then
        -- Unregister handlers if mode changed externally (optional cleanup)
        -- MouseManager.unregisterMode('overview')
        return
    end

    -- Handle delayed rotation mode activation (existing logic)
    if not STATE.tracking.isModeTransitionInProgress and STATE.overview.enableRotationAfterToggle then
        STATE.overview.enableRotationAfterToggle = nil
        Log.debug("Overview mode fully enabled, now toggling rotation mode")
        RotationUtils.toggleRotation()
    end

    -- Get current camera state *once* per frame
    local camState = CameraManager.getCameraState("TurboOverviewCamera.update")

    -- Ensure we're intended to be in FPS mode for overview camera control
    if camState.mode ~= 0 then
        TrackingManager.disableTracking()
        return
    end

    -- Handle smooth zoom height transitions independently
    local currentActualHeight = camState.py
    local targetHeight = STATE.overview.targetHeight or OverviewCameraUtils.calculateCurrentHeight()
    local heightForThisFrame = currentActualHeight -- Start with actual height

    if math.abs(currentActualHeight - targetHeight) > 1 then
        -- Height difference threshold
        -- Interpolate height for this frame
        heightForThisFrame = CameraCommons.smoothStep(currentActualHeight, targetHeight, CONFIG.CAMERA_MODES.OVERVIEW.ZOOM_TRANSITION_FACTOR)
    else
        -- Snap to target height if close enough
        heightForThisFrame = targetHeight
        -- Ensure targetHeight state matches if we snapped
        if STATE.overview.targetHeight ~= targetHeight then
            STATE.overview.targetHeight = targetHeight
        end
    end

    -- Track if user is controlling the camera view rotation via mouse drag
    local userControllingView = (STATE.mouse and STATE.mouse.isMiddleMouseDown) or STATE.overview.userLookedAround

    -- === Main Logic Branching ===

    -- Handle mode transitions (like movement from moveToTarget)
    if STATE.tracking.isModeTransitionInProgress then
        -- This function now handles calculating AND applying the intermediate state
        handleModeTransition(camState, heightForThisFrame, userControllingView)
        -- The rest of the update logic is skipped because the transition handler applied the state
        return
    end

    -- If not in a mode transition, handle normal or rotation mode updates

    -- Initialize tracking state if this is the very first update after enabling
    if STATE.tracking.lastCamPos.x == 0 and STATE.tracking.lastCamPos.y == 0 and STATE.tracking.lastCamPos.z == 0 then
        Log.debug("First update: Initializing tracking state and fixed position.")
        -- Use the manager's function to initialize tracking state fully
        TrackingManager.updateTrackingState(camState)
        -- Initialize fixed camera position from current state
        STATE.overview.fixedCamPos = { x = camState.px, z = camState.pz }
        -- Ensure target rotations match current state initially
        STATE.overview.targetRx = camState.rx
        STATE.overview.targetRy = camState.ry
    end

    -- Handle different camera modes (Rotation vs Normal Free Look)
    if STATE.overview.isRotationModeActive then
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

    if STATE.tracking.mode == 'overview' then
        TrackingManager.disableTracking()
        Log.debug("Turbo Overview camera disabled")
        return
    end

    local mapX = Game.mapSizeX
    local mapZ = Game.mapSizeZ
    local mapDiagonal = math.sqrt(mapX * mapX + mapZ * mapZ)

    STATE.overview.heightLevel = CONFIG.CAMERA_MODES.OVERVIEW.DEFAULT_HEIGHT_LEVEL
    STATE.overview.maxRotationSpeed = CONFIG.CAMERA_MODES.OVERVIEW.MAX_ROTATION_SPEED
    STATE.overview.edgeRotationMultiplier = CONFIG.CAMERA_MODES.OVERVIEW.EDGE_ROTATION_MULTIPLIER
    STATE.overview.maxAngularVelocity = CONFIG.CAMERA_MODES.OVERVIEW.MAX_ANGULAR_VELOCITY
    STATE.overview.angularDamping = CONFIG.CAMERA_MODES.OVERVIEW.ANGULAR_DAMPING
    STATE.overview.forwardVelocity = CONFIG.CAMERA_MODES.OVERVIEW.FORWARD_VELOCITY
    STATE.overview.minDistanceToTarget = CONFIG.CAMERA_MODES.OVERVIEW.MIN_DISTANCE
    STATE.overview.movementTransitionFactor = CONFIG.CAMERA_MODES.OVERVIEW.TRANSITION_FACTOR
    STATE.overview.mouseMoveSensitivity = CONFIG.CAMERA_MODES.OVERVIEW.MOUSE_MOVE_SENSITIVITY
    STATE.overview.userLookedAround = false
    STATE.overview.targetHeight = nil
    STATE.overview.movingToTarget = false
    STATE.overview.inMovementTransition = false
    STATE.overview.angularVelocity = 0
    STATE.overview.movementAngle = 0
    STATE.overview.distanceToTarget = CONFIG.CAMERA_MODES.OVERVIEW.MIN_DISTANCE
    STATE.overview.height = math.max(math.max(mapDiagonal * CONFIG.CAMERA_MODES.OVERVIEW.HEIGHT_FACTOR, 2500), 500)

    -- Add new movement velocity tracking
    STATE.overview.movementVelocity = nil
    STATE.overview.velocityDecay = 0.95

    local currentCamState = CameraManager.getCameraState("TurboOverviewCamera.toggle")
    local selectedUnits = Spring.GetSelectedUnits()
    local targetPoint, targetCamPos

    if #selectedUnits > 0 then
        local unitID = selectedUnits[1]
        local unitX, unitY, unitZ = Spring.GetUnitPosition(unitID)
        if unitX and unitZ then
            targetPoint = { x = unitX, y = unitY, z = unitZ }
            STATE.overview.heightLevel = CONFIG.CAMERA_MODES.OVERVIEW.HEIGHT_CONTROL_GRANULARITY
            targetCamPos = OverviewCameraUtils.calculateCameraPosition(
                    targetPoint,
                    OverviewCameraUtils.calculateCurrentHeight(),
                    mapX,
                    mapZ
            )
            Log.debug("Setting target position to look at selected unit " .. unitID)
        else
            Log.debug("Could not get selected unit position, using default positioning")
            targetCamPos = { x = currentCamState.px, z = currentCamState.pz }
        end
    else
        targetPoint = { x = mapX / 2, y = 0, z = mapZ / 2 } -- y=0 for ground level target
        STATE.overview.heightLevel = CONFIG.CAMERA_MODES.OVERVIEW.DEFAULT_HEIGHT_LEVEL
        targetCamPos = { x = mapX / 2, z = mapZ / 2 }
    end

    local currentHeight = OverviewCameraUtils.calculateCurrentHeight()
    STATE.overview.targetHeight = currentHeight
    targetCamPos.y = currentHeight -- Set target height

    STATE.overview.fixedCamPos = { x = currentCamState.px, y = currentCamState.py, z = currentCamState.pz }
    STATE.overview.targetCamPos = targetCamPos

    local lookDir = CameraCommons.calculateCameraDirectionToThePoint(targetCamPos, targetPoint)
    STATE.overview.targetRy = lookDir.ry
    if #selectedUnits == 0 then
        STATE.overview.targetRx = math.pi * 0.75 -- Look more downwards for map center
    else
        STATE.overview.targetRx = lookDir.rx
    end

    -- Use manager's function to initialize tracking state for the transition
    TrackingManager.updateTrackingState(currentCamState)

    TurboOverviewCamera.registerMouseHandlers()
    TrackingManager.startModeTransition('overview')

    Log.debug("Turbo Overview camera enabled (Target Height: " .. math.floor(currentHeight) .. " units)")
end

function TurboOverviewCamera.registerMouseHandlers()
    MouseManager.registerMode('overview')

    -- MMB click - move to point
    MouseManager.onMMB('overview', function(x, y)
        Log.debug("MMB - initiating movement")
        MovementUtils.moveToTarget()

        -- Moving cancels rotation
        RotationUtils.cancelRotation("movement")
    end)

    -- MMB hold - look around
    MouseManager.onDragStartMMB('overview', function(startX, startY, currentX, currentY)
        RotationUtils.initCursorRotation(startX, startY)
        Log.debug("Starting MMB drag for look around")

        -- Looking around cancels rotation
        RotationUtils.cancelRotation("looking around")
    end)

    MouseManager.onDragMMB('overview', function(dx, dy, x, y)
        if RotationUtils.updateCursorRotation(dx, dy) then
            STATE.overview.userLookedAround = true
            Log.debug("MMB drag - looking around")
        end
    end)

    MouseManager.onReleaseMMB('overview', function(x, y)
        RotationUtils.resetCursorRotation()
        Log.debug("Resetting cursor rotation after MMB look around")
    end)

    -- RMB hold - toggle rotation mode
    MouseManager.onHoldRMB('overview', function(x, y, holdTime)
        -- If the user just holds RMB and doesn't drag, toggle rotation mode after a threshold
        if holdTime > STATE.mouse.dragTimeThreshold and not STATE.overview.isRotationModeActive then
            -- Only enable rotation if we have a previous target point
            if STATE.overview.lastTargetPoint then
                Log.debug("RMB hold - toggling rotation mode")
                RotationUtils.toggleRotation()
            else
                Log.debug("Cannot enable rotation: No target point available")
            end
        elseif STATE.overview.isRotationModeActive then
            -- Update rotation speed based on cursor position while holding RMB
            RotationUtils.updateRotationSpeed(x, y)
        end
    end)

    -- RMB drag - update rotation speed
    MouseManager.onDragRMB('overview', function(dx, dy, x, y)
        if STATE.overview.isRotationModeActive then
            -- Update rotation speed based on current cursor position
            RotationUtils.updateRotationSpeed(x, y)
        end
    end)

    -- RMB release - cleanup
    MouseManager.onReleaseRMB('overview', function(x, y, wasDoubleClick, wasDragging, holdTime)
        -- If rotation is active but RMB was just a brief click (not dragging),
        -- we should disable rotation mode
        if STATE.overview.isRotationModeActive and not wasDragging and holdTime < STATE.mouse.dragTimeThreshold then
            RotationUtils.cancelRotation("brief click release")
        elseif STATE.overview.isRotationModeActive then
            -- Apply momentum when releasing RMB
            RotationUtils.applyMomentum()
        end

        -- Clear the moveButtonPressed flag that was used in the old system
        STATE.overview.moveButtonPressed = false
    end)
end

-- Simple height change function that updates height and triggers move to target
function TurboOverviewCamera.changeHeightAndMove(amount)
    if Util.isModeDisabled("overview") then
        return
    end

    local granularity = CONFIG.CAMERA_MODES.OVERVIEW.HEIGHT_CONTROL_GRANULARITY
    if not STATE.overview.heightLevel then
        STATE.overview.heightLevel = CONFIG.CAMERA_MODES.OVERVIEW.DEFAULT_HEIGHT_LEVEL
    end

    -- Calculate the new height level
    local newHeightLevel = STATE.overview.heightLevel + amount

    -- Check if the new height level is within valid range
    if newHeightLevel >= 1 and newHeightLevel <= granularity then
        -- Store the previous height level to check if there was a change
        local previousHeightLevel = STATE.overview.heightLevel

        -- Update the height level
        STATE.overview.heightLevel = newHeightLevel

        -- Calculate the new target height
        local newTargetHeight = OverviewCameraUtils.calculateCurrentHeight()

        -- Only proceed with move-to-target if height actually changed
        if previousHeightLevel ~= newHeightLevel then
            -- Set the target height for the move operation
            STATE.overview.targetHeight = newTargetHeight

            -- Call the standard move to target function which uses cursor position
            MovementUtils.moveToTarget()

            Log.debug("Height changed to level " .. STATE.overview.heightLevel ..
                    " (target height: " .. math.floor(newTargetHeight) .. " units)")
        else
            Log.debug("Height level unchanged: " .. STATE.overview.heightLevel)
        end
    else
        Log.debug("Cannot change height level: would exceed valid range (1-" .. granularity .. ")")
    end
end

return {
    TurboOverviewCamera = TurboOverviewCamera
}
