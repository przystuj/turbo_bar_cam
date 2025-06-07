---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CameraAnchorPersistence = ModuleManager.CameraAnchorPersistence(function(m) CameraAnchorPersistence = m end)
local Util = ModuleManager.Util(function(m) Util = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local TransitionManager = ModuleManager.TransitionManager(function(m) TransitionManager = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local VelocityTracker = ModuleManager.VelocityTracker(function(m) VelocityTracker = m end)
local CameraTracker = ModuleManager.CameraTracker(function(m) CameraTracker = m end)
local CameraAnchorVisualization = ModuleManager.CameraAnchorVisualization(function(m) CameraAnchorVisualization = m end)

---@class CameraAnchor
local CameraAnchor = {}

local ANCHOR_TRANSITION_ID = "CameraAnchor.universalTransition"
local SET_POSITION_THRESHOLD_SQ = 100 -- Squared distance to consider an anchor "in the same spot" for toggling
local MIN_LOOKAT_DISTANCE_SQ = 4.0 -- Squared safety threshold to prevent camera instability

--- Traces a ray from the center of the screen to find a point on the ground or in the distance.
---@param startState table The camera state to trace from.
---@return table lookAtPoint A table with {x, y, z} coordinates.
local function getLookAtTargetFromRaycast(startState)
    local vsx, vsy = Spring.GetViewGeometry()
    local _, groundPos = Spring.TraceScreenRay(vsx / 2, vsy / 2, true)
    if groundPos then
        return { x = groundPos[1], y = groundPos[2], z = groundPos[3] }
    else
        local camDir = Spring.GetCameraDirection()
        local DISTANCE = 10000
        return {
            x = startState.px + camDir[1] * DISTANCE,
            y = startState.py + camDir[2] * DISTANCE,
            z = startState.pz + camDir[3] * DISTANCE
        }
    end
end

--- Sets a camera anchor, with toggle functionality for look-at points.
---@param index number Anchor index
function CameraAnchor.set(index)
    if Util.isTurboBarCamDisabled() then return end

    index = tonumber(index)
    if not (index and index >= 0) then return end

    local camState = Spring.GetCameraState()
    local camPos = { x = camState.px, y = camState.py, z = camState.pz }
    local existingAnchor = STATE.anchor.points[index]

    if existingAnchor then
        local distSq = CameraCommons.distanceSquared(camPos, {x=existingAnchor.position.px, y=existingAnchor.position.py, z=existingAnchor.position.pz})
        if distSq < SET_POSITION_THRESHOLD_SQ then
            if existingAnchor.target then
                existingAnchor.target = nil
                existingAnchor.rotation = { rx = camState.rx, ry = camState.ry }
                Log:info("Anchor " .. index .. ": Look-at point removed. Converted to simple anchor.")
            else
                existingAnchor.rotation = nil
                local selectedUnits = Spring.GetSelectedUnits()
                if #selectedUnits > 0 then
                    existingAnchor.target = { type = "unit", data = selectedUnits[1] }
                    Log:info("Anchor " .. index .. ": Look-at point added (tracking unit " .. selectedUnits[1] .. ").")
                else
                    existingAnchor.target = { type = "point", data = getLookAtTargetFromRaycast(camState) }
                    Log:info("Anchor " .. index .. ": Look-at point added.")
                end
            end
            return
        end
    end

    STATE.anchor.points[index] = {
        position = { px = camState.px, py = camState.py, pz = camState.pz },
        rotation = { rx = camState.rx, ry = camState.ry },
    }
    Log:info("Anchor " .. index .. ": Simple anchor created/updated.")
end

--- Creates the onUpdate function for a "simple" anchor transition.
local function createSimpleTransitionUpdater(startState, endState, posStartTangent, posEndTangent)
    local startRot = { rx = startState.rx, ry = startState.ry, rz = startState.rz }
    local endRot = { rx = endState.rotation.rx, ry = endState.rotation.ry, rz = startState.rz }
    local PI2 = math.pi * 2
    local diff_ry = endRot.ry - startRot.ry
    if diff_ry > math.pi then endRot.ry = endRot.ry - PI2
    elseif diff_ry < -math.pi then endRot.ry = endRot.ry + PI2 end

    local _, _, startRotVel, _ = VelocityTracker.getCurrentVelocity()
    local rotStartTangent = {
        rx = (startRotVel.x or 0) * endState.duration,
        ry = (startRotVel.y or 0) * endState.duration,
        rz = (startRotVel.z or 0) * endState.duration,
    }
    local rotEndTangent = { rx = 0, ry = 0, rz = 0 }

    return function(raw_progress, eased_progress, dt)
        local currentPos = Util.hermiteInterpolate(startState, endState.position, posStartTangent, posEndTangent, raw_progress)
        local finalRx, finalRy = Util.hermiteInterpolateRotation(startRot, endRot, rotStartTangent, rotEndTangent, raw_progress)

        local dir = CameraCommons.getDirectionFromRotation(finalRx, finalRy)

        -- Use the correct engine API call to find the ground intersection point for a smooth handover.
        local rayLength, hitX, hitY, hitZ = Spring.TraceRayGroundInDirection(currentPos.x, currentPos.y, currentPos.z, dir.x, dir.y, dir.z)
        if rayLength then
            STATE.anchor.lastKnownLookAtPoint = { x = hitX, y = hitY, z = hitZ }
        else
            -- Fallback if looking at the sky
            STATE.anchor.lastKnownLookAtPoint = { x = currentPos.x + dir.x * 10000, y = currentPos.y + dir.y * 10000, z = currentPos.z + dir.z * 10000 }
        end
        STATE.anchor.lastKnownRotation = { rx = finalRx, ry = finalRy }

        local camState = { px = currentPos.x, py = currentPos.y, pz = currentPos.z, rx = finalRx, ry = finalRy, dx = dir.x, dy = dir.y, dz = dir.z }
        CameraTracker.updateLastKnownCameraState(camState)
        Spring.SetCameraState(camState, 0)
    end
end

--- Creates the onUpdate function for a "look-at" anchor transition.
local function createLookAtTransitionUpdater(startState, endState, posStartTangent, posEndTangent)
    local startLookAtPoint
    if TransitionManager.isTransitioning(ANCHOR_TRANSITION_ID) and STATE.anchor.lastKnownLookAtPoint then
        startLookAtPoint = STATE.anchor.lastKnownLookAtPoint
    else
        startLookAtPoint = getLookAtTargetFromRaycast(startState)
    end
    STATE.anchor.lastKnownRotation = { rx = startState.rx, ry = startState.ry }

    local _, _, startRotVel, _ = VelocityTracker.getCurrentVelocity()
    local lookAtStartTangent
    do
        local dt_pred = 1/60
        local next_rx = startState.rx + (startRotVel.x or 0) * dt_pred
        local next_ry = startState.ry + (startRotVel.y or 0) * dt_pred

        local dir_next = CameraCommons.getDirectionFromRotation(next_rx, next_ry)

        local startPosVec = Util.camStateToVector(startState, "p")
        local dist_to_target = math.sqrt(CameraCommons.distanceSquared(startPosVec, startLookAtPoint))

        local point_next = {
            x = startState.px + dir_next.x * dist_to_target,
            y = startState.py + dir_next.y * dist_to_target,
            z = startState.pz + dir_next.z * dist_to_target,
        }

        local vel_vec = CameraCommons.vectorSubtract(point_next, startLookAtPoint)
        lookAtStartTangent = CameraCommons.vectorMultiply(vel_vec, endState.duration / dt_pred)
    end

    local lookAtEndTangent = { x = 0, y = 0, z = 0 }

    return function(raw_progress, eased_progress, dt)
        local currentPos = Util.hermiteInterpolate(startState, endState.position, posStartTangent, posEndTangent, raw_progress)

        local finalLookAtTarget
        if endState.target.type == "unit" and Spring.ValidUnitID(endState.target.data) then
            local uX, uY, uZ = Spring.GetUnitPosition(endState.target.data)
            if uX then finalLookAtTarget = { x = uX, y = uY, z = uZ } end
        else
            finalLookAtTarget = endState.target.data
        end
        finalLookAtTarget = finalLookAtTarget or startLookAtPoint

        local currentLookAtPoint = Util.hermiteInterpolate(startLookAtPoint, finalLookAtTarget, lookAtStartTangent, lookAtEndTangent, raw_progress)
        STATE.anchor.lastKnownLookAtPoint = currentLookAtPoint

        local distSq = CameraCommons.distanceSquared(currentPos, currentLookAtPoint)
        if distSq > MIN_LOOKAT_DISTANCE_SQ then
            local directionState = CameraCommons.calculateCameraDirectionToThePoint(currentPos, currentLookAtPoint)
            if directionState then
                STATE.anchor.lastKnownRotation.rx = directionState.rx
                STATE.anchor.lastKnownRotation.ry = directionState.ry
            end
        end

        local dir = CameraCommons.getDirectionFromRotation(STATE.anchor.lastKnownRotation.rx, STATE.anchor.lastKnownRotation.ry)
        local camState = { px = currentPos.x, py = currentPos.y, pz = currentPos.z, rx = STATE.anchor.lastKnownRotation.rx, ry = STATE.anchor.lastKnownRotation.ry, dx = dir.x, dy = dir.y, dz = dir.z }
        CameraTracker.updateLastKnownCameraState(camState)
        Spring.SetCameraState(camState, 0)
    end
end

--- Main function to focus on an anchor, dispatching to the correct transition type.
function CameraAnchor.focus(index)
    if Util.isTurboBarCamDisabled() then return true end

    index = tonumber(index)
    local newTargetState = STATE.anchor.points[index]
    if not (index and index >= 0 and newTargetState and newTargetState.position) then
        Log:warn("Invalid anchor data for index: " .. tostring(index))
        return true
    end

    local duration = CONFIG.CAMERA_MODES.ANCHOR.DURATION
    if STATE.lastUsedAnchor == index and TransitionManager.isTransitioning(ANCHOR_TRANSITION_ID) then
        duration = 0.2
    end
    newTargetState.duration = duration

    STATE.anchor.activeAnchorId = index
    if STATE.mode.name then ModeManager.disableMode() end

    local startState = Spring.GetCameraState()
    local startVel, _, _, _ = VelocityTracker.getCurrentVelocity()
    local posStartTangent = CameraCommons.vectorMultiply(startVel, duration)
    local posEndTangent = { x = 0, y = 0, z = 0 }

    local onUpdate
    if newTargetState.target then
        onUpdate = createLookAtTransitionUpdater(startState, newTargetState, posStartTangent, posEndTangent)
    else
        onUpdate = createSimpleTransitionUpdater(startState, newTargetState, posStartTangent, posEndTangent)
    end

    TransitionManager.force({
        id = ANCHOR_TRANSITION_ID,
        duration = duration,
        respectGameSpeed = false,
        onUpdate = onUpdate,
        onComplete = function()
            Log:debug("Anchor: Transition complete.")
            STATE.anchor.activeAnchorId = nil
            STATE.anchor.lastKnownLookAtPoint = nil
            STATE.anchor.lastKnownRotation = nil
        end
    })

    STATE.lastUsedAnchor = index
    return true
end

function CameraAnchor.save(id)
    if Util.isTurboBarCamDisabled() then return false end
    return CameraAnchorPersistence.saveToFile(id, false)
end

function CameraAnchor.load(id)
    if Util.isTurboBarCamDisabled() then return false end
    return CameraAnchorPersistence.loadFromFile(id)
end

function CameraAnchor.toggleVisualization()
    if Util.isTurboBarCamDisabled() then return end
    STATE.anchor.visualizationEnabled = not STATE.anchor.visualizationEnabled
    Log:info("Camera anchor visualization " .. (STATE.anchor.visualizationEnabled and "enabled" or "disabled"))
end

function CameraAnchor.draw()
    CameraAnchorVisualization.draw()
end

function CameraAnchor.adjustParams(params)
    if Util.isTurboBarCamDisabled() then return end
    Util.adjustParams(params, 'ANCHOR', function()
        CONFIG.CAMERA_MODES.ANCHOR.DURATION = 2
    end)
end

return CameraAnchor