---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type DollyCamPathPlanner
local DollyCamPathPlanner = VFS.Include("LuaUI/TurboBarCam/features/dollycam/dollycam_path_planner.lua").DollyCamPathPlanner

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE

---@class DollyCamNavigator
local DollyCamNavigator = {}

-- Start navigation on a route
---@return boolean success Whether navigation was started
function DollyCamNavigator.startNavigation(noCamera)
    STATE.dollyCam.route = STATE.dollyCam.route or { points = {} }

    if #STATE.dollyCam.route.points < 2 then
        Log.warn("Cannot start navigation: Route needs at least 2 waypoints")
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

    Log.info("[DollyCam] Started navigation")
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

    Log.info("[DollyCam] Stopped navigation")
end

-- Set the target speed for navigation
---@param speed number Target speed from 0 to 1.0
---@return boolean success Whether speed was set
function DollyCamNavigator.adjustSpeed(speed)
    if not STATE.dollyCam.isNavigating then
        Log.trace("Cannot set speed when not navigating")
        return false
    end

    local newSpeed = STATE.dollyCam.targetSpeed + tonumber(speed)

    -- Clamp speed to valid range
    newSpeed = math.max(0, math.min(1.0, newSpeed))

    STATE.dollyCam.targetSpeed = newSpeed

    Log.debug("Speed set to " .. newSpeed)
    return true
end

-- Set centripetal parameterization alpha value
---@param alpha number Alpha value (0.0-1.0)
---@return boolean success Whether alpha was set
function DollyCamNavigator.setAlpha(alpha)
    if alpha < 0.0 or alpha > 1.0 then
        Log.warn("Alpha value must be between 0.0 and 1.0")
        return false
    end

    -- Store the old value for logging
    local oldAlpha = STATE.dollyCam.alpha

    -- Set the new value
    STATE.dollyCam.alpha = alpha

    Log.info(string.format("Changed centripetal alpha from %.2f to %.2f", oldAlpha, alpha))

    if STATE.dollyCam.route then
        DollyCamPathPlanner.generateSmoothPath()
        Log.info("Regenerated path with new alpha value")
    end

    return true
end

-- Update navigation state
---@param deltaTime number Time since last update in seconds
---@return boolean active Whether navigation is active
function DollyCamNavigator.update(deltaTime)
    if not STATE.dollyCam.isNavigating then
        return
    end

    if not STATE.dollyCam.route then
        Log.warn("Active route not found, stopping navigation")
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
        Log.debug("positionData is missing")
        return -- Continue navigation even if position retrieval fails
    end

    -- Prepare camera state update
    local camState = {
        px = positionData.x,
        py = positionData.y,
        pz = positionData.z
    }

    -- Apply lookAt if active
    if STATE.dollyCam.activeLookAt then
        local lookAtPos = nil

        if STATE.dollyCam.activeLookAt.unitID then
            -- Get unit position for lookAt
            if Spring.ValidUnitID(STATE.dollyCam.activeLookAt.unitID) then
                local x, y, z = Spring.GetUnitPosition(STATE.dollyCam.activeLookAt.unitID)
                lookAtPos = { x = x, y = y, z = z }
            end
        elseif STATE.dollyCam.activeLookAt.point then
            -- Use fixed point
            lookAtPos = STATE.dollyCam.activeLookAt.point
        end

        if lookAtPos then
            -- Calculate direction to lookAt target
            local dx = lookAtPos.x - positionData.x
            local dy = lookAtPos.y - positionData.y
            local dz = lookAtPos.z - positionData.z

            -- Calculate rotation angles
            local dist = math.sqrt(dx * dx + dz * dz)
            local ry = math.atan2(dx, dz)
            local rx = -math.atan2(dy, dist)

            -- Apply to camera state
            camState.rx = rx
            camState.ry = ry
        end
    end

    if STATE.dollyCam.noCamera then
        return
    end
    CameraManager.setCameraState(camState, 0, "DollyCamNavigator.update")
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

    -- Apply target speed if defined
    if waypoint.targetSpeed then
        STATE.dollyCam.targetSpeed = waypoint.targetSpeed
        Log.debug(string.format("Waypoint %d: Set target speed to %.2f",
                waypointIndex, waypoint.targetSpeed))
    end

    -- Apply lookAt if defined
    if waypoint.hasLookAt then
        if waypoint.lookAtUnitID and Spring.ValidUnitID(waypoint.lookAtUnitID) then
            -- Setup unit tracking lookAt
            STATE.dollyCam.activeLookAt = {
                unitID = waypoint.lookAtUnitID,
                point = nil
            }
            Log.debug(string.format("Waypoint %d: Set lookAt to track unit %d",
                    waypointIndex, waypoint.lookAtUnitID))
        elseif waypoint.lookAtPoint then
            -- Setup fixed point lookAt
            STATE.dollyCam.activeLookAt = {
                unitID = nil,
                point = waypoint.lookAtPoint
            }
            Log.debug(string.format("Waypoint %d: Set lookAt to fixed point (%.1f, %.1f, %.1f)",
                    waypointIndex, waypoint.lookAtPoint.x, waypoint.lookAtPoint.y, waypoint.lookAtPoint.z))
        end
    else
        -- Disable lookAt if waypoint doesn't have it
        STATE.dollyCam.activeLookAt = nil
    end
end

return {
    DollyCamNavigator = DollyCamNavigator
}
