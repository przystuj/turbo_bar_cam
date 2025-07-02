---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local Log = ModuleManager.Log(function(m) Log = m end, "TableUtils")

---@class TableUtils
local TableUtils = {}

--- Checks if a value exists in an array
---@param tbl table The array to search in
---@param value any The value to search for
---@return boolean found Whether the value was found
function TableUtils.tableContains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

--- Creates a deep copy of a table
---@param orig table Table to copy
---@return table copy Deep copy of the table
function TableUtils.deepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = TableUtils.deepCopy(orig_value)
        end
    else
        copy = orig
    end
    return copy
end

--- Subtracts the values of t2 from t1 for matching keys, if both are numbers.
--- It iterates through all keys in t1. If a key in t1 does not exist in t2,
--- or if the value in t1 or t2 for a key is not a number,
--- the value from t1 is used in the result.
---@param t1 table The table to subtract from (Minuend).
---@param t2 table The table whose values are subtracted (Subtrahend).
---@return table result A new table containing the subtraction results.
function TableUtils.subtractTable(t1, t2)
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


--- Applies new values from a source table to a target table.
--- This function modifies the target table in place.
---
--- • It ADDS new key-value pairs from the source to the target.
--- • It UPDATES existing values in the target with those from the source.
--- • It recursively patches nested tables.
--- • It NEVER removes keys from the target. Keys that exist in the target but not in the source are left untouched.
---
---@param target table The table to be updated.
---@param source table The table containing the new values.
---@return table The modified target table.
function TableUtils.patchTable(target, source)
    if type(target) ~= "table" then
        Log:warn("Utils.deepApplyTableParams: targetTable is not a table. Got: " .. type(target))
        return target -- Or return nil/error based on desired strictness
    end
    if type(source) ~= "table" then
        Log:warn("Utils.deepApplyTableParams: sourceTable is not a table. Got: " .. type(source))
        -- No changes to targetTable if source is invalid
        return target
    end

    for key, sourceValue in pairs(source) do
        local targetValue = target[key]

        if type(sourceValue) == "table" then
            if type(targetValue) == "table" then
                -- Both are tables, recurse to merge
                TableUtils.patchTable(targetValue, sourceValue)
            else
                -- Source is a table, target is not (or nil).
                -- Assign a deep copy of the source table to the target.
                target[key] = TableUtils.deepCopy(sourceValue)
            end
        else
            -- Source is not a table, so directly assign its value.
            target[key] = sourceValue
        end
    end

    return target
end

--- Makes a target table an exact structural copy of a source table.
--- This function modifies the target table in place.
---
--- • It ADDS new key-value pairs from the source to the target.
--- • It UPDATES existing values in the target with those from the source.
--- • It REMOVES any keys from the target that are not present in the source.
---
--- After this operation, the target table will be a structural mirror of the source.
---
---@param target table The table to be synchronized.
---@param source table The blueprint table to copy from.
---@return table The modified target table.
function TableUtils.syncTable(target, source)
    if type(target) ~= "table" then
        Log:warn("TableUtils.syncTable: target is not a table. Got: " .. type(target))
        return target
    end
    if type(source) ~= "table" then
        Log:warn("TableUtils.syncTable: source is not a table. Got: " .. type(source))
        -- If source is not a table, it has no keys.
        -- Therefore, all keys must be removed from target.
        for k in pairs(target) do
            target[k] = nil
        end
        return target
    end

    -- Step 1: Update and add keys from source to target.
    -- This step ensures that target has all the keys from source,
    -- with values updated or recursively synchronized.
    for key, sourceValue in pairs(source) do
        local targetValue = target[key]

        if type(sourceValue) == "table" then
            if type(targetValue) == "table" then
                -- If both the source and target values for a key are tables,
                -- recurse into them to synchronize their contents.
                TableUtils.syncTable(targetValue, sourceValue)
            else
                -- If the source value is a table but the target's is not (or nil),
                -- replace the target value with a deep copy of the source table
                -- to ensure the structure matches and prevent reference sharing.
                target[key] = TableUtils.deepCopy(sourceValue)
            end
        else
            -- If the source value is not a table, simply assign it to the target.
            target[key] = sourceValue
        end
    end

    -- Step 2: Remove keys from target that are not present in source.
    -- This ensures that target does not contain any extra keys.
    for key, _ in pairs(target) do
        if source[key] == nil then
            target[key] = nil
        end
    end

    return target
end

--- Counts number of elements in a table (including non-numeric keys)
---@param t table The table to count
---@return number count The number of elements
function TableUtils.tableCount(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

return TableUtils