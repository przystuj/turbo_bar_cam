---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)

---@class VelocityTracker
local VelocityTracker = {}

function VelocityTracker.update()
    if not STATE.cameraVelocity.initialized then
        STATE.cameraVelocity.isTracking = true
        STATE.cameraVelocity.initialized = true
        Log:trace("Camera velocity tracking initialized")
    end

    if STATE.cameraVelocity.isTracking then
        VelocityTracker.updateVelocityTracking()
    end
end

function VelocityTracker.updateVelocityTracking()
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
                local oldestRot = velocityState.rotationHistory[#velocityState.rotationHistory]
                local totalDt = Spring.DiffTimers(currentTime, oldestPos.time)

                if totalDt > 0.01 then -- Ensure enough time passed
                    velocityState.currentVelocity = {
                        x = (pos.x - oldestPos.pos.x) / totalDt,
                        y = (pos.y - oldestPos.pos.y) / totalDt,
                        z = (pos.z - oldestPos.pos.z) / totalDt,
                    }
                    velocityState.currentRotationalVelocity = {
                        x = CameraCommons.getAngleDiff(oldestRot.rot.x, rot.x) / totalDt,
                        y = CameraCommons.getAngleDiff(oldestRot.rot.y, rot.y) / totalDt,
                        z = CameraCommons.getAngleDiff(oldestRot.rot.z, rot.z) / totalDt,
                    }
                end
            end
        end
    else
        -- Initialize history on first run
        table.insert(velocityState.positionHistory, 1, { pos = pos, time = currentTime })
        table.insert(velocityState.rotationHistory, 1, { rot = rot, time = currentTime })
    end

    velocityState.lastUpdateTime = currentTime
    STATE.cameraVelocity.lastPosition = pos
    STATE.cameraVelocity.lastRotation = rot
end

function VelocityTracker.calculateVelocity()
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

function VelocityTracker.startVelocityTracking()
    STATE.cameraVelocity.isTracking = true
    Log:trace("Camera velocity tracking enabled")
end

function VelocityTracker.stopVelocityTracking()
    STATE.cameraVelocity.isTracking = false
    STATE.cameraVelocity.positionHistory = {}
    STATE.cameraVelocity.currentVelocity = {x = 0, y = 0, z = 0}
    Log:trace("Camera velocity tracking disabled")
end

function VelocityTracker.getCurrentVelocity()
    local vel = STATE.cameraVelocity.currentVelocity
    local rotVel = STATE.cameraVelocity.currentRotationalVelocity
    local magnitude = CameraCommons.vectorMagnitude(vel)
    local rotMagnitude = CameraCommons.vectorMagnitude(rotVel)
    return vel, magnitude, rotVel, rotMagnitude
end

function VelocityTracker.applyVelocityDecay(decayRate, deltaTime)
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
function VelocityTracker.predictState(currentState, vel, rotVel, deltaTime, decayRate)
    if decayRate <= 0 or deltaTime <= 0 then
        return TableUtils.deepCopy(currentState)
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

function VelocityTracker.hasSignificantVelocity(threshold)
    threshold = threshold or 10.0
    local _, magnitude = VelocityTracker.getCurrentVelocity()
    return magnitude > threshold
end

return  VelocityTracker
