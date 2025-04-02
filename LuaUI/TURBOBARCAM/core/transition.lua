-- Camera Transition module for TURBOBARCAM
-- Load modules
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type Util
local UtilsModule = VFS.Include("LuaUI/TURBOBARCAM/common/utils.lua")

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE
local Util = UtilsModule.Util

---@class CameraTransition
local CameraTransition = {}

--- Generates a sequence of camera states for smooth transition
---@param startState table Start camera state
---@param endState table End camera state
---@param numSteps number Number of transition steps
---@return table[] steps Array of transition step states
function CameraTransition.generateSteps(startState, endState, numSteps)
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
        local easedT = Util.easeInOutCubic(t)

        -- Create a new state by interpolating between start and end
        local statePatch = {}

        -- Core position parameters
        statePatch.px = Util.lerp(startState.px, endState.px, easedT)
        statePatch.py = Util.lerp(startState.py, endState.py, easedT)
        statePatch.pz = Util.lerp(startState.pz, endState.pz, easedT)

        -- Core direction parameters
        statePatch.dx = Util.lerp(startState.dx, endState.dx, easedT)
        statePatch.dy = Util.lerp(startState.dy, endState.dy, easedT)
        statePatch.dz = Util.lerp(startState.dz, endState.dz, easedT)

        -- Camera specific parameters (non-rotational)
        for _, param in ipairs(cameraParams) do
            if startState[param] ~= nil and endState[param] ~= nil then
                statePatch[param] = Util.lerp(startState[param], endState[param], easedT)
            end
        end

        -- Camera rotation parameters (need special angle interpolation)
        for _, param in ipairs(rotationParams) do
            if startState[param] ~= nil and endState[param] ~= nil then
                statePatch[param] = Util.lerpAngle(startState[param], endState[param], easedT)
            end
        end

        -- Always keep FPS mode
        statePatch.mode = 0
        statePatch.name = "fps"

        steps[i] = statePatch
    end

    -- Ensure the last step is exactly the end state but keep FPS mode
    steps[numSteps] = Util.deepCopy(endState)
    steps[numSteps].mode = 0
    steps[numSteps].name = "fps"

    return steps
end

--- Handles transition updates
function CameraTransition.update()
    if not STATE.transition.active then
        return
    end

    local now = Spring.GetTimer()

    -- Calculate current progress
    local elapsed = Spring.DiffTimers(now, STATE.transition.startTime)
    local targetProgress = math.min(elapsed / CONFIG.TRANSITION.DURATION, 1.0)

    -- Determine which step to use based on progress
    local totalSteps = #STATE.transition.steps
    local targetStep = math.max(1, math.min(totalSteps, math.ceil(targetProgress * totalSteps)))

    -- Only update if we need to move to a new step
    if targetStep > STATE.transition.currentStepIndex then
        STATE.transition.currentStepIndex = targetStep

        -- Apply the camera state for this step
        local state = STATE.transition.steps[STATE.transition.currentStepIndex]

        -- Apply the base camera state (position)
        Spring.SetCameraState(state, 0)

        -- Check if we've reached the end
        if STATE.transition.currentStepIndex >= totalSteps then
            STATE.transition.active = false
            STATE.transition.currentAnchorIndex = nil
        end
    end
end

--- Starts a transition between camera states
---@param endState table End camera state
---@param duration number Transition duration in seconds
function CameraTransition.start(endState, duration)
    -- Generate transition steps for smooth transition
    local startState = Spring.GetCameraState()
    local numSteps = math.max(2, math.floor(duration * CONFIG.TRANSITION.STEPS_PER_SECOND))

    -- Ensure the target state is in FPS mode
    endState.mode = 0
    endState.name = "fps"

    STATE.transition.steps = CameraTransition.generateSteps(startState, endState, numSteps)
    STATE.transition.currentStepIndex = 1
    STATE.transition.startTime = Spring.GetTimer()
    STATE.transition.active = true
end

--- Starts a position transition with optional focus point
---@param startPos table Start position {x, y, z}
---@param endPos table End position {x, y, z}
---@param duration number Transition duration
---@param targetPoint table|nil Point to keep looking at during transition
---@return table transitionSteps Array of transition steps
function CameraTransition.createPositionTransition(startPos, endPos, duration, targetPoint)
    local numSteps = math.max(2, math.floor(duration * CONFIG.TRANSITION.STEPS_PER_SECOND))
    local steps = {}
    
    for i = 1, numSteps do
        local t = (i - 1) / (numSteps - 1)
        local easedT = Util.easeInOutCubic(t)
        
        -- Interpolate position
        local position = {
            x = Util.lerp(startPos.x, endPos.x, easedT),
            y = Util.lerp(startPos.y, endPos.y, easedT),
            z = Util.lerp(startPos.z, endPos.z, easedT)
        }
        
        -- Create state patch
        local statePatch = {
            mode = 0,
            name = "fps",
            px = position.x,
            py = position.y,
            pz = position.z
        }
        
        -- If we have a target point, calculate look direction
        if targetPoint then
            local lookDir = Util.calculateLookAtPoint(position, targetPoint)
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

--- Starts a mode transition
---@param prevMode string Previous camera mode
---@param newMode string New camera mode
---@return boolean success Whether transition started successfully
function CameraTransition.startModeTransition(prevMode, newMode)
    -- Only start a transition if we're switching between different modes
    if prevMode == newMode then
        return false
    end
    
    -- Store modes
    STATE.tracking.prevMode = prevMode
    STATE.tracking.mode = newMode
    
    -- Set up transition state
    STATE.tracking.modeTransition = true
    STATE.tracking.transitionStartState = Spring.GetCameraState()
    STATE.tracking.transitionStartTime = Spring.GetTimer()
    
    -- Store current camera position as last position to smooth from
    local camState = Spring.GetCameraState()
    STATE.tracking.lastCamPos = { x = camState.px, y = camState.py, z = camState.pz }
    STATE.tracking.lastCamDir = { x = camState.dx, y = camState.dy, z = camState.dz }
    STATE.tracking.lastRotation = { rx = camState.rx, ry = camState.ry, rz = camState.rz }
    
    return true
end

--- Checks if a mode transition is complete
---@return boolean isComplete Whether the transition is complete
function CameraTransition.isModeTransitionComplete()
    if not STATE.tracking.modeTransition then
        return true
    end
    
    local now = Spring.GetTimer()
    local elapsed = Spring.DiffTimers(now, STATE.tracking.transitionStartTime)
    
    if elapsed > 1.0 then
        STATE.tracking.modeTransition = false
        return true
    end
    
    return false
end

return {
    CameraTransition = CameraTransition
}