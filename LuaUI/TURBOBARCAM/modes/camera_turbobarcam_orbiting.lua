-- Orbiting Camera module for TURBOBARCAM
---@type {CONFIG: CONFIG, STATE: STATE}
local TurboConfig = VFS.Include("LuaUI/TURBOBARCAM/camera_turbobarcam_config.lua")
---@type {Util: Util}
local TurboUtils = VFS.Include("LuaUI/TURBOBARCAM/camera_turbobarcam_utils.lua")

local CONFIG = TurboConfig.CONFIG
local STATE = TurboConfig.STATE
local Util = TurboUtils.Util

---@class OrbitingCamera
local OrbitingCamera = {}

--- Toggles orbiting camera mode
---@param unitID number|nil Optional unit ID (uses selected unit if nil)
function OrbitingCamera.toggle(unitID)
    if not STATE.enabled then
        Spring.Echo("TURBOBARCAM must be enabled first")
        return
    end

    -- If no unitID provided, use the first selected unit
    if not unitID then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            unitID = selectedUnits[1]
        else
            Spring.Echo("No unit selected for Orbiting view")
            return
        end
    end

    -- Check if it's a valid unit
    if not Spring.ValidUnitID(unitID) then
        Spring.Echo("Invalid unit ID for Orbiting view")
        return
    end

    -- If we're already tracking this exact unit in Orbiting mode, turn it off
    if STATE.tracking.mode == 'orbit' and STATE.tracking.unitID == unitID then
        -- Save current orbiting settings before disabling
        STATE.orbit.unitOffsets[unitID] = {
            speed = CONFIG.ORBIT.SPEED
        }

        Util.disableTracking()
        Spring.Echo("Orbiting camera detached")
        return
    end

    -- Get unit height for the default height offset
    local unitHeight = Util.getUnitHeight(unitID)

    -- Check if we have stored settings for this unit
    if STATE.orbit.unitOffsets[unitID] then
        -- Use stored settings
        CONFIG.ORBIT.SPEED = STATE.orbit.unitOffsets[unitID].speed
        Spring.Echo("Using previous orbit speed for unit " .. unitID)
    else
        -- Use default settings
        CONFIG.ORBIT.SPEED = CONFIG.ORBIT.DEFAULT_SPEED

        -- Initialize storage for this unit
        STATE.orbit.unitOffsets[unitID] = {
            speed = CONFIG.ORBIT.SPEED
        }
    end

    -- Set height based on unit height
    CONFIG.ORBIT.HEIGHT = unitHeight * CONFIG.ORBIT.DEFAULT_HEIGHT_FACTOR
    CONFIG.ORBIT.DISTANCE = CONFIG.ORBIT.DEFAULT_DISTANCE

    -- Begin mode transition from previous mode to orbit mode
    Util.beginModeTransition('orbit')
    STATE.tracking.unitID = unitID

    -- Initialize orbit angle based on current camera position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(unitID)
    local camState = Spring.GetCameraState()

    -- Calculate current angle based on camera position relative to unit
    STATE.orbit.angle = math.atan2(camState.px - unitX, camState.pz - unitZ)

    -- Initialize the last position for auto-orbit feature
    STATE.orbit.lastPosition = { x = unitX, y = unitY, z = unitZ }
    STATE.orbit.stationaryTimer = nil
    STATE.orbit.autoOrbitActive = false

    -- Switch to FPS camera mode for consistent behavior
    local camStatePatch = {
        name = "fps",
        mode = 0  -- FPS camera mode
    }
    Spring.SetCameraState(camStatePatch, 0)

    Spring.Echo("Orbiting camera attached to unit " .. unitID)
end

--- Updates the orbit camera's position and rotation
function OrbitingCamera.update()
    if STATE.tracking.mode ~= 'orbit' or not STATE.tracking.unitID then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Spring.Echo("Unit no longer exists, detaching Orbiting camera")
        Util.disableTracking()
        return
    end

    -- Get unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)

    -- Update orbit angle
    STATE.orbit.angle = STATE.orbit.angle + CONFIG.ORBIT.SPEED

    -- Calculate camera position on the orbit circle
    local camX = unitX + CONFIG.ORBIT.DISTANCE * math.sin(STATE.orbit.angle)
    local camY = unitY + CONFIG.ORBIT.HEIGHT
    local camZ = unitZ + CONFIG.ORBIT.DISTANCE * math.cos(STATE.orbit.angle)

    -- Create camera state looking at the unit
    local camPos = { x = camX, y = camY, z = camZ }
    local targetPos = { x = unitX, y = unitY, z = unitZ }
    local lookDir = Util.calculateLookAtPoint(camPos, targetPos)

    -- Determine smoothing factor based on whether we're in a mode transition
    local smoothFactor = CONFIG.SMOOTHING.POSITION_FACTOR
    local rotFactor = CONFIG.SMOOTHING.ROTATION_FACTOR

    if STATE.tracking.modeTransition then
        -- Use a special transition factor during mode changes
        smoothFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR
        rotFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR

        -- Check if we should end the transition (after ~1 second)
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.transitionStartTime)
        if elapsed > 1.0 then
            STATE.tracking.modeTransition = false
        end
    end

    -- If this is the first update, initialize last positions
    if STATE.tracking.lastCamPos.x == 0 and STATE.tracking.lastCamPos.y == 0 and STATE.tracking.lastCamPos.z == 0 then
        STATE.tracking.lastCamPos = { x = camX, y = camY, z = camZ }
        STATE.tracking.lastCamDir = { x = lookDir.dx, y = lookDir.dy, z = lookDir.dz }
        STATE.tracking.lastRotation = { rx = lookDir.rx, ry = lookDir.ry, rz = 0 }
    end

    -- Prepare camera state patch with smoothed values
    local camStatePatch = {
        mode = 0,
        name = "fps",

        -- Smooth camera position
        px = Util.smoothStep(STATE.tracking.lastCamPos.x, camX, smoothFactor),
        py = Util.smoothStep(STATE.tracking.lastCamPos.y, camY, smoothFactor),
        pz = Util.smoothStep(STATE.tracking.lastCamPos.z, camZ, smoothFactor),

        -- Smooth direction
        dx = Util.smoothStep(STATE.tracking.lastCamDir.x, lookDir.dx, smoothFactor),
        dy = Util.smoothStep(STATE.tracking.lastCamDir.y, lookDir.dy, smoothFactor),
        dz = Util.smoothStep(STATE.tracking.lastCamDir.z, lookDir.dz, smoothFactor),

        -- Smooth rotation
        rx = Util.smoothStep(STATE.tracking.lastRotation.rx, lookDir.rx, rotFactor),
        ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, lookDir.ry, rotFactor),
        rz = 0
    }

    -- Update last values for next frame
    STATE.tracking.lastCamPos.x = camStatePatch.px
    STATE.tracking.lastCamPos.y = camStatePatch.py
    STATE.tracking.lastCamPos.z = camStatePatch.pz
    STATE.tracking.lastCamDir.x = camStatePatch.dx
    STATE.tracking.lastCamDir.y = camStatePatch.dy
    STATE.tracking.lastCamDir.z = camStatePatch.dz
    STATE.tracking.lastRotation.rx = camStatePatch.rx
    STATE.tracking.lastRotation.ry = camStatePatch.ry

    -- Apply camera state
    Spring.SetCameraState(camStatePatch, 0)
end

--- Adjusts the orbit speed
---@param amount number Amount to adjust orbit speed by
function OrbitingCamera.adjustSpeed(amount)
    if not STATE.enabled then
        Spring.Echo("TURBOBARCAM must be enabled first")
        return
    end

    -- Make sure we have a unit to orbit around
    if STATE.tracking.mode ~= 'orbit' or not STATE.tracking.unitID then
        Spring.Echo("No unit being orbited")
        return
    end

    CONFIG.ORBIT.SPEED = math.max(0.0001, math.min(0.05, CONFIG.ORBIT.SPEED + amount))

    -- Update stored settings for the current unit
    if STATE.tracking.unitID then
        if not STATE.orbit.unitOffsets[STATE.tracking.unitID] then
            STATE.orbit.unitOffsets[STATE.tracking.unitID] = {}
        end

        STATE.orbit.unitOffsets[STATE.tracking.unitID].speed = CONFIG.ORBIT.SPEED
    end

    -- Print the updated settings
    Spring.Echo("Orbit speed for unit " .. STATE.tracking.unitID .. ": " .. CONFIG.ORBIT.SPEED)
end

--- Resets orbit settings to defaults
function OrbitingCamera.resetSettings()
    if not STATE.enabled then
        Spring.Echo("TURBOBARCAM must be enabled first")
        return
    end

    -- If we have a tracked unit, reset its orbit speed
    if STATE.tracking.mode == 'orbit' and STATE.tracking.unitID and Spring.ValidUnitID(STATE.tracking.unitID) then
        CONFIG.ORBIT.SPEED = CONFIG.ORBIT.DEFAULT_SPEED

        -- Update stored settings for this unit
        if not STATE.orbit.unitOffsets[STATE.tracking.unitID] then
            STATE.orbit.unitOffsets[STATE.tracking.unitID] = {}
        end
        STATE.orbit.unitOffsets[STATE.tracking.unitID].speed = CONFIG.ORBIT.SPEED

        Spring.Echo("Reset orbit speed for unit " .. STATE.tracking.unitID .. " to default")
    else
        Spring.Echo("No unit being orbited")
    end
end

--- Checks for unit movement and handles auto-orbit functionality
function OrbitingCamera.checkUnitMovement()
    -- Only check if we're in FPS mode with a valid unit and auto-orbit is enabled
    if STATE.tracking.mode ~= 'fps' or not STATE.tracking.unitID or not CONFIG.ORBIT.AUTO_ORBIT_ENABLED then
        return
    end

    -- Get current unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)
    local currentPos = { x = unitX, y = unitY, z = unitZ }

    -- If this is the first check, just store the position
    if not STATE.orbit.lastPosition then
        STATE.orbit.lastPosition = currentPos
        return
    end

    -- Check if unit has moved
    local epsilon = 0.1  -- Small threshold to account for floating point precision
    local hasMoved = math.abs(currentPos.x - STATE.orbit.lastPosition.x) > epsilon or
            math.abs(currentPos.y - STATE.orbit.lastPosition.y) > epsilon or
            math.abs(currentPos.z - STATE.orbit.lastPosition.z) > epsilon

    if hasMoved then
        -- Unit is moving, reset timer
        STATE.orbit.stationaryTimer = nil

        -- If auto-orbit is active, transition back to FPS
        if STATE.orbit.autoOrbitActive then
            STATE.orbit.autoOrbitActive = false

            -- Begin transition from orbit back to FPS mode
            -- We need to do this manually as we're already in "fps" tracking mode
            STATE.tracking.modeTransition = true
            STATE.tracking.transitionStartTime = Spring.GetTimer()

            -- Restore original transition factor
            if STATE.orbit.originalTransitionFactor then
                CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR = STATE.orbit.originalTransitionFactor
                STATE.orbit.originalTransitionFactor = nil
            end

            -- Store current camera position as last position to smooth from
            local camState = Spring.GetCameraState()
            STATE.tracking.lastCamPos = { x = camState.px, y = camState.py, z = camState.pz }
            STATE.tracking.lastCamDir = { x = camState.dx, y = camState.dy, z = camState.dz }
            STATE.tracking.lastRotation = { rx = camState.rx, ry = camState.ry, rz = camState.rz }
        end
    else
        -- Unit is stationary
        if not STATE.orbit.stationaryTimer then
            -- Start timer
            STATE.orbit.stationaryTimer = Spring.GetTimer()
        else
            -- Check if we've been stationary long enough
            local now = Spring.GetTimer()
            local elapsed = Spring.DiffTimers(now, STATE.orbit.stationaryTimer)

            if elapsed > CONFIG.ORBIT.AUTO_ORBIT_DELAY and not STATE.orbit.autoOrbitActive then
                -- Transition to auto-orbit
                STATE.orbit.autoOrbitActive = true

                -- Initialize orbit settings with default values
                local unitHeight = Util.getUnitHeight(STATE.tracking.unitID)
                CONFIG.ORBIT.HEIGHT = unitHeight * CONFIG.ORBIT.DEFAULT_HEIGHT_FACTOR
                CONFIG.ORBIT.DISTANCE = CONFIG.ORBIT.DEFAULT_DISTANCE
                CONFIG.ORBIT.SPEED = CONFIG.ORBIT.DEFAULT_SPEED

                -- Initialize orbit angle based on current camera position
                local camState = Spring.GetCameraState()
                STATE.orbit.angle = math.atan2(camState.px - unitX, camState.pz - unitZ)

                -- Begin transition from FPS to orbit
                -- We need to do this manually as we're already in "fps" tracking mode
                STATE.tracking.modeTransition = true
                STATE.tracking.transitionStartTime = Spring.GetTimer()

                -- Store current camera position as last position to smooth from
                STATE.tracking.lastCamPos = { x = camState.px, y = camState.py, z = camState.pz }
                STATE.tracking.lastCamDir = { x = camState.dx, y = camState.dy, z = camState.dz }
                STATE.tracking.lastRotation = { rx = camState.rx, ry = camState.ry, rz = camState.rz }

                -- Store original transition factor and use a more delayed transition
                STATE.orbit.originalTransitionFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR
                CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR / CONFIG.ORBIT.AUTO_ORBIT_SMOOTHING_FACTOR
            end
        end
    end
    -- Update last position
    STATE.orbit.lastPosition = currentPos
end

--- Updates the auto-orbit camera
function OrbitingCamera.updateAutoOrbit()
    if not STATE.orbit.autoOrbitActive or STATE.tracking.mode ~= 'fps' or not STATE.tracking.unitID then
        return
    end

    -- Auto-orbit uses the same update logic as manual orbit, but without changing tracking.mode
    -- Get unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)

    -- Update orbit angle
    STATE.orbit.angle = STATE.orbit.angle + CONFIG.ORBIT.SPEED

    -- Calculate camera position on the orbit circle
    local camX = unitX + CONFIG.ORBIT.DISTANCE * math.sin(STATE.orbit.angle)
    local camY = unitY + CONFIG.ORBIT.HEIGHT
    local camZ = unitZ + CONFIG.ORBIT.DISTANCE * math.cos(STATE.orbit.angle)

    -- Create camera state looking at the unit
    local camPos = { x = camX, y = camY, z = camZ }
    local targetPos = { x = unitX, y = unitY, z = unitZ }
    local lookDir = Util.calculateLookAtPoint(camPos, targetPos)

    -- Determine smoothing factor - use a very smooth transition for auto-orbit
    local smoothFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR / CONFIG.ORBIT.AUTO_ORBIT_SMOOTHING_FACTOR
    local rotFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR / CONFIG.ORBIT.AUTO_ORBIT_SMOOTHING_FACTOR

    -- Prepare camera state patch with smoothed values
    local camStatePatch = {
        mode = 0,
        name = "fps",

        -- Smooth camera position
        px = Util.smoothStep(STATE.tracking.lastCamPos.x, camX, smoothFactor),
        py = Util.smoothStep(STATE.tracking.lastCamPos.y, camY, smoothFactor),
        pz = Util.smoothStep(STATE.tracking.lastCamPos.z, camZ, smoothFactor),

        -- Smooth direction
        dx = Util.smoothStep(STATE.tracking.lastCamDir.x, lookDir.dx, smoothFactor),
        dy = Util.smoothStep(STATE.tracking.lastCamDir.y, lookDir.dy, smoothFactor),
        dz = Util.smoothStep(STATE.tracking.lastCamDir.z, lookDir.dz, smoothFactor),

        -- Smooth rotation
        rx = Util.smoothStep(STATE.tracking.lastRotation.rx, lookDir.rx, rotFactor),
        ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, lookDir.ry, rotFactor),
        rz = 0
    }

    -- Update last values for next frame
    STATE.tracking.lastCamPos.x = camStatePatch.px
    STATE.tracking.lastCamPos.y = camStatePatch.py
    STATE.tracking.lastCamPos.z = camStatePatch.pz
    STATE.tracking.lastCamDir.x = camStatePatch.dx
    STATE.tracking.lastCamDir.y = camStatePatch.dy
    STATE.tracking.lastCamDir.z = camStatePatch.dz
    STATE.tracking.lastRotation.rx = camStatePatch.rx
    STATE.tracking.lastRotation.ry = camStatePatch.ry

    -- Apply camera state
    Spring.SetCameraState(camStatePatch, 0)
end

return {
    OrbitingCamera = OrbitingCamera
}