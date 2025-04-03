-- Tracking utility functions for TURBOBARCAM
-- This module provides reusable utility functions for camera tracking

---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")

local CONFIG = WidgetContext.WidgetConfig.CONFIG

---@class TrackingUtils
local TrackingUtils = {}

--- Checks if a unit is an aircraft
---@param unitID number Unit ID
---@return boolean isAircraft Whether the unit is an aircraft
function TrackingUtils.isAircraftUnit(unitID)
    if not Spring.ValidUnitID(unitID) then
        return false
    end

    local unitDefID = Spring.GetUnitDefID(unitID)
    if not unitDefID then
        return false
    end

    local unitDef = UnitDefs[unitDefID]
    if not unitDef then
        return false
    end

    -- Check if unit is in the aircraft types list
    local aircraftTypes = CONFIG.GROUP_TRACKING.AIRCRAFT_UNIT_TYPES
    if aircraftTypes and aircraftTypes[unitDef.name] then
        return true
    end

    -- Check if the unit can fly
    if unitDef.canFly then
        return true
    end

    return false
end

--- Checks if a group contains at least one aircraft
---@param units table Array of unit IDs
---@return boolean hasAircraft Whether the group contains aircraft
function TrackingUtils.groupContainsAircraft(units)
    for _, unitID in ipairs(units) do
        if TrackingUtils.isAircraftUnit(unitID) then
            return true
        end
    end
    return false
end

--- Counts the number of valid units in a group
---@param units table Array of unit IDs
---@return number validCount Number of valid units
function TrackingUtils.countValidUnits(units)
    local count = 0
    for _, unitID in ipairs(units) do
        if Spring.ValidUnitID(unitID) then
            count = count + 1
        end
    end
    return count
end

--- Calculates the distance between two points in 3D space
---@param p1 table Position {x, y, z}
---@param p2 table Position {x, y, z}
---@return number distance The distance between the points
function TrackingUtils.distance(p1, p2)
    local dx = p1.x - p2.x
    local dy = p1.y - p2.y
    local dz = p1.z - p2.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

--- Calculates the average position of a group of units
---@param units table Array of unit IDs
---@return table position Average position {x, y, z}
---@return number validUnits Number of valid units used in calculation
function TrackingUtils.calculateAveragePosition(units)
    local sumX, sumY, sumZ = 0, 0, 0
    local validUnits = 0
    
    for _, unitID in ipairs(units) do
        if Spring.ValidUnitID(unitID) then
            local x, y, z = Spring.GetUnitPosition(unitID)
            sumX = sumX + x
            sumY = sumY + y
            sumZ = sumZ + z
            validUnits = validUnits + 1
        end
    end
    
    if validUnits > 0 then
        return {
            x = sumX / validUnits,
            y = sumY / validUnits,
            z = sumZ / validUnits
        }, validUnits
    else
        return {x = 0, y = 0, z = 0}, 0
    end
end

--- Checks if two directions are substantially different
---@param dir1 table Direction vector {x, z}
---@param dir2 table Direction vector {x, z}
---@param threshold number Threshold value (default: 0.7)
---@return boolean isDifferent Whether the directions are substantially different
function TrackingUtils.isDirectionDifferent(dir1, dir2, threshold)
    threshold = threshold or 0.7
    local dot = dir1.x * dir2.x + dir1.z * dir2.z
    return dot < threshold
end

--- Calculates dot product between two 2D direction vectors
---@param dir1 table Direction vector {x, z}
---@param dir2 table Direction vector {x, z}
---@return number dot Dot product between the vectors
function TrackingUtils.dotProduct2D(dir1, dir2)
    return dir1.x * dir2.x + dir1.z * dir2.z
end

--- Normalizes a 2D direction vector
---@param dir table Direction vector {x, z}
---@return table normalizedDir Normalized direction vector {x, z}
function TrackingUtils.normalizeDirection(dir)
    local magnitude = math.sqrt(dir.x * dir.x + dir.z * dir.z)
    if magnitude > 0 then
        return {
            x = dir.x / magnitude,
            z = dir.z / magnitude
        }
    else
        return {x = 0, z = 1} -- Default direction if magnitude is zero
    end
end

--- Rotates a 2D direction vector by the given angle
---@param dir table Direction vector {x, z}
---@param angle number Angle in radians
---@return table rotatedDir Rotated direction vector {x, z}
function TrackingUtils.rotateDirection(dir, angle)
    local cos = math.cos(angle)
    local sin = math.sin(angle)
    return {
        x = dir.x * cos - dir.z * sin,
        z = dir.x * sin + dir.z * cos
    }
end

--- Calculates the angle of a 2D direction vector
---@param dir table Direction vector {x, z}
---@return number angle Angle in radians
function TrackingUtils.getDirectionAngle(dir)
    return math.atan2(dir.z, dir.x)
end

return {
    TrackingUtils = TrackingUtils
}