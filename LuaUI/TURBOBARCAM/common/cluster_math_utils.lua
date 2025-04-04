-- Math utilities for clustering and spatial operations
-- Load context for access to core utilities

---@class ClusterMathUtils
local ClusterMathUtils = {}

--- Calculates squared distance between two points
---@param p1 table First position with x, y, z fields
---@param p2 table Second position with x, y, z fields
---@return number distanceSquared The squared distance between points
function ClusterMathUtils.distanceSquared(p1, p2)
    local dx = p1.x - p2.x
    local dy = p1.y - p2.y
    local dz = p1.z - p2.z
    return dx*dx + dy*dy + dz*dz
end

--- Checks if a value exists in an array
---@param tbl table The array to search in
---@param value any The value to search for
---@return boolean found Whether the value was found
function ClusterMathUtils.tableContains(tbl, value)
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
function ClusterMathUtils.tableCount(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

--- Calculates the weighted center of mass for a group of units
---@param unitIDs table Array of unit IDs
---@return table centerOfMass Position {x, y, z} of center of mass
---@return number totalWeight Combined weight of all units
---@return number validUnits Number of valid units used in calculation
function ClusterMathUtils.calculateCenterOfMass(unitIDs)
    local weightedX, weightedY, weightedZ = 0, 0, 0
    local totalWeight = 0
    local validUnits = 0

    for _, unitID in ipairs(unitIDs) do
        if Spring.ValidUnitID(unitID) then
            local x, y, z = Spring.GetUnitPosition(unitID)

            -- Get unit weight from its definition
            local unitDefID = Spring.GetUnitDefID(unitID)
            local weight = 1 -- Default weight if we can't get from definition

            if unitDefID and UnitDefs[unitDefID] then
                -- Use mass as weight, or fallback to 1
                weight = UnitDefs[unitDefID].mass or 1
            end

            weightedX = weightedX + (x * weight)
            weightedY = weightedY + (y * weight)
            weightedZ = weightedZ + (z * weight)
            totalWeight = totalWeight + weight
            validUnits = validUnits + 1
        end
    end

    -- Calculate center of mass
    local center = {x = 0, y = 0, z = 0}
    if validUnits > 0 and totalWeight > 0 then
        center.x = weightedX / totalWeight
        center.y = weightedY / totalWeight
        center.z = weightedZ / totalWeight
    else
        -- No valid units, use the map center as fallback
        center.x = Game.mapSizeX / 2
        center.y = 0
        center.z = Game.mapSizeZ / 2
        totalWeight = 0
    end

    return center, totalWeight, validUnits
end

--- Calculates the radius of a group (max distance from center to any unit)
---@param unitIDs table Array of unit IDs
---@param center table Center position {x, y, z}
---@return number radius The radius of the group
function ClusterMathUtils.calculateGroupRadius(unitIDs, center)
    local maxDistSquared = 0
    local validUnits = 0

    for _, unitID in ipairs(unitIDs) do
        if Spring.ValidUnitID(unitID) then
            local x, y, z = Spring.GetUnitPosition(unitID)
            local dx = x - center.x
            local dy = y - center.y
            local dz = z - center.z
            local distSquared = dx*dx + dy*dy + dz*dz

            if distSquared > maxDistSquared then
                maxDistSquared = distSquared
            end

            validUnits = validUnits + 1
        end
    end

    -- Calculate radius (square root of max squared distance)
    local radius = math.sqrt(maxDistSquared)

    -- If no valid units, default to a small radius
    if validUnits == 0 then
        radius = 100
    end

    return radius
end

--- Calculates velocity vector of a group based on change in center of mass
---@param currentCenter table Current center of mass {x, y, z}
---@param previousCenter table Previous center of mass {x, y, z}
---@param deltaTime number Time elapsed between measurements
---@return table velocity Velocity vector {x, y, z}
function ClusterMathUtils.calculateVelocity(currentCenter, previousCenter, deltaTime)
    if deltaTime <= 0 then
        return {x = 0, y = 0, z = 0}
    end

    return {
        x = (currentCenter.x - previousCenter.x) / deltaTime,
        y = (currentCenter.y - previousCenter.y) / deltaTime,
        z = (currentCenter.z - previousCenter.z) / deltaTime
    }
end

--- Calculates the magnitude of a 3D vector
---@param vector table Vector with x, y, z components
---@return number magnitude The magnitude of the vector
function ClusterMathUtils.vectorMagnitude(vector)
    return math.sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
end

return {
    ClusterMathUtils = ClusterMathUtils
}
