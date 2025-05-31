---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua")

local STATE = WidgetContext.STATE

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
---    duration = number,       -- Duration in "effective seconds". If 'respectGameSpeed' is true, this is in game-time seconds; otherwise, real-time seconds.
---    respectGameSpeed = boolean, -- Optional (default: false). If true, transition speed scales with game speed and pauses if game speed is 0.
---    easingFn = function,   -- Easing function (e.g., CameraCommons.easeInOut), defaults to linear
---    onUpdate = function,   -- Function(progress, easedProgress, effectiveDt) called each frame. 'effectiveDt' is game-time scaled if respectGameSpeed is true.
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
        startTime = Spring.GetTimer(), -- For reference, not directly used for progress if using elapsedEffectiveTime
        duration = config.duration,
        respectGameSpeed = config.respectGameSpeed or false,
        elapsedEffectiveTime = 0, -- Tracks accumulated effective time
        easingFn = config.easingFn or linearEase,
        onUpdate = config.onUpdate,
        onComplete = config.onComplete,
    }
    Log.trace("TransitionManager: Started transition [" .. config.id .. "] for " .. config.duration ..
            (config.respectGameSpeed and " effective game seconds." or " effective real seconds."))
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

--- Cancels and removes all active transitions.
--- Does not call onComplete callbacks.
function TransitionManager.stopAll()
    local count = 0
    for id, _ in pairs(STATE.transitions) do
        STATE.transitions[id] = nil
        count = count + 1
    end
    if count > 0 then
        Log.trace("TransitionManager: Stopped all " .. count .. " transitions.")
    end
end

--- Starts a new transition, stopping all others first.
---@param config table Configuration for the transition (same as start).
---@return boolean success Whether the transition was started.
function TransitionManager.force(config)
    Log.trace("TransitionManager: Forcing transition [" .. (config.id or "unknown") .. "], stopping all others first.")
    TransitionManager.stopAll()
    return TransitionManager.start(config)
end


--- Checks if a transition with the given ID is currently active.
---@param id string The ID to check.
---@return boolean isTransitioning
function TransitionManager.isTransitioning(id)
    return STATE.transitions[id] ~= nil
end

--- Updates all active transitions. Called every frame by UpdateManager.
---@param dt_real number Real delta time since last frame.
function TransitionManager.update(dt_real)
    -- Ensure dt_real is a valid positive number
    if not dt_real or dt_real <= 0 then
        dt_real = 1 / 60 -- Fallback to a typical frame duration if dt_real is invalid
    end

    local transitionsToRemove = {}
    local _, actualGameSpeed = Spring.GetGameSpeed() -- This is the game speed multiplier

    for id, t in pairs(STATE.transitions) do
        local effectiveDt = dt_real
        if t.respectGameSpeed then
            if actualGameSpeed > 0 then
                effectiveDt = dt_real * actualGameSpeed
            else -- actualGameSpeed is 0 (paused) or potentially negative (if engine supports)
                effectiveDt = 0 -- Transition effectively pauses if respecting game speed and game is paused
            end
        end

        if t.duration > 0 then -- Only advance time if duration is positive
            t.elapsedEffectiveTime = t.elapsedEffectiveTime + effectiveDt
        end

        local progress
        if t.duration <= 0 then -- Treat zero or negative duration as instantly complete
            progress = 1.0
        else
            progress = math.min(t.elapsedEffectiveTime / t.duration, 1.0)
        end

        local easedProgress = t.easingFn(progress)

        -- Call the update callback, passing the calculated effectiveDt
        t.onUpdate(progress, easedProgress, effectiveDt)

        if progress >= 1.0 then
            if t.onComplete then
                t.onComplete()
            end
            table.insert(transitionsToRemove, id)
        end
    end

    for _, idToRemove in ipairs(transitionsToRemove) do
        STATE.transitions[idToRemove] = nil
        Log.trace("TransitionManager: Finished transition [" .. idToRemove .. "].")
    end
end

return TransitionManager