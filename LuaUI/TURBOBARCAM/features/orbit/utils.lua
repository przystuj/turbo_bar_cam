-- Orbiting Camera utils for TURBOBARCAM
-- Load modules
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CommonModules
local TurboCommons = VFS.Include("LuaUI/TURBOBARCAM/common.lua")

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE
local Util = TurboCommons.Util

---@class OrbitCameraUtils
local OrbitCameraUtils = {}

--- Calculates camera position on orbit path
---@param unitPos table Unit position {x, y, z}
---@param angle number Current orbit angle
---@param height number Orbit height
---@param distance number Orbit distance
---@return table camPos Camera position {x, y, z}
function OrbitCameraUtils.calculateOrbitPosition(unitPos, angle, height, distance)
    return {
        x = unitPos.x + distance * math.sin(angle),
        y = unitPos.y + height,
        z = unitPos.z + distance * math.cos(angle)
    }
end

--- Checks for unit movement and handles auto-orbit functionality
---@return boolean stateChanged Whether the tracking state changed
function OrbitCameraUtils.checkUnitMovement()
    -- Only check if we're in FPS mode with a valid unit and auto-orbit is enabled
    if STATE.tracking.mode ~= 'fps' or not STATE.tracking.unitID or not CONFIG.CAMERA_MODES.ORBIT.AUTO_ORBIT.ENABLED then
        return false
    end

    -- Get current unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)
    local currentPos = { x = unitX, y = unitY, z = unitZ }

    -- If this is the first check, just store the position
    if not STATE.orbit.lastPosition then
        STATE.orbit.lastPosition = currentPos
        return false
    end

    -- Check if unit has moved
    local epsilon = 0.1  -- Small threshold to account for floating point precision
    local hasMoved = math.abs(currentPos.x - STATE.orbit.lastPosition.x) > epsilon or
            math.abs(currentPos.y - STATE.orbit.lastPosition.y) > epsilon or
            math.abs(currentPos.z - STATE.orbit.lastPosition.z) > epsilon

    local stateChanged = false

    if hasMoved then
        -- Unit is moving, reset timer
        STATE.orbit.stationaryTimer = nil

        -- If auto-orbit is active, transition back to FPS
        if STATE.orbit.autoOrbitActive then
            STATE.orbit.autoOrbitActive = false
            stateChanged = true

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

            if elapsed > CONFIG.CAMERA_MODES.ORBIT.AUTO_ORBIT.DELAY and not STATE.orbit.autoOrbitActive then
                -- Transition to auto-orbit
                STATE.orbit.autoOrbitActive = true
                stateChanged = true

                -- Initialize orbit settings with default values
                local unitHeight = Util.getUnitHeight(STATE.tracking.unitID)
                CONFIG.CAMERA_MODES.ORBIT.HEIGHT = unitHeight * CONFIG.CAMERA_MODES.ORBIT.HEIGHT_FACTOR
                CONFIG.CAMERA_MODES.ORBIT.SPEED = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_SPEED

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
                CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR / CONFIG.CAMERA_MODES.ORBIT.AUTO_ORBIT.SMOOTHING_FACTOR
            end
        end
    end
    
    -- Update last position
    STATE.orbit.lastPosition = currentPos
    return stateChanged
end

--- Adjusts the orbit speed
---@param amount number Amount to adjust orbit speed by
---@return boolean success Whether speed was adjusted successfully
function OrbitCameraUtils.adjustSpeed(amount)
    if not STATE.enabled then
        Util.debugEcho("TURBOBARCAM must be enabled first")
        return false
    end

    -- Make sure we have a unit to orbit around
    if STATE.tracking.mode ~= 'orbit' or not STATE.tracking.unitID then
        Util.debugEcho("No unit being orbited")
        return false
    end

    CONFIG.CAMERA_MODES.ORBIT.SPEED = math.max(0.0001, math.min(0.005, CONFIG.CAMERA_MODES.ORBIT.SPEED + amount))

    -- Update stored settings for the current unit
    if STATE.tracking.unitID then
        if not STATE.orbit.unitOffsets[STATE.tracking.unitID] then
            STATE.orbit.unitOffsets[STATE.tracking.unitID] = {}
        end

        STATE.orbit.unitOffsets[STATE.tracking.unitID].speed = CONFIG.CAMERA_MODES.ORBIT.SPEED
    end

    -- Print the updated settings
    Util.debugEcho("Orbit speed for unit " .. STATE.tracking.unitID .. ": " .. CONFIG.CAMERA_MODES.ORBIT.SPEED)
    return true
end

--- Resets orbit settings to defaults
---@return boolean success Whether settings were reset successfully
function OrbitCameraUtils.resetSettings()
    if not STATE.enabled then
        Util.debugEcho("TURBOBARCAM must be enabled first")
        return false
    end

    -- If we have a tracked unit, reset its orbit speed
    if STATE.tracking.mode == 'orbit' and STATE.tracking.unitID and Spring.ValidUnitID(STATE.tracking.unitID) then
        CONFIG.CAMERA_MODES.ORBIT.SPEED = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_SPEED

        -- Update stored settings for this unit
        if not STATE.orbit.unitOffsets[STATE.tracking.unitID] then
            STATE.orbit.unitOffsets[STATE.tracking.unitID] = {}
        end
        STATE.orbit.unitOffsets[STATE.tracking.unitID].speed = CONFIG.CAMERA_MODES.ORBIT.SPEED

        Util.debugEcho("Reset orbit speed for unit " .. STATE.tracking.unitID .. " to default")
        return true
    else
        Util.debugEcho("No unit being orbited")
        return false
    end

end

return {
    OrbitCameraUtils = OrbitCameraUtils
}