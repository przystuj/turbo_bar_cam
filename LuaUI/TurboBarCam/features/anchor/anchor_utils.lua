---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Util = ModuleManager.Util(function(m) Util = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local EasingFunctions = ModuleManager.EasingFunctions(function(m) EasingFunctions = m end)

---@class CameraAnchorUtils
local CameraAnchorUtils = {}

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
                statePatch[param] = CameraCommons.lerpAngle(startState[param], endState[param], easedT)
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
    local startState = Spring.GetCameraState()
    local numSteps = math.max(2, math.floor(duration * CONFIG.PERFORMANCE.ANCHOR_STEPS_PER_SECOND))

    STATE.transition.steps = CameraAnchorUtils.generateSteps(startState, endState, numSteps, interpolationFunc)
    STATE.transition.currentStepIndex = 1
    STATE.transition.startTime = Spring.GetTimer()
    STATE.transition.active = true
end

return CameraAnchorUtils