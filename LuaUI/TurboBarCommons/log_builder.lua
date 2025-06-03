-- This table will serve as the prototype for all logger instances
---@class LoggerInstance
local LoggerPrototype = {}
LoggerPrototype.__index = LoggerPrototype -- For metatable behavior

local function selfCheck(self)
    if not self or not self.getLogLevel or not self.prefix then
        error(string.format("Log is misconfigured. Self=%s, getLogLevel=%s, prefix=%s", tostring(self),
                self and tostring(self.getLogLevel) or "nil",
                self and tostring(self.prefix) or "nil"))
    end
end

--- Converts a value to a string representation for debugging
--- This function is part of the LoggerPrototype and can be accessed via logger instances.
---@param o any Value to dump
---@return string representation
function LoggerPrototype:dump(o)
    selfCheck(self)
    if type(o) == 'table' then
        -- Call serializeTable using self to allow for potential future overrides if necessary,
        -- though currently serializeTable itself doesn't use self.
        return self:serializeTable(o)
    else
        return tostring(o)
    end
end

--- Serializes a table to a string.
--- This function is part of the LoggerPrototype.
---@param t table Table to serialize
---@param indent number? Current indentation level
---@return string representation
function LoggerPrototype:serializeTable(t, indent)
    selfCheck(self)
    if not t then
        return "nil"
    end
    indent = indent or 0
    local result = ""
    local indentStr = string.rep(" ", indent)

    for k, v in pairs(t) do
        if type(v) == "table" then
            result = result .. indentStr .. tostring(k) .. " = {\n"
            -- Recursive call to serializeTable on the same instance context
            result = result .. self:serializeTable(v, indent + 2)
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

--- Formats a vector-like table.
--- This function is part of the LoggerPrototype.
---@param vector table|nil The vector table with x, y, z fields
---@return string|nil String representation or nil
function LoggerPrototype:formatVec(vector)
    if not vector then
        return "nil"
    end
    if vector.x or vector.y or vector.z then
        return string.format("{x=%.6f, y=%.6f, z=%.6f}", vector.x or 0, vector.y or 0, vector.z or 0)
    end
    return nil
end

--- Formats a camera state-like table.
--- This function is part of the LoggerPrototype.
---@param camState table|nil The camera state table
---@return string|nil String representation or nil
function LoggerPrototype:formatCamState(camState)
    if not camState then
        return "nil"
    end
    if camState.px or camState.py or camState.pz or camState.dx or camState.dy or camState.dz or camState.rx or camState.ry or camState.rz then
        return string.format("{px=%.6f, py=%.6f, pz=%.6f, dx=%.6f, dy=%.6f, dz=%.6f, rx=%.6f, ry=%.6f, rz=%.6f}",
                camState.px or 0, camState.py or 0, camState.pz or 0, camState.dx or 0, camState.dy or 0, camState.dz or 0, camState.rx or 0, camState.ry or 0, camState.rz or 0)
    end
    return nil
end

-- Helper function to concatenate multiple arguments into a single string
-- with proper type conversion. It uses the instance's formatting methods.
local function formatMessage(instance, ...)
    local args = { ... }
    local parts = {}
    for i = 1, #args do
        local arg = args[i]
        if type(arg) ~= "string" then
            if type(arg) == "table" then
                parts[i] = instance:formatCamState(arg) or instance:formatVec(arg) or instance:dump(arg)
            elseif type(arg) == "number" then
                parts[i] = string.format("%.6f", arg)
            else
                parts[i] = instance:dump(arg) -- Use instance's dump method
            end
        else
            parts[i] = arg
        end
    end
    return table.concat(parts, " | ")
end

--- Logs an informational message.
---@param self LoggerInstance
function LoggerPrototype:info(...)
    selfCheck(self)
    local message = "[INFO ] " .. formatMessage(self, ...)
    Spring.Echo("[" .. self.prefix .. "] " .. message)
end

--- Logs a trace message if the log level is TRACE.
---@param self LoggerInstance
function LoggerPrototype:trace(...)
    selfCheck(self)
    if self:getLogLevel() == "TRACE" then
        local message = "[TRACE] " .. formatMessage(self, ...)
        Spring.Echo("[" .. self.prefix .. "] " .. message)
    end
end

--- Logs a debug message if the log level is TRACE or DEBUG.
---@param self LoggerInstance
function LoggerPrototype:debug(...)
    selfCheck(self)
    local logLevel = self:getLogLevel()
    if logLevel == "TRACE" or logLevel == "DEBUG" then
        local message = "[DEBUG] " .. formatMessage(self, ...)
        Spring.Echo("[" .. self.prefix .. "] " .. message)
    end
end

--- Logs a debug message randomly (5% chance) if log level is TRACE or DEBUG.
---@param self LoggerInstance
function LoggerPrototype:staggeredLog(...)
    selfCheck(self)
    if math.random() < 0.05 then
        return
    end
    local logLevel = self:getLogLevel()
    if logLevel == "TRACE" or logLevel == "DEBUG" then
        local message = "[DEBUG] " .. formatMessage(self, ...)
        Spring.Echo("[" .. self.prefix .. "] " .. message)
    end
end

--- Logs an error message and halts execution.
---@param self LoggerInstance
function LoggerPrototype:error(...)
    selfCheck(self)
    error("[" .. self.prefix .. "] Error: " .. formatMessage(self, ...))
end

--- Logs a warning message.
---@param self LoggerInstance
function LoggerPrototype:warn(...)
    selfCheck(self)
    local message = "[WARN ] " .. formatMessage(self, ...)
    Spring.Echo("[" .. self.prefix .. "] " .. message)
end

--- Creates a new logger instance with an appended prefix.
--- The new logger inherits the log level getter from the parent.
---@param self LoggerInstance
---@param additionalPrefix string The prefix string to append
---@return LoggerInstance A new logger instance
function LoggerPrototype:appendPrefix(additionalPrefix)
    selfCheck(self)
    -- self.prefix stores the "content" of the prefix, e.g., "widgetName" or "widgetName] [OldSubFile"
    -- The new prefix content will be "oldPrefixContent] [newSubFile"
    local newPrefixValue = self.prefix .. "][" .. additionalPrefix

    ---@type LoggerInstance
    local subLogger = {
        prefix = newPrefixValue,
        getLogLevel = self.getLogLevel -- Inherit the log level getter function
    }
    setmetatable(subLogger, LoggerPrototype) -- All methods are inherited from LoggerPrototype
    return subLogger
end

---@class LogBuilder
local LogBuilder = {
    --- Creates a new logger instance.
    ---@param prefix string The initial prefix for this logger (e.g., "widgetName")
    ---@param logLevelGetter function A function that returns the current log level string (e.g., "DEBUG", "INFO")
    ---@return LoggerInstance
    createInstance = function(prefixString, logLevelGetterFunc)
        ---@type LoggerInstance
        local instance = {
            prefix = prefixString, -- Stores the base prefix string
            getLogLevel = logLevelGetterFunc -- Stores the function to get the log level
        }
        setmetatable(instance, LoggerPrototype)
        return instance
    end
}

return LogBuilder