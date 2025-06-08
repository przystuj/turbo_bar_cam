---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local TransitionManager = ModuleManager.TransitionManager(function(m) TransitionManager = m end)
local CameraStateTracker = ModuleManager.CameraStateTracker(function(m) CameraStateTracker = m end)
local Util = ModuleManager.Util(function(m) Util = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local QuaternionUtils = ModuleManager.QuaternionUtils(function(m) QuaternionUtils = m end)

---@class OrientationController
local OrientationController = {}

local TRANSITION_ID = "OrientationController.universalTransition"
local MIN_LOOKAT_DISTANCE_SQ = 4.0

--- Wipes the controller's temporary state.
local function resetState()
    STATE.orientationController.lastKnownLookAtPoint = nil
    STATE.orientationController.lastKnownRotation = nil
end

--- Creates the onUpdate function for a "look-at" anchor transition by interpolating the look-at point.
local function createLookAtTransitionUpdater(startEuler, target, duration)
    local startPos = CameraStateTracker.getPosition()

    local startLookAtPoint
    if STATE.orientationController.lastKnownLookAtPoint then
        startLookAtPoint = STATE.orientationController.lastKnownLookAtPoint
    else
        local vsx, vsy = Spring.GetViewGeometry()
        local _, groundPos = Spring.TraceScreenRay(vsx / 2, vsy / 2, true)
        if groundPos then
            startLookAtPoint = { x = groundPos[1], y = groundPos[2], z = groundPos[3] }
        else
            local camDir = CameraCommons.getDirectionFromRotation(startEuler.rx, startEuler.ry)
            startLookAtPoint = { x = startPos.x + camDir.x * 10000, y = startPos.y + camDir.y * 10000, z = startPos.z + camDir.z * 10000 }
        end
    end

    STATE.orientationController.lastKnownRotation = { rx = startEuler.rx, ry = startEuler.ry }

    return function(raw_progress, eased_progress, dt)
        local currentPos = CameraStateTracker.getPosition()
        if not currentPos then return end

        local finalLookAtTarget
        if target.type == "unit" and Spring.ValidUnitID(target.data) then
            local uX, uY, uZ = Spring.GetUnitPosition(target.data)
            if uX then finalLookAtTarget = { x = uX, y = uY, z = uZ }
            else -- Unit died mid-transition
                TransitionManager.cancel(TRANSITION_ID)
                resetState()
                return
            end
        elseif target.type == "point" then
            finalLookAtTarget = target.data
        end
        finalLookAtTarget = finalLookAtTarget or startLookAtPoint

        local currentLookAtPoint = {}
        currentLookAtPoint.x = CameraCommons.lerp(startLookAtPoint.x, finalLookAtTarget.x, eased_progress)
        currentLookAtPoint.y = CameraCommons.lerp(startLookAtPoint.y, finalLookAtTarget.y, eased_progress)
        currentLookAtPoint.z = CameraCommons.lerp(startLookAtPoint.z, finalLookAtTarget.z, eased_progress)
        STATE.orientationController.lastKnownLookAtPoint = currentLookAtPoint

        if CameraCommons.distanceSquared(currentPos, currentLookAtPoint) > MIN_LOOKAT_DISTANCE_SQ then
            local directionState = CameraCommons.calculateCameraDirectionToThePoint(currentPos, currentLookAtPoint)
            if directionState then
                STATE.orientationController.lastKnownRotation = { rx = directionState.rx, ry = directionState.ry }
                Spring.SetCameraState({ rx = directionState.rx, ry = directionState.ry }, 0)
            end
        else
            local lastRot = STATE.orientationController.lastKnownRotation
            Spring.SetCameraState({ rx = lastRot.rx, ry = lastRot.ry }, 0)
        end
    end
end

--- Rotates to a fixed orientation using Squad for a smooth, velocity-aware transition.
function OrientationController.transitionTo(targetEuler, duration)
    resetState()
    local q0 = CameraStateTracker.getOrientation()
    local omega0 = CameraStateTracker.getAngularVelocityEuler()

    if not q0 or not omega0 then Log:warn("OrientationController: No start state from tracker."); return end

    local q1 = QuaternionUtils.fromEuler(targetEuler.rx, targetEuler.ry)
    local omega1 = { x = 0, y = 0, z = 0 }

    local w0_q = { w = 0, x = omega0.x, y = omega0.y, z = omega0.z }
    local w1_q = { w = 0, x = omega1.x, y = omega1.y, z = omega1.z }

    local tangentFactor = duration / 3.0
    local a0 = QuaternionUtils.multiply(q0, QuaternionUtils.exp(QuaternionUtils.scalePureQuaternion(w0_q, tangentFactor)))
    local b1 = QuaternionUtils.multiply(q1, QuaternionUtils.exp(QuaternionUtils.scalePureQuaternion(w1_q, -tangentFactor)))

    TransitionManager.start({
        id = TRANSITION_ID,
        duration = duration,
        respectGameSpeed = false,
        onUpdate = function(raw_progress, eased_progress, dt)
            local current_q = QuaternionUtils.squad(q0, q1, a0, b1, eased_progress)
            local rx, ry = QuaternionUtils.toEuler(current_q)
            Spring.SetCameraState({ rx = rx, ry = ry }, 0)
        end,
        onComplete = resetState
    })
end

--- Tracks a potentially moving target for a fixed duration.
function OrientationController.trackFor(target, duration)
    resetState()
    local startEuler = CameraStateTracker.getEuler()
    if not startEuler then Log:warn("OrientationController: No start euler state."); return end

    TransitionManager.start({
        id = TRANSITION_ID,
        duration = duration,
        respectGameSpeed = false,
        onUpdate = createLookAtTransitionUpdater(startEuler, target, duration),
        onComplete = resetState
    })
end

function OrientationController.stop()
    TransitionManager.cancel(TRANSITION_ID)
    resetState()
end

function OrientationController.isTransitioning()
    return TransitionManager.isTransitioning(TRANSITION_ID)
end

return OrientationController