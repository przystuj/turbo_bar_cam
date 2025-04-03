-- DBSCAN (Density-Based Spatial Clustering of Applications with Noise) implementation
-- This module provides a standalone implementation of DBSCAN clustering algorithm
-- for identifying unit clusters in the group tracking camera
-- For detecting clusters of units in TURBOBARCAM
---@type ClusterMathUtils
local ClusterMathUtils = VFS.Include("LuaUI/TURBOBARCAM/common/cluster_math_utils.lua").ClusterMathUtils

---@class DBSCAN
local DBSCAN = {}

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
            unitPositions[unitID] = {x = x, y = y, z = z}
        end
    end
    
    -- Helper function to get neighbors within epsilon distance
    local function getNeighbors(unitID)
        local neighbors = {}
        local pos1 = unitPositions[unitID]
        
        if not pos1 then return neighbors end
        
        for otherUnitID, pos2 in pairs(unitPositions) do
            local distSquared = ClusterMathUtils.distanceSquared(pos1, pos2)
            
            if distSquared <= epsilon*epsilon then
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
                        if not ClusterMathUtils.tableContains(neighbors, neighborID) then
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
    local positionSum = {x = 0, y = 0, z = 0}
    local validUnits = 0
    local unitPositions = {}
    
    for _, unitID in ipairs(units) do
        if Spring.ValidUnitID(unitID) then
            local x, y, z = Spring.GetUnitPosition(unitID)
            unitPositions[validUnits+1] = {x = x, y = y, z = z}
            
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
        totalDistSquared = totalDistSquared + (dx*dx + dy*dy + dz*dz)
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

-- Export the module
return {
    DBSCAN = DBSCAN
}