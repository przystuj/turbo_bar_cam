---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Log = ModuleManager.Log(function(m) Log = m end)

---@class OverviewCameraUtils
local OverviewCameraUtils = {}

--- Uses the current height level to determine the appropriate height above ground
--- Now uses equal steps based on granularity setting
---@return number height The camera height in world units
function OverviewCameraUtils.calculateCurrentHeight()
    -- Get granularity setting from config
    local granularity = CONFIG.CAMERA_MODES.OVERVIEW.HEIGHT_CONTROL_GRANULARITY or 4

    -- Current height level (1 is highest, granularity is lowest)
    local heightLevel = STATE.active.mode.overview.heightLevel or 1

    -- Ensure level is valid
    heightLevel = math.max(1, math.min(granularity, heightLevel))

    -- Calculate the factor: ranges from 1.0 (level 1) to 0.25 (level 4) for granularity 4
    local factor = 1.0 - ((heightLevel - 1) / granularity) * 0.95

    -- Enforce minimum height to prevent getting too close to ground
    return math.max(STATE.active.mode.overview.height * factor, 500)
end

--- Converts screen cursor position to 3D world coordinates
--- If cursor is outside the map, returns the nearest valid point on map edge
---@return table position Position {x, y, z} or nil if should ignore
function OverviewCameraUtils.getCursorWorldPosition()
    local mx, my = Spring.GetMouseState()
    local _, pos = Spring.TraceScreenRay(mx, my, true)

    if pos then
        -- Valid cursor position on map
        return { x = pos[1], y = pos[2], z = pos[3] }
    else
        -- Cursor is outside the map
        -- Trace ray to find direction where user was clicking
        local traceType, tracePos = Spring.TraceScreenRay(mx, my, false, true, true, true)

        -- If we can't even get a direction, ignore the click
        if not traceType or traceType ~= "sky" then
            return nil
        end

        -- Get the direction the ray is pointing
        local dirX = tracePos[1]
        local dirY = tracePos[2]
        local dirZ = tracePos[3]

        -- Get current camera position
        local camState = Spring.GetCameraState()
        local camX, camY, camZ = camState.px, camState.py, camState.pz

        -- Get map dimensions
        local mapX = Game.mapSizeX
        local mapZ = Game.mapSizeZ

        -- Normalize direction vector
        local dirLen = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)
        dirX, dirY, dirZ = dirX / dirLen, dirY / dirLen, dirZ / dirLen

        -- We need to find intersection with map boundaries
        -- First check if we're looking down enough to hit the ground
        if dirY < 0 then
            -- Calculate distance to ground
            local dist = -camY / dirY
            -- Calculate ground intersection point
            local hitX = camX + dirX * dist
            local hitZ = camZ + dirZ * dist

            -- Check if point is within map boundaries
            if hitX >= 0 and hitX <= mapX and hitZ >= 0 and hitZ <= mapZ then
                return { x = hitX, y = 0, z = hitZ }
            end
        end

        -- If not hitting ground, find intersection with map edges
        -- We'll find the closest valid intersection point

        -- Variables to store closest hit
        local closestDist = math.huge
        local closestPoint

        -- Check intersection with X=0 boundary
        if dirX ~= 0 then
            local dist = -camX / dirX
            if dist > 0 then
                local hitY = camY + dirY * dist
                local hitZ = camZ + dirZ * dist
                if hitZ >= 0 and hitZ <= mapZ and hitY >= 0 then
                    if dist < closestDist then
                        closestDist = dist
                        closestPoint = { x = 0, y = 0, z = hitZ }
                    end
                end
            end
        end

        -- Check intersection with X=mapX boundary
        if dirX ~= 0 then
            local dist = (mapX - camX) / dirX
            if dist > 0 then
                local hitY = camY + dirY * dist
                local hitZ = camZ + dirZ * dist
                if hitZ >= 0 and hitZ <= mapZ and hitY >= 0 then
                    if dist < closestDist then
                        closestDist = dist
                        closestPoint = { x = mapX, y = 0, z = hitZ }
                    end
                end
            end
        end

        -- Check intersection with Z=0 boundary
        if dirZ ~= 0 then
            local dist = -camZ / dirZ
            if dist > 0 then
                local hitX = camX + dirX * dist
                local hitY = camY + dirY * dist
                if hitX >= 0 and hitX <= mapX and hitY >= 0 then
                    if dist < closestDist then
                        closestDist = dist
                        closestPoint = { x = hitX, y = 0, z = 0 }
                    end
                end
            end
        end

        -- Check intersection with Z=mapZ boundary
        if dirZ ~= 0 then
            local dist = (mapZ - camZ) / dirZ
            if dist > 0 then
                local hitX = camX + dirX * dist
                local hitY = camY + dirY * dist
                if hitX >= 0 and hitX <= mapX and hitY >= 0 then
                    if dist < closestDist then
                        closestDist = dist
                        closestPoint = { x = hitX, y = 0, z = mapZ }
                    end
                end
            end
        end

        if closestPoint then
            return closestPoint
        end

        -- If no valid intersection found, return nil to indicate we should ignore this click
        return nil
    end
end

--- Calculates a position for the camera to view a target point
---@param targetPoint table The target point to look at {x, y, z}
---@param currentHeight number The current camera height
---@param mapX number Map X size
---@param mapZ number Map Z size
---@param currentCamState table|nil Current camera state (optional)
---@param distanceFactor number|nil Distance factor to multiply the base offset (optional, default 1.0)
---@return table targetCamPos The calculated camera position
function OverviewCameraUtils.calculateCameraPosition(targetPoint, currentHeight, mapX, mapZ, currentCamState, distanceFactor)
    -- Apply distance factor (default to 1.0 if not provided)
    distanceFactor = distanceFactor or 1

    -- Scale distance based on height to maintain proper viewing angle
    -- We're using distanceFactor to adjust this relationship
    local offsetDistance = currentHeight * distanceFactor

    -- Add a small margin for map boundaries
    local margin = 200

    -- Default direction if no current camera state
    local dirX, dirZ = 1, 0

    if currentCamState then
        -- Calculate direction from target to current camera position
        dirX = currentCamState.px - targetPoint.x
        dirZ = currentCamState.pz - targetPoint.z

        -- Normalize the direction vector
        local length = math.sqrt(dirX * dirX + dirZ * dirZ)
        if length > 0 then
            dirX = dirX / length
            dirZ = dirZ / length
        else
            -- Default to a direction if camera is directly above target
            dirX, dirZ = 1, 0
        end
    end

    -- Calculate new position by moving in the same direction from target
    local newX = targetPoint.x + dirX * offsetDistance
    local newZ = targetPoint.z + dirZ * offsetDistance

    -- Check if position is within map boundaries
    if newX >= margin and newX <= mapX - margin and
            newZ >= margin and newZ <= mapZ - margin then
        -- Position is valid
        return {
            x = newX,
            y = currentHeight,
            z = newZ
        }
    end

    -- If we hit a map boundary, try to find a valid position along the same angle
    -- by reducing the distance
    local validPosition = false
    local reductionFactor = 0.8
    local attempts = 0
    local maxAttempts = 5

    while not validPosition and attempts < maxAttempts do
        -- Reduce distance
        offsetDistance = offsetDistance * reductionFactor

        -- Try new position
        newX = targetPoint.x + dirX * offsetDistance
        newZ = targetPoint.z + dirZ * offsetDistance

        -- Check if in bounds
        if newX >= margin and newX <= mapX - margin and
                newZ >= margin and newZ <= mapZ - margin then
            validPosition = true
        end

        attempts = attempts + 1
    end

    -- If we still don't have a valid position, default to directly above target
    if not validPosition then
        Log:trace("Could not find valid position in same direction, positioning above target")
        return {
            x = targetPoint.x,
            y = currentHeight,
            z = targetPoint.z
        }
    end

    Log:trace(string.format("Camera positioned at straight line offset (%.1f, %.1f)", newX - targetPoint.x, newZ - targetPoint.z))

    return {
        x = newX,
        y = currentHeight,
        z = newZ
    }
end


return OverviewCameraUtils