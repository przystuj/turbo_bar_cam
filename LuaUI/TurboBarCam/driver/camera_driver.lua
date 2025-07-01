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

local DEFAULT_SMOOTH_TIME = 0.3

--- Helper function to resolve the lookAt target to a concrete point
local function getLookAtPoint(target)
    if not target then return nil end
    if target.type == CONSTANTS.TARGET_TYPE.POINT then
        return target.data
    elseif target.type == CONSTANTS.TARGET_TYPE.UNIT and Spring.ValidUnitID(target.data) then
        local x, y, z = Spring.GetUnitPosition(target.data)
        if x then return { x = x, y = y, z = z } end
    end
    return nil
end

--- Applies the final calculated simulation state to the in-game camera.
local function applySimulationToCamera()
    local simState = STATE.core.driver.simulation
    local rx, ry = QuaternionUtils.toEuler(simState.orientation)
    simState.euler = { rx = rx, ry = ry }
    Spring.SetCameraState({
        px = simState.position.x, py = simState.position.y, pz = simState.position.z,
        rx = rx, ry = ry,
    })
end

--- Sets the camera's declarative target state and seeds the simulation.
---@param targetConfig table Configuration for the target state.
function CameraDriver.setTarget(targetConfig)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    local targetSTATE = STATE.core.driver.target
    local simulationSTATE = STATE.core.driver.simulation
    local transitionSTATE = STATE.core.driver.transition
    local wasAlreadyActive = (targetSTATE.position ~= nil or targetSTATE.lookAt ~= nil or targetSTATE.euler ~= nil)

    if targetConfig.isSnap then
        if targetConfig.position then
            simulationSTATE.position = TableUtils.deepCopy(targetConfig.position)
        end

        local finalTargetOrientation
        if targetConfig.lookAt then
            local lookAtPoint = getLookAtPoint(targetConfig.lookAt)
            if lookAtPoint then
                local posForCalc = targetConfig.position or simulationSTATE.position
                local dirState = CameraCommons.calculateCameraDirectionToThePoint(posForCalc, lookAtPoint)
                finalTargetOrientation = QuaternionUtils.fromEuler(dirState.rx, dirState.ry)
            end
        elseif targetConfig.euler then
            finalTargetOrientation = QuaternionUtils.fromEuler(targetConfig.euler.rx, targetConfig.euler.ry)
        end

        if finalTargetOrientation then
            simulationSTATE.orientation = finalTargetOrientation
        end

        simulationSTATE.velocity = { x = 0, y = 0, z = 0 }
        simulationSTATE.angularVelocity = { x = 0, y = 0, z = 0 }
        applySimulationToCamera()

    elseif not wasAlreadyActive then
        simulationSTATE.euler = CameraStateTracker.getEuler()
        simulationSTATE.position = CameraStateTracker.getPosition()
        simulationSTATE.orientation = CameraStateTracker.getOrientation()
        simulationSTATE.velocity = CameraStateTracker.getVelocity() or { x = 0, y = 0, z = 0 }
        simulationSTATE.angularVelocity = CameraStateTracker.getAngularVelocity() or { x = 0, y = 0, z = 0 }
    end

    -- Set the main target values
    targetSTATE.position = targetConfig.position
    targetSTATE.lookAt = targetConfig.lookAt
    targetSTATE.euler = targetConfig.euler
    targetSTATE.smoothTimePos = targetConfig.smoothTimePos or DEFAULT_SMOOTH_TIME
    targetSTATE.smoothTimeRot = targetConfig.smoothTimeRot or targetSTATE.smoothTimePos
    transitionSTATE.sourceSmoothTimePos = transitionSTATE.currentSmoothTimePos
    transitionSTATE.sourceSmoothTimeRot = transitionSTATE.currentSmoothTimeRot
    transitionSTATE.smoothTimeTransitionStart = Spring.GetTimer()

    if targetConfig.position and simulationSTATE.position then
        local distSq = MathUtils.vector.distanceSq(simulationSTATE.position, targetConfig.position)
        transitionSTATE.isRotationOnly = (distSq < CONFIG.DRIVER.DISTANCE_TARGET)
    else
        transitionSTATE.isRotationOnly = not targetConfig.position
    end
end

--- Determines the correct smoothing values to use for the current frame.
local function getLiveSmoothTimes()
    local transitionSTATE = STATE.core.driver.transition

    -- Otherwise, perform the gradual transition logic.
    local target = STATE.core.driver.target
    if not transitionSTATE.smoothTimeTransitionStart then
        -- No transition active, just use the target values.
        transitionSTATE.currentSmoothTimePos = target.smoothTimePos
        transitionSTATE.currentSmoothTimeRot = target.smoothTimeRot
    else
        -- Interpolate during an active transition.
        local elapsed = Spring.DiffTimers(Spring.GetTimer(), transitionSTATE.smoothTimeTransitionStart)
        local duration = CONFIG.DRIVER.TRANSITION_TIME
        local alpha = (duration > 0) and (elapsed / duration) or 1.0

        if alpha >= 1.0 then
            transitionSTATE.currentSmoothTimePos = target.smoothTimePos
            transitionSTATE.currentSmoothTimeRot = target.smoothTimeRot
            transitionSTATE.smoothTimeTransitionStart = nil
        else
            transitionSTATE.currentSmoothTimePos = transitionSTATE.sourceSmoothTimePos * (1.0 - alpha) + target.smoothTimePos * alpha
            transitionSTATE.currentSmoothTimeRot = transitionSTATE.sourceSmoothTimeRot * (1.0 - alpha) + target.smoothTimeRot * alpha
        end
    end

    return transitionSTATE.currentSmoothTimePos, transitionSTATE.currentSmoothTimeRot
end

--- Updates the position of the camera simulation via smooth damping.
local function updatePosition(dt, liveSmoothTimePos)
    local targetSTATE = STATE.core.driver.target
    local simulationSTATE = STATE.core.driver.simulation
    local transitionSTATE = STATE.core.driver.transition
    if not targetSTATE.position or transitionSTATE.isRotationOnly then
        simulationSTATE.position = CameraStateTracker.getPosition()
        return
    end

    local newPosition, newVelocity = MathUtils.vectorSmoothDamp(simulationSTATE.position, targetSTATE.position, simulationSTATE.velocity, liveSmoothTimePos, dt)
    simulationSTATE.position = newPosition
    simulationSTATE.velocity = newVelocity
end

--- Determines the target orientation and updates the simulation via smooth damping.
local function updateOrientation(dt, liveSmoothTimeRot)
    local target = STATE.core.driver.target
    local simState = STATE.core.driver.simulation
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
    local targetSTATE = STATE.core.driver.target
    local simulationSTATE = STATE.core.driver.simulation
    local transitionSTATE = STATE.core.driver.transition

    -- Calculate current metrics for UI feedback
    local angularVelMag = MathUtils.vector.magnitudeSq(simulationSTATE.angularVelocity)
    transitionSTATE.angularVelocityMagnitude = angularVelMag

    if targetSTATE.position then
        transitionSTATE.distance = MathUtils.vector.distanceSq(simulationSTATE.position, targetSTATE.position)
        transitionSTATE.velocityMagnitude = MathUtils.vector.magnitudeSq(simulationSTATE.velocity)
    else
        transitionSTATE.distance = 0
        transitionSTATE.velocityMagnitude = 0
    end

    -- Reset completion flags each frame
    transitionSTATE.isPositionComplete = false
    transitionSTATE.isRotationComplete = false

    local hasRotationTask = targetSTATE.euler ~= nil
    local hasPositionTask = targetSTATE.position ~= nil

    -- Check rotation completion
    if not hasRotationTask or angularVelMag < CONFIG.DRIVER.ANGULAR_VELOCITY_TARGET then
        transitionSTATE.isRotationComplete = true
    end

    -- Check position completion
    if not hasPositionTask then
        transitionSTATE.isPositionComplete = true
    else
        if transitionSTATE.isRotationOnly then
            transitionSTATE.isPositionComplete = true -- Positional part is ignored
        elseif transitionSTATE.distance < CONFIG.DRIVER.DISTANCE_TARGET and transitionSTATE.velocityMagnitude < CONFIG.DRIVER.VELOCITY_TARGET then
            transitionSTATE.isPositionComplete = true
        end
    end

    -- if lookAt target is active, the driver should never complete on its own.
    if transitionSTATE.isPositionComplete and transitionSTATE.isRotationComplete and not targetSTATE.lookAt then
        Log:debug("Driver task completed")
        CameraDriver.stop()
    end
end

--- The main update function, called every frame.
function CameraDriver.update(dt)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    -- Guard clauses for performance and safety
    local driverSTATE = STATE.core.driver
    if not driverSTATE.target.position and not driverSTATE.target.lookAt and not driverSTATE.target.euler then
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
    STATE.core.driver.transition = TableUtils.deepCopy(STATE.DEFAULT.core.driver.transition)
    STATE.core.driver.target = TableUtils.deepCopy(STATE.DEFAULT.core.driver.target)
end

return CameraDriver