---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "ProjectileTracker")

---@class ProjectileTracker
local ProjectileTracker = {}

-- Configuration for projectile tracking
ProjectileTracker.config = {
    -- How long to maintain projectile data after unit deselection (seconds)
    retentionTime = 10,

    -- Maximum projectiles to track per unit
    maxProjectilesPerUnit = 30,

    -- Update frequency (frame modulo)
    updateFrequency = 5
}

---@type table<number, boolean>
local trackableUnitDefIDs = {}

--- Initializes the tracker by caching the UnitDefIDs of trackable units from config.
function ProjectileTracker.initialize()
    trackableUnitDefIDs = {}
    local trackableUnitDefs = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.TRACKABLE_UNIT_DEFS

    for unitDefID, unitDef in pairs(UnitDefs) do
        for _, unitDefName in ipairs(trackableUnitDefs) do
            if unitDef.name == unitDefName then
                trackableUnitDefIDs[unitDefID] = true
            end
        end
    end
end

-- Initialize unit projectile tracking storage
---@param unitID number Unit ID to initialize tracking for
function ProjectileTracker.initUnitTracking(unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then
        return
    end

    if not STATE.core.projectileTracking.unitProjectiles[unitID] then
        STATE.core.projectileTracking.unitProjectiles[unitID] = {
            lastUpdateTime = Spring.GetGameSeconds(),
            active = true, -- Whether this unit is actively being tracked
            projectiles = {}  -- Will contain projectile data
        }
        Log:trace("Initialized projectile tracking for unit " .. unitID)
    else
        -- Unit already being tracked, just mark as active and update time
        STATE.core.projectileTracking.unitProjectiles[unitID].active = true
        STATE.core.projectileTracking.unitProjectiles[unitID].lastUpdateTime = Spring.GetGameSeconds()
    end
end

-- Mark unit tracking as inactive but retain projectile data
---@param unitID number Unit ID to mark as inactive
function ProjectileTracker.markUnitInactive(unitID)
    if not unitID or not STATE.core.projectileTracking.unitProjectiles[unitID] then
        return
    end

    STATE.core.projectileTracking.unitProjectiles[unitID].active = false
    Log:trace("Marked unit " .. unitID .. " as inactive for projectile tracking")
end

-- Remove projectile tracking data for a unit
---@param unitID number Unit ID to remove tracking for
function ProjectileTracker.removeUnitTracking(unitID)
    if not unitID then
        return
    end

    STATE.core.projectileTracking.unitProjectiles[unitID] = nil
    Log:trace("Removed projectile tracking for unit " .. unitID)
end

-- Find new projectiles for a tracked unit
---@param unitID number Unit ID to find projectiles for
---@return table newProjectiles Array of newly discovered projectile IDs
function ProjectileTracker.findNewProjectiles(unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then
        return {}
    end

    local ux, uy, uz = Spring.GetUnitPosition(unitID)
    if not ux then
        return {}
    end

    local boxSize = 200
    local projectilesInBox = Spring.GetProjectilesInRectangle(ux - boxSize, uz - boxSize, ux + boxSize, uz + boxSize)

    local newProjectiles = {}
    local currentTime = Spring.GetGameSeconds()
    local trackedProjectiles = STATE.core.projectileTracking.unitProjectiles[unitID] and STATE.core.projectileTracking.unitProjectiles[unitID].projectiles or {}
    local knownProjectileIDs = {}
    for _, proj in ipairs(trackedProjectiles) do
        knownProjectileIDs[proj.id] = true
    end

    for i = 1, #projectilesInBox do
        local projectileID = projectilesInBox[i]
        if Spring.GetProjectileOwnerID(projectileID) == unitID and not knownProjectileIDs[projectileID] then
            table.insert(newProjectiles, {
                id = projectileID,
                creationTime = currentTime
            })
        end
    end

    return newProjectiles
end

-- Update projectile tracking for all units
---@param frameNum number Current frame number
function ProjectileTracker.update(frameNum)
    if frameNum % ProjectileTracker.config.updateFrequency ~= 0 then
        return
    end

    local currentTime = Spring.GetGameSeconds()
    local unitsToTrack = {}

    -- 1. Add units from the global config list (for new cycle feature)
    local allUnits = Spring.GetAllUnits()
    for i = 1, #allUnits do
        local unitID = allUnits[i]
        local unitDefID = Spring.GetUnitDefID(unitID)
        if unitDefID and trackableUnitDefIDs[unitDefID] then
            unitsToTrack[unitID] = true
        end
    end

    -- 2. Add the unit that is "armed" for tracking (for old functionality)
    local projCamState = STATE.active.mode.projectile_camera
    if projCamState and projCamState.isArmed and projCamState.watchedUnitID then
        unitsToTrack[projCamState.watchedUnitID] = true
    end

    -- 3. Mark units that are no longer present/tracked as inactive
    for unitID, unitData in pairs(STATE.core.projectileTracking.unitProjectiles) do
        if not unitsToTrack[unitID] and unitData.active then
            ProjectileTracker.markUnitInactive(unitID)
        end
    end

    -- 4. Find new projectiles for all currently tracked units
    for unitID, _ in pairs(unitsToTrack) do
        if Spring.ValidUnitID(unitID) then
            ProjectileTracker.initUnitTracking(unitID) -- This will also mark them as active
            local newProjectiles = ProjectileTracker.findNewProjectiles(unitID)
            if #newProjectiles > 0 then
                local unitProjectileData = STATE.core.projectileTracking.unitProjectiles[unitID]
                for _, proj in ipairs(newProjectiles) do
                    if #unitProjectileData.projectiles >= ProjectileTracker.config.maxProjectilesPerUnit then
                        table.remove(unitProjectileData.projectiles, 1)
                    end
                    ---@class Projectile
                    local projectile = {
                        id = proj.id,
                        ownerID = unitID,
                        creationTime = proj.creationTime,
                        position = { x = 0, y = 0, z = 0 },
                        velocity = { x = 0, y = 0, z = 0, speed = 0 },
                        previousVelocity = { x = 0, y = 0, z = 0, speed = 0 }
                    }
                    table.insert(unitProjectileData.projectiles, projectile)
                    Log:trace("Added new projectile " .. proj.id .. " for unit " .. unitID)
                end
            end
        end
    end

    -- 5. Update all tracked projectiles and clean up old data
    for unitID, unitData in pairs(STATE.core.projectileTracking.unitProjectiles) do
        if not unitData.active and (currentTime - unitData.lastUpdateTime > ProjectileTracker.config.retentionTime) then
            ProjectileTracker.removeUnitTracking(unitID)
        else
            local validProjectiles = {}
            for _, projectile in ipairs(unitData.projectiles) do
                local px, py, pz = Spring.GetProjectilePosition(projectile.id)
                local vx, vy, vz = Spring.GetProjectileVelocity(projectile.id)

                if px and vx then
                    local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
                    projectile.position = { x = px, y = py, z = pz }
                    projectile.previousVelocity = projectile.velocity
                    projectile.velocity = {
                        x = speed > 0 and vx / speed or 0,
                        y = speed > 0 and vy / speed or 0,
                        z = speed > 0 and vz / speed or 0,
                        speed = speed
                    }
                    table.insert(validProjectiles, projectile)
                else
                    Log:trace("Projectile " .. projectile.id .. " no longer exists, removing from tracking")
                end
            end
            unitData.projectiles = validProjectiles
        end
    end
end

--- Gets a specific projectile by its ID from the tracking data.
---@param projectileID number The ID of the projectile to find.
---@return Projectile|nil The projectile data, or nil if not found.
function ProjectileTracker.getProjectileByID(projectileID)
    if not projectileID then return nil end
    for unitID, unitData in pairs(STATE.core.projectileTracking.unitProjectiles) do
        for _, projectile in ipairs(unitData.projectiles) do
            if projectile.id == projectileID then
                return projectile
            end
        end
    end
    return nil
end


--- Gets a flattened list of all projectiles currently being tracked.
---@return Projectile[] allProjectiles A list of all projectiles, sorted newest first.
function ProjectileTracker.getAllTrackedProjectiles()
    local allProjectiles = {}
    for unitID, unitData in pairs(STATE.core.projectileTracking.unitProjectiles) do
        for _, projectile in ipairs(unitData.projectiles) do
            table.insert(allProjectiles, projectile)
        end
    end
    -- Sort by creation time, newest first
    table.sort(allProjectiles, function(a, b)
        return a.creationTime > b.creationTime
    end)
    return allProjectiles
end

-- Get all projectiles for a specific unit
---@param unitID number Unit ID to get projectiles for
---@return table projectiles Array of all projectile data for the unit
function ProjectileTracker.getUnitProjectiles(unitID)
    if not unitID or not STATE.core.projectileTracking.unitProjectiles[unitID] then
        return {}
    end

    return STATE.core.projectileTracking.unitProjectiles[unitID].projectiles
end

return ProjectileTracker
