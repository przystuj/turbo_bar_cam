---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local CameraStateTracker = ModuleManager.CameraStateTracker(function(m) CameraStateTracker = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local QuaternionUtils = ModuleManager.QuaternionUtils(function(m) QuaternionUtils = m end)
local MathUtils = ModuleManager.MathUtils(function(m) MathUtils = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "CameraDriver")

---@class CameraDriver
local CameraDriver = {}

local DEFAULT_SMOOTH_TIME = 0.3

--- Sets the camera's declarative target state and seeds the simulation.
---@param targetConfig table Configuration for the target state.
function CameraDriver.setTarget(targetConfig)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    local target = STATE.active.driver.target
    local sim = STATE.active.driver.simulation
    local wasAlreadyActive = (target and target.position ~= nil)

    -- Set the main target values
    target.position = targetConfig.position
    target.lookAt = targetConfig.lookAt
    target.euler = targetConfig.euler
    target.smoothTimePos = targetConfig.smoothTimePos or DEFAULT_SMOOTH_TIME
    target.smoothTimeRot = targetConfig.smoothTimeRot or target.smoothTimePos

    if targetConfig.isForcedSmoothing then
        -- This is a FORCED override. Set the forced values and complete any running transition.
        sim.forcedSmoothingPos = target.smoothTimePos
        sim.forcedSmoothingRot = target.smoothTimeRot
        sim.smoothTimeTransitionStart = nil
    else
        -- This is a NORMAL move. Clear any forced values and set up a gradual transition.
        sim.forcedSmoothingPos = nil
        sim.forcedSmoothingRot = nil

        sim.sourceSmoothTimePos = sim.currentSmoothTimePos
        sim.sourceSmoothTimeRot = sim.currentSmoothTimeRot
        sim.smoothTimeTransitionStart = Spring.GetTimer()
    end

    if not wasAlreadyActive then
        sim.position = TableUtils.deepCopy(CameraStateTracker.getPosition())
        sim.orientation = TableUtils.deepCopy(CameraStateTracker.getOrientation())
        sim.velocity = TableUtils.deepCopy(CameraStateTracker.getVelocity() or { x = 0, y = 0, z = 0 })
        sim.angularVelocity = TableUtils.deepCopy(CameraStateTracker.getAngularVelocity() or { x = 0, y = 0, z = 0 })
    end

    local ROTATION_ONLY_THRESHOLD_SQ = 1.0
    if targetConfig.position and sim.position then
        local distSq = MathUtils.vector.distanceSq(sim.position, targetConfig.position)
        sim.isRotationOnly = (distSq < ROTATION_ONLY_THRESHOLD_SQ)
    else
        sim.isRotationOnly = not targetConfig.position
    end
end

--- Determines the correct smoothing values to use for the current frame.
local function getLiveSmoothTimes()
    local sim = STATE.active.driver.simulation

    -- If a forced smoothing override is active, use it immediately and bypass transitions.
    if sim.forcedSmoothingPos then
        return sim.forcedSmoothingPos, sim.forcedSmoothingRot
    end
    -- Otherwise, perform the gradual transition logic.
    local target = STATE.active.driver.target
    if not sim.smoothTimeTransitionStart then
        -- No transition active, just use the target values.
        sim.currentSmoothTimePos = target.smoothTimePos
        sim.currentSmoothTimeRot = target.smoothTimeRot
    else
        -- Interpolate during an active transition.
        local elapsed = Spring.DiffTimers(Spring.GetTimer(), sim.smoothTimeTransitionStart)
        local alpha = math.min(1.0, sim.smoothTimeTransitionDuration and (elapsed / sim.smoothTimeTransitionDuration) or 1.0)

        sim.currentSmoothTimePos = sim.sourceSmoothTimePos * (1.0 - alpha) + target.smoothTimePos * alpha
        sim.currentSmoothTimeRot = sim.sourceSmoothTimeRot * (1.0 - alpha) + target.smoothTimeRot * alpha

        if alpha >= 1.0 then
            sim.smoothTimeTransitionStart = nil
        end
    end

    return sim.currentSmoothTimePos, sim.currentSmoothTimeRot
end

--- Helper function to resolve the lookAt target to a concrete point
local function getLookAtPoint(target)
    if not target then return nil end
    if target.type == "point" then
        return target.data
    elseif target.type == "unit" and Spring.ValidUnitID(target.data) then
        local x, y, z = Spring.GetUnitPosition(target.data)
        if x then return { x = x, y = y, z = z } end
    end
    return nil
end

--- Updates the position of the camera simulation via smooth damping.
local function updatePosition(dt, liveSmoothTimePos)
    local target = STATE.active.driver.target
    local simState = STATE.active.driver.simulation
    if not target.position or simState.isRotationOnly then return end

    local newPosition, newVelocity = MathUtils.vectorSmoothDamp(simState.position, target.position, simState.velocity, liveSmoothTimePos, dt)
    simState.position = newPosition
    simState.velocity = newVelocity
end

--- Determines the target orientation and updates the simulation via smooth damping.
local function updateOrientation(dt, liveSmoothTimeRot)
    local target = STATE.active.driver.target
    local simState = STATE.active.driver.simulation
    local finalTargetOrientation
    if target.lookAt then
        local lookAtPoint = getLookAtPoint(target.lookAt)
        if lookAtPoint then
            local dirState = CameraCommons.calculateCameraDirectionToThePoint(simState.position, lookAtPoint)
            finalTargetOrientation = QuaternionUtils.fromEuler(dirState.rx, dirState.ry)
        end
    elseif target.euler then
        finalTargetOrientation = QuaternionUtils.fromEuler(target.euler.rx, target.euler.ry)
    end

    if finalTargetOrientation then
        local newOrientation, newAngularVelocity = QuaternionUtils.quaternionSmoothDamp(simState.orientation, finalTargetOrientation, simState.angularVelocity, liveSmoothTimeRot, dt)
        simState.orientation = newOrientation
        simState.angularVelocity = newAngularVelocity
    end
end

--- Checks if the movement has reached its target and resets the driver if complete.
local function checkAndCompleteTask()
    local target = STATE.active.driver.target

    -- if lookAt target is active, the driver should never complete on its own.
    if target.lookAt then
        return
    end

    if not target.position and not target.euler then
        return
    end

    local simState = STATE.active.driver.simulation

    local POS_EPSILON_SQ = 0.01
    local VEL_EPSILON_SQ = 0.01
    local ANG_VEL_EPSILON_SQ = 0.0001

    if target.euler then
        if MathUtils.vector.magnitudeSq(simState.angularVelocity) >= ANG_VEL_EPSILON_SQ then
            return -- Not complete yet
        end
    end

    if target.position then
        if simState.isRotationOnly then
            -- For rotation-only moves, positional completion is assumed.
        else
            local distSq = MathUtils.vector.distanceSq(simState.position, target.position)
            local velSq = MathUtils.vector.magnitudeSq(simState.velocity)
            if distSq >= POS_EPSILON_SQ or velSq >= VEL_EPSILON_SQ then
                return -- Not complete yet
            end
        end
    end

    Log:debug("Driver task completed")
    STATE.active.driver.target = TableUtils.deepCopy(STATE.DEFAULT.active.driver.target)
end

--- Applies the final calculated simulation state to the in-game camera.
local function applySimulationToCamera()
    local simState = STATE.active.driver.simulation
    local rx, ry = QuaternionUtils.toEuler(simState.orientation)
    Spring.SetCameraState({
        px = simState.position.x, py = simState.position.y, pz = simState.position.z,
        rx = rx, ry = ry,
    })
end

--- The main update function, called every frame.
function CameraDriver.update(dt)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    -- Guard clauses for performance and safety
    local driverState = STATE.active.driver
    if not driverState or not driverState.target or dt <= 0 then
        return
    end
    if not driverState.target.position and not driverState.target.lookAt and not driverState.target.euler then
        return
    end

    -- Perform simulation updates
    local liveSmoothTimePos, liveSmoothTimeRot = getLiveSmoothTimes()
    updatePosition(dt, liveSmoothTimePos)
    updateOrientation(dt, liveSmoothTimeRot)

    -- Apply the result to the game camera
    checkAndCompleteTask()
    applySimulationToCamera()
end

return CameraDriver