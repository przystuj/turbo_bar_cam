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

--- Serializes a table to a string with smart formatting.
--- It orders fields, sorts them, and switches between single-line and multi-line
--- representation based on the resulting string length.
---@param t table Table to serialize
---@param indent number? Current indentation level
---@return string representation
function LoggerPrototype:serializeTable(t, indent)
    selfCheck(self)
    -- Handle non-table or nil inputs
    if type(t) ~= "table" then
        return tostring(t)
    end
    -- Handle empty tables
    if next(t) == nil then
        return "{}"
    end

    indent = indent or 0

    -- Step 1: Categorize and sort keys based on their value type
    local numKeys, strKeys, funcKeys, tblKeys, otherKeys = {}, {}, {}, {}, {}
    for k in pairs(t) do
        local v = t[k]
        local vType = type(v)
        if vType == "number" then
            table.insert(numKeys, k)
        elseif vType == "string" then
            table.insert(strKeys, k)
        elseif vType == "function" then
            table.insert(funcKeys, k)
        elseif vType == "table" then
            table.insert(tblKeys, k)
        else
            -- Catch-all for booleans, etc.
            table.insert(otherKeys, k)
        end
    end

    table.sort(numKeys)
    -- Sort strings by value length
    table.sort(strKeys, function(a, b) return string.len(t[a]) < string.len(t[b]) end)
    table.sort(funcKeys)
    table.sort(tblKeys)
    table.sort(otherKeys)

    -- Step 2: Generate serialized "key=value" parts for each category
    local numParts, strParts, funcParts, otherParts = {}, {}, {}, {}

    for _, k in ipairs(numKeys) do table.insert(numParts, tostring(k) .. "=" .. string.format("%.6f", t[k])) end
    -- Use %q to safely quote strings with special characters
    for _, k in ipairs(strKeys) do table.insert(strParts, tostring(k) .. "=" .. string.format("%q", t[k])) end
    for _, k in ipairs(funcKeys) do table.insert(funcParts, tostring(k) .. "=function") end
    for _, k in ipairs(otherKeys) do table.insert(otherParts, tostring(k) .. "=" .. tostring(t[k])) end

    -- Step 3: Recursively serialize sub-tables
    local tblParts = {}
    local containsMultilineSubTable = false
    for _, k in ipairs(tblKeys) do
        -- The indentation for the content inside the sub-table is handled by the recursive call
        local serializedSubTable = self:serializeTable(t[k], indent + 2)
        if string.find(serializedSubTable, "\n") then
            containsMultilineSubTable = true
        end
        tblParts[k] = serializedSubTable
    end

    -- Step 4: Attempt to build a single-line representation
    local allPartsForSingleLine = {}
    local categoriesInOrder = {numParts, strParts, funcParts, otherParts}
    for _, category in ipairs(categoriesInOrder) do
        for _, part in ipairs(category) do
            table.insert(allPartsForSingleLine, part)
        end
    end
    for _, k in ipairs(tblKeys) do
        table.insert(allPartsForSingleLine, tostring(k) .. "=" .. tblParts[k])
    end
    local singleLineResult = "{" .. table.concat(allPartsForSingleLine, ", ") .. "}"

    -- Step 5: Decide whether to use single-line or multi-line format
    if containsMultilineSubTable or #singleLineResult >= 300 then
        local indentStr = string.rep(" ", indent)
        local nextIndentStr = string.rep(" ", indent + 2)
        local finalLines = {}

        -- Add lines for each category if they contain items
        if #numParts > 0 then table.insert(finalLines, nextIndentStr .. table.concat(numParts, ", ")) end
        if #strParts > 0 then table.insert(finalLines, nextIndentStr .. table.concat(strParts, ", ")) end
        if #funcParts > 0 then table.insert(finalLines, nextIndentStr .. table.concat(funcParts, ", ")) end
        if #otherParts > 0 then table.insert(finalLines, nextIndentStr .. table.concat(otherParts, ", ")) end

        for _, k in ipairs(tblKeys) do
            table.insert(finalLines, nextIndentStr .. tostring(k) .. " = " .. tblParts[k])
        end

        return "{\n" .. table.concat(finalLines, "\n") .. "\n" .. indentStr .. "}"
    else
        return singleLineResult
    end
end

-- Helper function to concatenate multiple arguments into a single string
-- with proper type conversion. It uses the instance's formatting methods.
---@param instance LoggerInstance
local function formatMessage(instance, ...)
    local args = { ... }
    local parts = {}
    for i = 1, #args do
        local arg = args[i]
        if type(arg) ~= "string" then
            if type(arg) == "table" then
                parts[i] = instance:serializeTable(arg)
            elseif type(arg) == "number" then
                parts[i] = string.format("%.6f", arg)
            else
                parts[i] = tostring(arg)
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
    local message = "[INFO] " .. formatMessage(self, ...)
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
    local message = "[WARN] " .. formatMessage(self, ...)
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