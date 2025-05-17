---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local STATE = WidgetContext.STATE
local Log = CommonModules.Log

---@class Scheduler
local Scheduler = {}

--- Schedules a function to be executed after a specified delay
---
--- Usage example:
---   Scheduler.schedule(function() print("Scheduled task executed") end, 2, "task1")
---
--- @param fn function The function to execute after delay
--- @param delay number Delay time in seconds before executing the function
--- @param id string The identifier for the scheduled task
--- @return nil
function Scheduler.schedule(fn, delay, id)
    -- Store the scheduled function with its delay and time to execute
    STATE.scheduler.schedules[id] = {
        fn = fn,
        delay = delay,
        startTime = Spring.GetTimer(),  -- Current time using stable timer
        type = "normal"
    }
    Log.trace(string.format("Scheduled function [%s] to run in [%ss].", id, delay))
end

--- Debounces a function call - will only execute after the specified delay
--- If called again before the delay expires, resets the timer
---
--- Usage example:
---   Scheduler.debounce(function() print("Debounced task executed") end, 1, "debounce1")
---
--- @param fn function The function to execute after delay (if not called again before delay expires)
--- @param delay number Delay time in seconds before executing the function
--- @param id string The identifier for the debounced task
--- @return nil
function Scheduler.debounce(fn, delay, id)
    local currentTime = Spring.GetTimer()

    -- Check if this task is already scheduled
    if STATE.scheduler.schedules[id] then
        -- Update only the execution start time without logging a new schedule
        STATE.scheduler.schedules[id].startTime = currentTime
    else
        -- Create a new debounce schedule
        STATE.scheduler.schedules[id] = {
            fn = fn,
            delay = delay,
            startTime = currentTime,
            type = "debounce"
        }
        Log.trace(string.format("Debounced function [%s] set to run in [%ss] if not called again.", id, delay))
    end
end

--- Cancels a scheduled or debounced task
---
--- @param id string The identifier of the task to cancel
--- @return boolean success Whether a task was found and canceled
function Scheduler.cancel(id)
    if STATE.scheduler.schedules[id] then
        STATE.scheduler.schedules[id] = nil
        Log.trace(string.format("Canceled scheduled function [%s].", id))
        return true
    end
    return false
end

--- Checks if a task with the given ID is currently scheduled
---
--- @param id string The identifier to check
--- @return boolean isScheduled Whether the task is scheduled
function Scheduler.isScheduled(id)
    return STATE.scheduler.schedules[id] ~= nil
end

--- Gets the remaining time before a scheduled task executes
---
--- @param id string The identifier of the task
--- @return number|nil timeRemaining The time remaining in seconds, or nil if not scheduled
function Scheduler.getTimeRemaining(id)
    if STATE.scheduler.schedules[id] then
        local schedule = STATE.scheduler.schedules[id]
        local currentTime = Spring.GetTimer()

        -- Calculate time that has passed
        local timePassed = Spring.DiffTimers(currentTime, schedule.startTime)

        -- Calculate remaining time
        local remainingTime = schedule.delay - timePassed
        return math.max(0, remainingTime)
    end
    return nil
end

--- Handles and executes all due schedules
function Scheduler.handleSchedules()
    if not STATE.scheduler.schedules or #STATE.scheduler.schedules == 0 then
        return
    end

    local currentTime = Spring.GetTimer()

    -- Iterate over all scheduled tasks and execute the ones that are due
    for id, schedule in pairs(STATE.scheduler.schedules) do
        -- Check if it's time to execute based on time difference
        local timePassed = Spring.DiffTimers(currentTime, schedule.startTime)
        if timePassed >= schedule.delay then
            local type = schedule.type or "normal"
            Log.trace(string.format("Executing %s function [%s] after [%ss].", type, id, schedule.delay))
            schedule.fn()  -- Execute the scheduled function
            STATE.scheduler.schedules[id] = nil  -- Remove the schedule after execution
        end
    end
end



return {
    Scheduler = Scheduler
}