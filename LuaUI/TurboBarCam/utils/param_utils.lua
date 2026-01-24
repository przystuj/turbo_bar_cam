---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local Log = ModuleManager.Log(function(m) Log = m end, "ParamUtils")
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)


---@class ParamUtils
local ParamUtils = {}

local function parseParams(params, moduleName)
    -- Check if the moduleName string is empty or nil
    if not moduleName or moduleName == "" or not CONFIG.MODIFIABLE_PARAMS[moduleName] then
        Log:error("Invalid moduleName " .. tostring(moduleName))
        return nil -- Return nil on error
    end

    -- Check if the params string is empty or nil
    if not params or params == "" then
        Log:error("Empty parameters string")
        return nil -- Return nil on error
    end

    -- Split the params string by semicolons
    local parts = {}
    for part in string.gmatch(params, "[^;]+") do
        table.insert(parts, part)
    end

    -- Get the command type (first part)
    local command = parts[1]
    if not command then
        Log:error("No command specified")
        return nil -- Return nil on error
    end

    local validParams = CONFIG.MODIFIABLE_PARAMS[moduleName].PARAM_NAMES
    local modifiedParams = {}

    -- Handle reset command
    if command == "reset" then
        table.insert(modifiedParams, { name = "reset" }) -- the value doesn't matter here
        return modifiedParams
    end

    -- Check if command is valid
    if command ~= "set" and command ~= "add" and command ~= "temp" then
        Log:error("Invalid command '" .. command .. "', must be 'set', 'add', 'temp', or 'reset'")
        return nil -- Return nil on error
    end

    for i = 2, #parts do
        local paramPair = parts[i]

        -- Split by comma to get parameter name and value
        local paramName, valueStr = string.match(paramPair, "([^,]+),([^,]*)")

        -- Check if parameter name and value are valid
        if not paramName then
            Log:error("Invalid parameter format at '" .. paramPair .. "'")
            return nil -- Return nil on error
        end

        -- Check if parameter name is recognized
        local isValidParam = false
        local paramConfig

        -- Try direct match first
        if validParams[paramName] then
            isValidParam = true
            paramConfig = validParams[paramName]
        else
            -- Check for nested parameters (e.g., "OFFSETS.FORWARD")
            for validParamName, config in pairs(validParams) do
                if validParamName == paramName then
                    isValidParam = true
                    paramConfig = config
                    break
                end
            end
        end

        if not isValidParam then
            Log:error("Unknown parameter '" .. paramName .. "'")
            return nil -- Return nil on error
        end

        -- Convert value to number
        local value = tonumber(valueStr)
        if not value then
            Log:error("Invalid numeric value for parameter '" .. paramName .. "'")
            return nil -- Return nil on error
        end

        ---@class CommandData
        local commandData = { name = command, param = paramName, value = value }
        table.insert(modifiedParams, commandData)
    end

    return modifiedParams
end

---@param command CommandData
local function adjustParam(command, module)
    local newValue = command.value

    -- Handle nested parameters (e.g., "OFFSETS.FORWARD")
    local paramParts = {}
    for part in string.gmatch(command.param, "[^.]+") do
        table.insert(paramParts, part)
    end

    -- Navigate to the correct parameter location
    local currentConfigTable = CONFIG.MODIFIABLE_PARAMS[module].PARAMS_ROOT
    local paramPath = {} -- For error reporting
    local paramName = paramParts[#paramParts] -- The last part is the actual parameter name

    -- Navigate the nested structure (except for the last part which is the parameter name)
    for i = 1, #paramParts - 1 do
        table.insert(paramPath, paramParts[i])
        if currentConfigTable[paramParts[i]] then
            currentConfigTable = currentConfigTable[paramParts[i]]
        else
            Log:error("Invalid parameter path: " .. table.concat(paramPath, "."))
            return
        end
    end

    -- Get the current value
    local currentValue = currentConfigTable[paramName]
    if currentValue == nil then
        Log:error("Parameter not found: " .. command.param)
        return
    end

    -- Get the parameter boundaries
    local boundaries = nil
    for validParamName, config in pairs(CONFIG.MODIFIABLE_PARAMS[module].PARAM_NAMES) do
        if validParamName == command.param then
            boundaries = config
            break
        end
    end

    if not boundaries then
        Log:error("Parameter boundaries not found for: " .. command.param)
        return
    end

    -- Apply 'add' command if needed
    if command.name == "add" then
        if boundaries[3] == "rad" then
            -- handle radians
            newValue = (currentValue + newValue) % (2 * math.pi)
            if newValue > math.pi then
                newValue = newValue - 2 * math.pi
            end
        else
            newValue = newValue + currentValue
        end
    end

    -- Apply boundaries
    local minValue = boundaries[1]
    local maxValue = boundaries[2]
    local type = boundaries[3]

    if minValue then
        newValue = math.max(newValue, minValue)
    end
    if maxValue then
        newValue = math.min(newValue, maxValue)
    end

    -- Check if value has changed
    if newValue == currentValue then
        Log:trace("Value has not changed.")
        return
    end

    -- Update the value
    currentConfigTable[paramName] = newValue

    -- Display formatted value
    local displayValue = newValue
    if type == "rad" then
        -- Print the updated offsets with rotation in degrees for easier understanding
        displayValue = math.floor(newValue * 180 / math.pi)
    end

    Log:debug(string.format("%s.%s = %s", module, command.param, displayValue))
    if command.name == "temp" then
        return true
    end
end

---@param params string Params to adjust in following format: [set|add|reset|temp];[paramName],[value];[paramName2],[value2];...
---@param module string module name as in ModifiableParams class (UNIT_FOLLOW, ORBIT, TRANSITION)
---@param resetFunction function function which will be called when 'reset' is used
---@param currentSubmode string|nil Optional current submode name (e.g., "DEFAULT", "FOLLOW")
---@param getSubmodeParamPrefixes function|nil Optional function that returns a table of submode_name -> prefix_string (e.g., {DEFAULT = "DEFAULT.", FOLLOW = "FOLLOW."})
---mode 'temp' sets the values like 'set' but result isn't persisted - it will reset to previous state after disabling the mode
function ParamUtils.adjustParams(params, module, resetFunction, currentSubmode, getSubmodeParamPrefixes)
    Log:trace("Adjusting module: " .. module .. (currentSubmode and (" (Submode: " .. currentSubmode .. ")") or ""))
    local adjustments = parseParams(params, module)

    if not adjustments then
        -- parseParams returned an error
        return
    end

    local submodeParamPrefixes
    if currentSubmode and getSubmodeParamPrefixes then
        submodeParamPrefixes = getSubmodeParamPrefixes()
    end

    ---@param adjustment CommandData
    for _, adjustment in ipairs(adjustments) do
        local shouldProcess = true -- Flag to control processing

        if adjustment.name == "reset" then
            if resetFunction then
                Log:debug("Resetting params for module " .. module)
                resetFunction()
                return -- Exit after reset
            else
                Log:error("Reset function missing for module " .. module)
                return
            end
        else
            -- Submode filtering logic
            if currentSubmode and submodeParamPrefixes then
                local paramName = adjustment.param
                local isSubmodeParam = false
                local belongsToCurrentSubmode = false

                -- Check if the param belongs to any submode and if it belongs to the current one
                for submodeKey, prefix in pairs(submodeParamPrefixes) do
                    -- Ensure prefix ends with a dot or is the full name to avoid partial matches
                    local prefixLen = string.len(prefix)
                    if string.sub(paramName, 1, prefixLen) == prefix then
                        isSubmodeParam = true
                        if submodeKey == currentSubmode then
                            belongsToCurrentSubmode = true
                            break -- Found its submode, no need to check others
                        end
                    end
                end

                -- If it's a submode param but *not* for the current submode, skip it
                if isSubmodeParam and not belongsToCurrentSubmode then
                    Log:trace("Skipping param '" .. paramName .. "' as it belongs to a different submode.")
                    shouldProcess = false
                end
            end

            -- Only adjust if the flag is true
            if shouldProcess then
                return adjustParam(adjustment, module)
            end
        end
    end
end

return ParamUtils
