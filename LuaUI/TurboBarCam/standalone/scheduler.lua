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
        scheduledTime = Spring.GetGameSeconds() + delay  -- Calculate the time when it should run
    }
    Log.trace(string.format("Scheduled function [%s] to run in [%ss].", id, delay))
end

--- Handles and executes all due schedules
--- This should be called regularly (e.g., each game tick) to process any pending scheduled tasks
function Scheduler.handleSchedules()
    local currentTime = Spring.GetGameSeconds()

    -- Iterate over all scheduled tasks and execute the ones that are due
    for id, schedule in pairs(STATE.scheduler.schedules) do
        if currentTime >= schedule.scheduledTime then
            Log.trace(string.format("Executing scheduled function [%s] after [%ss].", id, schedule.delay))
            schedule.fn()  -- Execute the scheduled function
            STATE.scheduler.schedules[id] = nil  -- Remove the schedule after execution
        end
    end
end

return {
    Scheduler = Scheduler
}
