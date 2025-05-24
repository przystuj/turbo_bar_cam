---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log
---@type Util
local Util = VFS.Include("LuaUI/TurboBarCam/common/utils.lua").Util
---@type CameraCommons -- Forward declaration for predictPosition usage if it were here
local CameraCommons = VFS.Include("LuaUI/TurboBarCam/common/camera_commons.lua").CameraCommons

local STATE = WidgetContext.STATE

---@class CameraManager
local CameraManager = {}

-- Initialize velocity tracking state
if not STATE.cameraVelocity then
    STATE.cameraVelocity = {
        positionHistory = {},
        maxHistorySize = 10,
        currentVelocity = {x=0, y=0, z=0},
        lastUpdateTime = nil,
        isTracking = false,
        initialized = false
    }
end

function CameraManager.update()
    if not STATE.cameraVelocity.initialized then
        STATE.cameraVelocity.isTracking = true
        STATE.cameraVelocity.initialized = true
        Log.trace("Camera velocity tracking initialized")
    end

    if STATE.cameraVelocity.isTracking then
        CameraManager.updateVelocityTracking()
    end
end

local function updateVelocityTracking()
    local currentState = Spring.GetCameraState()
    local velocityState = STATE.cameraVelocity
    local currentTime = Spring.GetTimer()

    local currentPos = {
        pos = {x = currentState.px, y = currentState.py, z = currentState.pz},
        time = currentTime
    }

    local isDuplicate = false
    if #velocityState.positionHistory > 0 then
        local lastEntry = velocityState.positionHistory[#velocityState.positionHistory]
        local timeDiff = Spring.DiffTimers(currentTime, lastEntry.time)

        -- Use CameraCommons for magnitude calculation if available and appropriate
        local posDiffVec = {
            x = currentPos.pos.x - lastEntry.pos.x,
            y = currentPos.pos.y - lastEntry.pos.y,
            z = currentPos.pos.z - lastEntry.pos.z
        }
        local posDiff = CameraCommons.vectorMagnitude(posDiffVec)


        if timeDiff < 0.01 and posDiff < 1.0 then
            isDuplicate = true
        end
    end

    if not isDuplicate then
        table.insert(velocityState.positionHistory, currentPos)
        while #velocityState.positionHistory > velocityState.maxHistorySize do
            table.remove(velocityState.positionHistory, 1)
        end
        if #velocityState.positionHistory >= 2 then
            CameraManager.calculateVelocity()
        end
        velocityState.lastUpdateTime = currentTime
    end
end
CameraManager.updateVelocityTracking = updateVelocityTracking

function CameraManager.calculateVelocity()
    local velocityState = STATE.cameraVelocity
    local history = velocityState.positionHistory

    if #history < 2 then
        velocityState.currentVelocity = {x = 0, y = 0, z = 0}
        return
    end

    local totalWeight = 0
    local weightedVelocity = {x = 0, y = 0, z = 0}

    for i = 2, #history do
        local prev = history[i - 1]
        local curr = history[i]
        local deltaTime = Spring.DiffTimers(curr.time, prev.time)

        if deltaTime > 0.001 then -- Avoid division by zero or tiny dt
            local weight = i / #history
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

function CameraManager.startVelocityTracking()
    STATE.cameraVelocity.isTracking = true
    Log.trace("Camera velocity tracking enabled")
end

function CameraManager.stopVelocityTracking()
    STATE.cameraVelocity.isTracking = false
    STATE.cameraVelocity.positionHistory = {}
    STATE.cameraVelocity.currentVelocity = {x = 0, y = 0, z = 0}
    Log.trace("Camera velocity tracking disabled")
end

function CameraManager.getCurrentVelocity()
    local vel = STATE.cameraVelocity.currentVelocity
    local magnitude = CameraCommons.vectorMagnitude(vel)
    return vel, magnitude
end

function CameraManager.applyVelocityDecay(decayRate, deltaTime)
    local velocityState = STATE.cameraVelocity
    local vel = velocityState.currentVelocity
    local decayFactor = math.exp(-decayRate * deltaTime)
    velocityState.currentVelocity = {
        x = vel.x * decayFactor,
        y = vel.y * decayFactor,
        z = vel.z * decayFactor
    }
    return velocityState.currentVelocity
end

--- Predicts future camera position based on a given velocity and decay.
--- This function is now more generic as it accepts the velocity to use.
---@param currentPos table Current camera position {x, y, z}
---@param velocity table Velocity to use for prediction {x, y, z}
---@param deltaTime number Time step for prediction
---@param decayRate number Rate of velocity decay
---@return table predictedPos Predicted position after deltaTime
function CameraManager.predictPosition(currentPos, velocity, deltaTime, decayRate)
    local vel = velocity -- Use the passed velocity

    local velMagnitude = CameraCommons.vectorMagnitude(vel)
    if velMagnitude < 0.1 then -- A small threshold to consider velocity negligible
        return Util.deepCopy(currentPos) -- Return a copy to avoid modifying original
    end

    -- If decayRate is effectively zero, perform linear prediction
    if decayRate <= 0.0001 then
        return {
            x = currentPos.x + vel.x * deltaTime,
            y = currentPos.y + vel.y * deltaTime,
            z = currentPos.z + vel.z * deltaTime,
        }
    end

    -- Calculate position with decaying velocity using the integral formula
    -- Integral of v*e^(-rt) dt = v*(1-e^(-rt))/r
    local decayFactorIntegral = (1.0 - math.exp(-decayRate * deltaTime)) / decayRate

    return {
        x = currentPos.x + vel.x * decayFactorIntegral,
        y = currentPos.y + vel.y * decayFactorIntegral,
        z = currentPos.z + vel.z * decayFactorIntegral
    }
end


function CameraManager.hasSignificantVelocity(threshold)
    threshold = threshold or 10.0
    local _, magnitude = CameraManager.getCurrentVelocity()
    return magnitude > threshold
end

function CameraManager.toggleZoom()
    if Util.isTurboBarCamDisabled() then
        return
    end
    local cycle = { [45] = 24, [24] = 12, [12] = 45 }
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

function CameraManager.getCameraState(source)
    assert(source, "Source parameter is required for getCameraState")
    return Spring.GetCameraState()
end

function CameraManager.setCameraState(cameraState, smoothing, source)
    assert(source, "Source parameter is required for setCameraState")
    Spring.SetCameraState(cameraState, smoothing)
end

return  CameraManager
