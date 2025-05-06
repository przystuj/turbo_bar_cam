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
function DollyCamNavigator.startNavigation()
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
    STATE.dollyCam.targetSpeed = 0.2
    STATE.dollyCam.currentSpeed = 0

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

    Log.info("[DollyCam] Stopped navigation")
end

-- Set the target speed for navigation
---@param speed number Target speed from -1.0 (full reverse) to 1.0 (full forward)
---@return boolean success Whether speed was set
function DollyCamNavigator.adjustSpeed(speed)
    if not STATE.dollyCam.isNavigating then
        Log.debug("Cannot set speed when not navigating")
        return false
    end

    local newSpeed = STATE.dollyCam.targetSpeed + tonumber(speed)

    -- Clamp speed to valid range
    newSpeed = math.max(-1.0, math.min(1.0, newSpeed))

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
    local speedDiff = STATE.dollyCam.targetSpeed - STATE.dollyCam.currentSpeed
    local accelStep = (STATE.dollyCam.acceleration * deltaTime) / STATE.dollyCam.maxSpeed

    if math.abs(speedDiff) <= accelStep then
        STATE.dollyCam.currentSpeed = STATE.dollyCam.targetSpeed
    else
        STATE.dollyCam.currentSpeed = STATE.dollyCam.currentSpeed +
                accelStep * (speedDiff > 0 and 1 or -1)
    end

    -- Calculate distance to move
    local distanceChange = STATE.dollyCam.currentSpeed * STATE.dollyCam.maxSpeed * deltaTime

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

    CameraManager.setCameraState(camState, 0, "DollyCamNavigator.update")
end

return {
    DollyCamNavigator = DollyCamNavigator
}
