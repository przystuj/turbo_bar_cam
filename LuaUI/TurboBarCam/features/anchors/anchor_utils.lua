---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type EasingFunctions
local EasingFunctions = VFS.Include("LuaUI/TurboBarCam/features/anchors/anchor_easing_functions.lua").EasingFunctions

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local CameraCommons = CommonModules.CameraCommons
local Log = CommonModules.Log

---@class CameraAnchorUtils
local CameraAnchorUtils = {}

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
---@param interpolationFunc function|nil Optional custom interpolation function
---@return table[] steps Array of transition step states
function CameraAnchorUtils.generateSteps(startState, endState, numSteps, interpolationFunc)
    local steps = {}

    -- Use default interpolation if none provided
    interpolationFunc = interpolationFunc or EasingFunctions.easeInOut

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
        local easedT = interpolationFunc(t)

        -- Create a new state by interpolating between start and end
        local statePatch = {}

        -- Core position parameters
        statePatch.px = CameraCommons.lerp(startState.px, endState.px, easedT)
        statePatch.py = CameraCommons.lerp(startState.py, endState.py, easedT)
        statePatch.pz = CameraCommons.lerp(startState.pz, endState.pz, easedT)

        -- Core direction parameters
        statePatch.dx = CameraCommons.lerp(startState.dx, endState.dx, easedT)
        statePatch.dy = CameraCommons.lerp(startState.dy, endState.dy, easedT)
        statePatch.dz = CameraCommons.lerp(startState.dz, endState.dz, easedT)

        -- Camera specific parameters (non-rotational)
        for _, param in ipairs(cameraParams) do
            if startState[param] ~= nil and endState[param] ~= nil then
                statePatch[param] = CameraCommons.lerp(startState[param], endState[param], easedT)
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

    -- Ensure the last step exactly matches the end state
    steps[numSteps] = Util.deepCopy(endState)

    return steps
end

--- Creates a position-based transition between camera states
---@param startState table Start camera state
---@param endState table End camera state
---@param duration number Transition duration in seconds
---@param targetPos table|nil Optional target position to focus on
---@param interpolationFunc function|nil Optional custom interpolation function
---@return table[] steps Array of transition step states
function CameraAnchorUtils.createPositionTransition(startState, endState, duration, targetPos, interpolationFunc)
    -- Generate transition steps for smooth transition
    local numSteps = math.max(2, math.floor(duration * CONFIG.PERFORMANCE.ANCHOR_STEPS_PER_SECOND))

    -- If tracking a unit, adjust the end position to maintain focus
    if targetPos then
        -- Create a hybrid end state that maintains unit focus
        local focusState = Util.deepCopy(endState)

        -- Calculate direction from position to target
        local direction = CameraCommons.calculateCameraDirectionToThePoint(focusState, targetPos)

        -- Update end state with focus direction
        focusState.dx = direction.dx
        focusState.dy = direction.dy
        focusState.dz = direction.dz
        focusState.rx = direction.rx
        focusState.ry = direction.ry

        return CameraAnchorUtils.generateSteps(startState, focusState, numSteps, interpolationFunc)
    end

    return CameraAnchorUtils.generateSteps(startState, endState, numSteps, interpolationFunc)
end

--- Starts a transition between camera states
---@param endState table End camera state
---@param duration number Transition duration in seconds
---@param interpolationFunc function|nil Optional interpolation function
function CameraAnchorUtils.startTransitionToAnchor(endState, duration, interpolationFunc)
    -- Generate transition steps for smooth transition
    local startState = CameraManager.getCameraState("CameraAnchorUtils.start")
    local numSteps = math.max(2, math.floor(duration * CONFIG.PERFORMANCE.ANCHOR_STEPS_PER_SECOND))

    STATE.transition.steps = CameraAnchorUtils.generateSteps(startState, endState, numSteps, interpolationFunc)
    STATE.transition.currentStepIndex = 1
    STATE.transition.startTime = Spring.GetTimer()
    STATE.transition.active = true
end

return {
    CameraAnchorUtils = CameraAnchorUtils
}