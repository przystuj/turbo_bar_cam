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

--- Gets world position at mouse cursor
---@return table|nil point World coordinates {x,y,z} or nil if outside map
function Util.getCursorWorldPosition()
    local mx, my = Spring.GetMouseState()
    local _, pos = Spring.TraceScreenRay(mx, my, true)
    if pos then
        return {x = pos[1], y = pos[2], z = pos[3]}
    end
    return nil
end

--- Validates and normalizes a tracking target
---@param target any The target to validate (unitID or {x,y,z})
---@return any normalizedTarget Validated target (unitID or {x,y,z})
---@return string targetType Target type ('UNIT', 'POINT', or 'NONE')
function Util.validateTarget(target)
    -- Check if target is a unit ID
    if type(target) == "number" then
        if Spring.ValidUnitID(target) then
            return target, STATE.TARGET_TYPES.UNIT
        end
        return nil, STATE.TARGET_TYPES.NONE
    end

    -- Check if target is a point
    if type(target) == "table" and target.x and target.z then
        -- Ensure y coordinate is present
        target.y = target.y or Spring.GetGroundHeight(target.x, target.z)
        return target, STATE.TARGET_TYPES.POINT
    end

    return nil, STATE.TARGET_TYPES.NONE
end

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
    if mode == "global" and STATE.tracking.mode then
        return true
    end
    if mode ~= "global" and STATE.tracking.mode ~= mode then
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
        Log.trace("Value has not changed.")
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
    Log.trace("Adjusting module: " .. module)
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

function Util.getUnitVectors(unitID)
    local x, y, z = Spring.GetUnitPosition(unitID)
    local front, up, right = Spring.GetUnitVectors(unitID)

    return { x = x, y = y, z = z }, front, up, right
end

--- Performs Hermite spline interpolation between two points with tangent vectors
--- This version is specialized for camera path interpolation with continuity preservation
---@param p0 table Start position with px,py,pz (or x,y,z)
---@param p1 table End position with px,py,pz (or x,y,z)
---@param v0 table Start tangent vector with x,y,z
---@param v1 table End tangent vector with x,y,z
---@param t number Interpolation factor (0-1)
---@return table result Interpolated position with x,y,z
function Util.hermiteInterpolate(p0, p1, v0, v1, t)
    -- Special handling for segment boundaries to preserve velocity
    -- At t=0 and t=1, we want to ensure the derivative matches the tangent exactly
    if t <= 0 then return {x = p0.px or p0.x, y = p0.py or p0.y, z = p0.pz or p0.z} end
    if t >= 1 then return {x = p1.px or p1.x, y = p1.py or p1.y, z = p1.pz or p1.z} end

    -- Hermite basis functions
    -- h00: position influence from p0
    -- h10: tangent influence from v0
    -- h01: position influence from p1
    -- h11: tangent influence from v1
    local t2 = t * t
    local t3 = t2 * t
    local h00 = 2*t3 - 3*t2 + 1
    local h10 = t3 - 2*t2 + t
    local h01 = -2*t3 + 3*t2
    local h11 = t3 - t2

    -- Use px, py, pz if available, otherwise fall back to x, y, z
    local p0x = p0.px or p0.x
    local p0y = p0.py or p0.y
    local p0z = p0.pz or p0.z

    local p1x = p1.px or p1.x
    local p1y = p1.py or p1.y
    local p1z = p1.pz or p1.z

    -- Calculate interpolated value, applying basis functions
    local result = {
        x = h00 * p0x + h10 * v0.x + h01 * p1x + h11 * v1.x,
        y = h00 * p0y + h10 * v0.y + h01 * p1y + h11 * v1.y,
        z = h00 * p0z + h10 * v0.z + h01 * p1z + h11 * v1.z
    }

    -- Check for NaN values (can occur with certain tangent combinations)
    if result.x ~= result.x or result.y ~= result.y or result.z ~= result.z then
        Log.warn("NaN detected in Hermite interpolation")
        -- Fall back to linear interpolation if Hermite produces NaN
        result.x = (1-t) * p0x + t * p1x
        result.y = (1-t) * p0y + t * p1y
        result.z = (1-t) * p0z + t * p1z
    end

    return result
end

Util.TimeHelpers = {}

--- Converts elapsed seconds to normalized time (0-1)
---@param elapsedSeconds number Time elapsed in seconds
---@param totalDuration number Total duration in seconds
---@return number normalizedTime Time as a 0-1 value
function Util.TimeHelpers.normalizeTime(elapsedSeconds, totalDuration)
    if totalDuration <= 0 then return 1 end
    return math.min(1, math.max(0, elapsedSeconds / totalDuration))
end

--- Converts normalized time (0-1) to seconds
---@param normalizedTime number Normalized time (0-1)
---@param totalDuration number Total duration in seconds
---@return number seconds Time in seconds
function Util.TimeHelpers.denormalizeTime(normalizedTime, totalDuration)
    return normalizedTime * totalDuration
end

--- Converts step index to normalized time (0-1)
---@param stepIndex number Current step index
---@param totalSteps number Total number of steps
---@return number normalizedTime Time as a 0-1 value
function Util.TimeHelpers.stepToNormalizedTime(stepIndex, totalSteps)
    if totalSteps <= 1 then return 1 end
    return math.min(1, math.max(0, (stepIndex - 1) / (totalSteps - 1)))
end

--- Converts normalized time (0-1) to the closest step index
---@param normalizedTime number Normalized time (0-1)
---@param totalSteps number Total number of steps
---@return number stepIndex The closest step index
function Util.TimeHelpers.normalizedTimeToStep(normalizedTime, totalSteps)
    if totalSteps <= 1 then return 1 end
    local stepIndexF = 1 + normalizedTime * (totalSteps - 1)
    return math.min(totalSteps, math.max(1, math.floor(stepIndexF + 0.5)))
end

--- Gets current normalized progress from timers
---@param startTime number Timer value when the transition/animation started
---@param duration number Duration in seconds
---@return number normalizedTime Current time as a 0-1 value
function Util.TimeHelpers.getTimerProgress(startTime, duration)
    local elapsed = Spring.DiffTimers(Spring.GetTimer(), startTime)
    return Util.TimeHelpers.normalizeTime(elapsed, duration)
end

-- Export to global scope
return {
    Util = Util
}