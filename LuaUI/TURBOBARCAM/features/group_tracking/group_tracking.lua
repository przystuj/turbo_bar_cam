-- Group Tracking module for TURBOBARCAM
-- This extends the existing tracking system with multi-unit group tracking capabilities
-- Load modules
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
        STATE.tracking.group.centerOfMass = {x = 0, y = 0, z = 0}
        STATE.tracking.group.targetDistance = CONFIG.CAMERA_MODES.GROUP_TRACKING.DEFAULT_DISTANCE
        STATE.tracking.group.currentDistance = CONFIG.CAMERA_MODES.GROUP_TRACKING.DEFAULT_DISTANCE
        STATE.tracking.group.radius = 0
        STATE.tracking.group.outliers = {}
        STATE.tracking.group.totalWeight = 0
        STATE.tracking.group.lastCenterOfMass = {x = 0, y = 0, z = 0}
        STATE.tracking.group.centerChanged = true
        STATE.tracking.group.lastOutlierCheck = Spring.GetGameSeconds()

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
    local units = STATE.tracking.group.unitIDs
    local weightedX, weightedY, weightedZ = 0, 0, 0
    local totalWeight = 0
    local validUnits = 0

    -- Exclude outliers from center of mass calculation
    local outliers = STATE.tracking.group.outliers

    for _, unitID in ipairs(units) do
        -- Skip outliers and invalid units
        if not outliers[unitID] and Spring.ValidUnitID(unitID) then
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

    -- Save the previous center of mass for comparison
    STATE.tracking.group.lastCenterOfMass.x = STATE.tracking.group.centerOfMass.x
    STATE.tracking.group.lastCenterOfMass.y = STATE.tracking.group.centerOfMass.y
    STATE.tracking.group.lastCenterOfMass.z = STATE.tracking.group.centerOfMass.z

    -- Calculate new center of mass if we have valid units
    if validUnits > 0 and totalWeight > 0 then
        STATE.tracking.group.centerOfMass.x = weightedX / totalWeight
        STATE.tracking.group.centerOfMass.y = weightedY / totalWeight
        STATE.tracking.group.centerOfMass.z = weightedZ / totalWeight
        STATE.tracking.group.totalWeight = totalWeight

        -- Check if center of mass has significantly changed
        local dx = STATE.tracking.group.centerOfMass.x - STATE.tracking.group.lastCenterOfMass.x
        local dy = STATE.tracking.group.centerOfMass.y - STATE.tracking.group.lastCenterOfMass.y
        local dz = STATE.tracking.group.centerOfMass.z - STATE.tracking.group.lastCenterOfMass.z
        local distSquared = dx*dx + dy*dy + dz*dz

        -- Consider it changed if moved more than 10 units
        STATE.tracking.group.centerChanged = distSquared > 100
    else
        -- No valid units, use the map center as fallback
        STATE.tracking.group.centerOfMass.x = Game.mapSizeX / 2
        STATE.tracking.group.centerOfMass.y = 0
        STATE.tracking.group.centerOfMass.z = Game.mapSizeZ / 2
        STATE.tracking.group.totalWeight = 0
        STATE.tracking.group.centerChanged = true
    end
end

--- Calculates the radius of the group (max distance from center to any unit)
function GroupTrackingCamera.calculateGroupRadius()
    local units = STATE.tracking.group.unitIDs
    local center = STATE.tracking.group.centerOfMass
    local maxDistSquared = 0
    local validUnits = 0

    for _, unitID in ipairs(units) do
        -- Only consider valid units that aren't outliers
        if Spring.ValidUnitID(unitID) and not STATE.tracking.group.outliers[unitID] then
            local x, y, z = Spring.GetUnitPosition(unitID)
            local dx = x - center.x
            local dy = y - center.y
            local dz = z - center.z
            local distSquared = dx*dx + dy*dy + dz*dz

            if distSquared > maxDistSquared then
                maxDistSquared = distSquared
            end

            validUnits = validUnits + 1
        end
    end

    -- Calculate radius (square root of max squared distance)
    STATE.tracking.group.radius = math.sqrt(maxDistSquared)

    -- If no valid units, default to a small radius
    if validUnits == 0 then
        STATE.tracking.group.radius = 100
    end
end

--- Detects and marks outlier units that are too far from the center
function GroupTrackingCamera.detectOutliers()
    local now = Spring.GetGameSeconds()

    -- Only check for outliers periodically (every 0.5 seconds) to avoid performance impact
    if now - STATE.tracking.group.lastOutlierCheck < 0.5 then
        return
    end

    STATE.tracking.group.lastOutlierCheck = now

    local units = STATE.tracking.group.unitIDs
    local center = STATE.tracking.group.centerOfMass
    local radius = STATE.tracking.group.radius
    local cutoffDistance = radius * CONFIG.CAMERA_MODES.GROUP_TRACKING.OUTLIER_CUTOFF_FACTOR
    local previousOutliers = Util.deepCopy(STATE.tracking.group.outliers)
    local newOutliers = {}
    local changed = false

    -- Find units that are too far from center
    for _, unitID in ipairs(units) do
        if Spring.ValidUnitID(unitID) then
            local x, y, z = Spring.GetUnitPosition(unitID)
            local dx = x - center.x
            local dy = y - center.y
            local dz = z - center.z
            local distance = math.sqrt(dx*dx + dy*dy + dz*dz)

            if distance > cutoffDistance then
                newOutliers[unitID] = true

                -- Check if this is a new outlier
                if not previousOutliers[unitID] then
                    changed = true
                end
            else
                -- Check if this was previously an outlier
                if previousOutliers[unitID] then
                    changed = true
                end
            end
        end
    end

    -- Update outliers if changed
    if changed then
        STATE.tracking.group.outliers = newOutliers

        -- Recalculate center of mass and radius without outliers
        GroupTrackingCamera.calculateCenterOfMass()
        GroupTrackingCamera.calculateGroupRadius()

        Util.debugEcho(string.format("Updated outliers: %d units excluded from tracking",
                Util.tableCount(newOutliers)))
    end
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
    local distance = math.sqrt(dx*dx + dz*dz)

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
end

--- Updates tracking camera to point at the group center of mass
function GroupTrackingCamera.update()
    if STATE.tracking.mode ~= 'group_tracking' then
        return
    end

    -- Check if we have any units to track
    if #STATE.tracking.group.unitIDs == 0 then
        Util.debugEcho("No units to track, disabling Group Tracking Camera")
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
        Util.debugEcho("All tracked units lost, disabling Group Tracking Camera")
        Util.disableTracking()
        return
    end

    -- Detect outliers (units too far from the group)
    GroupTrackingCamera.detectOutliers()

    -- Update center of mass
    GroupTrackingCamera.calculateCenterOfMass()

    -- Update group radius
    GroupTrackingCamera.calculateGroupRadius()

    -- Calculate required camera distance
    local targetDistance = GroupTrackingCamera.calculateRequiredDistance()

    -- Check if we're still in FPS mode
    local currentState = Spring.GetCameraState()
    if currentState.mode ~= 0 then
        -- Force back to FPS mode
        currentState.mode = 0
        currentState.name = "fps"
        Spring.SetCameraState(currentState, 0)
    end

    -- Get current camera position
    local camPos = { x = currentState.px, y = currentState.py, z = currentState.pz }

    -- Get center of mass
    local center = STATE.tracking.group.centerOfMass

    -- Calculate direction from camera to center
    local dx = center.x - camPos.x
    local dy = center.y - camPos.y
    local dz = center.z - camPos.z
    local currentDistance = math.sqrt(dx*dx + dy*dy + dz*dz)

    -- Determine camera height
    local targetHeight = center.y + (targetDistance * CONFIG.CAMERA_MODES.GROUP_TRACKING.DEFAULT_HEIGHT_FACTOR)

    -- Normalize direction vector
    if currentDistance > 0 then
        dx = dx / currentDistance
        dz = dz / currentDistance
    else
        -- Default direction if distance is too small
        dx = 1
        dz = 0
    end

    -- Calculate smoothing factor based on whether we're in a mode transition
    local posFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.POSITION_SMOOTHING
    local rotFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.ROTATION_SMOOTHING

    if STATE.tracking.modeTransition then
        -- Use a special transition factor during mode changes
        posFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR
        rotFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR

        -- Check if we should end the transition
        if CameraCommons.isTransitionComplete(STATE.tracking.transitionStartTime) then
            STATE.tracking.modeTransition = false
        end
    end

    -- Calculate new camera position with configurable backward offset
    local backwardFactor = CONFIG.CAMERA_MODES.GROUP_TRACKING.BACKWARD_FACTOR
    local newCamPos = {
        x = center.x - (dx * targetDistance * backwardFactor),
        y = targetHeight,
        z = center.z - (dz * targetDistance * backwardFactor)
    }

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

        -- Smooth direction vector
        dx = Util.smoothStep(STATE.tracking.lastCamDir.x, lookDir.dx, posFactor),
        dy = Util.smoothStep(STATE.tracking.lastCamDir.y, lookDir.dy, posFactor),
        dz = Util.smoothStep(STATE.tracking.lastCamDir.z, lookDir.dz, posFactor),

        -- Smooth rotations
        rx = Util.smoothStep(STATE.tracking.lastRotation.rx, lookDir.rx, rotFactor),
        ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, lookDir.ry, rotFactor),
        rz = 0
    }

    -- Update last values
    STATE.tracking.lastCamPos.x = camStatePatch.px
    STATE.tracking.lastCamPos.y = camStatePatch.py
    STATE.tracking.lastCamPos.z = camStatePatch.pz
    STATE.tracking.lastCamDir.x = camStatePatch.dx
    STATE.tracking.lastCamDir.y = camStatePatch.dy
    STATE.tracking.lastCamDir.z = camStatePatch.dz
    STATE.tracking.lastRotation.rx = camStatePatch.rx
    STATE.tracking.lastRotation.ry = camStatePatch.ry

    -- Apply camera state
    Spring.SetCameraState(camStatePatch, 0)
end

--- Adds a utility function to count table entries including non-numeric keys
---@param t table The table to count entries in
---@return number count The number of entries in the table
function Util.tableCount(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

return {
    GroupTrackingCamera = GroupTrackingCamera
}