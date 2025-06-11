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
    local wasAlreadyActive = (STATE.active.driver.target and STATE.active.driver.target.position ~= nil)
    STATE.active.driver.target.position = targetConfig.position
    STATE.active.driver.target.lookAt = targetConfig.lookAt
    STATE.active.driver.target.euler = targetConfig.euler
    STATE.active.driver.target.smoothTime = targetConfig.duration or DEFAULT_SMOOTH_TIME
    STATE.active.driver.target.transitionType = targetConfig.transitionType or "smooth"

    local sim = STATE.active.driver.simulation

    if not wasAlreadyActive then
        sim.position = TableUtils.deepCopy(CameraStateTracker.getPosition())
        sim.orientation = TableUtils.deepCopy(CameraStateTracker.getOrientation())
        sim.velocity = TableUtils.deepCopy(CameraStateTracker.getVelocity() or { x = 0, y = 0, z = 0 })
        sim.angularVelocity = TableUtils.deepCopy(CameraStateTracker.getAngularVelocity() or { x = 0, y = 0, z = 0 })
    end

    sim.startTime = Spring.GetTimer()
    sim.startOrient = TableUtils.deepCopy(sim.orientation)

    local ROTATION_ONLY_THRESHOLD_SQ = 1.0
    local distSq = MathUtils.vector.distanceSq(sim.position, targetConfig.position)
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

--- Updates the position of the camera simulation via smooth damping.
local function updatePosition(dt)
    local target = STATE.active.driver.target
    local simState = STATE.active.driver.simulation
    if not target.position or simState.isRotationOnly then return end

    local newPosition, newVelocity = MathUtils.vectorSmoothDamp(simState.position, target.position, simState.velocity, target.smoothTime, dt)
    simState.position = newPosition
    simState.velocity = newVelocity
end

--- Determines the target orientation and updates the simulation via smooth damping.
---@return table|nil finalTargetOrientation The calculated target orientation for this frame.
local function updateOrientation(dt)
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
        local smoothTime = target.lookAt and target.smoothTime / 4 or target.smoothTime
        local newOrientation, newAngularVelocity = QuaternionUtils.quaternionSmoothDamp(simState.orientation, finalTargetOrientation, simState.angularVelocity, smoothTime, dt)
        simState.orientation = newOrientation
        simState.angularVelocity = newAngularVelocity
    end

    return finalTargetOrientation
end

--- Checks if the movement has reached its target and resets the driver if complete.
local function checkAndCompleteTask(finalTargetOrientation)

    local simState = STATE.active.driver.simulation
    local target = STATE.active.driver.target

    local POS_EPSILON_SQ = 0.01
    local VEL_EPSILON_SQ = 0.01
    local ANG_VEL_EPSILON_SQ = 0.0001

    local angularVelSq = 0
    if finalTargetOrientation then
        angularVelSq = MathUtils.vector.magnitudeSq(simState.angularVelocity)
    end

    if angularVelSq < ANG_VEL_EPSILON_SQ then
        local distSq = MathUtils.vector.distanceSq(simState.position, target.position)
        local velSq = MathUtils.vector.magnitudeSq(simState.velocity)
        -- if lookAt then never stop following target
        if simState.isRotationOnly or (distSq < POS_EPSILON_SQ and velSq < VEL_EPSILON_SQ) and not target.lookAt then
            Log:debug("Driver task completed")
            STATE.active.driver.target = TableUtils.deepCopy(STATE.DEFAULT.active.driver.target)
        end
    end
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
    updatePosition(dt)
    local finalTargetOrientation = updateOrientation(dt)

    -- Apply the result to the game camera
    checkAndCompleteTask(finalTargetOrientation)
    applySimulationToCamera()
end

return CameraDriver