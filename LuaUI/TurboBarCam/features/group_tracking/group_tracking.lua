---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type GroupTrackingUtils
local TrackingUtils = VFS.Include("LuaUI/TurboBarCam/features/group_tracking/group_tracking_utils.lua").TrackingUtils
---@type DBSCAN
local DBSCAN = VFS.Include("LuaUI/TurboBarCam/features/group_tracking/dbscan.lua").DBSCAN

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local TrackingManager = CommonModules.TrackingManager
local CameraCommons = CommonModules.CameraCommons

---@class GroupTrackingCamera
local GroupTrackingCamera = {}

--- Toggles group tracking camera mode
---@return boolean success Always returns true for widget handler
function GroupTrackingCamera.toggle()
    if Util.isTurboBarCamDisabled() then
        return true
    end

    -- Get the selected units
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits == 0 then
        -- If no units are selected and tracking is currently on, turn it off
        if STATE.tracking.mode == 'group_tracking' then
            TrackingManager.disableTracking()
            Log.debug("Group Tracking Camera disabled")
        else
            Log.debug("No units selected for Group Tracking Camera")
        end
        return true
    end

    -- If we're already in group tracking mode, turn it off
    if STATE.tracking.mode == 'group_tracking' then
        TrackingManager.disableTracking()
        Log.debug("Group Tracking Camera disabled")
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
        STATE.tracking.group = {
            unitIDs = STATE.tracking.group.unitIDs,
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

        -- Initialize camera position based on center of mass
        GroupTrackingCamera.initializeCameraPosition()

        Log.debug(string.format("Group Tracking Camera enabled. Tracking %d units", #STATE.tracking.group.unitIDs))
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
    local newCenter, totalWeight, validUnits = DBSCAN.calculateCenterOfMass(unitsToUse)

    -- Update state with new center
    STATE.tracking.group.centerOfMass = newCenter

    -- Calculate velocity for the group (for determining movement direction)
    local timeSinceLast = Spring.DiffTimers(
            Spring.GetTimer(),
            STATE.tracking.group.lastCenterUpdateTime or Spring.GetTimer()
    )

    if timeSinceLast > 0 then
        -- Calculate raw velocity
        local rawVelocity = DBSCAN.calculateVelocity(
                STATE.tracking.group.centerOfMass,
                STATE.tracking.group.lastCenterOfMass,
                timeSinceLast
        )

        -- Use a simple but effective smoothing factor
        local velocitySmoothingFactor = 0.1

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
                x = CameraCommons.smoothStep(STATE.tracking.group.smoothedVelocity.x, rawVelocity.x, velocitySmoothingFactor),
                y = CameraCommons.smoothStep(STATE.tracking.group.smoothedVelocity.y, rawVelocity.y, velocitySmoothingFactor),
                z = CameraCommons.smoothStep(STATE.tracking.group.smoothedVelocity.z, rawVelocity.z, velocitySmoothingFactor)
            }
        end

        -- Track direction history
        if STATE.tracking.group.directionHistory == nil then
            STATE.tracking.group.directionHistory = {}
        end

        -- Add current direction to history (but only if the velocity is significant)
        local velocityMagnitude = DBSCAN.vectorMagnitude(STATE.tracking.group.smoothedVelocity)
        if velocityMagnitude > 5.0 then
            -- Normalize the velocity to get just the direction
            local normalizedDir = {
                x = STATE.tracking.group.smoothedVelocity.x / velocityMagnitude,
                z = STATE.tracking.group.smoothedVelocity.z / velocityMagnitude,
                time = Spring.GetGameSeconds(),
                magnitude = velocityMagnitude
            }

            -- Add to history
            table.insert(STATE.tracking.group.directionHistory, normalizedDir)

            -- Keep only the last 5 directions
            while #STATE.tracking.group.directionHistory > 5 do
                table.remove(STATE.tracking.group.directionHistory, 1)
            end
        end
    end

    -- Update last center update time
    STATE.tracking.group.lastCenterUpdateTime = Spring.GetTimer()

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
    STATE.tracking.group.radius = DBSCAN.calculateGroupRadius(unitsToUse, center)
end

--- Detects clusters and focuses on the most significant one using DBSCAN
function GroupTrackingCamera.detectClusters()
    local now = Spring.GetGameSeconds()

    -- Only check for clusters periodically to avoid performance impact
    local checkInterval = 1.0
    if now - STATE.tracking.group.lastClusterCheck < checkInterval then
        return
    end

    STATE.tracking.group.lastClusterCheck = now

    -- Get current set of tracked units
    local units = STATE.tracking.group.unitIDs
    if #units == 0 then
        return
    end

    -- Check if we're dealing with aircraft units
    local hasAircraft = TrackingUtils.groupContainsAircraft(units)

    -- If all aircraft, skip clustering and use all units
    local allAircraft = true
    for _, unitID in ipairs(units) do
        if Spring.ValidUnitID(unitID) then
            local unitDefID = Spring.GetUnitDefID(unitID)
            if unitDefID and not TrackingUtils.isAircraftUnit(unitID) then
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

    -- If there are very few units, don't bother with clustering
    local validUnits = TrackingUtils.countValidUnits(units)
    if validUnits <= 2 then
        STATE.tracking.group.outliers = {}
        STATE.tracking.group.currentCluster = {}
        for _, unitID in ipairs(units) do
            if Spring.ValidUnitID(unitID) then
                table.insert(STATE.tracking.group.currentCluster, unitID)
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
        if not (hasAircraft and TrackingUtils.isAircraftUnit(unitID) and true) then
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

        -- Add aircraft to the cluster if needed
        if hasAircraft then
            for _, unitID in ipairs(units) do
                if Spring.ValidUnitID(unitID) and
                        TrackingUtils.isAircraftUnit(unitID) and
                        not Util.tableContains(significantCluster, unitID) then
                    table.insert(significantCluster, unitID)
                end
            end
        end

        -- Mark units not in significant cluster as outliers
        for _, unitID in ipairs(units) do
            if Spring.ValidUnitID(unitID) and not Util.tableContains(significantCluster, unitID) then
                -- Don't mark aircraft as outliers if we want to include them
                if not (hasAircraft and TrackingUtils.isAircraftUnit(unitID)) then
                    newOutliers[unitID] = true
                end
            end
        end

        -- Update our main group to focus only on the significant cluster
        STATE.tracking.group.currentCluster = significantCluster
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
    if Util.tableCount(previousOutliers) ~= Util.tableCount(newOutliers) then
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

        -- Recalculate center of mass and radius without outliers
        GroupTrackingCamera.calculateCenterOfMass()
        GroupTrackingCamera.calculateGroupRadius()
    end
end

--- Initializes camera position for group tracking
function GroupTrackingCamera.initializeCameraPosition()
    local center = STATE.tracking.group.centerOfMass
    local currentState = CameraManager.getCameraState("GroupTrackingCamera.initializeCameraPosition")

    -- Calculate a good initial position more to the side than directly behind the group
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

    -- Adjust camera position to be more to the side (45 degrees offset)
    -- We'll rotate the normalized direction vector to position camera more to the side
    local sideAngle = math.pi / 4  -- 45 degrees in radians
    local rotatedDx = dx * math.cos(sideAngle) - dz * math.sin(sideAngle)
    local rotatedDz = dx * math.sin(sideAngle) + dz * math.cos(sideAngle)

    -- Use the rotated vector instead
    dx = rotatedDx
    dz = rotatedDz

    -- Save current camera height for smoother transition
    local currentHeight = currentState.py

    -- Reduce the height factor to position camera less above the units (60% of original)
    local heightFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.DEFAULT_HEIGHT_FACTOR * 0.6
    local targetHeight = center.y + (distance * heightFactor)

    -- Apply a gradual height transition from current to target height
    -- Start at an intermediate height rather than jumping directly to final height
    local transitionHeight = currentHeight + ((targetHeight - currentHeight) * 0.3)

    -- Set camera position with smoother height transition
    local camPos = {
        x = center.x + (dx * distance),
        y = transitionHeight, -- Use transition height instead of target height
        z = center.z + (dz * distance)
    }

    -- Save initial camera direction
    STATE.tracking.group.lastCameraDir = { x = dx, z = dz }

    -- Calculate look direction to center
    local camState = CameraCommons.focusOnPoint(camPos, center, CONFIG.SMOOTHING.TRACKING_FACTOR, CONFIG.SMOOTHING.ROTATION_FACTOR)

    -- Initialize tracking state with this position

    TrackingManager.updateTrackingState(camState)

    -- Store the target height for smooth transition in the update function
    STATE.tracking.group.targetHeight = targetHeight

    -- Apply camera state with a slower initial transition
    CameraManager.setCameraState(camState, 1, "GroupTrackingCamera.initializeCameraPosition")
end

--- Calculates required camera distance to see all units
function GroupTrackingCamera.calculateRequiredDistance()
    local radius = STATE.tracking.group.radius
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
    STATE.tracking.group.targetDistance = CameraCommons.smoothStep(
            STATE.tracking.group.targetDistance,
            requiredDistance,
            0.03
    )

    return STATE.tracking.group.targetDistance
end

--- Checks if the movement pattern indicates back-and-forth movement
function GroupTrackingCamera.isBackAndForthMovement()
    -- Need at least 4 direction samples
    local dirHistory = STATE.tracking.group.directionHistory
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
    if STATE.tracking.group.inStableMode then
        local timeSinceStableModeStart = Spring.GetGameSeconds() - STATE.tracking.group.stableModeStartTime
        if timeSinceStableModeStart < 4.0 then
            return true
        end
    end

    -- Check velocity magnitude - very small movement doesn't need tracking
    local velocityMagnitude = DBSCAN.vectorMagnitude(STATE.tracking.group.smoothedVelocity)
    if velocityMagnitude < 3.0 then
        return true
    end

    -- Check for back and forth movement patterns
    if GroupTrackingCamera.isBackAndForthMovement() then
        return true
    end

    return false
end

--- Updates tracking camera to point at the group center of mass
function GroupTrackingCamera.update()
    if STATE.tracking.mode ~= 'group_tracking' then
        return
    end

    -- Check if we have any units to track
    if #STATE.tracking.group.unitIDs == 0 then
        TrackingManager.disableTracking()
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
        TrackingManager.disableTracking()
        return
    end

    -- Main tracking update
    GroupTrackingCamera.detectClusters()
    GroupTrackingCamera.calculateCenterOfMass()
    GroupTrackingCamera.calculateGroupRadius()

    -- Get center position
    local center = STATE.tracking.group.centerOfMass

    -- Calculate required camera distance
    local targetDistance = GroupTrackingCamera.calculateRequiredDistance()

    -- Check if we're still in FPS mode
    local currentState = CameraManager.getCameraState("GroupTrackingCamera.update")
    if currentState.mode ~= 0 then
        currentState.mode = 0
        currentState.name = "fps"
        CameraManager.setCameraState(currentState, 0, "GroupTrackingCamera.update")
    end

    -- Determine camera height
    local heightFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.DEFAULT_HEIGHT_FACTOR * 0.6
    local targetHeight = center.y + (targetDistance * heightFactor)

    -- Check if we should be in stable camera mode
    local shouldUseStable = GroupTrackingCamera.shouldUseStableMode()

    -- Toggle stable mode if necessary
    if shouldUseStable and not STATE.tracking.group.inStableMode then
        STATE.tracking.group.inStableMode = true
        STATE.tracking.group.stableModeStartTime = Spring.GetGameSeconds()
    elseif not shouldUseStable and STATE.tracking.group.inStableMode then
        STATE.tracking.group.inStableMode = false
    end

    -- Determine camera direction based on mode
    local newCameraDir

    if STATE.tracking.group.inStableMode then
        -- In stable mode, maintain current camera direction
        newCameraDir = STATE.tracking.group.lastCameraDir
    else
        -- Normal tracking mode
        -- Get smoothed velocity and calculate direction
        local smoothedVelocity = STATE.tracking.group.smoothedVelocity
        local velocityMagnitude = DBSCAN.vectorMagnitude(smoothedVelocity)

        if velocityMagnitude > 5.0 then
            -- Use velocity direction (position camera behind units)
            newCameraDir = {
                x = -smoothedVelocity.x / velocityMagnitude,
                z = -smoothedVelocity.z / velocityMagnitude
            }

            -- Limit maximum rotation per update (gradual turns)
            local lastDir = STATE.tracking.group.lastCameraDir
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
            newCameraDir = STATE.tracking.group.lastCameraDir
        end
    end

    -- Apply orbit-style camera adjustments
    local newCamPos = TrackingUtils.applyCameraAdjustments(
            center,
            newCameraDir,
            targetDistance,
            targetHeight
    )

    -- Get current camera position for smooth transition
    local camPos = { x = currentState.px, y = currentState.py, z = currentState.pz }

    -- Determine smoothing factors based on stable mode
    local posFactor, rotFactor

    if STATE.tracking.group.inStableMode then
        posFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.SMOOTHING.STABLE_POSITION
        rotFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.SMOOTHING.STABLE_ROTATION
    else
        posFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.SMOOTHING.POSITION
        rotFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.SMOOTHING.ROTATION
    end

    -- Apply smoothing
    local smoothedPos = {
        x = CameraCommons.smoothStep(camPos.x, newCamPos.x, posFactor),
        y = CameraCommons.smoothStep(camPos.y, newCamPos.y, posFactor),
        z = CameraCommons.smoothStep(camPos.z, newCamPos.z, posFactor)
    }

    -- Calculate look direction to center using the smoothed position
    local camStatePatch = CameraCommons.focusOnPoint(smoothedPos, center, posFactor, rotFactor)

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
    CameraManager.setCameraState(camStatePatch, 0, "GroupTrackingCamera.update")
end

---@see ModifiableParams
---@see Util#adjustParams
function GroupTrackingCamera.adjustParams(params)
    TrackingUtils.adjustGroupTrackingParams(params)
end

return {
    GroupTrackingCamera = GroupTrackingCamera
}