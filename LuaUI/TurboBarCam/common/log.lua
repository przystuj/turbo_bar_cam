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

function Log.trace(message)
    if CONFIG.DEBUG.LOG_LEVEL == "TRACE" then
        if type(message) ~= "string" then
            message = Log.dump(message)
        end
        Log.info("[TRACE] " .. message)
    end
end

function Log.debug(message)
    if CONFIG.DEBUG.LOG_LEVEL == "TRACE" or CONFIG.DEBUG.LOG_LEVEL == "DEBUG" then
        if type(message) ~= "string" then
            message = Log.dump(message)
        end
        Log.info("[DEBUG] " .. message)
    end
end

---@param message string|any Message to print to console
function Log.info(message)
    if type(message) ~= "string" then
        message = Log.dump(message)
    end
    Spring.Echo("[TurboBarCam] " .. message)
end

---@param message string error message
function Log.error(message)
    error("[TurboBarCam] Error: " .. message)
end

---@param message string error message
function Log.warn(message)
    if type(message) ~= "string" then
        message = Log.dump(message)
    end
    Log.info("[WARN] " .. message)
end

return {
    Log = Log
}