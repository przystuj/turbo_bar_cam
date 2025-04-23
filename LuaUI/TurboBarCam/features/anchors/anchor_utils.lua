---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local CameraCommons = CommonModules.CameraCommons

---@class CameraAnchorUtils
local CameraAnchorUtils = {}

--- Cubic easing function for smooth transitions
---@param t number Transition progress (0.0-1.0)
---@return number eased value
function CameraAnchorUtils.easeInOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local t2 = (t - 1)
        return 1 + 4 * t2 * t2 * t2
    end
end

--- Linear interpolation between two values
---@param a number Start value
---@param b number End value
---@param t number Interpolation factor (0.0-1.0)
---@return number interpolated value
function CameraAnchorUtils.lerp(a, b, t)
    return a + (b - a) * t
end

--- Interpolates between two angles along the shortest path
---@param a number Start angle (in radians)
---@param b number End angle (in radians)
---@param t number Interpolation factor (0.0-1.0)
---@return number interpolated angle
function CameraAnchorUtils.lerpAngle(a, b, t)
    -- Normalize both angles to -pi to pi range
    a = CameraAnchorUtils.normalizeAngle(a)
    b = CameraAnchorUtils.normalizeAngle(b)

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

--- Normalizes an angle to be within -pi to pi range
---@param angle number|nil Angle to normalize (in radians)
---@return number normalized angle
function CameraAnchorUtils.normalizeAngle(angle)
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

--- Generates a sequence of camera states for smooth transition
---@param startState table Start camera state
---@param endState table End camera state
---@param numSteps number Number of transition steps
---@return table[] steps Array of transition step states
function CameraAnchorUtils.generateSteps(startState, endState, numSteps)
    local steps = {}

    -- Camera parameters to interpolate
    local cameraParams = {
        "zoomFromHeight", "fov", "gndOffset", "dist", "flipped",
        "vx", "vy", "vz", "ax", "ay", "az", "height",
        "rotZ"
    }

    -- Camera rotation parameters that need special angle interpolation
    local rotationParams = {
        "rx", "ry", "rz", "rotX", "rotY"
    }

    for i = 1, numSteps do
        local t = (i - 1) / (numSteps - 1)
        local easedT = CameraAnchorUtils.easeInOutCubic(t)

        -- Create a new state by interpolating between start and end
        local statePatch = {}

        -- Core position parameters
        statePatch.px = CameraAnchorUtils.lerp(startState.px, endState.px, easedT)
        statePatch.py = CameraAnchorUtils.lerp(startState.py, endState.py, easedT)
        statePatch.pz = CameraAnchorUtils.lerp(startState.pz, endState.pz, easedT)

        -- Core direction parameters
        statePatch.dx = CameraAnchorUtils.lerp(startState.dx, endState.dx, easedT)
        statePatch.dy = CameraAnchorUtils.lerp(startState.dy, endState.dy, easedT)
        statePatch.dz = CameraAnchorUtils.lerp(startState.dz, endState.dz, easedT)

        -- Camera specific parameters (non-rotational)
        for _, param in ipairs(cameraParams) do
            if startState[param] ~= nil and endState[param] ~= nil then
                statePatch[param] = CameraAnchorUtils.lerp(startState[param], endState[param], easedT)
            end
        end

        -- Camera rotation parameters (need special angle interpolation)
        for _, param in ipairs(rotationParams) do
            if startState[param] ~= nil and endState[param] ~= nil then
                statePatch[param] = CameraAnchorUtils.lerpAngle(startState[param], endState[param], easedT)
            end
        end

        steps[i] = statePatch
    end

    steps[numSteps] = Util.deepCopy(endState)

    return steps
end
--- Starts a transition between camera states
---@param endState table End camera state
---@param duration number Transition duration in seconds
function CameraAnchorUtils.start(endState, duration)
    -- Generate transition steps for smooth transition
    local startState = CameraManager.getCameraState("CameraAnchorUtils.start")
    local numSteps = math.max(2, math.floor(duration * CONFIG.PERFORMANCE.ANCHOR_STEPS_PER_SECOND))

    STATE.transition.steps = CameraAnchorUtils.generateSteps(startState, endState, numSteps)
    STATE.transition.currentStepIndex = 1
    STATE.transition.startTime = Spring.GetTimer()
    STATE.transition.active = true
end

--- Starts a position transition with optional focus point
---@param startPos table Start camera state
---@param endPos table End camera state
---@param duration number Transition duration
---@param targetPoint table|nil Point to keep looking at during transition
---@return table transitionSteps Array of transition steps
function CameraAnchorUtils.createPositionTransition(startPos, endPos, duration, targetPoint)
    local numSteps = math.max(2, math.floor(duration * CONFIG.PERFORMANCE.ANCHOR_STEPS_PER_SECOND))
    local steps = {}

    for i = 1, numSteps do
        local t = (i - 1) / (numSteps - 1)
        local easedT = CameraAnchorUtils.easeInOutCubic(t)

        -- Interpolate position
        local position = {
            x = CameraAnchorUtils.lerp(startPos.px, endPos.px, easedT),
            y = CameraAnchorUtils.lerp(startPos.py, endPos.py, easedT),
            z = CameraAnchorUtils.lerp(startPos.pz, endPos.pz, easedT)
        }
        
        -- Create state patch
        local statePatch = {
            px = position.x,
            py = position.y,
            pz = position.z
        }
        
        -- If we have a target point, calculate look direction
        if targetPoint then
            local lookDir = CameraCommons.calculateCameraDirectionToThePoint(position, targetPoint)
            statePatch.dx = lookDir.dx
            statePatch.dy = lookDir.dy
            statePatch.dz = lookDir.dz
            statePatch.rx = lookDir.rx
            statePatch.ry = lookDir.ry
            statePatch.rz = 0
        end
        
        table.insert(steps, statePatch)
    end
    
    return steps
end

return {
    CameraAnchorUtils = CameraAnchorUtils
}