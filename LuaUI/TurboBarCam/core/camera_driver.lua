---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local Log = ModuleManager.Log(function(m) Log = m end)
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CameraStateTracker = ModuleManager.CameraStateTracker(function(m) CameraStateTracker = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local QuaternionUtils = ModuleManager.QuaternionUtils(function(m) QuaternionUtils = m end)
local MathUtils = ModuleManager.MathUtils(function(m) MathUtils = m end)

---@class CameraDriver
local CameraDriver = {}

local DEFAULT_SMOOTH_TIME = 0.3

--- Sets the camera's declarative target state.
---@param targetConfig table Configuration for the target state.
function CameraDriver.setTarget(targetConfig)
    STATE.cameraTarget = {
        position = targetConfig.position,
        lookAt = targetConfig.lookAt,
        euler = targetConfig.euler,
        smoothTime = targetConfig.duration or DEFAULT_SMOOTH_TIME,
    }

    -- Seed the driver's private simulation state. This happens only ONCE at the start of a transition.
    -- We copy the current "real" velocity from the tracker to ensure a smooth takeover from manual control.
    STATE.cameraDriverState = {
        simVelocity = CameraStateTracker.getVelocity() or {x=0, y=0, z=0},
        simAngularVelocity = CameraStateTracker.getAngularVelocity() or {x=0, y=0, z=0},
    }
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
    -- If there's no target, the driver is idle.
    if not STATE.cameraTarget or dt <= 0 then
        -- Ensure private state is cleared when inactive.
        if STATE.cameraDriverState then
            STATE.cameraDriverState = nil
        end
        return
    end

    local currentPos = CameraStateTracker.getPosition()
    local currentOrient = CameraStateTracker.getOrientation()

    -- The driver must use its own private, persistent simulation state for the damper.
    -- It should NOT use the velocity from the tracker during the transition.
    local simVelocity = STATE.cameraDriverState.simVelocity
    local simAngularVelocity = STATE.cameraDriverState.simAngularVelocity

    if not currentPos or not currentOrient or not simVelocity or not simAngularVelocity then return end

    local target = STATE.cameraTarget
    local shouldUpdate = false

    -- === Position Smoothing ===
    if target.position then
        local newPos = MathUtils.vectorSmoothDamp(currentPos, target.position, simVelocity, target.smoothTime, dt)
        STATE.camera.position = newPos -- The temporary position for this frame is stored in the main state
        shouldUpdate = true
    end

    -- === Orientation Smoothing ===
    local targetOrientation
    if target.lookAt then
        local lookAtPoint = getLookAtPoint(target.lookAt)
        if lookAtPoint then
            local dirState = CameraCommons.calculateCameraDirectionToThePoint(STATE.camera.position, lookAtPoint)
            targetOrientation = QuaternionUtils.fromEuler(dirState.rx, dirState.ry)
        end
    elseif target.euler then
        targetOrientation = QuaternionUtils.fromEuler(target.euler.rx, target.euler.ry)
    end

    if targetOrientation then
        local rotSmoothTime = target.smoothTime * 0.8
        local newOrient = QuaternionUtils.quaternionSmoothDamp(currentOrient, targetOrientation, simAngularVelocity, rotSmoothTime, dt)
        STATE.camera.orientation = newOrient -- The temporary orientation is stored in the main state
        shouldUpdate = true
    end

    -- === Check for Completion ===
    if target.position then
        local posOffset = CameraCommons.vectorSubtract(target.position, STATE.camera.position)
        local distSq = posOffset.x^2 + posOffset.y^2 + posOffset.z^2
        local velSq = simVelocity.x^2 + simVelocity.y^2 + simVelocity.z^2
        local angVelSq = simAngularVelocity.x^2 + simAngularVelocity.y^2 + simAngularVelocity.z^2

        local POS_EPSILON_SQ = 1000
        local VEL_EPSILON_SQ = 100

        Log:debug(distSq, POS_EPSILON_SQ , velSq , VEL_EPSILON_SQ , angVelSq , VEL_EPSILON_SQ)
        if distSq < POS_EPSILON_SQ and velSq < VEL_EPSILON_SQ and angVelSq < VEL_EPSILON_SQ then
            STATE.camera.position = target.position
            if targetOrientation then
                STATE.camera.orientation = targetOrientation
            end
            STATE.cameraTarget = nil -- Clear the target to signal completion.
            Log:debug("Target reached")
        end
    end

    -- === Apply final state to the engine ===
    if shouldUpdate then
        local finalEuler = { QuaternionUtils.toEuler(STATE.camera.orientation) }
        Spring.SetCameraState({
            px = STATE.camera.position.x, py = STATE.camera.position.y, pz = STATE.camera.position.z,
            rx = finalEuler[1], ry = finalEuler[2],
        })
    end
end

return CameraDriver