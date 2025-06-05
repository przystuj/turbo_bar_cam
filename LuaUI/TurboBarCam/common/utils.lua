---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)

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
        Log:trace(string.format("[%s] [%ss] Executing...", functionId, interval))
        fn()
        lastThrottledExecutionTimes[functionId] = currentTime
    end
end

function Util.isTurboBarCamDisabled()
    if not STATE.enabled then
        Log:trace("TurboBarCam must be enabled first. Use /turbobarcam_toggle")
        return true
    end
end

---@param mode 'fps'|'unit_tracking'|'orbit'|'overview'
function Util.isModeDisabled(mode)
    if mode == "global" and STATE.mode.name then
        return true
    end
    if mode ~= "global" and STATE.mode.name ~= mode then
        return true
    end
end

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
    if command ~= "set" and command ~= "add" then
        Log:error("Invalid command '" .. command .. "', must be 'set', 'add', or 'reset'")
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
end

---@param params string Params to adjust in following format: [set|add|reset];[paramName],[value];[paramName2],[value2];...
---@param module string module name as in ModifiableParams class (FPS, ORBIT, TRANSITION)
---@param resetFunction function function which will be called when 'reset' is used
---@param currentSubmode string|nil Optional current submode name (e.g., "PEACE", "FOLLOW")
---@param getSubmodeParamPrefixes function|nil Optional function that returns a table of submode_name -> prefix_string (e.g., {PEACE = "PEACE.", FOLLOW = "FOLLOW."})
function Util.adjustParams(params, module, resetFunction, currentSubmode, getSubmodeParamPrefixes)
    Log:trace("Adjusting module: " .. module .. (currentSubmode and (" (Submode: " .. currentSubmode .. ")") or ""))
    local adjustments = parseParams(params, module)

    if not adjustments then -- parseParams returned an error
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
                adjustParam(adjustment, module)
            end
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
        Log:warn("NaN detected in Hermite interpolation")
        -- Fall back to linear interpolation if Hermite produces NaN
        result.x = (1-t) * p0x + t * p1x
        result.y = (1-t) * p0y + t * p1y
        result.z = (1-t) * p0z + t * p1z
    end

    return result
end

--- Performs Hermite interpolation of camera rotations, handling the special case of angles
---@param rx0 number Start pitch angle
---@param ry0 number Start yaw angle
---@param rx1 number End pitch angle
---@param ry1 number End yaw angle
---@param v0 table Start tangent angles {rx, ry}
---@param v1 table End tangent angles {rx, ry}
---@param t number Interpolation factor (0-1)
---@return number rx Interpolated pitch angle
---@return number ry Interpolated yaw angle
function Util.hermiteInterpolateRotation(rx0, ry0, rx1, ry1, v0, v1, t)
    -- Special handling for segment boundaries
    if t <= 0 then return rx0, ry0 end
    if t >= 1 then return rx1, ry1 end

    -- Handle pitch (rx) with standard Hermite interpolation
    -- Pitch is constrained and doesn't wrap, so standard interpolation works
    local t2 = t * t
    local t3 = t2 * t

    local h00 = 2*t3 - 3*t2 + 1
    local h10 = t3 - 2*t2 + t
    local h01 = -2*t3 + 3*t2
    local h11 = t3 - t2

    local rx = h00 * rx0 + h10 * (v0.rx or 0) + h01 * rx1 + h11 * (v1.rx or 0)

    -- Handle yaw (ry) carefully because it wraps around
    -- Normalize angles to handle wrap-around correctly
    ry0 = CameraCommons.normalizeAngle(ry0)
    ry1 = CameraCommons.normalizeAngle(ry1)

    -- Find the shortest path for yaw
    local diff = ry1 - ry0
    if diff > math.pi then
        diff = diff - 2 * math.pi
    elseif diff < -math.pi then
        diff = diff + 2 * math.pi
    end

    -- Apply Hermite with the adjusted difference
    local ry = ry0 + h00 * 0 + h10 * (v0.ry or 0) + h01 * diff + h11 * (v1.ry or 0)

    -- Normalize the final angle
    ry = CameraCommons.normalizeAngle(ry)

    return rx, ry
end

function Util.getCleanMapName()
    local mapName = Game.mapName

    -- Remove version numbers at the end (patterns like 1.2.3 or V1.2.3)
    local cleanName = mapName:gsub("%s+[vV]?%d+%.?%d*%.?%d*$", "")

    return cleanName
end

--- Subtracts the values of t2 from t1 for matching keys, if both are numbers.
--- It iterates through all keys in t1. If a key in t1 does not exist in t2,
--- or if the value in t1 or t2 for a key is not a number,
--- the value from t1 is used in the result.
---@param t1 table The table to subtract from (Minuend).
---@param t2 table The table whose values are subtracted (Subtrahend).
---@return table result A new table containing the subtraction results.
function Util.subtractTable(t1, t2)
    -- Check if inputs are tables
    if type(t1) ~= "table" or type(t2) ~= "table" then
        Log:warn("Both inputs must be tables.")
        return {} -- Return an empty table on invalid input
    end

    local result = {}

    -- Iterate through all keys in the first table (t1)
    for key, value1 in pairs(t1) do
        local value2 = t2[key]

        -- Check if both values are numbers
        if type(value1) == "number" and type(value2) == "number" then
            -- Both are numbers, perform subtraction
            result[key] = value1 - value2
        elseif type(value1) == "number" and value2 == nil then
            -- Only t1 has a number, treat t2's value as 0
            result[key] = value1
        else
            -- If v1 is not a number, or v2 is not a number (but not nil),
            -- or v1 is nil, we default to using the value from t1.
            -- This also copies non-numeric fields.
            result[key] = value1
        end
    end

    for key, value2 in pairs(t2) do
        if t1[key] == nil and type(value2) == "number" then
            result[key] = -value2
        end
    end

    return result
end

--- Splits a string path by a delimiter.
-- @param path The string path to split (e.g., "A.B.C").
-- @param delimiter The character to split by (defaults to ".").
-- @return A table containing the path segments.
function Util.splitPath(path, delimiter)
    delimiter = delimiter or "."
    local segments = {}
    -- Use gmatch to find all sequences of characters that are not the delimiter
    for segment in string.gmatch(path, "([^" .. delimiter .. "]+)") do
        table.insert(segments, segment)
    end
    return segments
end

--- Recursively applies parameters from a source table to a target table.
--- Modifies the targetTable in place.
--- If a key from sourceTable exists in targetTable:
---   - If both values are tables, the function recursively calls itself to merge them.
---   - If the sourceValue is a table and targetValue is not (or nil),
---     the targetTable key is set to a deep copy of sourceValue.
---   - Otherwise (sourceValue is not a table, or targetValue is not a table to recurse into),
---     the value from sourceTable overwrites the value in targetTable.
--- If a key from sourceTable does not exist in targetTable, it is added.
---   (If the sourceValue is a table, it's deep copied to the targetTable).
--- Keys in targetTable not present in sourceTable are unaffected.
---
---@param target table The table to apply parameters to.
---@param source table The table to get parameters from.
---@return table targetTable The modified targetTable.
function Util.patchTable(target, source)
    if type(target) ~= "table" then
        Log:warn("Util.deepApplyTableParams: targetTable is not a table. Got: " .. type(target))
        return target -- Or return nil/error based on desired strictness
    end
    if type(source) ~= "table" then
        Log:warn("Util.deepApplyTableParams: sourceTable is not a table. Got: " .. type(source))
        -- No changes to targetTable if source is invalid
        return target
    end

    for key, sourceValue in pairs(source) do
        local targetValue = target[key]

        if type(sourceValue) == "table" then
            if type(targetValue) == "table" then
                -- Both are tables, recurse to merge
                Util.patchTable(targetValue, sourceValue)
            else
                -- Source is a table, target is not (or nil).
                -- Assign a deep copy of the source table to the target.
                target[key] = Util.deepCopy(sourceValue)
            end
        else
            -- Source is not a table, so directly assign its value.
            target[key] = sourceValue
        end
    end

    return target
end

return Util