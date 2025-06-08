---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Util = ModuleManager.Util(function(m) Util = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local TransitionManager = ModuleManager.TransitionManager(function(m) TransitionManager = m end)
local CameraStateTracker = ModuleManager.CameraStateTracker(function(m) CameraStateTracker = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)

---@class PositionController
local PositionController = {}

local POSITION_TRANSITION_ID = "PositionController.transition"

--- Moves the camera from its current position and velocity to a target position over a duration.
---@param targetPosition table The destination position {x, y, z}.
---@param duration number The time in seconds for the transition.
function PositionController.transitionTo(targetPosition, duration)
    local startPos = CameraStateTracker.getPosition()
    local startVel = CameraStateTracker.getVelocity()

    if not startPos or not startVel then
        Log:warn("PositionController: CameraStateTracker not initialized.")
        return
    end

    local startState = {
        px = startPos.x,
        py = startPos.y,
        pz = startPos.z,
    }

    local posStartTangent = CameraCommons.vectorMultiply(startVel, duration)
    local posEndTangent = { x = 0, y = 0, z = 0 }

    TransitionManager.start({
        id = POSITION_TRANSITION_ID,
        duration = duration,
        respectGameSpeed = false,
        onUpdate = function(raw_progress, eased_progress, dt)
            local currentPos = Util.hermiteInterpolate(startState, {px=targetPosition.x, py=targetPosition.y, pz=targetPosition.z}, posStartTangent, posEndTangent, raw_progress)
            Spring.SetCameraState({
                px = currentPos.x,
                py = currentPos.y,
                pz = currentPos.z,
            }, 0)
        end,
        onComplete = function()
            Spring.SetCameraState({
                px = targetPosition.x,
                py = targetPosition.y,
                pz = targetPosition.z,
            }, 0)
        end
    })
end

--- Stops any ongoing positional transition.
function PositionController.stop()
    TransitionManager.cancel(POSITION_TRANSITION_ID)
end

--- Checks if the controller is currently executing a transition.
---@return boolean
function PositionController.isTransitioning()
    return TransitionManager.isTransitioning(POSITION_TRANSITION_ID)
end

return PositionController