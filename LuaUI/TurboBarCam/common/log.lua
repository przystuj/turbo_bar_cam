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
        return Log.serializeTable(o)
    else
        return tostring(o)
    end
end

function Log.serializeTable(t, indent)
    if not t then
        return "nil"
    end
    if not indent then
        indent = 0
    end
    local result = ""
    local indentStr = string.rep(" ", indent)

    for k, v in pairs(t) do
        if type(v) == "table" then
            result = result .. indentStr .. tostring(k) .. " = {\n"
            result = result .. Log.serializeTable(v, indent + 2)
            result = result .. indentStr .. "}\n"
        elseif type(v) == "number" then
            -- Format numbers with higher precision for debugging
            result = result .. indentStr .. tostring(k) .. " = " .. string.format("%.9f", v) .. "\n"
        else
            result = result .. indentStr .. tostring(k) .. " = " .. tostring(v) .. "\n"
        end
    end

    return result
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

function Log.staggeredLog(...)
    if math.random() >= 0.05 then
        return
    end
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