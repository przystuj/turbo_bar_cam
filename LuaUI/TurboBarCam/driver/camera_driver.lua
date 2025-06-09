---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CameraStateTracker = ModuleManager.CameraStateTracker(function(m) CameraStateTracker = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local QuaternionUtils = ModuleManager.QuaternionUtils(function(m) QuaternionUtils = m end)
local MathUtils = ModuleManager.MathUtils(function(m) MathUtils = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local Log = ModuleManager.Log(function(m) Log = m end)

---@class CameraDriver
local CameraDriver = {}

local DEFAULT_SMOOTH_TIME = 0.3

--- Sets the camera's declarative target state and seeds the simulation.
---@param targetConfig table Configuration for the target state.
function CameraDriver.setTarget(targetConfig)
    -- Check if the driver was already active before this call.
    -- The presence of a target.position indicates an active move.
    local wasAlreadyActive = (STATE.active.driver.target and STATE.active.driver.target.position ~= nil)

    -- Set the new target for the movement in the designated state table.
    STATE.active.driver.target = {
        position = targetConfig.position,
        lookAt = targetConfig.lookAt,
        euler = targetConfig.euler,
        smoothTime = targetConfig.duration or DEFAULT_SMOOTH_TIME,
        transitionType = targetConfig.transitionType or "smooth",
    }

    local sim = STATE.active.driver.simulation

    -- CRITICAL: Only seed the simulation state from the tracker if the driver was
    -- previously idle. If it was already moving, we preserve its internal
    -- velocities to ensure a perfectly smooth, continuous transition.
    if not wasAlreadyActive then
        sim.velocity = TableUtils.deepCopy(CameraStateTracker.getVelocity() or {x=0, y=0, z=0})
        sim.angularVelocity = TableUtils.deepCopy(CameraStateTracker.getAngularVelocity() or {x=0, y=0, z=0})
    end
    -- If the driver was already active, its existing sim.velocity and
    -- sim.angularVelocity are carried over into the new movement calculation.

    -- Always update the start time and transforms for the new curve.
    sim.startTime = Spring.GetTimer()
    sim.startPos = TableUtils.deepCopy(CameraStateTracker.getPosition())
    sim.startOrient = TableUtils.deepCopy(CameraStateTracker.getOrientation())
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
    -- Exit if the driver is idle (no target position) or dt is invalid.
    if not driverState or not driverState.target.position or dt <= 0 then
        return
    end

    -- Get the camera's current state from the tracker (The Sensor).
    local currentPos = CameraStateTracker.getPosition()
    local currentOrient = CameraStateTracker.getOrientation()

    -- CRITICAL: Use the driver's own private simulation state for the damper.
    -- This state persists across frames and is only modified by the damper functions,
    -- preventing the "fight" with the tracker's real-time state.
    local simState = driverState.simulation
    if not currentPos or not currentOrient or not simState then return end

    local target = driverState.target
    local shouldUpdate = false

    -- Resolve the target orientation for this frame.
    local targetOrientation
    if target.lookAt then
        local lookAtPoint = getLookAtPoint(target.lookAt)
        if lookAtPoint then
            local lookFromPos = currentPos
            local dirState = CameraCommons.calculateCameraDirectionToThePoint(lookFromPos, lookAtPoint)
            targetOrientation = QuaternionUtils.fromEuler(dirState.rx, dirState.ry)
        end
    elseif target.euler then
        targetOrientation = QuaternionUtils.fromEuler(target.euler.rx, target.euler.ry)
    end

    -- === Movement Calculation ===
    if target.transitionType == "smooth" then
        if target.position then
            -- Pass the private simulation velocity to be used and updated.
            STATE.active.camera.position = MathUtils.vectorSmoothDamp(currentPos, target.position, simState.velocity, target.smoothTime, dt)
            shouldUpdate = true
        end
        if targetOrientation then
            -- Log state before the damper runs
            local preDampAngularVel = TableUtils.deepCopy(simState.angularVelocity)

            -- Pass the private simulation angular velocity to be used and updated.
            local newOrient = QuaternionUtils.quaternionSmoothDamp(currentOrient, targetOrientation, simState.angularVelocity, target.smoothTime, dt)
            STATE.active.camera.orientation = newOrient
            shouldUpdate = true

            -- Log inputs and outputs of the rotation damper
            Log:staggeredLog("ROTATION DAMPING |", {
                inputOrient = currentOrient,
                targetOrient = targetOrientation,
                outputOrient = newOrient,
                inputAngVel = preDampAngularVel,
                outputAngVel = simState.angularVelocity,
            })
        end
    end

    -- === Check for Completion ===
    if target.position then
        local posOffset = CameraCommons.vectorSubtract(target.position, STATE.active.camera.position)
        local distSq = CameraCommons.vectorMagnitudeSq(posOffset)
        -- Check the private simulation velocity, not the tracker's velocity.
        local velSq = CameraCommons.vectorMagnitudeSq(simState.velocity)
        local angVelSq = CameraCommons.vectorMagnitudeSq(simState.angularVelocity)

        local rotOffsetSq = 0
        if targetOrientation then
            local errorQ = QuaternionUtils.multiply(targetOrientation, QuaternionUtils.inverse(STATE.active.camera.orientation))
            local errorVec = QuaternionUtils.log(errorQ)
            rotOffsetSq = CameraCommons.vectorMagnitudeSq(errorVec)
        end

        local POS_EPSILON_SQ = 0.01
        local ROT_EPSILON_SQ = 0.0001
        local VEL_EPSILON_SQ = 0.01

        local isComplete = distSq < POS_EPSILON_SQ and rotOffsetSq < ROT_EPSILON_SQ and velSq < VEL_EPSILON_SQ and angVelSq < VEL_EPSILON_SQ

        if isComplete then
            STATE.active.camera.position = target.position
            if targetOrientation then
                STATE.active.camera.orientation = targetOrientation
            end
            -- Clear the target using the default state to signal completion.
            driverState.target = TableUtils.deepCopy(STATE.DEFAULT.active.driver.target)
        end
    end

    -- === Apply final state to the engine ===
    if shouldUpdate then
        local finalEuler = { QuaternionUtils.toEuler(STATE.active.camera.orientation) }
        local camState = {
            px = STATE.active.camera.position.x, py = STATE.active.camera.position.y, pz = STATE.active.camera.position.z,
            rx = finalEuler[1], ry = finalEuler[2],
        }
        -- Log:debug("Driver: final CamState", camState)
        Spring.SetCameraState(camState)
    end
end

return CameraDriver