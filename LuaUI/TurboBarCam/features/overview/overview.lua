---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local TrackingManager = CommonModules.TrackingManager
local CameraCommons = CommonModules.CameraCommons

---@type {OverviewCameraUtils: OverviewCameraUtils}
local OverviewUtils = VFS.Include("LuaUI/TurboBarCam/features/overview/overview_utils.lua")
local OverviewCameraUtils = OverviewUtils.OverviewCameraUtils

---@class TurboOverviewCamera
local TurboOverviewCamera = {}

--- Toggles turbo overview camera mode
--- Enables or disables the turbo overview camera. This camera mode provides a
--- high-altitude perspective with smooth rotation based on cursor position
--- and the ability to move toward target points.
function TurboOverviewCamera.toggle()
    if Util.isTurboBarCamDisabled() then
        return
    end

    -- If we're already in turbo overview mode, turn it off
    if STATE.tracking.mode == 'turbo_overview' then
        TrackingManager.disableTracking()
        Log.debug("Turbo Overview camera disabled")
        return
    end

    -- Get map dimensions to calculate height
    local mapX = Game.mapSizeX
    local mapZ = Game.mapSizeZ
    local mapDiagonal = math.sqrt(mapX * mapX + mapZ * mapZ)

    Log.debug("Map dimensions: " .. mapX .. " x " .. mapZ)
    Log.debug("Map diagonal: " .. mapDiagonal)

    -- Initialize turbo overview state with config values
    STATE.turboOverview.zoomLevel = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.DEFAULT_ZOOM_LEVEL

    -- Camera rotation parameters
    STATE.turboOverview.maxRotationSpeed = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.MAX_ROTATION_SPEED
    STATE.turboOverview.edgeRotationMultiplier = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.EDGE_ROTATION_MULTIPLIER

    -- Movement parameters
    STATE.turboOverview.maxAngularVelocity = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.MAX_ANGULAR_VELOCITY
    STATE.turboOverview.angularDamping = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ANGULAR_DAMPING
    STATE.turboOverview.forwardVelocity = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.FORWARD_VELOCITY
    STATE.turboOverview.minDistanceToTarget = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.MIN_DISTANCE
    STATE.turboOverview.movementTransitionFactor = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.TRANSITION_FACTOR
    STATE.turboOverview.modeTransitionTime = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.MODE_TRANSITION_TIME
    STATE.turboOverview.mouseMoveSensitivity = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.MOUSE_MOVE_SENSITIVITY / 10

    -- For tracking zoom transitions
    STATE.turboOverview.targetHeight = nil
    STATE.turboOverview.inZoomTransition = false

    -- Reset movement states
    STATE.turboOverview.isMovingToTarget = false
    STATE.turboOverview.movingToTarget = false
    STATE.turboOverview.inMovementTransition = false
    STATE.turboOverview.angularVelocity = 0
    STATE.turboOverview.movementAngle = 0
    STATE.turboOverview.distanceToTarget = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.MIN_DISTANCE

    -- Set a good default height based on map size and zoom level
    STATE.turboOverview.height = math.max(mapDiagonal * CONFIG.CAMERA_MODES.TURBO_OVERVIEW.HEIGHT_FACTOR, 500)
    Log.debug("Base camera height: " .. STATE.turboOverview.height)

    -- Calculate current height based on zoom level
    local currentHeight = OverviewCameraUtils.calculateCurrentHeight()
    STATE.turboOverview.targetHeight = currentHeight -- Initialize target height
    Log.debug("Current camera height: " .. currentHeight)

    -- Get current camera state
    local currentCamState = CameraManager.getCameraState("TurboOverviewCamera.toggle")

    -- Check if we have selected units
    local selectedUnits = Spring.GetSelectedUnits()
    local targetPoint = nil
    local targetCamPos = nil

    if #selectedUnits > 0 then
        -- Unit-focused mode: position camera to look at the selected unit
        local unitID = selectedUnits[1]
        local unitX, unitY, unitZ = Spring.GetUnitPosition(unitID)

        if unitX and unitZ then
            targetPoint = { x = unitX, y = unitY, z = unitZ }

            -- Calculate an appropriate position based on unit
            -- We want to be positioned at an angle (around 45 degrees) above the unit
            local offsetDistance = currentHeight * 0.8 -- Position the camera at offset based on height

            -- Calculate an appropriate angle (avoid positioning outside map)
            -- Start with default position (45 degrees to the south)
            local offsetX = -offsetDistance
            local offsetZ = -offsetDistance

            -- Check map boundaries
            local margin = 200
            local newX = targetPoint.x + offsetX
            local newZ = targetPoint.z + offsetZ

            -- If position would be outside map, try different quadrants
            if newX < margin or newX > mapX - margin or newZ < margin or newZ > mapZ - margin then
                -- Try northeast position
                offsetX = offsetDistance
                offsetZ = -offsetDistance
                newX = targetPoint.x + offsetX
                newZ = targetPoint.z + offsetZ

                -- If still outside, try northwest
                if newX < margin or newX > mapX - margin or newZ < margin or newZ > mapZ - margin then
                    offsetX = -offsetDistance
                    offsetZ = offsetDistance
                    newX = targetPoint.x + offsetX
                    newZ = targetPoint.z + offsetZ

                    -- If still outside, try southeast
                    if newX < margin or newX > mapX - margin or newZ < margin or newZ > mapZ - margin then
                        offsetX = offsetDistance
                        offsetZ = offsetDistance
                        newX = targetPoint.x + offsetX
                        newZ = targetPoint.z + offsetZ

                        -- Last resort, just position directly above
                        if newX < margin or newX > mapX - margin or newZ < margin or newZ > mapZ - margin then
                            newX = targetPoint.x
                            newZ = targetPoint.z
                        end
                    end
                end
            end

            -- Store the target camera position but don't set it directly
            targetCamPos = {
                x = newX,
                y = currentHeight,
                z = newZ
            }

            Log.debug("Setting target position to look at selected unit " .. unitID)
        else
            -- Fallback if unit position can't be determined
            Log.debug("Could not get selected unit position, using default positioning")
            targetCamPos = {
                x = currentCamState.px,
                y = currentHeight,
                z = currentCamState.pz
            }
        end
    else
        -- No unit selected, use trace ray approach from the current paste
        -- Calculate the position where the camera is currently looking
        local viewDistance = 1000 -- Default distance to look ahead
        targetPoint = {
            x = currentCamState.px + currentCamState.dx * viewDistance,
            y = currentCamState.py + currentCamState.dy * viewDistance,
            z = currentCamState.pz + currentCamState.dz * viewDistance
        }

        -- Trace a ray to find where the camera is actually looking
        local success, groundPos = Spring.TraceScreenRay(Spring.GetViewGeometry() / 2, Spring.GetViewGeometry() / 2, true)
        if success and groundPos then
            targetPoint = { x = groundPos[1], y = groundPos[2], z = groundPos[3] }
        end

        -- Use current position as target position
        targetCamPos = {
            x = currentCamState.px,
            y = currentHeight,
            z = currentCamState.pz
        }
    end

    -- For smooth transitions, we want to start from the current position
    -- but gradually move toward the target position during the transition
    STATE.turboOverview.fixedCamPos = {
        x = currentCamState.px,
        y = currentCamState.py, -- Will be smoothly adjusted to target height
        z = currentCamState.pz
    }

    -- Store the target position for smooth transition in update
    -- This is what makes the transition smooth instead of snapping
    STATE.turboOverview.targetCamPos = targetCamPos

    -- Calculate initial rotation to look at target point
    local lookDir = Util.calculateLookAtPoint(targetCamPos, targetPoint)

    -- Initialize rotation targets with calculated values for looking at focal point
    STATE.turboOverview.targetRx = lookDir.rx
    STATE.turboOverview.targetRy = lookDir.ry

    -- Get current mouse position for initialization
    STATE.turboOverview.lastMouseX, STATE.turboOverview.lastMouseY = Spring.GetMouseState()

    -- Set up initial tracking state values using current camera position
    STATE.tracking.lastCamPos = {
        x = currentCamState.px,
        y = currentCamState.py,
        z = currentCamState.pz
    }

    -- Initialize last camera direction
    STATE.tracking.lastCamDir = {
        x = currentCamState.dx or 0,
        y = currentCamState.dy or -1,
        z = currentCamState.dz or 0
    }

    -- Initialize last rotation for smooth transitions
    STATE.tracking.lastRotation = {
        rx = currentCamState.rx or math.pi / 4,
        ry = currentCamState.ry or 0,
        rz = 0
    }

    -- Setup initial tracking state
    TrackingManager.updateTrackingState(currentCamState)

    -- Begin mode transition from previous mode to turbo overview mode
    TrackingManager.startModeTransition('turbo_overview')

    Log.debug("Turbo Overview camera enabled (Zoom: x" ..
            CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ZOOM_LEVELS[STATE.turboOverview.zoomLevel] .. ")")
end

--- Updates the turbo overview camera's position and orientation
--- Called every frame when the camera is in turbo overview mode.
--- Handles smooth transitions, cursor tracking, zoom effects,
--- and target movement behavior.
function TurboOverviewCamera.update()
    if STATE.tracking.mode ~= 'turbo_overview' then
        return
    end

    -- Get current camera state
    local camState = CameraManager.getCameraState("TurboOverviewCamera.update")

    -- Ensure we're in FPS mode
    if camState.mode ~= 0 then
        camState.mode = 0
        camState.name = "fps"
    end

    -- Track if transition is ending this frame
    local transitionEndingThisFrame = false

    -- Determine smoothing factor based on whether we're in a mode transition
    local smoothFactor = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.MOVEMENT_SMOOTHING
    local rotFactor = CONFIG.SMOOTHING.FREE_CAMERA_FACTOR * 0.5

    if STATE.tracking.modeTransition then
        -- Use a gentler transition factor during mode changes to avoid fast movement
        smoothFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR * 0.5

        -- If we have a target camera position, smoothly move toward it during the transition
        if STATE.turboOverview.targetCamPos then
            STATE.turboOverview.fixedCamPos.x = Util.smoothStep(STATE.turboOverview.fixedCamPos.x,
                    STATE.turboOverview.targetCamPos.x,
                    smoothFactor)
            STATE.turboOverview.fixedCamPos.z = Util.smoothStep(STATE.turboOverview.fixedCamPos.z,
                    STATE.turboOverview.targetCamPos.z,
                    smoothFactor)
        end

        -- Allow cursor tracking during transition - this enables free look
        OverviewCameraUtils.updateCursorTracking(STATE.turboOverview)

        -- Check if we should end the transition
        if CameraCommons.isTransitionComplete(STATE.tracking.transitionStartTime) then
            -- Mark that transition is ending this frame
            transitionEndingThisFrame = true

            -- Record current camera state for a smooth handoff
            local handoffState = {
                position = {
                    x = camState.px,
                    y = camState.py,
                    z = camState.pz
                },
                rotation = {
                    rx = camState.rx,
                    ry = camState.ry
                },
                direction = {
                    x = camState.dx,
                    y = camState.dy,
                    z = camState.dz
                }
            }

            -- End the transition
            STATE.tracking.modeTransition = false

            -- Save the current target rotation values to prevent any jump
            STATE.turboOverview.targetRx = camState.rx
            STATE.turboOverview.targetRy = camState.ry

            -- Fix the camera position to the current actual position
            STATE.turboOverview.fixedCamPos = {
                x = camState.px,
                z = camState.pz
            }

            -- Clear the target position since we're done with it
            STATE.turboOverview.targetCamPos = nil

            -- Update tracking state to exactly match current camera
            STATE.tracking.lastCamPos = {
                x = camState.px,
                y = camState.py,
                z = camState.pz
            }

            STATE.tracking.lastCamDir = {
                x = camState.dx,
                y = camState.dy,
                z = camState.dz
            }

            STATE.tracking.lastRotation = {
                rx = camState.rx,
                ry = camState.ry,
                rz = camState.rz
            }

            Log.debug("Overview camera transition complete - continuing with current view")
        end
    end

    -- If this is the first update, initialize last positions to current
    if STATE.tracking.lastCamPos.x == 0 and
            STATE.tracking.lastCamPos.y == 0 and
            STATE.tracking.lastCamPos.z == 0 then
        STATE.tracking.lastCamPos = { x = camState.px, y = camState.py, z = camState.pz }
        -- Initialize fixed camera position too
        STATE.turboOverview.fixedCamPos = { x = camState.px, y = camState.py, z = camState.pz }
    end

    -- Handle zoom height transitions
    local currentHeight = camState.py
    local targetHeight = STATE.turboOverview.targetHeight or OverviewCameraUtils.calculateCurrentHeight()

    if math.abs(currentHeight - targetHeight) > 1 then
        -- We're in a zoom transition
        STATE.turboOverview.inZoomTransition = true
        currentHeight = Util.smoothStep(currentHeight, targetHeight, CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ZOOM_TRANSITION_FACTOR)
    else
        STATE.turboOverview.inZoomTransition = false
        currentHeight = targetHeight
    end

    -- Update target movement if in that mode
    if STATE.turboOverview.isMovingToTarget then
        OverviewCameraUtils.updateTargetMovement()

        -- Get camera position with current height
        local camPos = {
            x = STATE.turboOverview.fixedCamPos.x,
            y = currentHeight,
            z = STATE.turboOverview.fixedCamPos.z
        }

        -- Calculate look direction to the target point
        local lookDir = Util.calculateLookAtPoint(camPos, STATE.turboOverview.targetPoint)

        -- During movement transition, smoothly interpolate between current rotation and target rotation
        local rx, ry
        if STATE.turboOverview.inMovementTransition then
            rx = Util.smoothStep(STATE.tracking.lastRotation.rx, lookDir.rx, STATE.turboOverview.movementTransitionFactor)
            ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, lookDir.ry, STATE.turboOverview.movementTransitionFactor)
        else
            rx = lookDir.rx
            ry = lookDir.ry
        end

        -- Prepare camera state patch
        local camStatePatch = {
            mode = 0,
            name = "fps",
            -- Updated camera position
            px = camPos.x,
            py = camPos.y,
            pz = camPos.z,
            -- Direction vector to look at target
            dx = lookDir.dx,
            dy = lookDir.dy,
            dz = lookDir.dz,
            -- Rotation from look direction
            rx = rx,
            ry = ry,
            rz = 0
        }

        TrackingManager.updateTrackingState(camStatePatch)

        -- Apply camera state
        CameraManager.setCameraState(camStatePatch, 0, "TurboOverviewCamera.update")
        return
    end

    -- Use continuous rotation based on cursor position
    -- Only run normal cursor tracking if we're not in transition
    -- (because we're already updating cursor tracking during transition above)
    if not STATE.tracking.modeTransition and not transitionEndingThisFrame then
        OverviewCameraUtils.updateCursorTracking(STATE.turboOverview)
    end

    -- Get camera position - ensure we're using exactly the stored position
    local camPos = {
        x = STATE.turboOverview.fixedCamPos.x,
        y = currentHeight,
        z = STATE.turboOverview.fixedCamPos.z
    }

    -- Special case for transition ending frame - use exact current state
    local rx, ry, dx, dy, dz
    if transitionEndingThisFrame then
        -- On the transition ending frame, preserve the exact camera state
        rx = camState.rx
        ry = camState.ry
        dx = camState.dx
        dy = camState.dy
        dz = camState.dz
    else
        -- Normal rotation interpolation
        rx = Util.smoothStep(STATE.tracking.lastRotation.rx, STATE.turboOverview.targetRx, rotFactor)
        ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, STATE.turboOverview.targetRy, rotFactor)

        -- Calculate direction vector from rotation angles
        local cosRx = math.cos(rx)
        dx = math.sin(ry) * cosRx
        dz = math.cos(ry) * cosRx
        dy = math.sin(rx)
    end

    -- Prepare camera state patch
    local camStatePatch = {
        mode = 0,
        name = "fps",
        -- Fixed camera position (only moves when going to target)
        px = camPos.x,
        py = camPos.y,
        pz = camPos.z,
        -- Direction vector
        dx = dx,
        dy = dy,
        dz = dz,
        -- Rotation angles
        rx = rx,
        ry = ry,
        rz = 0
    }

    -- Update last position for next frame
    STATE.tracking.lastCamPos.x = camStatePatch.px
    STATE.tracking.lastCamPos.y = camStatePatch.py
    STATE.tracking.lastCamPos.z = camStatePatch.pz

    -- Update last rotation for next frame
    STATE.tracking.lastRotation.rx = camStatePatch.rx
    STATE.tracking.lastRotation.ry = camStatePatch.ry
    STATE.tracking.lastRotation.rz = camStatePatch.rz

    -- Also update last camera direction
    STATE.tracking.lastCamDir.x = camStatePatch.dx
    STATE.tracking.lastCamDir.y = camStatePatch.dy
    STATE.tracking.lastCamDir.z = camStatePatch.dz

    -- Apply camera state
    CameraManager.setCameraState(camStatePatch, 0, "TurboOverviewCamera.update")
end

--- Toggles between available zoom levels
--- Cycles through the predefined zoom levels with smooth transitions.
function TurboOverviewCamera.toggleZoom()
    if STATE.tracking.mode ~= 'turbo_overview' then
        Log.debug("Turbo Overview camera must be enabled first")
        return
    end

    -- Cycle to the next zoom level
    STATE.turboOverview.zoomLevel = STATE.turboOverview.zoomLevel + 1
    if STATE.turboOverview.zoomLevel > #CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ZOOM_LEVELS then
        STATE.turboOverview.zoomLevel = 1
    end

    -- Update target height for smooth transition
    STATE.turboOverview.targetHeight = OverviewCameraUtils.calculateCurrentHeight()

    local newZoom = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ZOOM_LEVELS[STATE.turboOverview.zoomLevel]
    Log.debug("Turbo Overview camera zoom: x" .. newZoom)

    -- Force an update to start the transition
    TurboOverviewCamera.update()
end

--- Sets a specific zoom level
--- Directly sets the camera to the specified zoom level with a smooth transition.
---@param level number Zoom level index (1-based index to zoomLevels array)
function TurboOverviewCamera.setZoomLevel(level)
    if STATE.tracking.mode ~= 'turbo_overview' then
        Log.debug("Turbo Overview camera must be enabled first")
        return
    end

    level = tonumber(level)
    if not level or level < 1 or level > #CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ZOOM_LEVELS then
        Log.debug("Invalid zoom level. Available levels: 1-" .. #CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ZOOM_LEVELS)
        return
    end

    -- Set the new zoom level
    STATE.turboOverview.zoomLevel = level

    -- Update target height for smooth transition
    STATE.turboOverview.targetHeight = OverviewCameraUtils.calculateCurrentHeight()

    local newZoom = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.ZOOM_LEVELS[STATE.turboOverview.zoomLevel]
    Log.debug("Turbo Overview camera zoom set to: x" .. newZoom)

    -- Force an update to start the transition
    TurboOverviewCamera.update()
end

---@see ModifiableParams
---@see Util#adjustParams
function TurboOverviewCamera.adjustParams(params)
    OverviewCameraUtils.adjustParams(params)
end

--- Moves the camera toward a target point with steering capability
--- Enables a mode where the camera moves toward the cursor position,
--- with the ability to steer using the mouse position.
---@return boolean success Whether the camera started moving successfully
function TurboOverviewCamera.moveToTarget()
    if Util.isModeDisabled("turbo_overview") then
        return false
    end

    -- Toggle target movement mode on/off
    if STATE.turboOverview.movingToTarget then
        STATE.turboOverview.movingToTarget = false
        Log.debug("Target movement mode exited")
    else
        -- Get cursor position and set it as target point
        STATE.turboOverview.targetPoint = OverviewCameraUtils.getCursorWorldPosition()

        -- Get current camera state
        local currentCamState = CameraManager.getCameraState("TurboOverviewCamera.moveToTarget")

        -- Begin mode transition explicitly
        STATE.tracking.modeTransition = true
        STATE.tracking.transitionStartTime = Spring.GetTimer()

        -- Start movement mode
        STATE.turboOverview.isMovingToTarget = true

        -- Store the screen center coordinates for relative cursor position calculations
        local screenWidth, screenHeight = Spring.GetViewGeometry()
        STATE.turboOverview.screenCenterX = screenWidth / 2
        STATE.turboOverview.screenCenterY = screenHeight / 2

        -- Initialize movement parameters
        local camPos = STATE.turboOverview.fixedCamPos

        -- Set initial target rotation to match current view direction
        -- This ensures smooth transition from current view to target
        STATE.turboOverview.targetRx = currentCamState.rx
        STATE.turboOverview.targetRy = currentCamState.ry

        -- Calculate the movement angle based on camera position
        STATE.turboOverview.movementAngle = OverviewCameraUtils.calculateMovementAngle(
                STATE.turboOverview.targetPoint, camPos)
        STATE.turboOverview.targetMovementAngle = STATE.turboOverview.movementAngle

        -- Calculate initial distance
        local dx = camPos.x - STATE.turboOverview.targetPoint.x
        local dz = camPos.z - STATE.turboOverview.targetPoint.z
        STATE.turboOverview.distanceToTarget = math.sqrt(dx * dx + dz * dz)

        -- Set the angular velocity to 0 initially
        STATE.turboOverview.angularVelocity = 0

        -- Set the forward velocity constant from CONFIG
        STATE.turboOverview.forwardVelocity = CONFIG.CAMERA_MODES.TURBO_OVERVIEW.FORWARD_VELOCITY

        -- Turn on active movement
        STATE.turboOverview.movingToTarget = true

        -- Enable movement transition mode (for smooth entry)
        STATE.turboOverview.inMovementTransition = true

        -- Record the start time for gradual acceleration
        STATE.turboOverview.moveStartTime = Spring.GetTimer()

        -- Get current mouse position
        STATE.turboOverview.lastMouseX, STATE.turboOverview.lastMouseY = Spring.GetMouseState()

        Log.debug("Target movement mode started")
    end

    return true
end

return {
    TurboOverviewCamera = TurboOverviewCamera
}