---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONSTANTS = ModuleManager.CONSTANTS(function(m) CONSTANTS = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local CameraStateTracker = ModuleManager.CameraStateTracker(function(m) CameraStateTracker = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local QuaternionUtils = ModuleManager.QuaternionUtils(function(m) QuaternionUtils = m end)
local MathUtils = ModuleManager.MathUtils(function(m) MathUtils = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "CameraDriver")

---@class CameraDriver
local CameraDriver = {}

local DEFAULT_SMOOTHING = 2
local TARGET_TYPE = CONSTANTS.TARGET_TYPE

-- Scratch/reusable tables to avoid per-frame allocations
local scratchLookAt = { x = 0, y = 0, z = 0 }
local eulerOut = { rx = 0, ry = 0 }
local cameraStateOut = { px = 0, py = 0, pz = 0, rx = 0, ry = 0 }
local isLookAtTargetType = {
    [TARGET_TYPE.POINT] = true,
    [TARGET_TYPE.UNIT] = true,
}

function CameraDriver.prepare(targetType, target)
    ---@class DriverJob : DriverTargetConfig
    local config = {}
    config.run = function()
        config.setTarget(targetType, target)
        CameraDriver.runJob(config)
    end
    ---@type fun(targetType: TargetType, target: number | Vector | Euler)
    config.setTarget = function(type, data)
        if type then
            config.targetEuler = type == TARGET_TYPE.EULER and data
            config.targetUnitId = type == TARGET_TYPE.UNIT and data
            config.targetPoint = type == TARGET_TYPE.POINT and data
            config.targetType = type
        end
    end
    return config
end

--- Helper function to resolve the lookAt target to a concrete point
---@param target table The target configuration object (e.g., targetConfig or STATE.core.driver.target)
local function getLookAtPoint(target)
    if not target then return nil end
    if target.targetType == TARGET_TYPE.POINT then
        local targetPoint = target.targetPoint
        scratchLookAt.x, scratchLookAt.y, scratchLookAt.z = targetPoint.x, targetPoint.y, targetPoint.z
        return scratchLookAt
    elseif target.targetType == TARGET_TYPE.UNIT and target.targetUnitId and Spring.ValidUnitID(target.targetUnitId) then
        local x, y, z = Spring.GetUnitPosition(target.targetUnitId)
        if x then
            scratchLookAt.x, scratchLookAt.y, scratchLookAt.z = x, y, z
            return scratchLookAt
        end
    end
    return nil
end

--- Applies the final calculated simulation state to the in-game camera.
local function applySimulationToCamera()
    local simState = STATE.core.driver.simulation
    local rx, ry = QuaternionUtils.toEuler(simState.orientation)
    eulerOut.rx, eulerOut.ry = rx, ry
    simState.euler = eulerOut
    local pos = simState.position
    cameraStateOut.px, cameraStateOut.py, cameraStateOut.pz = pos.x, pos.y, pos.z
    cameraStateOut.rx, cameraStateOut.ry = rx, ry
    Spring.SetCameraState(cameraStateOut)
end

--- Move camera instantly, bypassing simulation
local function handleCameraSnap(targetConfig)
    local simulationSTATE = STATE.core.driver.simulation
    if targetConfig.position then
        local position = targetConfig.position
        simulationSTATE.position.x, simulationSTATE.position.y, simulationSTATE.position.z = position.x or 0, position.y or 0, position.z or 0
    end

    local finalTargetOrientation
    local lookAtPoint = getLookAtPoint(targetConfig)
    if lookAtPoint then
        local posForCalc = targetConfig.position or simulationSTATE.position
        local dirState = CameraCommons.calculateCameraDirectionToThePoint(posForCalc, lookAtPoint)
        finalTargetOrientation = QuaternionUtils.fromEuler(dirState.rx, dirState.ry)
    elseif targetConfig.targetEuler then
        finalTargetOrientation = QuaternionUtils.fromEuler(targetConfig.targetEuler.rx, targetConfig.targetEuler.ry)
    end

    if finalTargetOrientation then
        simulationSTATE.orientation = finalTargetOrientation
    end

    simulationSTATE.velocity.x, simulationSTATE.velocity.y, simulationSTATE.velocity.z = 0, 0, 0
    simulationSTATE.angularVelocity.x, simulationSTATE.angularVelocity.y, simulationSTATE.angularVelocity.z = 0, 0, 0
    applySimulationToCamera()
end

--- Sets the camera's declarative target state and seeds the simulation.
---@param targetConfig DriverTargetConfig Configuration for the target state.
function CameraDriver.runJob(targetConfig)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    local targetSTATE = STATE.core.driver.target
    local simulationSTATE = STATE.core.driver.simulation
    local jobSTATE = STATE.core.driver.job
    local transitionSTATE = STATE.core.driver.smoothingTransition
    local wasAlreadyActive = jobSTATE.isActive

    if targetConfig.isSnap then
        handleCameraSnap(targetConfig)
    elseif not wasAlreadyActive then
        simulationSTATE.euler = CameraStateTracker.getEuler()
        simulationSTATE.position = CameraStateTracker.getPosition()
        simulationSTATE.orientation = CameraStateTracker.getOrientation()
        simulationSTATE.velocity = CameraStateTracker.getVelocity() or { x = 0, y = 0, z = 0 }
        simulationSTATE.angularVelocity = CameraStateTracker.getAngularVelocity() or { x = 0, y = 0, z = 0 }
    end

    jobSTATE.isActive = true

    TableUtils.syncTable(targetSTATE, targetConfig)

    targetSTATE.positionSmoothing = targetConfig.positionSmoothing or DEFAULT_SMOOTHING
    targetSTATE.rotationSmoothing = targetConfig.rotationSmoothing or DEFAULT_SMOOTHING

    transitionSTATE.startingPositionSmoothing = transitionSTATE.currentPositionSmoothing
    transitionSTATE.startingRotationSmoothing = transitionSTATE.currentRotationSmoothing
    transitionSTATE.smoothingTransitionStart = Spring.GetTimer()

    if targetConfig.position and simulationSTATE.position then
        local distSq = MathUtils.vector.distanceSq(simulationSTATE.position, targetConfig.position)
        jobSTATE.isRotationOnly = (distSq < CONFIG.DRIVER.DISTANCE_TARGET)
    else
        jobSTATE.isRotationOnly = not targetConfig.position
    end
end

--- Determines the correct smoothing values to use for the current frame.
local function getLiveSmoothTimes()
    local transitionSTATE = STATE.core.driver.smoothingTransition
    local target = STATE.core.driver.target

    local targetSmoothPos = target.positionSmoothing
    local targetSmoothRot = target.rotationSmoothing

    if not transitionSTATE.smoothingTransitionStart then
        -- No transition active, just use the target values.
        transitionSTATE.currentPositionSmoothing = targetSmoothPos
        transitionSTATE.currentRotationSmoothing = targetSmoothRot
    else
        -- Interpolate during an active transition.
        local elapsed = Spring.DiffTimers(Spring.GetTimer(), transitionSTATE.smoothingTransitionStart)
        local duration = CONFIG.DRIVER.TRANSITION_TIME
        local alpha = (duration > 0) and (elapsed / duration) or 1.0

        if alpha >= 1.0 then
            transitionSTATE.currentPositionSmoothing = targetSmoothPos
            transitionSTATE.currentRotationSmoothing = targetSmoothRot
            transitionSTATE.smoothingTransitionStart = nil
        else
            transitionSTATE.currentPositionSmoothing = transitionSTATE.startingPositionSmoothing * (1.0 - alpha) + targetSmoothPos * alpha
            transitionSTATE.currentRotationSmoothing = transitionSTATE.startingRotationSmoothing * (1.0 - alpha) + targetSmoothRot * alpha
        end
    end

    return transitionSTATE.currentPositionSmoothing, transitionSTATE.currentRotationSmoothing
end

--- Updates the position of the camera simulation via smooth damping.
local function updatePosition(dt, liveSmoothTimePos)
    local targetSTATE = STATE.core.driver.target
    local simulationSTATE = STATE.core.driver.simulation
    local jobSTATE = STATE.core.driver.job
    if not targetSTATE.position or jobSTATE.isRotationOnly then
        simulationSTATE.position = CameraStateTracker.getPosition()
        return
    end

    local newPosition, newVelocity = MathUtils.vectorSmoothDamp(simulationSTATE.position, targetSTATE.position, simulationSTATE.velocity, liveSmoothTimePos, dt)
    simulationSTATE.position = newPosition
    simulationSTATE.velocity = newVelocity
end

--- Determines the target orientation and updates the simulation via smooth damping.
local function updateOrientation(dt, liveSmoothTimeRot)
    local targetSTATE = STATE.core.driver.target
    local simulationSTATE = STATE.core.driver.simulation
    local finalTargetOrientation

    local lookAtPoint = getLookAtPoint(targetSTATE)
    if lookAtPoint then
        local dirState = CameraCommons.calculateCameraDirectionToThePoint(simulationSTATE.position, lookAtPoint)
        finalTargetOrientation = QuaternionUtils.fromEuler(dirState.rx, dirState.ry)
    elseif targetSTATE.targetEuler then
        finalTargetOrientation = QuaternionUtils.fromEuler(targetSTATE.targetEuler.rx, targetSTATE.targetEuler.ry)
    end

    if finalTargetOrientation then
        local newOrientation, newAngularVelocity = QuaternionUtils.quaternionSmoothDamp(simulationSTATE.orientation, finalTargetOrientation, simulationSTATE.angularVelocity, liveSmoothTimeRot, dt)
        simulationSTATE.orientation = newOrientation
        simulationSTATE.angularVelocity = newAngularVelocity
    end
end

--- Checks if the movement has reached its target and resets the driver if complete.
local function checkAndCompleteTask()
    local targetSTATE = STATE.core.driver.target
    local simulationSTATE = STATE.core.driver.simulation
    local jobSTATE = STATE.core.driver.job

    -- Calculate current metrics and store them in the job state
    local angularVelMag = MathUtils.vector.magnitudeSq(simulationSTATE.angularVelocity)
    jobSTATE.angularVelocityMagnitude = angularVelMag

    if targetSTATE.position then
        jobSTATE.distance = MathUtils.vector.distanceSq(simulationSTATE.position, targetSTATE.position)
        jobSTATE.velocityMagnitude = MathUtils.vector.magnitudeSq(simulationSTATE.velocity)
    else
        jobSTATE.distance = 0
        jobSTATE.velocityMagnitude = 0
    end

    -- Reset completion flags each frame
    jobSTATE.isPositionComplete = false
    jobSTATE.isRotationComplete = false

    local hasLookAtTarget = isLookAtTargetType[targetSTATE.targetType] or false
    local hasRotationTask = hasLookAtTarget or targetSTATE.targetEuler
    local hasPositionTask = targetSTATE.position ~= nil

    -- Check rotation completion
    if not hasRotationTask or angularVelMag < CONFIG.DRIVER.ANGULAR_VELOCITY_TARGET then
        jobSTATE.isRotationComplete = true
    end

    -- Check position completion
    if not hasPositionTask then
        jobSTATE.isPositionComplete = true
    else
        if jobSTATE.isRotationOnly then
            jobSTATE.isPositionComplete = true -- Positional part is ignored
        elseif jobSTATE.distance < CONFIG.DRIVER.DISTANCE_TARGET and jobSTATE.velocityMagnitude < CONFIG.DRIVER.VELOCITY_TARGET then
            jobSTATE.isPositionComplete = true
        end
    end

    -- If a lookAt target is active, the driver should never complete on its own.
    if jobSTATE.isPositionComplete and jobSTATE.isRotationComplete and not hasLookAtTarget then
        Log:trace("Driver task completed")
        CameraDriver.stop()
    end
end

--- The main update function, called every frame.
function CameraDriver.update(dt)
    if Utils.isTurboBarCamDisabled() or not STATE.core.driver.job.isActive then
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

function CameraDriver.stop()
    STATE.core.driver.job = TableUtils.deepCopy(STATE.DEFAULT.core.driver.job)
    STATE.core.driver.target = TableUtils.deepCopy(STATE.DEFAULT.core.driver.target)
    STATE.core.driver.smoothingTransition = TableUtils.deepCopy(STATE.DEFAULT.core.driver.smoothingTransition)
end

return CameraDriver
