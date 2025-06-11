---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
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
    local wasAlreadyActive = (STATE.active.driver.target and STATE.active.driver.target.position ~= nil)

    Log:debug("setTarget called", { wasAlreadyActive = wasAlreadyActive }, "targetConfig", targetConfig)

    STATE.active.driver.target = {
        position = targetConfig.position,
        lookAt = targetConfig.lookAt,
        euler = targetConfig.euler,
        smoothTime = targetConfig.duration or DEFAULT_SMOOTH_TIME,
        transitionType = targetConfig.transitionType or "smooth",
    }

    local sim = STATE.active.driver.simulation

    if not wasAlreadyActive then
        sim.position = TableUtils.deepCopy(CameraStateTracker.getPosition())
        sim.orientation = TableUtils.deepCopy(CameraStateTracker.getOrientation())
        sim.velocity = TableUtils.deepCopy(CameraStateTracker.getVelocity() or { x = 0, y = 0, z = 0 })
        sim.angularVelocity = TableUtils.deepCopy(CameraStateTracker.getAngularVelocity() or { x = 0, y = 0, z = 0 })
        Log:only("position", "orientation", "velocity", "angularVelocity")
           :debug("Seeding new simulation", sim)
    end

    sim.startTime = Spring.GetTimer()
    sim.startOrient = TableUtils.deepCopy(sim.orientation)

    local ROTATION_ONLY_THRESHOLD_SQ = 1.0
    local distSq = CameraCommons.distanceSquared(sim.position, targetConfig.position)
    sim.isRotationOnly = (distSq < ROTATION_ONLY_THRESHOLD_SQ)
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

--- The main update function, called every frame.
function CameraDriver.update(dt)
    local driverState = STATE.active.driver
    if not driverState or not driverState.target then return end

    if not driverState.target.position and not driverState.target.lookAt and not driverState.target.euler then
        return
    end

    if dt <= 0 then return end

    local simState = driverState.simulation
    if not simState or not simState.position then return end

    local target = driverState.target

    if target.position and not simState.isRotationOnly then
        local newPosition, newVelocity = MathUtils.vectorSmoothDamp(simState.position, target.position, simState.velocity, target.smoothTime, dt)
        simState.position = newPosition
        simState.velocity = newVelocity
    end

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
        local newOrientation, newAngularVelocity = QuaternionUtils.quaternionSmoothDamp(simState.orientation, finalTargetOrientation, simState.angularVelocity, target.smoothTime, dt)
        simState.orientation = newOrientation
        simState.angularVelocity = newAngularVelocity
    end

    if target.position then
        local isComplete = false
        local distSq = CameraCommons.distanceSquared(simState.position, target.position)
        local velSq = CameraCommons.vectorMagnitudeSq(simState.velocity)
        local angularVelSq = 0
        if finalTargetOrientation then
            -- Only check angular velocity if we have a rotation target
            angularVelSq = CameraCommons.vectorMagnitudeSq(simState.angularVelocity)
        end

        local POS_EPSILON_SQ = 0.01
        local VEL_EPSILON_SQ = 0.01
        local ANG_VEL_EPSILON_SQ = 0.0001

        if angularVelSq < ANG_VEL_EPSILON_SQ then
            if simState.isRotationOnly or (distSq < POS_EPSILON_SQ and velSq < VEL_EPSILON_SQ) then
                isComplete = true
                Log:debug("Driver task completed")
            end
        end

        if isComplete then
            driverState.target = TableUtils.deepCopy(STATE.DEFAULT.active.driver.target)
        end
    end

    local rx, ry = QuaternionUtils.toEuler(simState.orientation)
    local camState = {
        px = simState.position.x, py = simState.position.y, pz = simState.position.z,
        rx = rx, ry = ry,
    }
    Spring.SetCameraState(camState)
end

return CameraDriver