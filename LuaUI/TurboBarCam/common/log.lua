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
    local args = { ... }
    local parts = {}
    for i = 1, #args do
        if type(args[i]) ~= "string" then
            if type(args[i]) == "table" then
                parts[i] = Log.formatCamState(args[i]) or Log.formatVec(args[i]) or Log.dump(args[i])
            elseif type(args[i]) == "number" then
                parts[i] = string.format("%.6f", args[i])
            else
                parts[i] = Log.dump(args[i])
            end
        else
            parts[i] = args[i]
        end
    end
    return table.concat(parts, " | ")
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

function Log.formatVec(vector)
    if not vector then
        return "nil"
    end
    if vector.x or vector.y or vector.z then
        return string.format("{x=%.6f, y=%.6f, z=%.6f}", vector.x or 0, vector.y or 0, vector.z or 0)
    end
    return nil
end

function Log.formatCamState(camState)
    if not camState then
        return "nil"
    end
    if camState.px or camState.py or camState.pz or camState.dx or camState.dy or camState.dz or camState.rx or camState.ry or camState.rz then
        return string.format("{px=%.6f, py=%.6f, pz=%.6f, dx=%.6f, dy=%.6f, dz=%.6f, rx=%.6f, ry=%.6f, rz=%.6f}",
                camState.px or 0, camState.py or 0, camState.pz or 0, camState.dx or 0, camState.dy or 0, camState.dz or 0, camState.rx or 0, camState.ry or 0, camState.rz or 0)
    end

    return nil
end

return {
    Log = Log
}