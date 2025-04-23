---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log

-- Initialize projectile tracking in STATE if it doesn't exist
if not STATE.projectileTracking then
    STATE.projectileTracking = {
        unitProjectiles = {}  -- Will store projectiles by unit ID
    }
end

---@class ProjectileTracker
local ProjectileTracker = {}

-- Configuration for projectile tracking
ProjectileTracker.config = {
    -- How long to maintain projectile data after unit deselection (seconds)
    retentionTime = 10,

    -- Maximum projectiles to track per unit
    maxProjectilesPerUnit = 30,

    -- Update frequency (frame modulo)
    updateFrequency = 1
}

-- Initialize unit projectile tracking storage
---@param unitID number Unit ID to initialize tracking for
function ProjectileTracker.initUnitTracking(unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then
        return
    end

    if not STATE.projectileTracking.unitProjectiles[unitID] then
        STATE.projectileTracking.unitProjectiles[unitID] = {
            lastUpdateTime = Spring.GetGameSeconds(),
            active = true,  -- Whether this unit is actively being tracked
            projectiles = {}  -- Will contain projectile data
        }
        Log.debug("Initialized projectile tracking for unit " .. unitID)
    else
        -- Unit already being tracked, just mark as active
        STATE.projectileTracking.unitProjectiles[unitID].active = true
        STATE.projectileTracking.unitProjectiles[unitID].lastUpdateTime = Spring.GetGameSeconds()
    end
end

-- Mark unit tracking as inactive but retain projectile data
---@param unitID number Unit ID to mark as inactive
function ProjectileTracker.markUnitInactive(unitID)
    if not unitID or not STATE.projectileTracking.unitProjectiles[unitID] then
        return
    end

    STATE.projectileTracking.unitProjectiles[unitID].active = false
    Log.debug("Marked unit " .. unitID .. " as inactive for projectile tracking")
end

-- Remove projectile tracking data for a unit
---@param unitID number Unit ID to remove tracking for
function ProjectileTracker.removeUnitTracking(unitID)
    if not unitID then
        return
    end

    STATE.projectileTracking.unitProjectiles[unitID] = nil
    Log.debug("Removed projectile tracking for unit " .. unitID)
end

-- Find new projectiles for a tracked unit
---@param unitID number Unit ID to find projectiles for
---@return table newProjectiles Array of newly discovered projectile IDs
function ProjectileTracker.findNewProjectiles(unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then
        return {}
    end

    -- Get unit position
    local ux, uy, uz = Spring.GetUnitPosition(unitID)
    if not ux then return {} end

    -- Define search box around unit
    local boxSize = 200  -- Box to catch newly fired projectiles

    -- Get projectiles in the search box
    local projectiles = Spring.GetProjectilesInRectangle(
            ux - boxSize, uz - boxSize,
            ux + boxSize, uz + boxSize
    )

    local newProjectiles = {}
    local currentTime = Spring.GetGameSeconds()

    -- Look for projectiles owned by our unit
    for i=1, #projectiles do
        local projectileID = projectiles[i]
        local ownerID = Spring.GetProjectileOwnerID(projectileID)

        if ownerID == unitID then
            -- Check if this projectile is already being tracked
            local isTracked = false

            if STATE.projectileTracking.unitProjectiles[unitID] then
                for _, proj in pairs(STATE.projectileTracking.unitProjectiles[unitID].projectiles) do
                    if proj.id == projectileID then
                        isTracked = true
                        break
                    end
                end
            end

            -- If not already tracked, add it
            if not isTracked then
                table.insert(newProjectiles, {
                    id = projectileID,
                    creationTime = currentTime
                })
            end
        end
    end

    return newProjectiles
end

-- Update projectile tracking for all units
---@param frameNum number Current frame number
function ProjectileTracker.update(frameNum)
    -- Only update on certain frames to reduce performance impact
    if frameNum % ProjectileTracker.config.updateFrequency ~= 0 then
        return
    end

    local currentTime = Spring.GetGameSeconds()

    -- Always track the current unit
    local currentUnitID = STATE.tracking.unitID
    if currentUnitID and Spring.ValidUnitID(currentUnitID) then
        ProjectileTracker.initUnitTracking(currentUnitID)

        -- Find new projectiles
        local newProjectiles = ProjectileTracker.findNewProjectiles(currentUnitID)

        -- Add new projectiles to tracking
        for _, proj in ipairs(newProjectiles) do
            -- Limit number of tracked projectiles per unit
            if #STATE.projectileTracking.unitProjectiles[currentUnitID].projectiles >= ProjectileTracker.config.maxProjectilesPerUnit then
                -- Remove oldest projectile
                table.remove(STATE.projectileTracking.unitProjectiles[currentUnitID].projectiles, 1)
            end

            -- Add the new projectile
            table.insert(STATE.projectileTracking.unitProjectiles[currentUnitID].projectiles, {
                id = proj.id,
                creationTime = proj.creationTime,
                lastPosition = nil,  -- Will be updated below
                lastVelocity = nil   -- Will be updated below
            })

            Log.trace("Added new projectile " .. proj.id .. " for unit " .. currentUnitID)
        end
    end

    -- Update all tracked projectiles and clean up
    for unitID, unitData in pairs(STATE.projectileTracking.unitProjectiles) do
        -- Check if unit data should be removed (inactive and old)
        if not unitData.active and
                (currentTime - unitData.lastUpdateTime > ProjectileTracker.config.retentionTime) then
            ProjectileTracker.removeUnitTracking(unitID)
        else
            -- Update projectile data for this unit
            local validProjectiles = {}

            for _, projectile in ipairs(unitData.projectiles) do
                local px, py, pz = Spring.GetProjectilePosition(projectile.id)
                local vx, vy, vz = Spring.GetProjectileVelocity(projectile.id)

                if px and vx then
                    -- Projectile still exists, update position
                    local speed = math.sqrt(vx*vx + vy*vy + vz*vz)
                    projectile.lastPosition = { x = px, y = py, z = pz }
                    projectile.lastVelocity = {
                        x = speed > 0 and vx/speed or 0,
                        y = speed > 0 and vy/speed or 0,
                        z = speed > 0 and vz/speed or 0,
                        speed = speed
                    }
                    table.insert(validProjectiles, projectile)
                else
                    -- Projectile no longer exists
                    Log.trace("Projectile " .. projectile.id .. " no longer exists, removing from tracking")
                end
            end

            -- Update the list with only valid projectiles
            unitData.projectiles = validProjectiles
        end
    end
end

-- Get the newest projectile for a unit
---@param unitID number Unit ID to get projectile for
---@return table|nil projectile Newest projectile data or nil if none
function ProjectileTracker.getNewestProjectile(unitID)
    if not unitID or not STATE.projectileTracking.unitProjectiles[unitID] then
        return nil
    end

    local projectiles = STATE.projectileTracking.unitProjectiles[unitID].projectiles
    if #projectiles == 0 then
        return nil
    end

    -- Find newest projectile by creation time
    local newest = projectiles[1]
    for i=2, #projectiles do
        if projectiles[i].creationTime > newest.creationTime then
            newest = projectiles[i]
        end
    end

    return newest
end

-- Get all projectiles for a unit
---@param unitID number Unit ID to get projectiles for
---@return table projectiles Array of all projectile data for the unit
function ProjectileTracker.getUnitProjectiles(unitID)
    if not unitID or not STATE.projectileTracking.unitProjectiles[unitID] then
        return {}
    end

    return STATE.projectileTracking.unitProjectiles[unitID].projectiles
end

return {
    ProjectileTracker = ProjectileTracker
}