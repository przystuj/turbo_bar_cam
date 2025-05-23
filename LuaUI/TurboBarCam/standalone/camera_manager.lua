---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log
---@type Util
local Util = VFS.Include("LuaUI/TurboBarCam/common/utils.lua").Util

local STATE = WidgetContext.STATE

---@class CameraManager
local CameraManager = {}

-- Initialize velocity tracking state
-- Velocity tracking is managed internally by CameraManager for continuous monitoring
if not STATE.cameraVelocity then
    STATE.cameraVelocity = {
        positionHistory = {}, -- Array of {pos={x,y,z}, time=timer}
        maxHistorySize = 10,  -- Keep last 10 positions
        currentVelocity = {x=0, y=0, z=0},
        lastUpdateTime = nil,
        isTracking = false,
        initialized = false
    }
end

--- Updates velocity tracking by monitoring camera position changes
--- Called every frame to maintain continuous velocity data
function CameraManager.update()
    -- Initialize velocity tracking once
    if not STATE.cameraVelocity.initialized then
        STATE.cameraVelocity.isTracking = true
        STATE.cameraVelocity.initialized = true
        Log.trace("Camera velocity tracking initialized")
    end

    -- Monitor current camera position for velocity calculation
    if STATE.cameraVelocity.isTracking then
        CameraManager.updateVelocityTracking()
    end
end

--- Internal function to update velocity tracking by monitoring camera state
local function updateVelocityTracking()
    -- Get current camera state directly from Spring (bypasses our own setCameraState)
    local currentState = Spring.GetCameraState()

    local velocityState = STATE.cameraVelocity
    local currentTime = Spring.GetTimer()

    -- Create position record
    local currentPos = {
        pos = {x = currentState.px, y = currentState.py, z = currentState.pz},
        time = currentTime
    }

    -- Check if this is a new position (avoid duplicate entries)
    local isDuplicate = false
    if #velocityState.positionHistory > 0 then
        local lastEntry = velocityState.positionHistory[#velocityState.positionHistory]
        local timeDiff = Spring.DiffTimers(currentTime, lastEntry.time)
        local posDiff = math.sqrt(
                (currentPos.pos.x - lastEntry.pos.x)^2 +
                        (currentPos.pos.y - lastEntry.pos.y)^2 +
                        (currentPos.pos.z - lastEntry.pos.z)^2
        )

        -- Only update if enough time passed or position changed significantly
        if timeDiff < 0.01 and posDiff < 1.0 then
            isDuplicate = true
        end
    end

    if not isDuplicate then
        -- Add new position to history
        table.insert(velocityState.positionHistory, currentPos)

        -- Remove old entries
        while #velocityState.positionHistory > velocityState.maxHistorySize do
            table.remove(velocityState.positionHistory, 1)
        end

        -- Calculate velocity if we have enough data
        if #velocityState.positionHistory >= 2 then
            CameraManager.calculateVelocity()
        end

        velocityState.lastUpdateTime = currentTime
    end
end

--- Make the internal function accessible
CameraManager.updateVelocityTracking = updateVelocityTracking

--- Calculates current velocity based on recent position history
function CameraManager.calculateVelocity()
    local velocityState = STATE.cameraVelocity
    local history = velocityState.positionHistory

    if #history < 2 then
        velocityState.currentVelocity = {x = 0, y = 0, z = 0}
        return
    end

    -- Use weighted average of recent movements for smoother velocity
    local totalWeight = 0
    local weightedVelocity = {x = 0, y = 0, z = 0}

    -- Calculate velocity from recent position pairs, giving more weight to recent movements
    for i = 2, #history do
        local prev = history[i - 1]
        local curr = history[i]
        local deltaTime = Spring.DiffTimers(curr.time, prev.time)

        if deltaTime > 0 then
            local weight = i / #history  -- More recent = higher weight
            local velocity = {
                x = (curr.pos.x - prev.pos.x) / deltaTime,
                y = (curr.pos.y - prev.pos.y) / deltaTime,
                z = (curr.pos.z - prev.pos.z) / deltaTime
            }

            weightedVelocity.x = weightedVelocity.x + (velocity.x * weight)
            weightedVelocity.y = weightedVelocity.y + (velocity.y * weight)
            weightedVelocity.z = weightedVelocity.z + (velocity.z * weight)
            totalWeight = totalWeight + weight
        end
    end

    -- Normalize by total weight
    if totalWeight > 0 then
        velocityState.currentVelocity = {
            x = weightedVelocity.x / totalWeight,
            y = weightedVelocity.y / totalWeight,
            z = weightedVelocity.z / totalWeight
        }
    else
        velocityState.currentVelocity = {x = 0, y = 0, z = 0}
    end
end

--- Starts velocity tracking (for backwards compatibility - now automatic)
function CameraManager.startVelocityTracking()
    STATE.cameraVelocity.isTracking = true
    Log.trace("Camera velocity tracking enabled")
end

--- Stops velocity tracking and clears history
function CameraManager.stopVelocityTracking()
    STATE.cameraVelocity.isTracking = false
    STATE.cameraVelocity.positionHistory = {}
    STATE.cameraVelocity.currentVelocity = {x = 0, y = 0, z = 0}
    Log.trace("Camera velocity tracking disabled")
end

--- Gets the current camera velocity
---@return table velocity Current velocity {x, y, z}
---@return number magnitude Velocity magnitude
function CameraManager.getCurrentVelocity()
    local vel = STATE.cameraVelocity.currentVelocity
    local magnitude = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
    return vel, magnitude
end

--- Applies deceleration to current velocity over time
---@param decayRate number Rate of velocity decay (higher = faster decay)
---@param deltaTime number Time elapsed since last update
---@return table decayedVelocity New velocity after decay
function CameraManager.applyVelocityDecay(decayRate, deltaTime)
    local velocityState = STATE.cameraVelocity
    local vel = velocityState.currentVelocity

    -- Apply exponential decay
    local decayFactor = math.exp(-decayRate * deltaTime)

    velocityState.currentVelocity = {
        x = vel.x * decayFactor,
        y = vel.y * decayFactor,
        z = vel.z * decayFactor
    }

    return velocityState.currentVelocity
end

--- Predicts future camera position based on current velocity and decay
---@param currentPos table Current camera position {x, y, z}
---@param deltaTime number Time step for prediction
---@param decayRate number Rate of velocity decay
---@return table predictedPos Predicted position after deltaTime
function CameraManager.predictPosition(currentPos, deltaTime, decayRate)
    local vel = STATE.cameraVelocity.currentVelocity

    -- If velocity is negligible, return current position
    local velMagnitude = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
    if velMagnitude < 1.0 then
        return currentPos
    end

    -- Calculate position with decaying velocity
    -- For exponential decay: integral of v*e^(-rt) dt = v*(1-e^(-rt))/r
    local decayFactor = 1.0 - math.exp(-decayRate * deltaTime)
    local velocityIntegral = decayFactor / decayRate

    return {
        x = currentPos.x + vel.x * velocityIntegral,
        y = currentPos.y + vel.y * velocityIntegral,
        z = currentPos.z + vel.z * velocityIntegral
    }
end

--- Checks if camera has significant velocity
---@param threshold number Minimum velocity magnitude to consider significant
---@return boolean hasVelocity Whether camera has significant velocity
function CameraManager.hasSignificantVelocity(threshold)
    threshold = threshold or 10.0
    local _, magnitude = CameraManager.getCurrentVelocity()
    return magnitude > threshold
end

function CameraManager.toggleZoom()
    if Util.isTurboBarCamDisabled() then
        return
    end

    local cycle = {
        [45] = 24,
        [24] = 12,
        [12] = 45
    }
    local camState = CameraManager.getCameraState("WidgetControl.toggleZoom")
    local fov = cycle[camState.fov] or 45
    CameraManager.setCameraState({fov = fov}, 1, "WidgetControl.toggleZoom")
end

function CameraManager.setFov(fov)
    if Util.isTurboBarCamDisabled() then
        return
    end

    local camState = CameraManager.getCameraState("WidgetControl.setFov")
    if camState.fov == fov then
        return
    end
    CameraManager.setCameraState({fov = fov}, 1, "WidgetControl.setFov")
end

--- Get the current camera state (with time-based cache)
---@param source string Source of the getCameraState call for tracking
---@return table cameraState The current camera state
function CameraManager.getCameraState(source)
    assert(source, "Source parameter is required for getCameraState")
    return Spring.GetCameraState()
end

--- Apply camera state with optional smoothing
---@param cameraState table Camera state to apply
---@param smoothing number Smoothing factor (0 for no smoothing, 1 for full smoothing)
---@param source string Source of the setCameraState call for tracking
function CameraManager.setCameraState(cameraState, smoothing, source)
    assert(source, "Source parameter is required for setCameraState")

    -- Apply the camera state
    -- Note: Velocity tracking is handled by the update() method monitoring Spring.GetCameraState()
    Spring.SetCameraState(cameraState, smoothing)
end

return {
    CameraManager = CameraManager
}