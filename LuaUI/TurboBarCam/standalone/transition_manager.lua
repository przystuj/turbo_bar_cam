---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local STATE = WidgetContext.STATE
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons -- Needed for default easing

---@class TransitionManager
local TransitionManager = {}

-- Initialize the state for transitions if it doesn't exist
STATE.transitions = STATE.transitions or {}

--- Default linear easing function (if none provided)
---@param t number Progress (0.0-1.0)
---@return number Interpolated value (same as t for linear)
local function linearEase(t)
    return t
end

--- Starts or replaces a transition.
---@param config table Configuration for the transition:
---  {
---    id = string,           -- Unique ID for this transition
---    duration = number,       -- Duration in seconds
---    easingFn = function,   -- Easing function (e.g., CameraCommons.easeInOut), defaults to linear
---    onUpdate = function,   -- Function(progress, easedProgress) called each frame
---    onComplete = function  -- Optional function called when finished
---  }
---@return boolean success Whether the transition was started
function TransitionManager.start(config)
    if not config or not config.id or not config.duration or not config.onUpdate then
        Log.warn("TransitionManager: Cannot start transition - missing id, duration, or onUpdate.")
        return false
    end

    STATE.transitions[config.id] = {
        id = config.id,
        startTime = Spring.GetTimer(),
        duration = config.duration,
        easingFn = config.easingFn or linearEase,
        onUpdate = config.onUpdate,
        onComplete = config.onComplete,
    }
    Log.trace("TransitionManager: Started transition [" .. config.id .. "] for " .. config.duration .. "s.")
    return true
end

--- Cancels and removes an active transition.
---@param id string The ID of the transition to cancel.
---@return boolean success Whether a transition was found and canceled.
function TransitionManager.cancel(id)
    if STATE.transitions[id] then
        STATE.transitions[id] = nil
        Log.trace("TransitionManager: Canceled transition [" .. id .. "].")
        return true
    end
    return false
end

--- Checks if a transition with the given ID is currently active.
---@param id string The ID to check.
---@return boolean isTransitioning
function TransitionManager.isTransitioning(id)
    return STATE.transitions[id] ~= nil
end

--- Updates all active transitions. Called every frame by UpdateManager.
---@param dt number Delta time (currently unused but good practice)
function TransitionManager.update(dt)
    local currentTime = Spring.GetTimer()
    local transitionsToRemove = {}

    for id, t in pairs(STATE.transitions) do
        local elapsed = Spring.DiffTimers(currentTime, t.startTime)
        local progress = math.min(elapsed / t.duration, 1.0)
        local easedProgress = t.easingFn(progress)

        -- Call the update callback
        t.onUpdate(progress, easedProgress)

        -- Check for completion
        if progress >= 1.0 then
            -- If an onComplete callback exists, call it
            if t.onComplete then
                t.onComplete()
            end
            -- Mark for removal
            table.insert(transitionsToRemove, id)
        end
    end

    -- Remove completed transitions
    for _, id in ipairs(transitionsToRemove) do
        STATE.transitions[id] = nil
        Log.trace("TransitionManager: Finished transition [" .. id .. "].")
    end
end

return {
    TransitionManager = TransitionManager
}