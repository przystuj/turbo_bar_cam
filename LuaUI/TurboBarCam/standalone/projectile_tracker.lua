---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "ProjectileTracker")

local initialized = false

--- Finds all units of specific definitions across multiple teams.
---@param teamIDs number[] A list of team IDs to search within.
---@param unitDefIDs number[] A list of unit definition IDs to search for.
---@return number[] A list of unit IDs matching the criteria.
local function findUnits(teamIDs, unitDefIDs)
    local result = {}
    if not teamIDs or not unitDefIDs or #unitDefIDs == 0 then
        return result
    end

    for _, teamID in ipairs(teamIDs) do
        local teamUnits = Spring.GetTeamUnitsByDefs(teamID, unitDefIDs)
        for _, unitID in ipairs(teamUnits) do
            table.insert(result, unitID)
        end
    end
    return result
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
                table.insert(trackableUnitDefIDs, unitDefID)
            end
        end
    end
end

-- Initialize unit projectile tracking storage
---@param unitID number Unit ID to initialize tracking for
function ProjectileTracker.initTemporaryUnitTracking(unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then
        return
    end

    if not STATE.core.projectileTracking.unitProjectiles[unitID] then
        -- todo not needed?
        --local teamID = Spring.GetUnitTeam(unitID)
        --if not teamID then
        --    Log:warn("Could not determine team for unit " .. unitID .. ". Will not track.")
        --    return
        --end
        STATE.core.projectileTracking.unitProjectiles[unitID] = {
            --teamID = teamID,
            lastUpdateTime = Spring.GetTimer(),
            active = true, -- Whether this unit is actively being tracked
            projectiles = {}  -- Will contain projectile data
        }
        Log:trace("Initialized projectile tracking for unit " .. unitID)
    else
        -- Unit already being tracked, just mark as active and update time
        STATE.core.projectileTracking.unitProjectiles[unitID].active = true
        STATE.core.projectileTracking.unitProjectiles[unitID].lastUpdateTime = Spring.GetTimer()
    end
end

---@param unitIds number[] Track projectiles for these units in the future
function ProjectileTracker.registerUnitIds(unitIds)
    for _, unitId in ipairs(unitIds) do
        STATE.core.projectileTracking.registeredUnitIds[unitId] = true
        Log:debug("Tracking projectiles for", unitId)
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
---@param existingProjectiles number[] All existing projectile ids. Provided only after widget initialization
---@return table newProjectiles Array of newly discovered projectile IDs
function ProjectileTracker.findNewProjectiles(unitID, existingProjectiles)
    if not unitID or not Spring.ValidUnitID(unitID) then
        return {}
    end

    local unitData = STATE.core.projectileTracking.unitProjectiles[unitID]
    if not unitData then
        return {}
    end

    local ux, uy, uz = Spring.GetUnitPosition(unitID)
    if not ux then
        return {}
    end

    local trackedProjectiles = unitData.projectiles or {}
    local knownProjectileIDs = {}
    for _, proj in ipairs(trackedProjectiles) do
        knownProjectileIDs[proj.id] = true
    end
    local newProjectiles = {}
    local currentTime = Spring.GetTimer()

    if existingProjectiles then
        for _, projectileID in ipairs(existingProjectiles) do
            if Spring.GetProjectileOwnerID(projectileID) == unitID and not knownProjectileIDs[projectileID] then
                table.insert(newProjectiles, {
                    id = projectileID,
                    creationTime = currentTime
                })
            end
        end
    else
        local boxSize = 200
        local projectilesInBox = Spring.GetProjectilesInRectangle(ux - boxSize, uz - boxSize, ux + boxSize, uz + boxSize)

        for i = 1, #projectilesInBox do
            local projectileID = projectilesInBox[i]
            if Spring.GetProjectileOwnerID(projectileID) == unitID and not knownProjectileIDs[projectileID] then
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
    if frameNum % ProjectileTracker.config.updateFrequency ~= 0 then
        return
    end
    if Utils.isTurboBarCamDisabled() then
        return
    end

    local currentTime = Spring.GetTimer()
    local unitsToTrack = {}

    -- 1. Add persistently tracked units
    if #trackableUnitDefIDs > 0 then
        local allTrackableUnits = findUnits(Spring.GetTeamList(), trackableUnitDefIDs)
        for _, unitID in ipairs(allTrackableUnits) do
            unitsToTrack[unitID] = true
        end
    end

    for _, unitId in ipairs(STATE.core.projectileTracking.registeredUnitIds) do
        unitsToTrack[unitId] = true
    end

    -- 2. Add the unit that is "armed" for tracking
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

    local existingProjectiles
    if not initialized then
        initialized = true
        existingProjectiles = Spring.GetAllProjectiles()
    end

    -- 4. Find new projectiles for all currently tracked units
    for unitID, _ in pairs(unitsToTrack) do
        if Spring.ValidUnitID(unitID) then
            ProjectileTracker.initTemporaryUnitTracking(unitID) -- This will also mark them as active
            local newProjectiles = ProjectileTracker.findNewProjectiles(unitID, existingProjectiles)
            if #newProjectiles > 0 then
                local unitProjectileData = STATE.core.projectileTracking.unitProjectiles[unitID]
                -- Only proceed if the unit data exists, as init may fail if team is not found
                if unitProjectileData then
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
    end

    -- 5. Update all tracked projectiles and clean up old data
    for unitID, unitData in pairs(STATE.core.projectileTracking.unitProjectiles) do
        if not unitData.active and (Spring.DiffTimers(currentTime, unitData.lastUpdateTime) > ProjectileTracker.config.retentionTime) then
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
    projectileID = tonumber(projectileID)
    for _, unitData in pairs(STATE.core.projectileTracking.unitProjectiles) do
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
        return Spring.DiffTimers(a.creationTime, b.creationTime) > 0
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
