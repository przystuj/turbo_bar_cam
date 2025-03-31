-- Import configuration
local TurboConfig = VFS.Include("LuaUI/Widgets/TURBOBARCAM/camera_turbobarcam_config.lua")
local CONFIG = TurboConfig.CONFIG
local STATE = TurboConfig.STATE

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------
local Util = {}

-- Debug functions
function Util.dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then
                k = '"' .. k .. '"'
            end
            s = s .. '[' .. k .. '] = ' .. Util.dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

function Util.log(o)
    Spring.Echo(Util.dump(o))
end

-- Deep copy function for tables
function Util.deepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = Util.deepCopy(orig_value)
        end
    else
        copy = orig
    end
    return copy
end

-- Interpolation functions
function Util.easeInOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local t2 = (t - 1)
        return 1 + 4 * t2 * t2 * t2
    end
end

function Util.lerp(a, b, t)
    return a + (b - a) * t
end

-- Normalize angle to be within -pi to pi range
function Util.normalizeAngle(angle)
    if angle == nil then
        return 0 -- Default to 0 if angle is nil
    end

    local twoPi = 2 * math.pi
    angle = angle % twoPi
    if angle > math.pi then
        angle = angle - twoPi
    end
    return angle
end

-- Interpolate between two angles, always taking the shortest path
function Util.lerpAngle(a, b, t)
    -- Normalize both angles to -pi to pi range
    a = Util.normalizeAngle(a)
    b = Util.normalizeAngle(b)

    -- Find the shortest path
    local diff = b - a

    -- If the difference is greater than pi, we need to go the other way around
    if diff > math.pi then
        diff = diff - 2 * math.pi
    elseif diff < -math.pi then
        diff = diff + 2 * math.pi
    end

    return a + diff * t
end

-- Get unit height
function Util.getUnitHeight(unitID)
    if not Spring.ValidUnitID(unitID) then
        return CONFIG.FPS.DEFAULT_HEIGHT_OFFSET
    end

    -- Get unit definition ID and access height from UnitDefs
    local unitDefID = Spring.GetUnitDefID(unitID)
    if not unitDefID then
        return CONFIG.FPS.DEFAULT_HEIGHT_OFFSET
    end

    local unitDef = UnitDefs[unitDefID]
    if not unitDef then
        return CONFIG.FPS.DEFAULT_HEIGHT_OFFSET
    end

    -- Return unit height or default if not available
    return unitDef.height + 20 or CONFIG.FPS.DEFAULT_HEIGHT_OFFSET
end

function Util.smoothStep(current, target, factor)
    if current == nil or target == nil or factor == nil then
        return current or target or 0
    end
    return current + (target - current) * factor
end

-- Smooth interpolation between two angles
function Util.smoothStepAngle(current, target, factor)
    -- Add safety check for nil values
    if current == nil or target == nil or factor == nil then
        return current or target or 0 -- Return whichever is not nil, or 0 if both are nil
    end

    -- Normalize both angles to -pi to pi range
    current = Util.normalizeAngle(current)
    target = Util.normalizeAngle(target)

    -- Find the shortest path
    local diff = target - current

    -- If the difference is greater than pi, we need to go the other way around
    if diff > math.pi then
        diff = diff - 2 * math.pi
    elseif diff < -math.pi then
        diff = diff + 2 * math.pi
    end

    return current + diff * factor
end

-- Calculate camera direction and rotation to look at a point
function Util.calculateLookAtPoint(camPos, targetPos)
    -- Calculate direction vector from camera to target
    local dirX = targetPos.x - camPos.x
    local dirY = targetPos.y - camPos.y
    local dirZ = targetPos.z - camPos.z

    -- Normalize the direction vector
    local length = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)
    if length > 0 then
        dirX = dirX / length
        dirY = dirY / length
        dirZ = dirZ / length
    end

    -- Calculate appropriate rotation for FPS camera
    local ry = -math.atan2(dirX, dirZ) - math.pi

    -- Calculate pitch (rx)
    local horizontalLength = math.sqrt(dirX * dirX + dirZ * dirZ)
    local rx = -((math.atan2(dirY, horizontalLength) - math.pi) / 1.8)

    return {
        dx = dirX,
        dy = dirY,
        dz = dirZ,
        rx = rx,
        ry = ry,
        rz = 0
    }
end

function Util.beginModeTransition(newMode)
    -- Save the previous mode
    STATE.tracking.prevMode = STATE.tracking.mode
    STATE.tracking.mode = newMode

    -- Only start a transition if we're switching between different modes
    if STATE.tracking.prevMode ~= newMode then
        STATE.tracking.modeTransition = true
        STATE.tracking.transitionStartState = Spring.GetCameraState()
        STATE.tracking.transitionStartTime = Spring.GetTimer()

        -- Store current camera position as last position to smooth from
        local camState = Spring.GetCameraState()
        STATE.tracking.lastCamPos = { x = camState.px, y = camState.py, z = camState.pz }
        STATE.tracking.lastCamDir = { x = camState.dx, y = camState.dy, z = camState.dz }
        STATE.tracking.lastRotation = { rx = camState.rx, ry = camState.ry, rz = camState.rz }
    end
end

-- Disable tracking
function Util.disableTracking()
    -- Start mode transition if we're disabling from a tracking mode
    if STATE.tracking.mode then
        Util.beginModeTransition(nil)
    end

    -- Restore original transition factor if needed
    if STATE.orbit.originalTransitionFactor then
        CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR = STATE.orbit.originalTransitionFactor
        STATE.orbit.originalTransitionFactor = nil
    end

    STATE.tracking.unitID = nil
    STATE.tracking.targetUnitID = nil  -- Clear the target unit ID
    STATE.tracking.inFreeCameraMode = false
    STATE.tracking.graceTimer = nil
    STATE.tracking.lastUnitID = nil
    STATE.tracking.fixedPoint = nil
    STATE.tracking.mode = nil

    -- Reset orbit-specific states
    STATE.orbit.autoOrbitActive = false
    STATE.orbit.stationaryTimer = nil
    STATE.orbit.lastPosition = nil

    -- Clear freeCam state to prevent null pointer exceptions
    STATE.tracking.freeCam.lastMouseX = nil
    STATE.tracking.freeCam.lastMouseY = nil
    STATE.tracking.freeCam.targetRx = nil
    STATE.tracking.freeCam.targetRy = nil
    STATE.tracking.freeCam.lastUnitHeading = nil
end

-- Export to global scope
return {
    Util = Util
}