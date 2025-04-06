---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TURBOBARCAM/common.lua")

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE
local Util = CommonModules.Util

---@class CameraAnchorUtils
local CameraAnchorUtils = {}

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
--- Starts a transition between camera states
---@param endState table End camera state
---@param duration number Transition duration in seconds
function CameraAnchorUtils.start(endState, duration)
    -- Generate transition steps for smooth transition
    local startState = Spring.GetCameraState()
    local numSteps = math.max(2, math.floor(duration * CONFIG.CAMERA_MODES.ANCHOR.STEPS_PER_SECOND))

    -- Ensure the target state is in FPS mode
    endState.mode = 0
    endState.name = "fps"

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
    local numSteps = math.max(2, math.floor(duration * CONFIG.CAMERA_MODES.ANCHOR.STEPS_PER_SECOND))
    local steps = {}

    for i = 1, numSteps do
        local t = (i - 1) / (numSteps - 1)
        local easedT = Util.easeInOutCubic(t)

        -- Interpolate position
        local position = {
            x = Util.lerp(startPos.px, endPos.px, easedT),
            y = Util.lerp(startPos.py, endPos.py, easedT),
            z = Util.lerp(startPos.pz, endPos.pz, easedT)
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

return {
    CameraAnchorUtils = CameraAnchorUtils
}