-- Orbiting Camera utils for TURBOBARCAM
-- Load modules
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CommonModules
local TurboCommons = VFS.Include("LuaUI/TURBOBARCAM/common.lua")

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE
local Util = TurboCommons.Util
local Tracking = TurboCommons.Tracking

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
---@return boolean stateChanged Whether the auto orbit state has changed
function OrbitCameraUtils.handleAutoOrbit()
    -- Only check if we're in FPS mode with a valid unit and auto-orbit is enabled
    if STATE.tracking.mode ~= 'fps' or not STATE.tracking.unitID or not CONFIG.CAMERA_MODES.ORBIT.AUTO_ORBIT.ENABLED then
        return false
    end

    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Util.debugEcho("[handleAutoOrbit] Unit no longer exists")
        Tracking.disableTracking()
        return
    end

    -- Get current unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)
    local currentPos = { x = unitX, y = unitY, z = unitZ }

    -- Get current camera state
    local camState = Spring.GetCameraState()
    local currentCamPos = { x = camState.px, y = camState.py, z = camState.pz }
    local currentCamRot = { rx = camState.rx, ry = camState.ry, rz = camState.rz }

    -- If this is the first check, just store the positions
    if not STATE.orbit.lastPosition then
        STATE.orbit.lastPosition = currentPos
        STATE.orbit.lastCamPos = currentCamPos
        STATE.orbit.lastCamRot = currentCamRot
        return false
    end

    -- Check if unit has moved
    local epsilon = 0.1  -- Small threshold to account for floating point precision
    local hasMoved = math.abs(currentPos.x - STATE.orbit.lastPosition.x) > epsilon or
            math.abs(currentPos.y - STATE.orbit.lastPosition.y) > epsilon or
            math.abs(currentPos.z - STATE.orbit.lastPosition.z) > epsilon

    -- Check if camera has moved (user interaction)
    local camEpsilon = 0.5  -- Slightly larger threshold for camera movement
    local rotEpsilon = 0.01  -- Threshold for rotation changes

    -- Only check camera position/rotation if we have previous values
    local hasCamMoved = false
    if STATE.orbit.autoOrbitActive then
        hasCamMoved = false
    elseif STATE.orbit.lastCamPos and STATE.orbit.lastCamRot then
        hasCamMoved = math.abs(currentCamPos.x - STATE.orbit.lastCamPos.x) > camEpsilon or
                math.abs(currentCamPos.y - STATE.orbit.lastCamPos.y) > camEpsilon or
                math.abs(currentCamPos.z - STATE.orbit.lastCamPos.z) > camEpsilon or
                math.abs(currentCamRot.rx - STATE.orbit.lastCamRot.rx) > rotEpsilon or
                math.abs(currentCamRot.ry - STATE.orbit.lastCamRot.ry) > rotEpsilon
    end

    local stateChanged = false

    -- Consider either unit movement or camera movement as activity
    if hasMoved or hasCamMoved then
        -- Unit or camera is moving, reset timer
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
            Tracking.updateTrackingState(camState)
        end
    else
        -- Unit and camera are stationary
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
                local unitHeight = math.max(Util.getUnitHeight(unitID) + 30, 100)
                CONFIG.CAMERA_MODES.ORBIT.HEIGHT = unitHeight * CONFIG.CAMERA_MODES.ORBIT.HEIGHT_FACTOR
                CONFIG.CAMERA_MODES.ORBIT.SPEED = CONFIG.CAMERA_MODES.ORBIT.DEFAULT_SPEED

                -- Initialize orbit angle based on current camera position
                STATE.orbit.angle = math.atan2(camState.px - unitX, camState.pz - unitZ)

                -- Begin transition from FPS to orbit
                -- We need to do this manually as we're already in "fps" tracking mode
                STATE.tracking.modeTransition = true
                STATE.tracking.transitionStartTime = Spring.GetTimer()

                -- Store current camera position as last position to smooth from
                Tracking.updateTrackingState(camState)

                -- Store original transition factor and use a more delayed transition
                STATE.orbit.originalTransitionFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR
                CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR / CONFIG.CAMERA_MODES.ORBIT.AUTO_ORBIT.SMOOTHING_FACTOR
            end
        end
    end

    -- Update last positions
    STATE.orbit.lastPosition = currentPos
    STATE.orbit.lastCamPos = currentCamPos
    STATE.orbit.lastCamRot = currentCamRot

    return stateChanged
end

---@see ModifiableParams
---@see UtilsModule#adjustParams
function OrbitCameraUtils.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("orbit") then
        return
    end
    -- Make sure we have a unit to orbit around
    if not STATE.tracking.unitID then
        Util.debugEcho("No unit is being orbited")
        return
    end

    Util.adjustParams(params, "ORBIT", function() OrbitCameraUtils.resetSettings() end)

    -- Update stored settings for the current unit
    if STATE.tracking.unitID then
        if not STATE.orbit.unitOffsets[STATE.tracking.unitID] then
            STATE.orbit.unitOffsets[STATE.tracking.unitID] = {}
        end

        STATE.orbit.unitOffsets[STATE.tracking.unitID] = CONFIG.CAMERA_MODES.ORBIT
    end
end

--- Resets orbit settings to defaults
---@return boolean success Whether settings were reset successfully
function OrbitCameraUtils.resetSettings()
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("orbit") then
        return
    end

    -- If we have a tracked unit, reset its orbit speed
    if STATE.tracking.unitID and Spring.ValidUnitID(STATE.tracking.unitID) then
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