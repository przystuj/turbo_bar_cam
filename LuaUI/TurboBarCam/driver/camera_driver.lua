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
        sim.velocity = TableUtils.deepCopy(CameraStateTracker.getVelocity() or {x=0, y=0, z=0})
        sim.angularVelocity = TableUtils.deepCopy(CameraStateTracker.getAngularVelocity() or {x=0, y=0, z=0})
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
        if x then return {x=x, y=y, z=z} end
    end
    return nil
end

--- The main update function, called every frame.
function CameraDriver.update(dt)
    local driverState = STATE.active.driver
    if not driverState or not driverState.target.position or dt <= 0 then
        return
    end

    local simState = driverState.simulation
    if not simState or not simState.orientation or not simState.startOrient then return end

    local target = driverState.target
    local newPos = simState.position

    if not simState.isRotationOnly then
        newPos = MathUtils.vectorSmoothDamp(simState.position, target.position, simState.velocity, target.smoothTime, dt)
        simState.position = newPos
    end

    local newOrient = simState.orientation
    if target.transitionType == "smooth" then
        local finalTargetOrientation
        if target.lookAt then
            local lookAtPoint = getLookAtPoint(target.lookAt)
            if lookAtPoint then
                local dirState = CameraCommons.calculateCameraDirectionToThePoint(newPos, lookAtPoint)
                finalTargetOrientation = QuaternionUtils.fromEuler(dirState.rx, dirState.ry)
            end
        elseif target.euler then
            finalTargetOrientation = QuaternionUtils.fromEuler(target.euler.rx, target.euler.ry)
        end

        if finalTargetOrientation then
            local rotationDuration = target.smoothTime
            local elapsedTime = Spring.DiffTimers(Spring.GetTimer(), simState.startTime)
            local rawAlpha = math.min(1.0, elapsedTime / rotationDuration)
            local easedAlpha = CameraCommons.easeInOut(rawAlpha)
            local proxyTargetOrient = QuaternionUtils.slerp(simState.startOrient, finalTargetOrientation, easedAlpha)
            local PROXY_CHASE_SMOOTH_TIME = 0.15
            newOrient = QuaternionUtils.quaternionSmoothDamp(simState.orientation, proxyTargetOrient, simState.angularVelocity, PROXY_CHASE_SMOOTH_TIME, dt)
            simState.orientation = newOrient
        end
    end

    local isComplete = false
    if simState.isRotationOnly then
        local rotationDuration = target.smoothTime
        if Spring.DiffTimers(Spring.GetTimer(), simState.startTime) >= rotationDuration then
            isComplete = true
        end
    else
        local distSq = CameraCommons.distanceSquared(newPos, target.position)
        local velSq = CameraCommons.vectorMagnitudeSq(simState.velocity)
        local POS_EPSILON_SQ = 0.01
        local VEL_EPSILON_SQ = 0.01
        if distSq < POS_EPSILON_SQ and velSq < VEL_EPSILON_SQ then
            isComplete = true
        end
    end

    if isComplete then
        newPos = target.position
        if target.lookAt then
            local lookAtPoint = getLookAtPoint(target.lookAt)
            if lookAtPoint then
                local dirState = CameraCommons.calculateCameraDirectionToThePoint(target.position, lookAtPoint)
                newOrient = QuaternionUtils.fromEuler(dirState.rx, dirState.ry)
            end
        elseif target.euler then
            newOrient = QuaternionUtils.fromEuler(target.euler.rx, target.euler.ry)
        end
        driverState.target = TableUtils.deepCopy(STATE.DEFAULT.active.driver.target)
        simState.isRotationOnly = false
    end

    local finalEuler = { QuaternionUtils.toEuler(newOrient) }
    local camState = {
        px = newPos.x, py = newPos.y, pz = newPos.z,
        rx = finalEuler[1], ry = finalEuler[2],
    }
    Spring.SetCameraState(camState)
    CameraStateTracker.setCameraState(newPos, newOrient)
end

return CameraDriver