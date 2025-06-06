---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local DollyCamPathPlanner = ModuleManager.DollyCamPathPlanner(function(m) DollyCamPathPlanner = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local CameraTracker = ModuleManager.CameraTracker(function(m) CameraTracker = m end)

---@class DollyCamNavigator
local DollyCamNavigator = {}

-- Start navigation on a route
---@return boolean success Whether navigation was started
function DollyCamNavigator.startNavigation(noCamera)
    if #STATE.dollyCam.route.points < 2 then
        Log:warn("Cannot start navigation: Route needs at least 2 waypoints")
        return false
    end

    -- Make sure the path is generated
    if #STATE.dollyCam.route.path == 0 then
        DollyCamPathPlanner.generateSmoothPath()
    end

    -- Set the active route and state
    STATE.dollyCam.isNavigating = true
    STATE.dollyCam.currentDistance = 0
    STATE.dollyCam.targetSpeed = 1
    STATE.dollyCam.currentSpeed = 0
    STATE.dollyCam.direction = 1
    STATE.dollyCam.noCamera = noCamera

    Log:info("[DollyCam] Started navigation")
    return true
end

-- Stop navigation
---@return boolean success Whether navigation was stopped
function DollyCamNavigator.stopNavigation()
    if not STATE.dollyCam.isNavigating then
        return
    end

    STATE.dollyCam.isNavigating = false
    STATE.dollyCam.targetSpeed = 0
    STATE.dollyCam.currentSpeed = 0
    STATE.dollyCam.direction = 1
    STATE.dollyCam.noCamera = false

    Log:info("[DollyCam] Stopped navigation")
end

-- Set the target speed for navigation
---@param speed number Target speed from 0 to 1.0
---@return boolean success Whether speed was set
function DollyCamNavigator.adjustSpeed(speed)
    if not STATE.dollyCam.isNavigating then
        Log:trace("Cannot set speed when not navigating")
        return false
    end

    local newSpeed = STATE.dollyCam.targetSpeed + tonumber(speed)

    -- Clamp speed to valid range
    newSpeed = math.max(0, math.min(1.0, newSpeed))

    STATE.dollyCam.targetSpeed = newSpeed

    Log:debug("Speed set to " .. newSpeed)
    return true
end

-- Set centripetal parameterization alpha value
---@param alpha number Alpha value (0.0-1.0)
---@return boolean success Whether alpha was set
function DollyCamNavigator.setAlpha(alpha)
    if alpha < 0.0 or alpha > 1.0 then
        Log:warn("Alpha value must be between 0.0 and 1.0")
        return false
    end

    -- Store the old value for logging
    local oldAlpha = STATE.dollyCam.alpha

    -- Set the new value
    STATE.dollyCam.alpha = alpha

    Log:info(string.format("Changed centripetal alpha from %.2f to %.2f", oldAlpha, alpha))

    if STATE.dollyCam.route then
        DollyCamPathPlanner.generateSmoothPath()
        Log:info("Regenerated path with new alpha value")
    end

    return true
end

local function createCameraState(position, direction)
    local camState = {}
    camState.px = position.x
    camState.py = position.y
    camState.pz = position.z

    if direction then
        camState.dx = direction.dx
        camState.dy = direction.dy
        camState.dz = direction.dz
        camState.rx = direction.rx
        camState.ry = direction.ry
        camState.rz = direction.rz
    end

    return camState
end

-- Update navigation state
---@param deltaTime number Time since last update in seconds
---@return boolean active Whether navigation is active
function DollyCamNavigator.update(deltaTime)
    if not STATE.dollyCam.isNavigating then
        return
    end

    if not STATE.dollyCam.route then
        Log:warn("Active route not found, stopping navigation")
        DollyCamNavigator.stopNavigation()
        return
    end

    -- Smooth acceleration toward target speed
    local speedDiff = (STATE.dollyCam.targetSpeed * STATE.dollyCam.direction) - STATE.dollyCam.currentSpeed
    local accelStep = (STATE.dollyCam.acceleration * deltaTime) / STATE.dollyCam.maxSpeed

    if math.abs(speedDiff) <= accelStep then
        STATE.dollyCam.currentSpeed = STATE.dollyCam.targetSpeed * STATE.dollyCam.direction
    else
        STATE.dollyCam.currentSpeed = STATE.dollyCam.currentSpeed +
                accelStep * (speedDiff > 0 and 1 or -1)
    end

    -- Calculate distance to move
    local distanceChange = STATE.dollyCam.currentSpeed * STATE.dollyCam.maxSpeed * deltaTime

    -- Previous distance for waypoint detection
    local prevDistance = STATE.dollyCam.currentDistance

    -- Update position along the path
    STATE.dollyCam.currentDistance = STATE.dollyCam.currentDistance + distanceChange

    -- Handle boundaries
    if STATE.dollyCam.currentDistance < 0 then
        STATE.dollyCam.currentDistance = 0
        STATE.dollyCam.currentSpeed = 0
    elseif STATE.dollyCam.currentDistance > STATE.dollyCam.route.totalDistance then
        STATE.dollyCam.currentDistance = STATE.dollyCam.route.totalDistance
        STATE.dollyCam.currentSpeed = 0
    end

    -- Check if we passed any waypoints and apply their properties
    DollyCamNavigator.checkWaypointsPassed(prevDistance, STATE.dollyCam.currentDistance)

    -- Get position at current distance
    local positionData = DollyCamPathPlanner.getPositionAtDistance(STATE.dollyCam.currentDistance)
    if not positionData then
        Log:debug("positionData is missing")
        return -- Continue navigation even if position retrieval fails
    end

    -- Prepare camera state update
    local camState = {
        x = positionData.x,
        y = positionData.y,
        z = positionData.z
    }

    -- Apply lookAt if active
    local directionState
    if STATE.dollyCam.activeLookAt then
        local lookAtPos = nil

        if STATE.dollyCam.activeLookAt.unitID then
            -- Get unit position for lookAt
            if Spring.ValidUnitID(STATE.dollyCam.activeLookAt.unitID) then
                local x, y, z = Spring.GetUnitPosition(STATE.dollyCam.activeLookAt.unitID)
                lookAtPos = { x = x, y = y, z = z }
            end
        end

        if lookAtPos then
            directionState = CameraCommons.focusOnPoint(camState, lookAtPos, CONFIG.MODE_TRANSITION_SMOOTHING, CONFIG.MODE_TRANSITION_SMOOTHING)
            directionState.px, directionState.py, directionState.pz = nil, nil, nil
        end
    end

    if STATE.dollyCam.noCamera then
        return
    end

    camState = createCameraState(camState, directionState)
    CameraTracker.updateLastKnownCameraState(camState)
    Spring.SetCameraState(camState, 0)
end

function DollyCamNavigator.checkWaypointsPassed(prevDistance, currentDistance)
    -- Skip if no route
    if not STATE.dollyCam.route or not STATE.dollyCam.route.points then
        return
    end

    -- Calculate distances to each waypoint
    local waypointDistances = {}
    local cumulativeDistance = 0

    for i, segmentDist in ipairs(STATE.dollyCam.route.segmentDistances) do
        if i > 1 then
            cumulativeDistance = cumulativeDistance + segmentDist
            waypointDistances[i] = cumulativeDistance
        end
    end
    waypointDistances[1] = 0 -- First waypoint is at distance 0
    table.insert(waypointDistances, STATE.dollyCam.route.totalDistance) -- Last waypoint is at total distance

    -- Check each waypoint to see if we passed it
    for i, waypoint in ipairs(STATE.dollyCam.route.points) do
        local waypointDist = waypointDistances[i]

        -- Moving forward and passing a waypoint
        if STATE.dollyCam.direction > 0 and
                prevDistance < waypointDist and currentDistance >= waypointDist then
            DollyCamNavigator.applyWaypointProperties(i)
        end

        -- Moving backward and passing a waypoint
        if STATE.dollyCam.direction < 0 and
                prevDistance > waypointDist and currentDistance <= waypointDist then

            -- When moving backward, use the previous waypoint's speed (if available)
            if i > 1 then
                DollyCamNavigator.applyWaypointProperties(i - 1)
            end
        end
    end
end

function DollyCamNavigator.applyWaypointProperties(waypointIndex)
    local waypoint = STATE.dollyCam.route.points[waypointIndex]
    if not waypoint then
        return
    end

    -- Apply target speed if explicitly set (including default values marked as explicit)
    if waypoint.targetSpeed and waypoint.hasExplicitSpeed then
        STATE.dollyCam.targetSpeed = waypoint.targetSpeed
        -- Remember this speed for propagation
        STATE.dollyCam.lastExplicitSpeed = waypoint.targetSpeed
        Log:debug(string.format("Waypoint %d: Set explicit target speed to %.2f",
                waypointIndex, waypoint.targetSpeed))
    elseif STATE.dollyCam.lastExplicitSpeed then
        -- Apply propagated speed if no explicit speed is set at this waypoint
        STATE.dollyCam.targetSpeed = STATE.dollyCam.lastExplicitSpeed
        Log:debug(string.format("Waypoint %d: Using propagated speed %.2f",
                waypointIndex, STATE.dollyCam.lastExplicitSpeed))
    end

    -- Apply lookAt if defined
    if waypoint.hasLookAt then
        if waypoint.lookAtUnitID and Spring.ValidUnitID(waypoint.lookAtUnitID) then
            -- Setup unit tracking lookAt
            STATE.dollyCam.activeLookAt = {
                unitID = waypoint.lookAtUnitID,
                point = nil
            }
            -- Remember this lookAt for propagation
            STATE.dollyCam.lastExplicitLookAt = {
                unitID = waypoint.lookAtUnitID,
                point = nil
            }
            Log:debug(string.format("Waypoint %d: Set lookAt to track unit %d",
                    waypointIndex, waypoint.lookAtUnitID))
        elseif waypoint.lookAtPoint then
            -- Setup fixed point lookAt
            STATE.dollyCam.activeLookAt = {
                unitID = nil,
                point = waypoint.lookAtPoint
            }
            -- Remember this lookAt for propagation
            STATE.dollyCam.lastExplicitLookAt = {
                unitID = nil,
                point = {
                    x = waypoint.lookAtPoint.x,
                    y = waypoint.lookAtPoint.y,
                    z = waypoint.lookAtPoint.z
                }
            }
            Log:debug(string.format("Waypoint %d: Set lookAt to fixed point (%.1f, %.1f, %.1f)",
                    waypointIndex, waypoint.lookAtPoint.x, waypoint.lookAtPoint.y, waypoint.lookAtPoint.z))
        else
            -- Explicit reset of lookAt
            STATE.dollyCam.activeLookAt = nil
            STATE.dollyCam.lastExplicitLookAt = nil
            Log:debug(string.format("Waypoint %d: Reset lookAt properties", waypointIndex))
        end
    elseif STATE.dollyCam.lastExplicitLookAt then
        -- Apply propagated lookAt if no explicit lookAt is set at this waypoint
        STATE.dollyCam.activeLookAt = STATE.dollyCam.lastExplicitLookAt
        Log:debug(string.format("Waypoint %d: Using propagated lookAt", waypointIndex))
    end
end

return DollyCamNavigator
