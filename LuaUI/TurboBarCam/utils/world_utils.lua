---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)


---@class WorldUtils
local WorldUtils = {}

--- Gets world position at mouse cursor
---@return table|nil point World coordinates {x,y,z} or nil if outside map
function WorldUtils.getCursorWorldPosition()
    local mx, my = Spring.GetMouseState()
    local _, pos = Spring.TraceScreenRay(mx, my, true)
    if pos then
        return { x = pos[1], y = pos[2], z = pos[3] }
    end
    return nil
end

--- Validates and normalizes a tracking target
---@param target any The target to validate (unitID or {x,y,z})
---@return any normalizedTarget Validated target (unitID or {x,y,z})
---@return string targetType Target type ('UNIT', 'POINT', or 'NONE')
function WorldUtils.validateTarget(target)
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

--- Gets the height of a unit
---@param unitID number Unit ID
---@return number unit height
function WorldUtils.getUnitHeight(unitID)
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

function WorldUtils.getUnitVectors(unitID)
    local x, y, z = Spring.GetUnitPosition(unitID)
    local front, up, right = Spring.GetUnitVectors(unitID)

    return { x = x, y = y, z = z }, front, up, right
end

function WorldUtils.getCleanMapName()
    local mapName = Game.mapName

    -- Remove version numbers at the end (patterns like 1.2.3 or V1.2.3)
    local cleanName = mapName:gsub("%s+[vV]?%d+%.?%d*%.?%d*$", "")

    return cleanName
end

return WorldUtils