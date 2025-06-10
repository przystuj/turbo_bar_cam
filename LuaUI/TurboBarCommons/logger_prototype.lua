local SPRING_ECHO_PREFIX_LENGTH = 30
local MAX_LINE_LENGTH = 280
local LOG_LEVEL_PREFIX_LENGTH = 7

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

--- Serializes a table to a string with smart formatting and filtering.
---@param t table Table to serialize
---@param indent number? Current indentation level
---@param reservedSpace number? Space to reserve on the first line for prefixes.
---@return string representation
function LoggerPrototype:serializeTable(t, indent, reservedSpace)
    selfCheck(self)
    if type(t) ~= "table" then
        return tostring(t)
    end
    if next(t) == nil then
        return "{}"
    end

    indent = indent or 0
    reservedSpace = reservedSpace or 0

    -- Step 1: Categorize and sort keys.
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
            table.insert(otherKeys, k)
        end
    end
    table.sort(numKeys)
    table.sort(strKeys, function(a, b) return string.len(t[a]) < string.len(t[b]) end)
    table.sort(funcKeys)
    table.sort(tblKeys)
    table.sort(otherKeys)

    -- Step 2: Combine keys into a single list of "items" to be processed linearly.
    local items = {}
    for _, k in ipairs(numKeys)   do table.insert(items, {key=k, type="number"}) end
    for _, k in ipairs(strKeys)   do table.insert(items, {key=k, type="string"}) end
    for _, k in ipairs(funcKeys)  do table.insert(items, {key=k, type="function"}) end
    for _, k in ipairs(otherKeys) do table.insert(items, {key=k, type="other"}) end
    for _, k in ipairs(tblKeys)   do table.insert(items, {key=k, type="table"}) end

    -- NEW: Filter items based on `only` list if present
    local filterConfig = self.filterConfig
    if filterConfig and filterConfig.only then
        local keptItems = {}
        for _, item in ipairs(items) do
            local k_str = tostring(item.key)
            for _, pattern in ipairs(filterConfig.only) do
                if string.match(k_str, pattern) then
                    table.insert(keptItems, item)
                    break
                end
            end
        end
        items = keptItems
    end

    if #items == 0 then
        return "{}"
    end

    -- Step 3: Linearly build the output string.
    local result = "{"
    local lineContentLength = 0
    local currentLinePrefixLength = reservedSpace

    for i, item in ipairs(items) do
        -- NEW: Check if this item should have its value ignored
        local isIgnored = false
        if filterConfig and filterConfig.ignore then
            local k_str = tostring(item.key)
            for _, pattern in ipairs(filterConfig.ignore) do
                if string.match(k_str, pattern) then
                    isIgnored = true
                    break
                end
            end
        end

        local isFirstItem = (i == 1)
        local separator = isFirstItem and "" or ", "
        local part

        if isIgnored then
            local valueString
            local vType = type(t[item.key])
            if vType == "table" then
                valueString = "{<ignored>}"
            elseif vType == "string" then
                valueString = string.format("%q", "<ignored>")
            else
                valueString = "<ignored>"
            end
            part = tostring(item.key) .. "=" .. valueString

            if currentLinePrefixLength + lineContentLength + #separator + #part > MAX_LINE_LENGTH and not isFirstItem then
                result = result .. ",\n" .. string.rep(" ", indent + 2) .. part
                currentLinePrefixLength = indent + 2
                lineContentLength = #part
            else
                result = result .. separator .. part
                lineContentLength = lineContentLength + #separator + #part
            end
        elseif item.type ~= "table" then
            if item.type == "number"   then part = tostring(item.key) .. "=" .. string.format("%.6f", t[item.key])
            elseif item.type == "string"   then part = tostring(item.key) .. "=" .. string.format("%q", t[item.key])
            elseif item.type == "function" then part = tostring(item.key) .. "=function"
            else part = tostring(item.key) .. "=" .. tostring(t[item.key]) end

            if currentLinePrefixLength + lineContentLength + #separator + #part > MAX_LINE_LENGTH and not isFirstItem then
                result = result .. ",\n" .. string.rep(" ", indent + 2) .. part
                currentLinePrefixLength = indent + 2
                lineContentLength = #part
            else
                result = result .. separator .. part
                lineContentLength = lineContentLength + #separator + #part
            end
        else -- This item is a table and not ignored
            local keyPart = tostring(item.key) .. " = "

            if currentLinePrefixLength + lineContentLength + #separator + #keyPart > MAX_LINE_LENGTH and not isFirstItem then
                result = result .. ",\n" .. string.rep(" ", indent + 2) .. keyPart
                currentLinePrefixLength = indent + 2
                lineContentLength = #keyPart
            else
                result = result .. separator .. keyPart
                lineContentLength = lineContentLength + #separator + #keyPart
            end

            local spaceForRecursiveCall = currentLinePrefixLength + lineContentLength
            local serializedContent = self:serializeTable(t[item.key], indent + 2, spaceForRecursiveCall)

            result = result .. serializedContent

            local lastLineOfContent = serializedContent:match("[^\n]*$")
            if string.find(serializedContent, "\n") then
                currentLinePrefixLength = indent + 2
                lineContentLength = #lastLineOfContent
            else
                lineContentLength = lineContentLength + #serializedContent
            end
        end
    end

    result = result .. "}"
    return result
end

-- Helper function to concatenate multiple arguments into a single string
-- with proper type conversion. It uses the instance's formatting methods.
---@param instance LoggerInstance
local function formatMessage(instance, ...)
    local args = {...}
    local preComputedParts = {}
    local isAnyPartLarge = false
    local MULTILINE_THRESHOLD = 140

    -- This is the full, static prefix for any non-itemized log from this logger instance.
    local basePrefixLength = SPRING_ECHO_PREFIX_LENGTH + string.len("[" .. instance.prefix .. "] ") + LOG_LEVEL_PREFIX_LENGTH

    -- Pass 1: Pre-compute all parts and check if a multi-line layout is needed.
    local i = 1
    local runningSingleLineLength = basePrefixLength
    while i <= #args do
        local arg = args[i]
        local currentPart = { content = "", indices = {}, isTable = false, originalArg = nil, label = nil }

        if i + 1 <= #args and type(arg) == "string" and type(args[i + 1]) == "table" then
            currentPart.isTable = true
            currentPart.originalArg = args[i+1]
            currentPart.label = arg
            currentPart.indices = {i, i + 1}
            local labelPart = string.format("'%s' = ", arg)
            -- For this pre-computation, calculate reserved space assuming a single-line layout.
            local reservedSpace = runningSingleLineLength + #labelPart + (#preComputedParts * 3) -- * 3 for " | " separators
            currentPart.content = labelPart .. instance:serializeTable(args[i+1], 0, reservedSpace)
            i = i + 2
        else
            currentPart.originalArg = arg
            currentPart.isTable = (type(arg) == "table")
            if currentPart.isTable then
                local reservedSpace = runningSingleLineLength + (#preComputedParts * 3)
                currentPart.content = instance:serializeTable(arg, 0, reservedSpace)
            elseif type(arg) == "number" then
                currentPart.content = string.format("%.6f", arg)
            else
                currentPart.content = tostring(arg)
            end
            currentPart.indices = {i}
            i = i + 1
        end

        table.insert(preComputedParts, currentPart)
        runningSingleLineLength = runningSingleLineLength + #currentPart.content

        if not isAnyPartLarge then
            if string.find(currentPart.content, "\n") or #currentPart.content > MULTILINE_THRESHOLD then
                isAnyPartLarge = true
            end
        end
    end

    -- Pass 2: Assemble the final string based on the chosen layout.
    if isAnyPartLarge and #preComputedParts > 1 then
        local multiLines = {}
        for _, part in ipairs(preComputedParts) do
            local content
            -- Re-serialize tables for the itemized view, which has a different (and fixed) prefix.
            if part.isTable then
                local tablePrefixLength = 12 -- Approx length for "#i,j   -> "
                if part.label then
                    local labelPart = string.format("'%s' = ", part.label)
                    content = labelPart .. instance:serializeTable(part.originalArg, 2, tablePrefixLength + #labelPart)
                else
                    content = instance:serializeTable(part.originalArg, 2, tablePrefixLength)
                end
            else
                content = part.content
            end

            local indicesStr = "#" .. table.concat(part.indices, ",")
            local formattedIndices = string.format("%-7s", indicesStr)
            content = string.gsub(content, "\n", "\n           ")

            local line = formattedIndices .. "-> " .. content
            table.insert(multiLines, line)
        end
        return "\n" .. table.concat(multiLines, "\n")
    else
        local singleLineParts = {}
        for _, p in ipairs(preComputedParts) do
            table.insert(singleLineParts, p.content)
        end
        return table.concat(singleLineParts, " | ")
    end
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
    if math.random() >= 0.1 then
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
    local newPrefixValue = self.prefix .. "] [" .. additionalPrefix

    ---@type LoggerInstance
    local subLogger = {
        prefix = newPrefixValue,
        getLogLevel = self.getLogLevel -- Inherit the log level getter function
    }
    setmetatable(subLogger, LoggerPrototype) -- All methods are inherited from LoggerPrototype
    return subLogger
end

--- Creates a temporary logger instance that will ignore specified fields when serializing a table.
--- Field names are treated as Lua patterns.
---@param self LoggerInstance
---@vararg string
---@return LoggerInstance A new logger instance with an 'ignore' filter
function LoggerPrototype:ignore(...)
    local tempLogger = {}
    for k, v in pairs(self) do tempLogger[k] = v end
    tempLogger.filterConfig = { ignore = {...} }
    setmetatable(tempLogger, getmetatable(self))
    return tempLogger
end

--- Creates a temporary logger instance that will only include specified fields when serializing a table.
--- All other fields will be omitted. Field names are treated as Lua patterns.
---@param self LoggerInstance
---@vararg string
---@return LoggerInstance A new logger instance with an 'only' filter
function LoggerPrototype:only(...)
    local tempLogger = {}
    for k, v in pairs(self) do tempLogger[k] = v end
    tempLogger.filterConfig = { only = {...} }
    setmetatable(tempLogger, getmetatable(self))
    return tempLogger
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