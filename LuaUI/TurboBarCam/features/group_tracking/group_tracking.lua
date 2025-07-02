---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CONSTANTS = ModuleManager.CONSTANTS(function(m) CONSTANTS = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "GroupTrackingCamera")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local GroupTrackingUtils = ModuleManager.GroupTrackingUtils(function(m) GroupTrackingUtils = m end)
local DBSCAN = ModuleManager.DBSCAN(function(m) DBSCAN = m end)
local CameraDriver = ModuleManager.CameraDriver(function(m) CameraDriver = m end)

---@class GroupTrackingCamera
local GroupTrackingCamera = {}

local MODE_NAME = CONSTANTS.MODE.GROUP_TRACKING

--- Toggles group tracking camera mode
---@return boolean success Always returns true for widget handler
function GroupTrackingCamera.toggle()
    if Utils.isTurboBarCamDisabled() then
        return true
    end

    -- Get the selected units
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits == 0 then
        -- If no units are selected and tracking is currently on, turn it off
        if STATE.active.mode.name == MODE_NAME then
            ModeManager.disableMode()
            Log:trace("Group Tracking Camera disabled")
        else
            Log:trace("No units selected for Group Tracking Camera")
        end
        return true
    end

    -- If we're already in group tracking mode, turn it off
    if STATE.active.mode.name == MODE_NAME then
        ModeManager.disableMode()
        Log:trace("Group Tracking Camera disabled")
        return true
    end

    -- Initialize the tracking system for group tracking
    -- We use unitID = 0 as a placeholder since we're tracking multiple units
    if ModeManager.initializeMode(MODE_NAME, selectedUnits[1]) then
        -- Store the group of units we're tracking
        STATE.active.mode.group_tracking.unitIDs = {}
        for _, unitID in ipairs(selectedUnits) do
            table.insert(STATE.active.mode.group_tracking.unitIDs, unitID)
        end

        -- Initialize group tracking state
        STATE.active.mode.group_tracking = {
            unitIDs = STATE.active.mode.group_tracking.unitIDs,
            centerOfMass = { x = 0, y = 0, z = 0 },
            lastCenterOfMass = { x = 0, y = 0, z = 0 },
            targetDistance = CONFIG.CAMERA_MODES.GROUP_TRACKING.DEFAULT_DISTANCE,
            radius = 0,
            outliers = {},
            currentCluster = {},
            totalWeight = 0,

            -- Tracking state
            lastClusterCheck = Spring.GetGameSeconds(),
            lastCenterUpdateTime = Spring.GetTimer(),
            lastDirectionChangeTime = Spring.GetGameSeconds(),

            -- Movement tracking
            velocity = { x = 0, y = 0, z = 0 },
            smoothedVelocity = { x = 0, y = 0, z = 0 },
            directionHistory = {},
            stabilityCounter = 0,

            -- Camera control
            lastCameraDir = { x = 0, z = 0 },
            inStableMode = false,
            stableModeStartTime = 0
        }

        -- Calculate the initial center of mass and radius
        GroupTrackingCamera.calculateCenterOfMass()
        GroupTrackingCamera.calculateGroupRadius()

        Log:trace(string.format("Group Tracking Camera enabled. Tracking %d units", #STATE.active.mode.group_tracking.unitIDs))
    end

    return true
end

--- Updates tracking camera to point at the group center of mass
function GroupTrackingCamera.update()
    if STATE.active.mode.name ~= MODE_NAME then
        return
    end

    -- Check if we have any units to track
    if #STATE.active.mode.group_tracking.unitIDs == 0 then
        ModeManager.disableMode()
        return
    end

    -- Check for invalid units
    local validUnits = {}
    for _, unitID in ipairs(STATE.active.mode.group_tracking.unitIDs) do
        if Spring.ValidUnitID(unitID) then
            table.insert(validUnits, unitID)
        end
    end

    -- Update tracked units list
    STATE.active.mode.group_tracking.unitIDs = validUnits

    if #validUnits == 0 then
        ModeManager.disableMode()
        return
    end

    -- Main tracking update
    GroupTrackingCamera.detectClusters()
    GroupTrackingCamera.calculateCenterOfMass()
    GroupTrackingCamera.calculateGroupRadius()

    -- Get center position
    local center = STATE.active.mode.group_tracking.centerOfMass

    -- Calculate required camera distance
    local targetDistance = GroupTrackingCamera.calculateRequiredDistance()


    -- Determine camera height
    local heightFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.DEFAULT_HEIGHT_FACTOR * 0.6
    local targetHeight = center.y + (targetDistance * heightFactor)

    -- Check if we should be in stable camera mode
    local shouldUseStable = GroupTrackingCamera.shouldUseStableMode()

    -- Toggle stable mode if necessary
    if shouldUseStable and not STATE.active.mode.group_tracking.inStableMode then
        STATE.active.mode.group_tracking.inStableMode = true
        STATE.active.mode.group_tracking.stableModeStartTime = Spring.GetGameSeconds()
    elseif not shouldUseStable and STATE.active.mode.group_tracking.inStableMode then
        STATE.active.mode.group_tracking.inStableMode = false
    end

    -- Determine camera direction based on mode
    local newCameraDir

    if STATE.active.mode.group_tracking.inStableMode then
        -- In stable mode, maintain current camera direction
        newCameraDir = STATE.active.mode.group_tracking.lastCameraDir
    else
        -- Normal tracking mode
        -- Get smoothed velocity and calculate direction
        local smoothedVelocity = STATE.active.mode.group_tracking.smoothedVelocity
        local velocityMagnitude = DBSCAN.vectorMagnitude(smoothedVelocity)

        if velocityMagnitude > 5.0 then
            -- Use velocity direction (position camera behind units)
            newCameraDir = {
                x = -smoothedVelocity.x / velocityMagnitude,
                z = -smoothedVelocity.z / velocityMagnitude
            }

            -- Limit maximum rotation per update (gradual turns)
            local lastDir = STATE.active.mode.group_tracking.lastCameraDir
            local currentDot = newCameraDir.x * lastDir.x + newCameraDir.z * lastDir.z

            -- If directions are very different, limit the change
            if currentDot < 0 then
                -- Severe direction change (more than 90 degrees)
                -- Limit to a maximum of 45 degrees per update
                local angle = math.atan2(lastDir.z, lastDir.x)
                local targetAngle = math.atan2(newCameraDir.z, newCameraDir.x)
                local angleDiff = targetAngle - angle

                -- Normalize to -pi to pi
                while angleDiff > math.pi do
                    angleDiff = angleDiff - 2 * math.pi
                end
                while angleDiff < -math.pi do
                    angleDiff = angleDiff + 2 * math.pi
                end

                -- Limit angle change to 45 degrees max (π/4 radians)
                local maxChange = math.pi / 4
                if math.abs(angleDiff) > maxChange then
                    local sign = angleDiff > 0 and 1 or -1
                    angle = angle + (sign * maxChange)

                    -- Convert back to direction vector
                    newCameraDir = {
                        x = math.cos(angle),
                        z = math.sin(angle)
                    }
                end
            end
        else
            -- For slow/stationary units, maintain current camera direction
            newCameraDir = STATE.active.mode.group_tracking.lastCameraDir
        end
    end

    -- Apply orbit-style camera adjustments
    local totalDistance = targetDistance + CONFIG.CAMERA_MODES.GROUP_TRACKING.EXTRA_DISTANCE
    local totalHeight = targetHeight + CONFIG.CAMERA_MODES.GROUP_TRACKING.EXTRA_HEIGHT
    local newCamPos = GroupTrackingUtils.applyCameraAdjustments(
            center,
            newCameraDir,
            totalDistance,
            totalHeight
    )

    -- Determine smoothing factors based on stable mode
    local posFactor, rotFactor
    if STATE.active.mode.group_tracking.inStableMode then
        posFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.SMOOTHING.STABLE_POSITION
        rotFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.SMOOTHING.STABLE_ROTATION
    else
        posFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.SMOOTHING.POSITION
        rotFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.SMOOTHING.ROTATION
    end

    local cameraDriverJob = CameraDriver.prepare()
    cameraDriverJob.rotationSmoothing = posFactor/4
    cameraDriverJob.positionSmoothing = posFactor
    cameraDriverJob.position = newCamPos
    cameraDriverJob.targetType = CONSTANTS.TARGET_TYPE.POINT
    cameraDriverJob.targetPoint = center
    cameraDriverJob.run()
end

--- Calculates the weighted center of mass for the group
function GroupTrackingCamera.calculateCenterOfMass()
    local unitsToUse

    -- If we have a current cluster defined, use that instead of calculating from scratch
    if STATE.active.mode.group_tracking.currentCluster and #STATE.active.mode.group_tracking.currentCluster > 0 then
        unitsToUse = STATE.active.mode.group_tracking.currentCluster
    else
        -- Otherwise use all non-outlier units
        local units = STATE.active.mode.group_tracking.unitIDs
        local outliers = STATE.active.mode.group_tracking.outliers
        unitsToUse = {}

        for _, unitID in ipairs(units) do
            if not outliers[unitID] and Spring.ValidUnitID(unitID) then
                table.insert(unitsToUse, unitID)
            end
        end
    end

    -- Save the previous center of mass for comparison
    STATE.active.mode.group_tracking.lastCenterOfMass.x = STATE.active.mode.group_tracking.centerOfMass.x
    STATE.active.mode.group_tracking.lastCenterOfMass.y = STATE.active.mode.group_tracking.centerOfMass.y
    STATE.active.mode.group_tracking.lastCenterOfMass.z = STATE.active.mode.group_tracking.centerOfMass.z

    -- Calculate center of mass using the math utility
    local newCenter, totalWeight, validUnits = DBSCAN.calculateCenterOfMass(unitsToUse)

    -- Update state with new center
    STATE.active.mode.group_tracking.centerOfMass = newCenter

    -- Calculate velocity for the group (for determining movement direction)
    local timeSinceLast = Spring.DiffTimers(
            Spring.GetTimer(),
            STATE.active.mode.group_tracking.lastCenterUpdateTime or Spring.GetTimer()
    )

    if timeSinceLast > 0 then
        -- Calculate raw velocity
        local rawVelocity = DBSCAN.calculateVelocity(
                STATE.active.mode.group_tracking.centerOfMass,
                STATE.active.mode.group_tracking.lastCenterOfMass,
                timeSinceLast
        )

        -- Use a simple but effective smoothing factor
        local velocitySmoothingFactor = 0.1

        -- If we don't have smoothed velocity yet, initialize it
        if not STATE.active.mode.group_tracking.smoothedVelocity then
            STATE.active.mode.group_tracking.smoothedVelocity = {
                x = rawVelocity.x,
                y = rawVelocity.y,
                z = rawVelocity.z
            }
        else
            -- Smooth the velocity
            STATE.active.mode.group_tracking.smoothedVelocity = {
                x = CameraCommons.lerp(STATE.active.mode.group_tracking.smoothedVelocity.x, rawVelocity.x, velocitySmoothingFactor),
                y = CameraCommons.lerp(STATE.active.mode.group_tracking.smoothedVelocity.y, rawVelocity.y, velocitySmoothingFactor),
                z = CameraCommons.lerp(STATE.active.mode.group_tracking.smoothedVelocity.z, rawVelocity.z, velocitySmoothingFactor)
            }
        end

        -- Track direction history
        if STATE.active.mode.group_tracking.directionHistory == nil then
            STATE.active.mode.group_tracking.directionHistory = {}
        end

        -- Add current direction to history (but only if the velocity is significant)
        local velocityMagnitude = DBSCAN.vectorMagnitude(STATE.active.mode.group_tracking.smoothedVelocity)
        if velocityMagnitude > 5.0 then
            -- Normalize the velocity to get just the direction
            local normalizedDir = {
                x = STATE.active.mode.group_tracking.smoothedVelocity.x / velocityMagnitude,
                z = STATE.active.mode.group_tracking.smoothedVelocity.z / velocityMagnitude,
                time = Spring.GetGameSeconds(),
                magnitude = velocityMagnitude
            }

            -- Add to history
            table.insert(STATE.active.mode.group_tracking.directionHistory, normalizedDir)

            -- Keep only the last 5 directions
            while #STATE.active.mode.group_tracking.directionHistory > 5 do
                table.remove(STATE.active.mode.group_tracking.directionHistory, 1)
            end
        end
    end

    -- Update last center update time
    STATE.active.mode.group_tracking.lastCenterUpdateTime = Spring.GetTimer()

    return validUnits > 0
end

--- Calculates the radius of the group (max distance from center to any unit)
function GroupTrackingCamera.calculateGroupRadius()
    local center = STATE.active.mode.group_tracking.centerOfMass
    local unitsToUse

    -- If we have a current cluster defined, use that instead of all units
    if STATE.active.mode.group_tracking.currentCluster and #STATE.active.mode.group_tracking.currentCluster > 0 then
        unitsToUse = STATE.active.mode.group_tracking.currentCluster
    else
        -- Otherwise use all non-outlier units
        local units = STATE.active.mode.group_tracking.unitIDs
        local outliers = STATE.active.mode.group_tracking.outliers
        unitsToUse = {}

        for _, unitID in ipairs(units) do
            if not outliers[unitID] and Spring.ValidUnitID(unitID) then
                table.insert(unitsToUse, unitID)
            end
        end
    end

    -- Calculate radius using the math utility
    STATE.active.mode.group_tracking.radius = DBSCAN.calculateGroupRadius(unitsToUse, center)
end

--- Detects clusters and focuses on the most significant one using DBSCAN
function GroupTrackingCamera.detectClusters()
    local now = Spring.GetGameSeconds()

    -- Only check for clusters periodically to avoid performance impact
    local checkInterval = 1.0
    if now - STATE.active.mode.group_tracking.lastClusterCheck < checkInterval then
        return
    end

    STATE.active.mode.group_tracking.lastClusterCheck = now

    -- Get current set of tracked units
    local units = STATE.active.mode.group_tracking.unitIDs
    if #units == 0 then
        return
    end

    -- Check if we're dealing with aircraft units
    local hasAircraft = GroupTrackingUtils.groupContainsAircraft(units)

    -- If all aircraft, skip clustering and use all units
    local allAircraft = true
    for _, unitID in ipairs(units) do
        if Spring.ValidUnitID(unitID) then
            local unitDefID = Spring.GetUnitDefID(unitID)
            if unitDefID and not GroupTrackingUtils.isAircraftUnit(unitID) then
                allAircraft = false
                break
            end
        end
    end

    if allAircraft then
        -- For all-aircraft groups, include all valid units in the cluster
        STATE.active.mode.group_tracking.outliers = {}
        STATE.active.mode.group_tracking.currentCluster = {}
        for _, unitID in ipairs(units) do
            if Spring.ValidUnitID(unitID) then
                table.insert(STATE.active.mode.group_tracking.currentCluster, unitID)
            end
        end
        return
    end

    -- If there are very few units, don't bother with clustering
    local validUnits = GroupTrackingUtils.countValidUnits(units)
    if validUnits <= 2 then
        STATE.active.mode.group_tracking.outliers = {}
        STATE.active.mode.group_tracking.currentCluster = {}
        for _, unitID in ipairs(units) do
            if Spring.ValidUnitID(unitID) then
                table.insert(STATE.active.mode.group_tracking.currentCluster, unitID)
            end
        end
        return
    end

    -- Create custom config for clustering
    local clusterConfig = {
        EPSILON_FACTOR = hasAircraft and 10.0 or 3.0,
        MIN_EPSILON = hasAircraft and 600 or 400,
        MAX_EPSILON = hasAircraft and 2400 or 1100,
        MIN_POINTS_FACTOR = 0.05,
        MAX_MIN_POINTS = 2,
        MIN_CLUSTER_SIZE = 2
    }

    local adaptiveEpsilon, minPoints = DBSCAN.calculateAdaptiveParameters(units, clusterConfig)

    -- Perform DBSCAN clustering
    local clusters, noise = DBSCAN.performClustering(units, adaptiveEpsilon, minPoints)

    -- Mark detected noise as outliers
    local newOutliers = {}
    for _, unitID in ipairs(noise) do
        -- Don't mark aircraft as outliers if we want to include them
        if not (hasAircraft and GroupTrackingUtils.isAircraftUnit(unitID) and true) then
            newOutliers[unitID] = true
        end
    end

    -- If no clusters found but we have valid units, use all units as one cluster
    if #clusters == 0 and validUnits > 0 then
        STATE.active.mode.group_tracking.currentCluster = {}
        for _, unitID in ipairs(units) do
            if Spring.ValidUnitID(unitID) then
                table.insert(STATE.active.mode.group_tracking.currentCluster, unitID)
            end
        end
        STATE.active.mode.group_tracking.outliers = {}
        return
    end

    -- If we found any clusters, focus on the most significant one
    if #clusters > 0 then
        local significantCluster, _ = DBSCAN.findMostSignificantCluster(clusters)

        -- Add aircraft to the cluster if needed
        if hasAircraft then
            for _, unitID in ipairs(units) do
                if Spring.ValidUnitID(unitID) and
                        GroupTrackingUtils.isAircraftUnit(unitID) and
                        not TableUtils.tableContains(significantCluster, unitID) then
                    table.insert(significantCluster, unitID)
                end
            end
        end

        -- Mark units not in significant cluster as outliers
        for _, unitID in ipairs(units) do
            if Spring.ValidUnitID(unitID) and not TableUtils.tableContains(significantCluster, unitID) then
                -- Don't mark aircraft as outliers if we want to include them
                if not (hasAircraft and GroupTrackingUtils.isAircraftUnit(unitID)) then
                    newOutliers[unitID] = true
                end
            end
        end

        -- Update our main group to focus only on the significant cluster
        STATE.active.mode.group_tracking.currentCluster = significantCluster
    else
        -- If no clusters found, just use all valid units and no outliers
        STATE.active.mode.group_tracking.currentCluster = {}
        for _, unitID in ipairs(units) do
            if Spring.ValidUnitID(unitID) then
                table.insert(STATE.active.mode.group_tracking.currentCluster, unitID)
            end
        end
        newOutliers = {}
    end

    -- Check if outliers changed
    local outliersChanged = false
    local previousOutliers = STATE.active.mode.group_tracking.outliers

    -- Compare previous and new outliers
    if TableUtils.tableCount(previousOutliers) ~= TableUtils.tableCount(newOutliers) then
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
        STATE.active.mode.group_tracking.outliers = newOutliers

        -- Recalculate center of mass and radius without outliers
        GroupTrackingCamera.calculateCenterOfMass()
        GroupTrackingCamera.calculateGroupRadius()
    end
end

--- Calculates required camera distance to see all units
function GroupTrackingCamera.calculateRequiredDistance()
    local radius = STATE.active.mode.group_tracking.radius
    local heightFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.DEFAULT_HEIGHT_FACTOR

    -- Use a fixed FOV factor
    local fovFactor = 45

    -- Calculate required distance using trigonometry:
    -- We need enough distance so that the radius fits within our FOV
    local fovRadians = math.rad(fovFactor)
    local requiredDistance = (radius / math.tan(fovRadians / 2)) / heightFactor

    -- Add padding and ensure within min/max bounds
    requiredDistance = requiredDistance + 50 -- padding
    requiredDistance = math.max(CONFIG.CAMERA_MODES.GROUP_TRACKING.MIN_DISTANCE,
            math.min(CONFIG.CAMERA_MODES.GROUP_TRACKING.MAX_DISTANCE, requiredDistance))

    -- Smoothly update target distance
    STATE.active.mode.group_tracking.targetDistance = CameraCommons.lerp(
            STATE.active.mode.group_tracking.targetDistance,
            requiredDistance,
            0.03
    )

    return STATE.active.mode.group_tracking.targetDistance
end

--- Checks if the movement pattern indicates back-and-forth movement
function GroupTrackingCamera.isBackAndForthMovement()
    -- Need at least 4 direction samples
    local dirHistory = STATE.active.mode.group_tracking.directionHistory
    if not dirHistory or #dirHistory < 4 then
        return false
    end

    -- Check for direction changes
    local directionChanges = 0
    local lastDot = nil

    for i = 2, #dirHistory do
        local d1 = dirHistory[i - 1]
        local d2 = dirHistory[i]

        -- Get dot product between consecutive directions
        local dot = d1.x * d2.x + d1.z * d2.z

        -- If dot product is negative, direction has significantly changed
        if dot < 0.3 then
            directionChanges = directionChanges + 1
        end

        -- If we have opposing directions, may indicate back and forth
        if i > 2 and dot < -0.7 and lastDot and lastDot < -0.7 then
            return true
        end

        lastDot = dot
    end

    -- If we have multiple direction changes in our short history, likely back and forth
    return directionChanges >= 2
end

--- Determines if we should enter stable camera mode
function GroupTrackingCamera.shouldUseStableMode()
    -- If we're already in stable mode, continue using it for a minimum time
    if STATE.active.mode.group_tracking.inStableMode then
        local timeSinceStableModeStart = Spring.GetGameSeconds() - STATE.active.mode.group_tracking.stableModeStartTime
        if timeSinceStableModeStart < 4.0 then
            return true
        end
    end

    -- Check velocity magnitude - very small movement doesn't need tracking
    local velocityMagnitude = DBSCAN.vectorMagnitude(STATE.active.mode.group_tracking.smoothedVelocity)
    if velocityMagnitude < 3.0 then
        return true
    end

    -- Check for back and forth movement patterns
    if GroupTrackingCamera.isBackAndForthMovement() then
        return true
    end

    return false
end

---@see ModifiableParams
---@see Utils#adjustParams
function GroupTrackingCamera.adjustParams(params)
    GroupTrackingUtils.adjustGroupTrackingParams(params)
end

return GroupTrackingCamera