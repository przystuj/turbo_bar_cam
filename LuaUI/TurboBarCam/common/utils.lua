---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------
---@class Util
local Util = {}

local lastThrottledExecutionTimes = {}

--- Checks if a value exists in an array
---@param tbl table The array to search in
---@param value any The value to search for
---@return boolean found Whether the value was found
function Util.tableContains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

--- Counts number of elements in a table (including non-numeric keys)
---@param t table The table to count
---@return number count The number of elements
function Util.tableCount(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

--- Throttles function execution to occur at most once per specified interval
--- The first call initializes the timer without executing the function.
---
--- Usage example:
---   Util.throttleExecution(function() print("Heavy calculation") end, 1, "calculation")
---
--- @param fn function The function to throttle
--- @param interval number Minimum time in seconds between executions
--- @param id string|nil Optional identifier for the throttle (allows different throttles for different functions)
--- @return nil
function Util.throttleExecution(fn, interval, id)
    -- Default to a generic ID if none provided
    local functionId = id or "throttledExecution"

    if not lastThrottledExecutionTimes[functionId] then
        lastThrottledExecutionTimes[functionId] = Spring.GetGameSeconds()
        return
    end

    local currentTime = Spring.GetGameSeconds()
    if currentTime - lastThrottledExecutionTimes[functionId] >= interval then
        Log.trace(string.format("[%s] [%ss] Executing...", functionId, interval))
        fn()
        lastThrottledExecutionTimes[functionId] = currentTime
    end
end

function Util.isTurboBarCamDisabled()
    if not STATE.enabled then
        Log.trace("TurboBarCam must be enabled first. Use /turbobarcam_toggle")
        return true
    end
end

---@param mode 'fps'|'unit_tracking'|'orbit'|'overview'
function Util.isModeDisabled(mode)
    if STATE.tracking.mode ~= mode then
        Log.trace(string.format("Mode %s must be enabled first. Current mode: %s", mode, tostring(STATE.tracking.mode)))
        return true
    end
end

local function parseParams(params, moduleName)
    -- Check if the moduleName string is empty or nil
    if not moduleName or moduleName == "" or not CONFIG.MODIFIABLE_PARAMS[moduleName] then
        Log.error("Invalid moduleName " .. tostring(moduleName))
    end

    -- Check if the params string is empty or nil
    if not params or params == "" then
        Log.error("Empty parameters string")
    end

    -- Split the params string by semicolons
    local parts = {}
    for part in string.gmatch(params, "[^;]+") do
        table.insert(parts, part)
    end

    -- Get the command type (first part)
    local command = parts[1]
    if not command then
        Log.error("No command specified")
    end

    local validParams = CONFIG.MODIFIABLE_PARAMS[moduleName].PARAM_NAMES
    local modifiedParams = {}

    -- Handle reset command
    if command == "reset" then
        table.insert(modifiedParams, { name = "reset" }) -- the value doesn't matter here
        return modifiedParams
    end

    -- Check if command is valid
    if command ~= "set" and command ~= "add" then
        Log.error("Invalid command '" .. command .. "', must be 'set', 'add', or 'reset'")
    end

    for i = 2, #parts do
        local paramPair = parts[i]

        -- Split by comma to get parameter name and value
        local paramName, valueStr = string.match(paramPair, "([^,]+),([^,]*)")

        -- Check if parameter name and value are valid
        if not paramName then
            Log.error("Invalid parameter format at '" .. paramPair .. "'")
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
            Log.error("Unknown parameter '" .. paramName .. "'")
        end

        -- Convert value to number
        local value = tonumber(valueStr)
        if not value then
            Log.error("Invalid numeric value for parameter '" .. paramName .. "'")
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
            Log.error("Invalid parameter path: " .. table.concat(paramPath, "."))
            return
        end
    end

    -- Get the current value
    local currentValue = currentConfigTable[paramName]
    if currentValue == nil then
        Log.error("Parameter not found: " .. command.param)
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
        Log.error("Parameter boundaries not found for: " .. command.param)
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
        Log.debug("Value has not changed.")
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

    Log.debug(string.format("%s.%s = %s", module, command.param, displayValue))
end

---@param params string Params to adjust in following format: [set|add|reset];[paramName],[value];[paramName2],[value2];...
---@param module string module name as in ModifiableParams class (FPS, ORBIT, TRANSITION)
---@param resetFunction function function which will be called when 'reset' is used
---to decrease value use 'add' with negative value
---if you use 'reset', the params will be ignored. All params will be rest to default values
---example params: add;HEIGHT,100;DISTANCE,-50
---@see ModifiableParams
function Util.adjustParams(params, module, resetFunction)
    Log.debug("Adjusting module: " .. module)
    local adjustments = parseParams(params, module)

    ---@param adjustment CommandData
    for _, adjustment in ipairs(adjustments) do
        if adjustment.name == "reset" then
            if resetFunction then
                Log.debug("Resetting params for module " .. module)
                resetFunction()
                return
            else
                Log.error("Reset function missing for module " .. module)
                return
            end
        else
            adjustParam(adjustment, module)
        end
    end
end

--- Creates a deep copy of a table
---@param orig table Table to copy
---@return table copy Deep copy of the table
function Util.deepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = Util.deepCopy(orig_value)
        end
    else
        copy = orig
    end
    return copy
end

--- Gets the height of a unit
---@param unitID number Unit ID
---@return number unit height
function Util.getUnitHeight(unitID)
    if not Spring.ValidUnitID(unitID) then
        return 200
    end

    -- Get unit definition ID and access height from UnitDefs
    local unitDefID = Spring.GetUnitDefID(unitID)
    if not unitDefID then
        return 200
    end

    local unitDef = UnitDefs[unitDefID]
    if not unitDef then
        return 200
    end

    -- Return unit height or default if not available
    return unitDef.height or 200
end

--- Check if two points are within a certain distance threshold
--- Distance is calculated on the x-z plane only (ignoring height)
---@param point1 table First point with x and z coordinates
---@param point2 table Second point with x and z coordinates
---@param threshold number Distance threshold
---@return boolean within Whether the points are within the threshold distance
function Util.pointsWithinDistance(point1, point2, threshold)
    if not point1 or not point2 then return false end

    local distSq = (point1.x - point2.x)^2 + (point1.z - point2.z)^2
    return distSq <= threshold^2
end

-- Export to global scope
return {
    Util = Util
}