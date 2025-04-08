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
        Log.info(string.format("[%s] [%ss] Executing...", functionId, interval))
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

---@param mode 'fps'|'unit_tracking'|'orbit'|'turbo_overview'
function Util.isModeDisabled(mode)
    if STATE.tracking.mode ~= mode then
        Log.trace(string.format("Mode %s must be enabled first. Current mode: %s", mode, tostring(STATE.tracking.mode)))
        return true
    end
end

---@param message string error message
function Util.error(message)
    error("[TurboBarCam] Error: " .. message)
end

local function parseParams(params, moduleName)
    -- Check if the moduleName string is empty or nil
    if not moduleName or moduleName == "" or not CONFIG.MODIFIABLE_PARAMS[moduleName] then
        Util.error("Invalid moduleName " .. tostring(moduleName))
    end

    -- Check if the params string is empty or nil
    if not params or params == "" then
        Util.error("Empty parameters string")
    end

    -- Split the params string by semicolons
    local parts = {}
    for part in string.gmatch(params, "[^;]+") do
        table.insert(parts, part)
    end

    -- Get the command type (first part)
    local command = parts[1]
    if not command then
        Util.error("No command specified")
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
        Util.error("Invalid command '" .. command .. "', must be 'set', 'add', or 'reset'")
    end

    for i = 2, #parts do
        local paramPair = parts[i]

        -- Split by comma to get parameter name and value
        local paramName, valueStr = string.match(paramPair, "([^,]+),([^,]*)")

        -- Check if parameter name and value are valid
        if not paramName then
            Util.error("Invalid parameter format at '" .. paramPair .. "'")
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
            Util.error("Unknown parameter '" .. paramName .. "'")
        end

        -- Convert value to number
        local value = tonumber(valueStr)
        if not value then
            Util.error("Invalid numeric value for parameter '" .. paramName .. "'")
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
            Util.error("Invalid parameter path: " .. table.concat(paramPath, "."))
            return
        end
    end

    -- Get the current value
    local currentValue = currentConfigTable[paramName]
    if currentValue == nil then
        Util.error("Parameter not found: " .. command.param)
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
        Util.error("Parameter boundaries not found for: " .. command.param)
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
                Util.error("Reset function missing for module " .. module)
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

--- Cubic easing function for smooth transitions
---@param t number Transition progress (0.0-1.0)
---@return number eased value
function Util.easeInOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local t2 = (t - 1)
        return 1 + 4 * t2 * t2 * t2
    end
end

--- Linear interpolation between two values
---@param a number Start value
---@param b number End value
---@param t number Interpolation factor (0.0-1.0)
---@return number interpolated value
function Util.lerp(a, b, t)
    return a + (b - a) * t
end

--- Normalizes an angle to be within -pi to pi range
---@param angle number|nil Angle to normalize (in radians)
---@return number normalized angle
function Util.normalizeAngle(angle)
    if angle == nil then
        return 0 -- Default to 0 if angle is nil
    end

    local twoPi = 2 * math.pi
    angle = angle % twoPi
    if angle > math.pi then
        angle = angle - twoPi
    end
    return angle
end

--- Interpolates between two angles along the shortest path
---@param a number Start angle (in radians)
---@param b number End angle (in radians)
---@param t number Interpolation factor (0.0-1.0)
---@return number interpolated angle
function Util.lerpAngle(a, b, t)
    -- Normalize both angles to -pi to pi range
    a = Util.normalizeAngle(a)
    b = Util.normalizeAngle(b)

    -- Find the shortest path
    local diff = b - a

    -- If the difference is greater than pi, we need to go the other way around
    if diff > math.pi then
        diff = diff - 2 * math.pi
    elseif diff < -math.pi then
        diff = diff + 2 * math.pi
    end

    return a + diff * t
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

--- Smoothly interpolates between current and target values
---@param current number|nil Current value
---@param target number|nil Target value
---@param factor number Smoothing factor (0.0-1.0)
---@return number smoothed value
function Util.smoothStep(current, target, factor)
    if current == nil or target == nil or factor == nil then
        return current or target or 0
    end
    return current + (target - current) * factor
end

--- Smoothly interpolates between angles
---@param current number|nil Current angle (in radians)
---@param target number|nil Target angle (in radians)
---@param factor number Smoothing factor (0.0-1.0)
---@return number smoothed angle
function Util.smoothStepAngle(current, target, factor)
    -- Add safety check for nil values
    if current == nil or target == nil or factor == nil then
        return current or target or 0 -- Return whichever is not nil, or 0 if both are nil
    end

    -- Normalize both angles to -pi to pi range
    current = Util.normalizeAngle(current)
    target = Util.normalizeAngle(target)

    -- Find the shortest path
    local diff = target - current

    -- If the difference is greater than pi, we need to go the other way around
    if diff > math.pi then
        diff = diff - 2 * math.pi
    elseif diff < -math.pi then
        diff = diff + 2 * math.pi
    end

    return current + diff * factor
end

--- Calculates camera direction and rotation to look at a point
---@param camPos table Camera position {x, y, z}
---@param targetPos table Target position {x, y, z}
---@return table direction and rotation values
function Util.calculateLookAtPoint(camPos, targetPos)
    -- Calculate direction vector from camera to target
    local dirX = targetPos.x - camPos.x
    local dirY = targetPos.y - camPos.y
    local dirZ = targetPos.z - camPos.z

    -- Normalize the direction vector
    local length = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)
    if length > 0 then
        dirX = dirX / length
        dirY = dirY / length
        dirZ = dirZ / length
    end

    -- Calculate appropriate rotation for FPS camera
    local ry = -math.atan2(dirX, dirZ) - math.pi

    -- Calculate pitch (rx)
    local horizontalLength = math.sqrt(dirX * dirX + dirZ * dirZ)
    local rx = -((math.atan2(dirY, horizontalLength) - math.pi) / 1.8)

    return {
        dx = dirX,
        dy = dirY,
        dz = dirZ,
        rx = rx,
        ry = ry,
        rz = 0
    }
end

-- Export to global scope
return {
    Util = Util
}