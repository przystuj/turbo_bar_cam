---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local Util = ModuleManager.Util(function(m) Util = m end)

---@class DBSCAN
local DBSCAN = {}

--- Density-based spatial clustering of applications with noise
--- Performs DBSCAN clustering on unit positions
---@param units table Array of unit IDs
---@param epsilon number Distance threshold for considering units as neighbors
---@param minPoints number Minimum points required to form a cluster
---@return table clusters Array of clusters, each containing unit IDs
---@return table noise Array of unit IDs that are considered noise/outliers
function DBSCAN.performClustering(units, epsilon, minPoints)
    local clusters = {}
    local noise = {}
    local visited = {}
    local clustered = {}

    -- Get valid unit positions
    local unitPositions = {}
    for _, unitID in ipairs(units) do
        if Spring.ValidUnitID(unitID) then
            local x, y, z = Spring.GetUnitPosition(unitID)
            unitPositions[unitID] = { x = x, y = y, z = z }
        end
    end

    -- Helper function to get neighbors within epsilon distance
    local function getNeighbors(unitID)
        local neighbors = {}
        local pos1 = unitPositions[unitID]

        if not pos1 then
            return neighbors
        end

        for otherUnitID, pos2 in pairs(unitPositions) do
            local distSquared = DBSCAN.distanceSquared(pos1, pos2)

            if distSquared <= epsilon * epsilon then
                table.insert(neighbors, otherUnitID)
            end
        end

        return neighbors
    end

    -- Helper function to expand cluster
    local function expandCluster(unitID, neighbors, clusterID)
        table.insert(clusters[clusterID], unitID)
        clustered[unitID] = true

        for i = 1, #neighbors do
            local currentUnitID = neighbors[i]

            if not visited[currentUnitID] then
                visited[currentUnitID] = true
                local currentNeighbors = getNeighbors(currentUnitID)

                if #currentNeighbors >= minPoints then
                    -- Merge neighbors
                    for _, neighborID in ipairs(currentNeighbors) do
                        if not Util.tableContains(neighbors, neighborID) then
                            table.insert(neighbors, neighborID)
                        end
                    end
                end
            end

            if not clustered[currentUnitID] then
                table.insert(clusters[clusterID], currentUnitID)
                clustered[currentUnitID] = true
            end
        end
    end

    -- Main DBSCAN algorithm
    local clusterID = 0

    for _, unitID in ipairs(units) do
        if not visited[unitID] and unitPositions[unitID] then
            visited[unitID] = true
            local neighbors = getNeighbors(unitID)

            if #neighbors < minPoints then
                -- Mark as noise initially, might be claimed by a cluster later
                table.insert(noise, unitID)
            else
                -- Start a new cluster
                clusterID = clusterID + 1
                clusters[clusterID] = {}
                expandCluster(unitID, neighbors, clusterID)
            end
        end
    end

    -- Check if noise points were claimed by a cluster
    local finalNoise = {}
    for _, unitID in ipairs(noise) do
        if not clustered[unitID] then
            table.insert(finalNoise, unitID)
        end
    end

    return clusters, finalNoise
end

--- Helper function to find the largest cluster
---@param clusters table Array of clusters
---@return table largestCluster The largest cluster
---@return number clusterIndex The index of the largest cluster
function DBSCAN.findLargestCluster(clusters)
    local largestSize = 0
    local largestCluster = {}
    local largestIndex = 0

    for i, cluster in ipairs(clusters) do
        if #cluster > largestSize then
            largestSize = #cluster
            largestCluster = cluster
            largestIndex = i
        end
    end

    return largestCluster, largestIndex
end

--- Finds the most significant cluster based on unit weights
---@param clusters table Array of clusters
---@return table significantCluster The most significant cluster by combined weight
---@return number clusterIndex The index of the most significant cluster
function DBSCAN.findMostSignificantCluster(clusters)
    local highestWeight = 0
    local significantCluster = {}
    local significantIndex = 0

    for i, cluster in ipairs(clusters) do
        local clusterWeight = 0

        -- Calculate the combined weight of the cluster
        for _, unitID in ipairs(cluster) do
            if Spring.ValidUnitID(unitID) then
                local unitDefID = Spring.GetUnitDefID(unitID)
                local weight = 1

                if unitDefID and UnitDefs[unitDefID] then
                    weight = UnitDefs[unitDefID].mass or 1
                end

                clusterWeight = clusterWeight + weight
            end
        end

        if clusterWeight > highestWeight then
            highestWeight = clusterWeight
            significantCluster = cluster
            significantIndex = i
        end
    end

    return significantCluster, significantIndex
end

--- Calculate adaptive parameters for DBSCAN based on unit distribution
---@param units table Array of unit IDs
---@param config table Configuration parameters
---@return number epsilon The calculated epsilon value
---@return number minPoints The calculated minPoints value
function DBSCAN.calculateAdaptiveParameters(units, config)
    -- Calculate average distance between units
    local positionSum = { x = 0, y = 0, z = 0 }
    local validUnits = 0
    local unitPositions = {}

    for _, unitID in ipairs(units) do
        if Spring.ValidUnitID(unitID) then
            local x, y, z = Spring.GetUnitPosition(unitID)
            unitPositions[validUnits + 1] = { x = x, y = y, z = z }

            positionSum.x = positionSum.x + x
            positionSum.y = positionSum.y + y
            positionSum.z = positionSum.z + z

            validUnits = validUnits + 1
        end
    end

    -- If too few units, use default parameters
    if validUnits <= config.MIN_CLUSTER_SIZE then
        return config.MIN_EPSILON, 2
    end

    -- Calculate average position
    local avgPos = {
        x = positionSum.x / validUnits,
        y = positionSum.y / validUnits,
        z = positionSum.z / validUnits
    }

    -- Calculate average distance from center
    local totalDistSquared = 0
    for i = 1, validUnits do
        local pos = unitPositions[i]
        local dx = pos.x - avgPos.x
        local dy = pos.y - avgPos.y
        local dz = pos.z - avgPos.z
        totalDistSquared = totalDistSquared + (dx * dx + dy * dy + dz * dz)
    end

    local averageDistSquared = totalDistSquared / validUnits

    -- Adaptive epsilon is scaled by the square root of the average squared distance
    local adaptiveEpsilon = math.sqrt(averageDistSquared) * config.EPSILON_FACTOR

    -- Clamp epsilon to reasonable limits
    adaptiveEpsilon = math.max(
            config.MIN_EPSILON,
            math.min(config.MAX_EPSILON, adaptiveEpsilon)
    )

    -- Calculate minPoints based on unit count
    local minPoints = math.max(
            2,
            math.min(
                    math.floor(validUnits * config.MIN_POINTS_FACTOR),
                    config.MAX_MIN_POINTS
            )
    )

    return adaptiveEpsilon, minPoints
end

--- Calculates squared distance between two points
---@param p1 table First position with x, y, z fields
---@param p2 table Second position with x, y, z fields
---@return number distanceSquared The squared distance between points
function DBSCAN.distanceSquared(p1, p2)
    local dx = p1.x - p2.x
    local dy = p1.y - p2.y
    local dz = p1.z - p2.z
    return dx * dx + dy * dy + dz * dz
end

--- Calculates the weighted center of mass for a group of units
---@param unitIDs table Array of unit IDs
---@return table centerOfMass Position {x, y, z} of center of mass
---@return number totalWeight Combined weight of all units
---@return number validUnits Number of valid units used in calculation
function DBSCAN.calculateCenterOfMass(unitIDs)
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
    local center = { x = 0, y = 0, z = 0 }
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
function DBSCAN.calculateGroupRadius(unitIDs, center)
    local maxDistSquared = 0
    local validUnits = 0

    for _, unitID in ipairs(unitIDs) do
        if Spring.ValidUnitID(unitID) then
            local x, y, z = Spring.GetUnitPosition(unitID)
            local dx = x - center.x
            local dy = y - center.y
            local dz = z - center.z
            local distSquared = dx * dx + dy * dy + dz * dz

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
function DBSCAN.calculateVelocity(currentCenter, previousCenter, deltaTime)
    if deltaTime <= 0 then
        return { x = 0, y = 0, z = 0 }
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
function DBSCAN.vectorMagnitude(vector)
    return math.sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
end

return DBSCAN