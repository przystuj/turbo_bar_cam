-- Group Tracking module for TURBOBARCAM with stability improvements
-- This extends the existing tracking system with multi-unit group tracking capabilities
-- using DBSCAN clustering to identify unit groups and focus on significant ones
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CommonModules
local TurboCommons = VFS.Include("LuaUI/TURBOBARCAM/common.lua")
---@type CoreModules
local TurboCore = VFS.Include("LuaUI/TURBOBARCAM/core.lua")

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE
local Util = TurboCommons.Util
local CameraCommons = TurboCore.CameraCommons
local TrackingManager = TurboCommons.Tracking
local ClusterMathUtils = TurboCommons.ClusterMathUtils
local DBSCAN = TurboCommons.DBSCAN

---@class GroupTrackingCamera
local GroupTrackingCamera = {}

--- Toggles group tracking camera mode
---@return boolean success Always returns true for widget handler
function GroupTrackingCamera.toggle()
    if not STATE.enabled then
        Util.debugEcho("TURBOBARCAM must be enabled first")
        return true
    end

    -- Get the selected units
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits == 0 then
        -- If no units are selected and tracking is currently on, turn it off
        if STATE.tracking.mode == 'group_tracking' then
            Util.disableTracking()
            Util.debugEcho("Group Tracking Camera disabled")
        else
            Util.debugEcho("No units selected for Group Tracking Camera")
        end
        return true
    end

    -- If we're already in group tracking mode, turn it off
    if STATE.tracking.mode == 'group_tracking' then
        Util.disableTracking()
        Util.debugEcho("Group Tracking Camera disabled")
        return true
    end

    -- Initialize the tracking system for group tracking
    -- We use unitID = 0 as a placeholder since we're tracking multiple units
    if TrackingManager.initializeTracking('group_tracking', selectedUnits[1]) then
        -- Store the group of units we're tracking
        STATE.tracking.group.unitIDs = {}
        for _, unitID in ipairs(selectedUnits) do
            table.insert(STATE.tracking.group.unitIDs, unitID)
        end

        -- Initialize group tracking state
        STATE.tracking.group.centerOfMass = { x = 0, y = 0, z = 0 }
        STATE.tracking.group.targetDistance = CONFIG.CAMERA_MODES.GROUP_TRACKING.DEFAULT_DISTANCE
        STATE.tracking.group.currentDistance = CONFIG.CAMERA_MODES.GROUP_TRACKING.DEFAULT_DISTANCE
        STATE.tracking.group.radius = 0
        STATE.tracking.group.outliers = {}
        STATE.tracking.group.currentCluster = {} -- Store current focused cluster
        STATE.tracking.group.totalWeight = 0
        STATE.tracking.group.lastCenterOfMass = { x = 0, y = 0, z = 0 }
        STATE.tracking.group.centerChanged = true
        STATE.tracking.group.lastClusterCheck = Spring.GetGameSeconds()
        STATE.tracking.group.velocity = { x = 0, y = 0, z = 0 }
        STATE.tracking.group.smoothedVelocity = { x = 0, y = 0, z = 0 } -- Add smoothed velocity
        STATE.tracking.group.lastCenterUpdateTime = Spring.GetTimer()
        STATE.tracking.group.lastTrackingUpdate = Spring.GetGameSeconds()
        STATE.tracking.group.lastDirectionChangeTime = Spring.GetGameSeconds() -- Track direction changes
        STATE.tracking.group.lastCameraDir = { x = 0, z = 0 } -- Track camera direction

        -- Calculate the initial center of mass and radius
        GroupTrackingCamera.calculateCenterOfMass()
        GroupTrackingCamera.calculateGroupRadius()

        -- Initialize camera position based on center of mass
        GroupTrackingCamera.initializeCameraPosition()

        Util.debugEcho(string.format("Group Tracking Camera enabled. Tracking %d units", #STATE.tracking.group.unitIDs))
    end

    return true
end

--- Calculates the weighted center of mass for the group
function GroupTrackingCamera.calculateCenterOfMass()
    local unitsToUse

    -- If we have a current cluster defined, use that instead of calculating from scratch
    if STATE.tracking.group.currentCluster and #STATE.tracking.group.currentCluster > 0 then
        unitsToUse = STATE.tracking.group.currentCluster
    else
        -- Otherwise use all non-outlier units
        local units = STATE.tracking.group.unitIDs
        local outliers = STATE.tracking.group.outliers
        unitsToUse = {}

        for _, unitID in ipairs(units) do
            if not outliers[unitID] and Spring.ValidUnitID(unitID) then
                table.insert(unitsToUse, unitID)
            end
        end
    end

    -- Save the previous center of mass for comparison
    STATE.tracking.group.lastCenterOfMass.x = STATE.tracking.group.centerOfMass.x
    STATE.tracking.group.lastCenterOfMass.y = STATE.tracking.group.centerOfMass.y
    STATE.tracking.group.lastCenterOfMass.z = STATE.tracking.group.centerOfMass.z

    -- Calculate center of mass using the math utility
    local newCenter, totalWeight, validUnits = ClusterMathUtils.calculateCenterOfMass(unitsToUse)

    -- Update state with new center
    STATE.tracking.group.centerOfMass = newCenter
    STATE.tracking.group.totalWeight = totalWeight

    -- Check if center of mass has significantly changed
    STATE.tracking.group.centerChanged = ClusterMathUtils.centerChanged(
            STATE.tracking.group.centerOfMass,
            STATE.tracking.group.lastCenterOfMass,
            CONFIG.CAMERA_MODES.GROUP_TRACKING.CENTER_CHANGE_THRESHOLD_SQ or 100 -- Default if not set
    )

    -- Calculate velocity for the group (for determining movement direction)
    local timeSinceLast = Spring.DiffTimers(
            Spring.GetTimer(),
            STATE.tracking.group.lastCenterUpdateTime or Spring.GetTimer()
    )

    if timeSinceLast > 0 then
        -- Calculate raw velocity
        local rawVelocity = ClusterMathUtils.calculateVelocity(
                STATE.tracking.group.centerOfMass,
                STATE.tracking.group.lastCenterOfMass,
                timeSinceLast
        )

        -- Get smoothing factor
        local velocitySmoothingFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.VELOCITY_SMOOTHING_FACTOR or 0.1

        -- If we don't have smoothed velocity yet, initialize it
        if not STATE.tracking.group.smoothedVelocity then
            STATE.tracking.group.smoothedVelocity = {
                x = rawVelocity.x,
                y = rawVelocity.y,
                z = rawVelocity.z
            }
        else
            -- Smooth the velocity
            STATE.tracking.group.smoothedVelocity = {
                x = Util.smoothStep(STATE.tracking.group.smoothedVelocity.x, rawVelocity.x, velocitySmoothingFactor),
                y = Util.smoothStep(STATE.tracking.group.smoothedVelocity.y, rawVelocity.y, velocitySmoothingFactor),
                z = Util.smoothStep(STATE.tracking.group.smoothedVelocity.z, rawVelocity.z, velocitySmoothingFactor)
            }
        end

        -- Store raw velocity for debugging
        STATE.tracking.group.velocity = rawVelocity
    end

    -- Update last center update time
    STATE.tracking.group.lastCenterUpdateTime = Spring.GetTimer()

    if CONFIG.CAMERA_MODES.GROUP_TRACKING.DEBUG_TRACKING then
        Util.debugEcho(string.format("Center of mass updated: x=%.1f, y=%.1f, z=%.1f (valid units: %d)",
                newCenter.x, newCenter.y, newCenter.z, validUnits))
    end

    return validUnits > 0
end

--- Calculates the radius of the group (max distance from center to any unit)
function GroupTrackingCamera.calculateGroupRadius()
    local center = STATE.tracking.group.centerOfMass
    local unitsToUse

    -- If we have a current cluster defined, use that instead of all units
    if STATE.tracking.group.currentCluster and #STATE.tracking.group.currentCluster > 0 then
        unitsToUse = STATE.tracking.group.currentCluster
    else
        -- Otherwise use all non-outlier units
        local units = STATE.tracking.group.unitIDs
        local outliers = STATE.tracking.group.outliers
        unitsToUse = {}

        for _, unitID in ipairs(units) do
            if not outliers[unitID] and Spring.ValidUnitID(unitID) then
                table.insert(unitsToUse, unitID)
            end
        end
    end

    -- Calculate radius using the math utility
    STATE.tracking.group.radius = ClusterMathUtils.calculateGroupRadius(unitsToUse, center)

    if CONFIG.CAMERA_MODES.GROUP_TRACKING.DEBUG_TRACKING then
        Util.debugEcho(string.format("Group radius: %.1f", STATE.tracking.group.radius))
    end
end

--- Detects clusters and focuses on the most significant one using DBSCAN
function GroupTrackingCamera.detectClusters()
    local now = Spring.GetGameSeconds()

    -- Only check for clusters periodically to avoid performance impact
    local checkInterval = CONFIG.CAMERA_MODES.GROUP_TRACKING.CLUSTER_CHECK_INTERVAL or 1.0
    if now - STATE.tracking.group.lastClusterCheck < checkInterval then
        return
    end

    STATE.tracking.group.lastClusterCheck = now

    -- Get current set of tracked units
    local units = STATE.tracking.group.unitIDs
    if #units == 0 then return end

    -- Check if we're dealing with aircraft units
    local hasAircraft = GroupTrackingCamera.containsAircraft()

    -- If all aircraft, skip clustering and use all units
    local allAircraft = true
    for _, unitID in ipairs(units) do
        if Spring.ValidUnitID(unitID) then
            local unitDefID = Spring.GetUnitDefID(unitID)
            if unitDefID and not GroupTrackingCamera.isAircraftUnit(unitID) then
                allAircraft = false
                break
            end
        end
    end

    if allAircraft then
        -- For all-aircraft groups, include all valid units in the cluster
        STATE.tracking.group.outliers = {}
        STATE.tracking.group.currentCluster = {}
        for _, unitID in ipairs(units) do
            if Spring.ValidUnitID(unitID) then
                table.insert(STATE.tracking.group.currentCluster, unitID)
            end
        end
        return
    end

    -- Calculate average distance between units for adaptive epsilon
    local positionSum = {x = 0, y = 0, z = 0}
    local validUnits = 0
    local unitPositions = {}

    for _, unitID in ipairs(units) do
        if Spring.ValidUnitID(unitID) then
            local x, y, z = Spring.GetUnitPosition(unitID)
            unitPositions[validUnits+1] = {x = x, y = y, z = z, unitID = unitID}

            positionSum.x = positionSum.x + x
            positionSum.y = positionSum.y + y
            positionSum.z = positionSum.z + z

            validUnits = validUnits + 1
        end
    end

    -- If we have too few units, don't bother with clustering
    local minClusterSize = CONFIG.CAMERA_MODES.GROUP_TRACKING.MIN_CLUSTER_SIZE or 2
    if validUnits <= minClusterSize then
        STATE.tracking.group.outliers = {}
        STATE.tracking.group.currentCluster = {}
        for _, unitID in ipairs(units) do
            if Spring.ValidUnitID(unitID) then
                table.insert(STATE.tracking.group.currentCluster, unitID)
            end
        end
        return
    end

    -- Calculate adaptive parameters with different settings based on unit types
    local config = CONFIG.CAMERA_MODES.GROUP_TRACKING

    -- Much more lenient values for clustering
    local epsilonFactor = config.EPSILON_FACTOR or 2.0

    -- If we have aircraft in the mix, use a much higher epsilon for clustering
    if hasAircraft then
        epsilonFactor = config.AIRCRAFT_EPSILON_FACTOR or 10.0
    end

    -- Get the other parameters
    local minEpsilon = config.MIN_EPSILON or 300
    local maxEpsilon = config.MAX_EPSILON or 1200

    if hasAircraft then
        minEpsilon = config.AIRCRAFT_MIN_EPSILON or 600 -- Double for aircraft
        maxEpsilon = config.AIRCRAFT_MAX_EPSILON or 2400 -- Double for aircraft
    end

    local minPointsFactor = config.MIN_POINTS_FACTOR or 0.1
    local maxMinPoints = config.MAX_MIN_POINTS or 3

    -- Create custom config for this clustering run
    local clusterConfig = {
        EPSILON_FACTOR = epsilonFactor,
        MIN_EPSILON = minEpsilon,
        MAX_EPSILON = maxEpsilon,
        MIN_POINTS_FACTOR = minPointsFactor,
        MAX_MIN_POINTS = maxMinPoints,
        MIN_CLUSTER_SIZE = config.MIN_CLUSTER_SIZE
    }

    Util.debugEcho(clusterConfig)

    local adaptiveEpsilon, minPoints = DBSCAN.calculateAdaptiveParameters(units, clusterConfig)

    -- Perform DBSCAN clustering
    local clusters, noise = DBSCAN.performClustering(units, adaptiveEpsilon, minPoints)

    -- Mark detected noise as outliers
    local newOutliers = {}
    for _, unitID in ipairs(noise) do
        -- Don't mark aircraft as outliers if we want to include them
        if not (hasAircraft and GroupTrackingCamera.isAircraftUnit(unitID) and
                config.ALWAYS_INCLUDE_AIRCRAFT) then
            newOutliers[unitID] = true
        end
    end

    -- If no clusters found but we have valid units, use all units as one cluster
    if #clusters == 0 and validUnits > 0 then
        STATE.tracking.group.currentCluster = {}
        for _, unitID in ipairs(units) do
            if Spring.ValidUnitID(unitID) then
                table.insert(STATE.tracking.group.currentCluster, unitID)
            end
        end
        STATE.tracking.group.outliers = {}
        return
    end

    -- If we found any clusters, focus on the most significant one
    if #clusters > 0 then
        local significantCluster, _ = DBSCAN.findMostSignificantCluster(clusters)

        -- If using contiguous unit detection, extend the cluster to include touching units
        if config.USE_CONTIGUOUS_UNIT_DETECTION then
            significantCluster = GroupTrackingCamera.extendClusterWithTouchingUnits(
                    significantCluster, units, adaptiveEpsilon)
        end

        -- Add aircraft to the cluster if needed
        if hasAircraft and config.ALWAYS_INCLUDE_AIRCRAFT then
            for _, unitID in ipairs(units) do
                if Spring.ValidUnitID(unitID) and
                        GroupTrackingCamera.isAircraftUnit(unitID) and
                        not ClusterMathUtils.tableContains(significantCluster, unitID) then
                    table.insert(significantCluster, unitID)
                end
            end
        end

        -- Mark units not in significant cluster as outliers
        for _, unitID in ipairs(units) do
            if Spring.ValidUnitID(unitID) and not ClusterMathUtils.tableContains(significantCluster, unitID) then
                -- Don't mark aircraft as outliers if we want to include them
                if not (hasAircraft and GroupTrackingCamera.isAircraftUnit(unitID) and
                        config.ALWAYS_INCLUDE_AIRCRAFT) then
                    newOutliers[unitID] = true
                end
            end
        end

        -- Update our main group to focus only on the significant cluster
        STATE.tracking.group.currentCluster = significantCluster

        -- Log diagnostic info
        if STATE.DEBUG then
            Util.debugEcho(string.format("Found %d clusters. Using largest with %d units.",
                    #clusters, #significantCluster))
        end
    else
        -- If no clusters found, just use all valid units and no outliers
        STATE.tracking.group.currentCluster = {}
        for _, unitID in ipairs(units) do
            if Spring.ValidUnitID(unitID) then
                table.insert(STATE.tracking.group.currentCluster, unitID)
            end
        end
        newOutliers = {}
    end

    -- Check if outliers changed
    local outliersChanged = false
    local previousOutliers = STATE.tracking.group.outliers

    -- Compare previous and new outliers
    if ClusterMathUtils.tableCount(previousOutliers) ~= ClusterMathUtils.tableCount(newOutliers) then
        outliersChanged = true
    else
        -- Check if any new outliers weren't in the previous set
        for unitID in pairs(newOutliers) do
            if not previousOutliers[unitID] then
                outliersChanged = true
                break
            end
        end

        -- If still not changed, check if any previous outliers aren't in the new set
        if not outliersChanged then
            for unitID in pairs(previousOutliers) do
                if not newOutliers[unitID] then
                    outliersChanged = true
                    break
                end
            end
        end
    end

    -- Update outliers if changed
    if outliersChanged then
        STATE.tracking.group.outliers = newOutliers

        -- Log diagnostic info if debug is enabled
        if STATE.DEBUG then
            local outlierCount = ClusterMathUtils.tableCount(newOutliers)
            local clusterCount = #clusters
            Util.debugEcho(string.format(
                    "Updated clusters: Found %d clusters, %d outliers. Using epsilon: %.1f, minPoints: %d",
                    clusterCount, outlierCount, adaptiveEpsilon, minPoints
            ))
        end

        -- Recalculate center of mass and radius without outliers
        GroupTrackingCamera.calculateCenterOfMass()
        GroupTrackingCamera.calculateGroupRadius()
    end
end

function GroupTrackingCamera.isAircraftUnit(unitID)
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
    local aircraftTypes = CONFIG.CAMERA_MODES.GROUP_TRACKING.AIRCRAFT_UNIT_TYPES
    if aircraftTypes and aircraftTypes[unitDef.name] then
        return true
    end

    -- Check if the unit can fly
    if unitDef.canFly then
        return true
    end

    return false
end

--- Extends a cluster to include units that are touching or very close to cluster units
--- with completely clean code (no goto statements)
---@param cluster table Array of unit IDs in the cluster
---@param allUnits table Array of all unit IDs to consider
---@param epsilon number Current epsilon value
---@return table extendedCluster The extended cluster
function GroupTrackingCamera.extendClusterWithTouchingUnits(cluster, allUnits, epsilon)
    local extendedCluster = {unpack(cluster)}
    local unitPositions = {}
    local clusterUnits = {}

    -- Get positions of all valid units
    for _, unitID in ipairs(allUnits) do
        if Spring.ValidUnitID(unitID) then
            local x, y, z = Spring.GetUnitPosition(unitID)
            unitPositions[unitID] = {x = x, y = y, z = z}
        end
    end

    -- Mark cluster units for quick lookup
    for _, unitID in ipairs(cluster) do
        clusterUnits[unitID] = true
    end

    -- Get unit radii for distance calculations
    local unitRadii = {}
    for _, unitID in ipairs(allUnits) do
        if Spring.ValidUnitID(unitID) then
            local unitDefID = Spring.GetUnitDefID(unitID)
            local radius = 20 -- Default radius

            if unitDefID and UnitDefs[unitDefID] then
                radius = UnitDefs[unitDefID].radius or 20
            end

            unitRadii[unitID] = radius
        end
    end

    -- Use a more aggressive epsilon for touching detection
    local touchingEpsilon = epsilon * 0.5 -- Half the clustering epsilon

    -- Check for units that are touching or very close to cluster units
    local changed = true
    local iterations = 0
    local maxIterations = 5 -- Limit iterations to prevent infinite loops

    while changed and iterations < maxIterations do
        changed = false
        iterations = iterations + 1

        -- First gather candidate units (not in cluster and valid)
        local candidateUnits = {}
        for _, unitID in ipairs(allUnits) do
            if not clusterUnits[unitID] and Spring.ValidUnitID(unitID) and unitPositions[unitID] then
                table.insert(candidateUnits, unitID)
            end
        end

        -- Now check each candidate against the existing cluster
        for _, unitID in ipairs(candidateUnits) do
            local unitPos = unitPositions[unitID]
            local isTouching = false

            -- Check against each cluster unit
            for _, clusterUnitID in ipairs(extendedCluster) do
                local clusterPos = unitPositions[clusterUnitID]

                -- Skip invalid positions
                if not clusterPos then
                    -- Just continue to next cluster unit
                else
                    -- Calculate distance between unit centers
                    local dx = unitPos.x - clusterPos.x
                    local dy = unitPos.y - clusterPos.y
                    local dz = unitPos.z - clusterPos.z
                    local distSquared = dx*dx + dy*dy + dz*dz

                    -- Sum of unit radii
                    local combinedRadius = (unitRadii[unitID] or 20) + (unitRadii[clusterUnitID] or 20)

                    -- Units are touching if distance is less than sum of radii plus a small buffer
                    local touchingDistanceSquared = (combinedRadius + touchingEpsilon) ^ 2

                    if distSquared <= touchingDistanceSquared then
                        isTouching = true
                        break -- No need to check other cluster units
                    end
                end
            end

            -- If unit is touching any cluster unit, add it
            if isTouching then
                table.insert(extendedCluster, unitID)
                clusterUnits[unitID] = true
                changed = true
            end
        end
    end

    return extendedCluster
end

--- Calculates required camera distance to see all units
function GroupTrackingCamera.calculateRequiredDistance()
    local radius = STATE.tracking.group.radius
    local heightFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.DEFAULT_HEIGHT_FACTOR
    local fovFactor = STATE.tracking.group.currentFOV

    -- Update FOV consideration based on current camera state
    local currentState = Spring.GetCameraState()
    if currentState.fov then
        STATE.tracking.group.currentFOV = currentState.fov * CONFIG.CAMERA_MODES.GROUP_TRACKING.FOV_FACTOR
        fovFactor = STATE.tracking.group.currentFOV
    end

    -- Calculate required distance using trigonometry:
    -- We need enough distance so that the radius fits within our FOV
    local fovRadians = math.rad(fovFactor)
    local requiredDistance = (radius / math.tan(fovRadians / 2)) / heightFactor

    -- Add padding and ensure within min/max bounds
    requiredDistance = requiredDistance + CONFIG.CAMERA_MODES.GROUP_TRACKING.DISTANCE_PADDING
    requiredDistance = math.max(CONFIG.CAMERA_MODES.GROUP_TRACKING.MIN_DISTANCE,
            math.min(CONFIG.CAMERA_MODES.GROUP_TRACKING.MAX_DISTANCE, requiredDistance))

    -- Smoothly update target distance
    STATE.tracking.group.targetDistance = Util.smoothStep(
            STATE.tracking.group.targetDistance,
            requiredDistance,
            CONFIG.CAMERA_MODES.GROUP_TRACKING.DISTANCE_SMOOTHING
    )

    return STATE.tracking.group.targetDistance
end

--- Initializes camera position for group tracking
function GroupTrackingCamera.initializeCameraPosition()
    local center = STATE.tracking.group.centerOfMass
    local currentState = Spring.GetCameraState()

    -- Calculate a good initial position behind the group
    -- Try to position camera between current pos and center for a smooth transition
    local dx = currentState.px - center.x
    local dz = currentState.pz - center.z
    local distance = math.sqrt(dx * dx + dz * dz)

    if distance < 1 then
        -- If camera is too close to center, use a default angle
        dx = -1
        dz = -1
        distance = math.sqrt(2)
    end

    -- Normalize direction vector
    dx = dx / distance
    dz = dz / distance

    -- Set distance to initial target distance
    distance = STATE.tracking.group.targetDistance

    -- Calculate height based on distance (with increased factor for more height)
    local height = center.y + (distance * CONFIG.CAMERA_MODES.GROUP_TRACKING.DEFAULT_HEIGHT_FACTOR)

    -- Set camera position
    local camPos = {
        x = center.x + (dx * distance),
        y = height,
        z = center.z + (dz * distance)
    }

    -- Save initial camera direction
    STATE.tracking.group.lastCameraDir = { x = dx, z = dz }

    -- Calculate look direction to center
    local lookDir = Util.calculateLookAtPoint(camPos, center)

    -- Create camera state
    local camState = {
        mode = 0, -- FPS camera mode
        name = "fps",
        px = camPos.x,
        py = camPos.y,
        pz = camPos.z,
        dx = lookDir.dx,
        dy = lookDir.dy,
        dz = lookDir.dz,
        rx = lookDir.rx,
        ry = lookDir.ry,
        rz = 0
    }

    -- Initialize tracking state with this position
    STATE.tracking.lastCamPos = { x = camPos.x, y = camPos.y, z = camPos.z }
    STATE.tracking.lastCamDir = { x = lookDir.dx, y = lookDir.dy, z = lookDir.dz }
    STATE.tracking.lastRotation = { rx = lookDir.rx, ry = lookDir.ry, rz = 0 }

    -- Apply camera state
    Spring.SetCameraState(camState, 0.5)

    if CONFIG.CAMERA_MODES.GROUP_TRACKING.DEBUG_TRACKING then
        Util.debugEcho("Camera position initialized")
    end
end

--- Tracks and averages unit positions to reduce jitter
function GroupTrackingCamera.updatePositionHistory()
    -- Initialize position history if it doesn't exist
    if not STATE.tracking.group.positionHistory then
        STATE.tracking.group.positionHistory = {}
        STATE.tracking.group.lastPositionSampleTime = Spring.GetGameSeconds()
        STATE.tracking.group.positionSampleIndex = 1
    end

    local now = Spring.GetGameSeconds()
    local config = CONFIG.CAMERA_MODES.GROUP_TRACKING
    local sampleInterval = config.POSITION_SAMPLE_INTERVAL or 0.1

    -- Only add samples at the specified interval
    if now - STATE.tracking.group.lastPositionSampleTime >= sampleInterval then
        STATE.tracking.group.lastPositionSampleTime = now

        -- Store current center of mass
        local center = STATE.tracking.group.centerOfMass
        local sampleIndex = STATE.tracking.group.positionSampleIndex
        local samples = config.POSITION_AVERAGING_SAMPLES or 10

        -- Add to history
        STATE.tracking.group.positionHistory[sampleIndex] = {
            x = center.x,
            y = center.y,
            z = center.z,
            time = now
        }

        -- Update index for next sample
        STATE.tracking.group.positionSampleIndex = (sampleIndex % samples) + 1
    end
end

--- Calculates the averaged center position from history
function GroupTrackingCamera.getSmoothedCenterPosition()
    if not STATE.tracking.group.positionHistory or not CONFIG.CAMERA_MODES.GROUP_TRACKING.USE_POSITION_AVERAGING then
        return STATE.tracking.group.centerOfMass
    end

    local history = STATE.tracking.group.positionHistory
    local count = 0
    local sumX, sumY, sumZ = 0, 0, 0

    -- Calculate weighted average (more recent samples have higher weight)
    local totalWeight = 0
    local now = Spring.GetGameSeconds()

    for _, pos in pairs(history) do
        if pos then
            -- Calculate age-based weight (newer samples have higher weight)
            local age = now - (pos.time or 0)
            local weight = math.max(0.1, 1.0 - (age / 3.0)) -- Samples older than 3 seconds have minimum weight

            sumX = sumX + (pos.x * weight)
            sumY = sumY + (pos.y * weight)
            sumZ = sumZ + (pos.z * weight)
            totalWeight = totalWeight + weight
            count = count + 1
        end
    end

    if count > 0 and totalWeight > 0 then
        return {
            x = sumX / totalWeight,
            y = sumY / totalWeight,
            z = sumZ / totalWeight
        }
    else
        return STATE.tracking.group.centerOfMass
    end
end

--- Applies Bezier smoothing to camera movement
function GroupTrackingCamera.applyBezierSmoothing(start, target, factor)
    if not CONFIG.CAMERA_MODES.GROUP_TRACKING.USE_BEZIER_SMOOTHING then
        return Util.smoothStep(start, target, factor)
    end

    -- Get current camera angle
    local cameraDir = STATE.tracking.group.lastCameraDir or { x = 0, z = 0 }
    local controlFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.BEZIER_CONTROL_POINT_FACTOR or 0.8

    -- Create a control point that's on the path from start toward current camera direction
    local distance = math.sqrt((target - start) ^ 2) * controlFactor
    local controlPoint = start + (cameraDir * distance)

    -- Apply quadratic Bezier interpolation
    local t = factor
    return (1 - t) ^ 2 * start + 2 * (1 - t) * t * controlPoint + t ^ 2 * target
end

--- Detects if the current unit group contains aircraft
function GroupTrackingCamera.containsAircraft()
    if not CONFIG.CAMERA_MODES.GROUP_TRACKING.AIRCRAFT_DETECTION_ENABLED then
        return false
    end

    local units = STATE.tracking.group.currentCluster or STATE.tracking.group.unitIDs

    for _, unitID in ipairs(units) do
        if Spring.ValidUnitID(unitID) then
            local unitDefID = Spring.GetUnitDefID(unitID)
            if unitDefID then
                local unitDef = UnitDefs[unitDefID]

                -- Check if unit is an aircraft either by name or by properties
                local isAircraft = false

                -- Method 1: Check against our list of known aircraft types
                local aircraftTypes = CONFIG.CAMERA_MODES.GROUP_TRACKING.AIRCRAFT_UNIT_TYPES
                if aircraftTypes and aircraftTypes[unitDef.name] then
                    isAircraft = true
                end

                -- Method 2: Check by unit properties
                if unitDef.canFly then
                    isAircraft = true
                end

                if isAircraft then
                    return true
                end
            end
        end
    end

    return false
end

--- Calculates the appropriate camera distance based on unit type and movement
function GroupTrackingCamera.calculateCameraDistance(baseDistance)
    local config = CONFIG.CAMERA_MODES.GROUP_TRACKING
    local distance = baseDistance

    -- Check if units are nearly stationary
    local velocityMagnitude = ClusterMathUtils.vectorMagnitude(STATE.tracking.group.smoothedVelocity or { x = 0, y = 0, z = 0 })
    if velocityMagnitude < (config.MIN_VELOCITY_THRESHOLD or 5.0) then
        -- Apply stationary distance factor
        distance = distance * (config.STATIONARY_DISTANCE_FACTOR or 1.5)
    end

    -- Check if group contains aircraft
    if GroupTrackingCamera.containsAircraft() then
        -- Add extra distance for aircraft
        distance = distance + (config.AIRCRAFT_EXTRA_DISTANCE or 300)
    end

    -- Ensure within min/max bounds
    return math.max(config.MIN_DISTANCE or 600,
            math.min(config.MAX_DISTANCE or 1200, distance))
end

--- Interpolates camera movement for smoother motion between updates
function GroupTrackingCamera.setupInterpolation(currentPos, targetPos)
    if not CONFIG.CAMERA_MODES.GROUP_TRACKING.USE_FRAME_INTERPOLATION then
        return
    end

    -- Initialize interpolation state if needed
    if not STATE.tracking.group.interpolation then
        STATE.tracking.group.interpolation = {
            active = false,
            currentStep = 0,
            steps = CONFIG.CAMERA_MODES.GROUP_TRACKING.INTERPOLATION_STEPS or 10,
            startPos = nil,
            endPos = nil,
            currentPos = nil
        }
    end

    -- Setup new interpolation
    STATE.tracking.group.interpolation.active = true
    STATE.tracking.group.interpolation.currentStep = 0
    STATE.tracking.group.interpolation.startPos = {
        x = currentPos.x,
        y = currentPos.y,
        z = currentPos.z
    }
    STATE.tracking.group.interpolation.endPos = {
        x = targetPos.x,
        y = targetPos.y,
        z = targetPos.z
    }
    STATE.tracking.group.interpolation.currentPos = {
        x = currentPos.x,
        y = currentPos.y,
        z = currentPos.z
    }
end

--- Updates the interpolation between camera positions
function GroupTrackingCamera.updateInterpolation()
    if not CONFIG.CAMERA_MODES.GROUP_TRACKING.USE_FRAME_INTERPOLATION or
            not STATE.tracking.group.interpolation or
            not STATE.tracking.group.interpolation.active then
        return nil
    end

    local interp = STATE.tracking.group.interpolation
    local steps = interp.steps

    -- Update step
    interp.currentStep = interp.currentStep + 1

    if interp.currentStep >= steps then
        -- Interpolation complete
        interp.active = false
        return nil
    end

    -- Calculate interpolated position
    local progress = interp.currentStep / steps
    local startPos = interp.startPos
    local endPos = interp.endPos

    -- Use smooth easing function
    local easedProgress = Util.easeInOutCubic(progress)

    -- Interpolate position
    interp.currentPos = {
        x = Util.lerp(startPos.x, endPos.x, easedProgress),
        y = Util.lerp(startPos.y, endPos.y, easedProgress),
        z = Util.lerp(startPos.z, endPos.z, easedProgress)
    }

    return interp.currentPos
end

--- Accelerates direction changes when turning
function GroupTrackingCamera.accelerateDirectionChange(lastDir, newDir, factor)
    if not lastDir or not newDir then
        return newDir
    end

    local config = CONFIG.CAMERA_MODES.GROUP_TRACKING
    local accelerationFactor = config.DIRECTION_CHANGE_ACCELERATION or 3.0

    -- Calculate dot product to measure how different the directions are
    local dotProduct = (lastDir.x * newDir.x) + (lastDir.z * newDir.z)

    -- If directions are very different, apply acceleration
    if dotProduct < config.DIRECTION_CHANGE_THRESHOLD then
        -- More acceleration for bigger turns
        local turnAcceleration = accelerationFactor * (1 - dotProduct)

        -- Accelerate the smoothing factor
        return factor * turnAcceleration
    end

    return factor
end

--- Applies a low-speed boost to make slow movements more noticeable
function GroupTrackingCamera.applyLowSpeedBoost(velocity)
    local config = CONFIG.CAMERA_MODES.GROUP_TRACKING
    local velocityMagnitude = ClusterMathUtils.vectorMagnitude(velocity)

    if velocityMagnitude > 0 and velocityMagnitude < (config.LOW_SPEED_BOOST_THRESHOLD or 0.5) then
        local boostFactor = config.LOW_SPEED_BOOST_FACTOR or 3.0

        return {
            x = velocity.x * boostFactor,
            y = velocity.y * boostFactor,
            z = velocity.z * boostFactor
        }
    end

    return velocity
end

--- Updates tracking camera to point at the group center of mass with ultra-smooth tracking
function GroupTrackingCamera.update()
    if STATE.tracking.mode ~= 'group_tracking' then
        return
    end

    -- Check if we have any units to track
    if #STATE.tracking.group.unitIDs == 0 then
        Util.disableTracking()
        return
    end

    -- Check for invalid units
    local validUnits = {}
    for _, unitID in ipairs(STATE.tracking.group.unitIDs) do
        if Spring.ValidUnitID(unitID) then
            table.insert(validUnits, unitID)
        end
    end

    -- Update tracked units list
    STATE.tracking.group.unitIDs = validUnits

    if #validUnits == 0 then
        Util.disableTracking()
        return
    end

    -- First check if we have an active interpolation to update
    if CONFIG.CAMERA_MODES.GROUP_TRACKING.USE_FRAME_INTERPOLATION and
            STATE.tracking.group.interpolation and
            STATE.tracking.group.interpolation.active then

        local interpolatedPos = GroupTrackingCamera.updateInterpolation()
        if interpolatedPos then
            -- Get current camera state
            local currentState = Spring.GetCameraState()

            -- Create minimal update to the interpolated position
            local camStatePatch = {
                px = interpolatedPos.x,
                py = interpolatedPos.y,
                pz = interpolatedPos.z
            }

            -- Apply the interpolated position
            Spring.SetCameraState(camStatePatch, 0)
            return
        end
    end

    -- Update tracking at a fixed interval for main updates
    local now = Spring.GetGameSeconds()

    -- Main tracking update
    GroupTrackingCamera.detectClusters()
    GroupTrackingCamera.calculateCenterOfMass()
    GroupTrackingCamera.calculateGroupRadius()
    GroupTrackingCamera.updatePositionHistory()

    -- Get smoothed center position
    local center = GroupTrackingCamera.getSmoothedCenterPosition()

    -- Calculate required camera distance
    local baseDistance = GroupTrackingCamera.calculateRequiredDistance()
    local targetDistance = GroupTrackingCamera.calculateCameraDistance(baseDistance)

    -- Check if we're still in FPS mode
    local currentState = Spring.GetCameraState()
    if currentState.mode ~= 0 then
        currentState.mode = 0
        currentState.name = "fps"
        Spring.SetCameraState(currentState, 0)
    end

    -- Get current camera position
    local camPos = { x = currentState.px, y = currentState.py, z = currentState.pz }

    -- Calculate direction from camera to center
    local dx = center.x - camPos.x
    local dy = center.y - camPos.y
    local dz = center.z - camPos.z
    local currentDistance = math.sqrt(dx * dx + dy * dy + dz * dz)

    -- Determine camera height
    local targetHeight = center.y + (targetDistance * CONFIG.CAMERA_MODES.GROUP_TRACKING.DEFAULT_HEIGHT_FACTOR)

    -- Normalize direction vector
    if currentDistance > 0 then
        dx = dx / currentDistance
        dz = dz / currentDistance
    else
        dx = 1
        dz = 0
    end

    -- Get config parameters
    local config = CONFIG.CAMERA_MODES.GROUP_TRACKING
    local posFactor = config.POSITION_SMOOTHING or 0.03
    local rotFactor = config.ROTATION_SMOOTHING or 0.04

    if STATE.tracking.modeTransition then
        posFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR
        rotFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR

        if CameraCommons.isTransitionComplete(STATE.tracking.transitionStartTime) then
            STATE.tracking.modeTransition = false
        end
    end

    -- Apply low-speed boost to velocity
    local smoothedVelocity = STATE.tracking.group.smoothedVelocity or { x = 0, y = 0, z = 0 }
    smoothedVelocity = GroupTrackingCamera.applyLowSpeedBoost(smoothedVelocity)

    -- Get velocity magnitude and thresholds
    local velocityMagnitude = ClusterMathUtils.vectorMagnitude(smoothedVelocity)
    local minVelocity = config.MIN_VELOCITY_THRESHOLD or 5.0
    local velocitySignificanceThreshold = config.VELOCITY_SIGNIFICANCE_THRESHOLD or 10.0
    local directionChangeThreshold = config.DIRECTION_CHANGE_THRESHOLD or 0.7
    local minDirectionChangeInterval = config.MIN_DIRECTION_CHANGE_INTERVAL or 0.5

    -- Get last camera direction or initialize it
    if not STATE.tracking.group.lastCameraDir then
        STATE.tracking.group.lastCameraDir = {
            x = -dx,
            z = -dz
        }
    end

    -- Determine camera direction
    local newCameraDir = { x = 0, z = 0 }
    local backwardFactor = config.BACKWARD_FACTOR or 1.0

    -- Check if we should use velocity-based direction or maintain current direction
    if velocityMagnitude > minVelocity then
        -- For significant movement, use smoothed velocity direction
        local velMag = math.sqrt(smoothedVelocity.x ^ 2 + smoothedVelocity.z ^ 2)

        if velMag > 0 then
            newCameraDir = {
                x = -smoothedVelocity.x / velMag,
                z = -smoothedVelocity.z / velMag
            }

            -- Check if this is a significant direction change
            local lastDir = STATE.tracking.group.lastCameraDir
            local dotProduct = newCameraDir.x * lastDir.x + newCameraDir.z * lastDir.z

            -- Only allow significant direction changes after minimum interval
            if dotProduct < directionChangeThreshold then
                local lastChangeTime = STATE.tracking.group.lastDirectionChangeTime or 0

                if now - lastChangeTime >= minDirectionChangeInterval then
                    -- New direction accepted, accelerate turning
                    STATE.tracking.group.lastDirectionChangeTime = now
                    rotFactor = GroupTrackingCamera.accelerateDirectionChange(lastDir, newCameraDir, rotFactor)
                else
                    -- Not enough time passed, blend directions
                    local blendFactor = (now - lastChangeTime) / minDirectionChangeInterval
                    newCameraDir = {
                        x = Util.lerp(lastDir.x, newCameraDir.x, blendFactor),
                        z = Util.lerp(lastDir.z, newCameraDir.z, blendFactor)
                    }
                end
            end
        else
            -- Fallback to current direction
            newCameraDir = STATE.tracking.group.lastCameraDir
        end
    else
        -- For slow/stationary units, maintain current camera direction
        local stationaryBias = config.STATIONARY_BIAS_FACTOR or 0.95
        local lastDir = STATE.tracking.group.lastCameraDir

        newCameraDir = {
            x = lastDir.x,
            z = lastDir.z
        }
    end

    -- Calculate new camera position with the determined direction
    local newCamPos = {
        x = center.x + (newCameraDir.x * targetDistance),
        y = targetHeight,
        z = center.z + (newCameraDir.z * targetDistance)
    }

    -- Check for jitter protection - avoid tiny movements
    local jitterRadius = config.JITTER_PROTECTION_RADIUS or 3.0
    local movementDelta = {
        x = newCamPos.x - camPos.x,
        y = newCamPos.y - camPos.y,
        z = newCamPos.z - camPos.z
    }
    local movementMagnitude = math.sqrt(movementDelta.x ^ 2 + movementDelta.y ^ 2 + movementDelta.z ^ 2)

    -- If movement is very small, don't move the camera at all
    if movementMagnitude < jitterRadius then
        newCamPos = {
            x = camPos.x,
            y = camPos.y,
            z = camPos.z
        }
    end

    -- Setup interpolation for smoother movement
    if CONFIG.CAMERA_MODES.GROUP_TRACKING.USE_FRAME_INTERPOLATION then
        GroupTrackingCamera.setupInterpolation(camPos, newCamPos)
    end

    -- Smooth camera position
    local smoothedPos = {
        x = Util.smoothStep(camPos.x, newCamPos.x, posFactor),
        y = Util.smoothStep(camPos.y, newCamPos.y, posFactor),
        z = Util.smoothStep(camPos.z, newCamPos.z, posFactor)
    }

    -- Calculate look direction to center
    local lookDir = Util.calculateLookAtPoint(smoothedPos, center)

    -- Create camera state patch
    local camStatePatch = {
        mode = 0,
        name = "fps",

        -- Position
        px = smoothedPos.x,
        py = smoothedPos.y,
        pz = smoothedPos.z,

        -- Direction vector
        dx = Util.smoothStep(STATE.tracking.lastCamDir.x, lookDir.dx, rotFactor),
        dy = Util.smoothStep(STATE.tracking.lastCamDir.y, lookDir.dy, rotFactor),
        dz = Util.smoothStep(STATE.tracking.lastCamDir.z, lookDir.dz, rotFactor),

        -- Rotation
        rx = Util.smoothStep(STATE.tracking.lastRotation.rx, lookDir.rx, rotFactor),
        ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, lookDir.ry, rotFactor),
        rz = 0
    }

    -- Update camera state
    STATE.tracking.lastCamPos.x = camStatePatch.px
    STATE.tracking.lastCamPos.y = camStatePatch.py
    STATE.tracking.lastCamPos.z = camStatePatch.pz
    STATE.tracking.lastCamDir.x = camStatePatch.dx
    STATE.tracking.lastCamDir.y = camStatePatch.dy
    STATE.tracking.lastCamDir.z = camStatePatch.dz
    STATE.tracking.lastRotation.rx = camStatePatch.rx
    STATE.tracking.lastRotation.ry = camStatePatch.ry
    STATE.tracking.group.lastCameraDir = newCameraDir

    -- Apply camera state
    Spring.SetCameraState(camStatePatch, 0)

    if config.DEBUG_TRACKING then
        Util.debugEcho(string.format("Tracking: VelMag=%.1f, Dist=%.1f, Aircraft=%s",
                velocityMagnitude, targetDistance, tostring(GroupTrackingCamera.containsAircraft())))
    end

end

return {
    GroupTrackingCamera = GroupTrackingCamera
}