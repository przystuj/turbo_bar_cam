---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CameraStateTracker = ModuleManager.CameraStateTracker(function(m) CameraStateTracker = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local QuaternionUtils = ModuleManager.QuaternionUtils(function(m) QuaternionUtils = m end)
local MathUtils = ModuleManager.MathUtils(function(m) MathUtils = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)

---@class CameraDriver
local CameraDriver = {}

local DEFAULT_SMOOTH_TIME = 0.3

--- Sets the camera's declarative target state and seeds the simulation.
---@param targetConfig table Configuration for the target state.
function CameraDriver.setTarget(targetConfig)
    -- Set the target for the new movement.
    STATE.active.driver.target = {
        position = targetConfig.position,
        lookAt = targetConfig.lookAt,
        euler = targetConfig.euler,
        smoothTime = targetConfig.duration or DEFAULT_SMOOTH_TIME,
        transitionType = targetConfig.transitionType or "smooth",
    }

    -- Seed the driver's private simulation state. This happens only ONCE.
    -- We copy the current "real" state from the tracker to ensure a smooth takeover.
    local sim = STATE.active.driver.simulation
    sim.velocity = TableUtils.deepCopy(CameraStateTracker.getVelocity() or {x=0, y=0, z=0})
    sim.angularVelocity = TableUtils.deepCopy(CameraStateTracker.getAngularVelocity() or {x=0, y=0, z=0})
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
    if not driverState or not driverState.target.position or dt <= 0 then
        return
    end

    local currentPos = CameraStateTracker.getPosition()
    local currentOrient = CameraStateTracker.getOrientation()

    -- The driver must use its own private, persistent simulation state for the damper.
    local simState = driverState.simulation
    if not currentPos or not currentOrient or not simState then return end

    local target = driverState.target
    local shouldUpdate = false

    -- === Orientation Target Resolution ===
    local targetOrientation
    if target.lookAt then
        local lookAtPoint = getLookAtPoint(target.lookAt)
        if lookAtPoint then
            -- We use the current frame's calculated position for the look-at point to prevent lag
            local lookFromPos = STATE.active.camera.position or currentPos
            local dirState = CameraCommons.calculateCameraDirectionToThePoint(lookFromPos, lookAtPoint)
            targetOrientation = QuaternionUtils.fromEuler(dirState.rx, dirState.ry)
        end
    elseif target.euler then
        targetOrientation = QuaternionUtils.fromEuler(target.euler.rx, target.euler.ry)
    end

    -- === Movement Calculation ===
    if target.transitionType == "smooth" then
        if target.position then
            STATE.active.camera.position = MathUtils.vectorSmoothDamp(currentPos, target.position, simState.velocity, target.smoothTime, dt)
            shouldUpdate = true
        end
        if targetOrientation then
            STATE.active.camera.orientation = QuaternionUtils.quaternionSmoothDamp(currentOrient, targetOrientation, simState.angularVelocity, target.smoothTime * 0.8, dt)
            shouldUpdate = true
        end
        -- NOTE: "linear" transition type would be implemented here as an `elseif`
    end

    -- === Check for Completion ===
    if target.position then
        local posOffset = CameraCommons.vectorSubtract(target.position, STATE.active.camera.position)
        local distSq = posOffset.x^2 + posOffset.y^2 + posOffset.z^2
        local velSq = simState.velocity.x^2 + simState.velocity.y^2 + simState.velocity.z^2
        local angVelSq = simState.angularVelocity.x^2 + simState.angularVelocity.y^2 + simState.angularVelocity.z^2

        local POS_EPSILON_SQ = 0.01
        local VEL_EPSILON_SQ = 0.01

        if distSq < POS_EPSILON_SQ and velSq < VEL_EPSILON_SQ and angVelSq < VEL_EPSILON_SQ then
            STATE.active.camera.position = target.position
            if targetOrientation then
                STATE.active.camera.orientation = targetOrientation
            end
            -- Clear the target to signal completion.
            driverState.target = STATE.DEFAULT.active.driver.target
        end
    end

    -- === Apply final state to the engine ===
    if shouldUpdate then
        local finalEuler = { QuaternionUtils.toEuler(STATE.active.camera.orientation) }
        Spring.SetCameraState({
            px = STATE.active.camera.position.x, py = STATE.active.camera.position.y, pz = STATE.active.camera.position.z,
            rx = finalEuler[1], ry = finalEuler[2],
        })
    end
end

return CameraDriver