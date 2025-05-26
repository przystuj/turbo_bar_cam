---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log
---@type Util
local Util = VFS.Include("LuaUI/TurboBarCam/common/utils.lua").Util
---@type CameraCommons
local CameraCommons = VFS.Include("LuaUI/TurboBarCam/common/camera_commons.lua").CameraCommons

local STATE = WidgetContext.STATE

---@class CameraManager
local CameraManager = {}

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

--- Calculates the shortest difference between two angles (handles wrapping).
--- Assumes CameraCommons exists and we can add this helper or it has one.
--- If not, we define it here or in camera_commons.lua.
local function getAngleDiff(a1, a2)
    local diff = a2 - a1
    while diff > math.pi do diff = diff - 2 * math.pi end
    while diff < -math.pi do diff = diff + 2 * math.pi end
    return diff
end

function CameraManager.updateVelocityTracking()
    local currentState = Spring.GetCameraState()
    local velocityState = STATE.cameraVelocity
    local currentTime = Spring.GetTimer()

    local pos = { x = currentState.px, y = currentState.py, z = currentState.pz }
    local rot = { x = currentState.rx, y = currentState.ry, z = currentState.rz }

    if velocityState.lastUpdateTime then
        local dt = Spring.DiffTimers(currentTime, velocityState.lastUpdateTime)
        if dt > 0.001 then -- Avoid division by zero
            table.insert(velocityState.positionHistory, 1, { pos = pos, time = currentTime })
            table.insert(velocityState.rotationHistory, 1, { rot = rot, time = currentTime })

            -- Trim history
            if #velocityState.positionHistory > velocityState.maxHistorySize then
                table.remove(velocityState.positionHistory)
            end
            if #velocityState.rotationHistory > velocityState.maxHistorySize then
                table.remove(velocityState.rotationHistory)
            end

            -- Calculate average velocity (using oldest and newest for simplicity, can be improved)
            if #velocityState.positionHistory > 1 then
                local oldestPos = velocityState.positionHistory[#velocityState.positionHistory]
                local oldestRot = velocityState.rotationHistory[#velocityState.rotationHistory] -- ADDED
                local totalDt = Spring.DiffTimers(currentTime, oldestPos.time)

                if totalDt > 0.01 then -- Ensure enough time passed
                    velocityState.currentVelocity = {
                        x = (pos.x - oldestPos.pos.x) / totalDt,
                        y = (pos.y - oldestPos.pos.y) / totalDt,
                        z = (pos.z - oldestPos.pos.z) / totalDt,
                    }
                    -- ADDED: Calculate rotational velocity
                    velocityState.currentRotationalVelocity = {
                        x = getAngleDiff(oldestRot.rot.x, rot.x) / totalDt,
                        y = getAngleDiff(oldestRot.rot.y, rot.y) / totalDt,
                        z = getAngleDiff(oldestRot.rot.z, rot.z) / totalDt,
                    }
                end
            end
        end
    else
        -- Initialize history on first run
        table.insert(velocityState.positionHistory, 1, { pos = pos, time = currentTime })
        table.insert(velocityState.rotationHistory, 1, { rot = rot, time = currentTime }) -- ADDED
    end

    velocityState.lastUpdateTime = currentTime
    STATE.cameraVelocity.lastPosition = pos
    STATE.cameraVelocity.lastRotation = rot -- ADDED
end

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
    local rotVel = STATE.cameraVelocity.currentRotationalVelocity
    local magnitude = CameraCommons.vectorMagnitude(vel)
    local rotMagnitude = CameraCommons.vectorMagnitude(rotVel)
    return vel, magnitude, rotVel, rotMagnitude
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

--- Predicts camera state based on current state, velocity, and decay.
---@param currentState table Current camera state {px, py, pz, rx, ry, rz}
---@param vel table Positional velocity {x, y, z}
---@param rotVel table Rotational velocity {rx, ry, rz}
---@param deltaTime number Time delta
---@param decayRate number Decay rate
---@return table predictedState Predicted camera state {px, py, pz, rx, ry, rz}
function CameraManager.predictState(currentState, vel, rotVel, deltaTime, decayRate)
    -- If no decay or dt is zero, return current state
    if decayRate <= 0 or deltaTime <= 0 then
        return Util.deepCopy(currentState) -- Return a copy
    end

    local decayFactorIntegral = (1 - math.exp(-decayRate * deltaTime)) / decayRate

    local predictedState = {
        px = currentState.px + vel.x * decayFactorIntegral,
        py = currentState.py + vel.y * decayFactorIntegral,
        pz = currentState.pz + vel.z * decayFactorIntegral,
        rx = currentState.rx + rotVel.x * decayFactorIntegral,
        ry = CameraCommons.normalizeAngle(currentState.ry + rotVel.y * decayFactorIntegral),
        rz = currentState.rz + rotVel.z * decayFactorIntegral,
        fov = currentState.fov
    }

    return predictedState
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
    return Spring.GetCameraState()
end

function CameraManager.setCameraState(cameraState, smoothing, source)
    Spring.SetCameraState(cameraState, smoothing)
end

return  CameraManager
