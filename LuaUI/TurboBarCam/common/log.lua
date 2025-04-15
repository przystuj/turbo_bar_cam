---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")

local CONFIG = WidgetContext.CONFIG

---@class Log
local Log = {}

--- Converts a value to a string representation for debugging
---@param o any Value to dump
---@return string representation
function Log.dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then
                k = '"' .. k .. '"'
            end
            s = s .. '[' .. k .. '] = ' .. Log.dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

-- Helper function to concatenate multiple arguments into a single string
-- with proper type conversion
local function formatMessage(...)
    local args = {...}
    local parts = {}
    for i = 1, #args do
        if type(args[i]) ~= "string" then
            parts[i] = Log.dump(args[i])
        else
            parts[i] = args[i]
        end
    end
    return table.concat(parts, " ")
end

function Log.trace(...)
    if CONFIG.DEBUG.LOG_LEVEL == "TRACE" then
        Log.info("[TRACE] " .. formatMessage(...))
    end
end

function Log.debug(...)
    if CONFIG.DEBUG.LOG_LEVEL == "TRACE" or CONFIG.DEBUG.LOG_LEVEL == "DEBUG" then
        Log.info("[DEBUG] " .. formatMessage(...))
    end
end

function Log.info(...)
    Spring.Echo("[TurboBarCam] " .. formatMessage(...))
end

function Log.error(...)
    error("[TurboBarCam] Error: " .. formatMessage(...))
end

function Log.warn(...)
    Log.info("[WARN] " .. formatMessage(...))
end

return {
    Log = Log
}