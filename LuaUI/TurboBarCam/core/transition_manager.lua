---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end)

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
---@class TransitionConfig
---@field id string | number Unique ID for this transition
---@field duration number Duration in "effective seconds". If 'respectGameSpeed' is true, this is in game-time seconds; otherwise, real-time seconds.
---@field respectGameSpeed? If true, transition speed scales with game speed and pauses if game speed is 0.
---@field easingFn? fun(progress: number): number defaults to linearEase
---@field onUpdate fun(rawProgress: number, easedProgress: number, dtEffective: number) called each frame. 'effectiveDt' is game-time scaled if respectGameSpeed is true.
---@field onComplete? fun() Optional function called when finished

--- Starts or replaces a transition.
---@param config TransitionConfig Configuration for the transition:
---@return boolean success Whether the transition was started
function TransitionManager.start(config)
    if not config or not config.duration or not config.onUpdate then
        Log:warn("TransitionManager: Cannot start transition - missing duration or onUpdate.")
        return false
    end

    config.id = config.id or math.random(1000,9999)

    ---@field onUpdate fun(raw_progress: number, eased_progress: number, dt_effective: number)
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
    Log:trace("TransitionManager: Started transition [" .. config.id .. "] for " .. config.duration ..
            (config.respectGameSpeed and " effective game seconds." or " effective real seconds."))
    return true
end

--- Cancels and removes an active transition.
---@param id string The ID of the transition to cancel.
---@return boolean success Whether a transition was found and canceled.
function TransitionManager.cancel(id)
    if STATE.transitions[id] then
        STATE.transitions[id] = nil
        Log:trace("TransitionManager: Canceled transition [" .. id .. "].")
        return true
    end
    return false
end

--- Instantly finishes active transition. OnComplete will be called
---@param id string The ID of the transition to finish.
---@return boolean success Whether a transition was found and finished.
function TransitionManager.finish(id)
    if STATE.transitions[id] then
        STATE.transitions[id].onComplete()
        STATE.transitions[id] = nil
        Log:trace("TransitionManager: Finished transition [" .. id .. "].")
        return true
    end
    return false
end

local function stringStartsWith(s, prefix)
    return string.sub(s, 1, #prefix) == prefix
end

--- Cancels and removes an active transitions by the prefix.
---@param prefix string Prefix of the IDs of the transitions to cancel.
---@return boolean success Whether a transitions were found and canceled.
function TransitionManager.cancelPrefix(prefix)
    local canceled = false
    for id, _ in pairs(STATE.transitions) do
        if stringStartsWith(id, prefix) then
            STATE.transitions[id] = nil
            Log:trace("TransitionManager: Canceled transition [" .. id .. "].")
            canceled = true
        end
    end
    return canceled
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
        Log:debug("TransitionManager: Stopped all " .. count .. " transitions.")
    end
end

--- Starts a new transition, stopping all others first.
---@param config table Configuration for the transition (same as start).
---@return boolean success Whether the transition was started.
function TransitionManager.force(config)
    Log:trace("TransitionManager: Forcing transition [" .. (config.id or "unknown") .. "], stopping all others first.")
    TransitionManager.stopAll()
    return TransitionManager.start(config)
end

--- Checks if a transition with the given ID is currently active.
---@param id string The ID to check.
---@return boolean isTransitioning
function TransitionManager.isTransitioning(id)
    if id then
        return STATE.transitions[id] ~= nil
    else
        local count = 0
        for _ in pairs(STATE.transitions) do
            count = count + 1
        end
        return count > 0
    end
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
            else
                -- actualGameSpeed is 0 (paused) or potentially negative (if engine supports)
                effectiveDt = 0 -- Transition effectively pauses if respecting game speed and game is paused
            end
        end

        if t.duration > 0 then
            -- Only advance time if duration is positive
            t.elapsedEffectiveTime = t.elapsedEffectiveTime + effectiveDt
        end

        local progress
        if t.duration <= 0 then
            -- Treat zero or negative duration as instantly complete
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
        Log:trace("TransitionManager: Finished transition [" .. idToRemove .. "].")
    end
end

return TransitionManager