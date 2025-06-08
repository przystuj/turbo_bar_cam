---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CameraStateTracker = ModuleManager.CameraStateTracker(function(m) CameraStateTracker = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local QuaternionUtils = ModuleManager.QuaternionUtils(function(m) QuaternionUtils = m end)
local Util = ModuleManager.Util(function(m) Util = m end)

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
end

--- Helper function to resolve the lookAt target to a concrete point
local function getLookAtPoint(target, fallbackPos)
    if not target then return nil end
    if target.type == "point" then
        return target.data
    elseif target.type == "unit" and Spring.ValidUnitID(target.data) then
        local x, y, z = Spring.GetUnitPosition(target.data)
        if x then return {x=x, y=y, z=z} end
    end
    return fallbackPos
end

--- The main update function, called every frame.
function CameraDriver.update(dt)
    if not STATE.camera or not STATE.cameraTarget or dt <= 0 then return end

    -- Get the current, real-world camera state from the tracker at the beginning of the frame.
    local currentPos = CameraStateTracker.getPosition()
    local currentOrient = CameraStateTracker.getOrientation()

    -- The velocity states are used as both input and output for the smoothing function,
    -- so we get a reference to them from the main state table.
    -- The tracker seeds these values, and the driver updates them for the next frame's simulation.
    local simVelocity = STATE.camera.velocity
    local simAngularVelocity = STATE.camera.angularVelocity

    if not currentPos or not currentOrient or not simVelocity or not simAngularVelocity then return end

    local target = STATE.cameraTarget
    local shouldUpdate = false

    -- === Position Smoothing ===
    if target.position then
        local newPos = Util.vectorSmoothDamp(currentPos, target.position, simVelocity, target.smoothTime, 100000, dt)
        STATE.camera.position = newPos -- Update the simulation state for the next frame
        shouldUpdate = true
    end

    -- === Orientation Smoothing ===
    local targetOrientation
    if target.lookAt then
        -- Note: We use the *newly calculated* position to determine the look-at direction. This prevents lag.
        local lookAtPoint = getLookAtPoint(target.lookAt, STATE.camera.position)
        if lookAtPoint then
            local dirState = CameraCommons.calculateCameraDirectionToThePoint(STATE.camera.position, lookAtPoint)
            targetOrientation = QuaternionUtils.fromEuler(dirState.rx, dirState.ry)
        end
    elseif target.euler then
        targetOrientation = QuaternionUtils.fromEuler(target.euler.rx, target.euler.ry)
    end

    if targetOrientation then
        -- For orientation, we use a slightly faster smooth time to feel responsive
        local rotSmoothTime = target.smoothTime * 0.8
        local newOrient = QuaternionUtils.quaternionSmoothDamp(currentOrient, targetOrientation, simAngularVelocity, rotSmoothTime, 100, dt)
        STATE.camera.orientation = newOrient -- Update the simulation state
        shouldUpdate = true
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