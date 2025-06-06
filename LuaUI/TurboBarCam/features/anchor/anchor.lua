---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CameraAnchorPersistence = ModuleManager.CameraAnchorPersistence(function(m) CameraAnchorPersistence = m end)
local EasingFunctions = ModuleManager.EasingFunctions(function(m) EasingFunctions = m end)
local Util = ModuleManager.Util(function(m) Util = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local TransitionManager = ModuleManager.TransitionManager(function(m) TransitionManager = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local VelocityTracker = ModuleManager.VelocityTracker(function(m) VelocityTracker = m end)
local CameraAnchorVisualization = ModuleManager.CameraAnchorVisualization(function(m) CameraAnchorVisualization = m end)

---@class CameraAnchor
local CameraAnchor = {}

local ANCHOR_TRANSITION_ID = "CameraAnchor.universalTransition"
local PI2 = math.pi * 2

--- A custom lerp function for angles that takes the shortest path.
---@param a number Start angle in radians
---@param b number End angle in radians
---@param t number Interpolation factor (0-1)
---@return number The interpolated angle
local function angleLerp(a, b, t)
    local diff = b - a
    if diff > math.pi then
        b = b - PI2
    elseif diff < -math.pi then
        b = b + PI2
    end
    return a + (b - a) * t
end

--- Sets a camera anchor
---@param index number Anchor index
---@return boolean success Always returns true for widget handler
function CameraAnchor.set(index)
    if Util.isTurboBarCamDisabled() then
        return
    end

    index = tonumber(index)
    if not (index and index >= 0) then
        return
    end

    local camState = Spring.GetCameraState()
    local selectedUnits = Spring.GetSelectedUnits()

    if #selectedUnits > 0 then
        -- A unit is selected, so the anchor will track this unit.
        local unitID = selectedUnits[1]
        STATE.anchor.points[index] = {
            position = { px = camState.px, py = camState.py, pz = camState.pz },
            target = { type = "unit", data = unitID },
            fov = camState.fov
        }
        Log:info("Saved camera anchor: " .. index .. " to track unit " .. unitID)
    else
        -- No unit selected, so find a static point to look at.
        local vsx, vsy = Spring.GetViewGeometry()
        local _, groundPos = Spring.TraceScreenRay(vsx / 2, vsy / 2, true)
        local lookAtPoint

        if groundPos then
            lookAtPoint = { x = groundPos[1], y = groundPos[2], z = groundPos[3] }
        else
            -- Fallback: If no ground is hit, use a point far in the camera's direction.
            local camDir = {Spring.GetCameraDirection()}
            local DISTANCE = 10000
            lookAtPoint = {
                x = camState.px + camDir[1] * DISTANCE,
                y = camState.py + camDir[2] * DISTANCE,
                z = camState.pz + camDir[3] * DISTANCE
            }
        end

        STATE.anchor.points[index] = {
            position = { px = camState.px, py = camState.py, pz = camState.pz },
            target = { type = "point", data = lookAtPoint },
            fov = camState.fov
        }
        Log:info("Saved camera anchor: " .. index .. " looking at point (" .. string.format("%.1f, %.1f, %.1f", lookAtPoint.x, lookAtPoint.y, lookAtPoint.z) .. ")")
    end

    return
end

--- Get the easing function based on type string
---@param easingType string|nil Easing type
---@return function easingFunc The easing function to use
function CameraAnchor.getEasingFunction(easingType)
    -- Use specified easing, or fall back to state easing, or default easing
    easingType = easingType or STATE.anchor.easing
    easingType = string.lower(easingType)

    local easingFunc = EasingFunctions[easingType]

    -- Fallback to default if not found
    if not easingFunc then
        Log:warn("Unknown easing type: " .. easingType .. ", falling back to none")
        easingFunc = EasingFunctions.none
    end

    return easingFunc
end

--- Focuses on a camera anchor with smooth transition
---@param index number Anchor index
---@param easingType string|nil Optional easing type
---@return boolean success Always returns true for widget handler
function CameraAnchor.focus(index, easingType)
    if Util.isTurboBarCamDisabled() then
        return true
    end

    index = tonumber(index)
    local newTargetState = STATE.anchor.points[index]
    if not (index and index >= 0 and newTargetState and newTargetState.position and newTargetState.target) then
        Log:warn("Invalid or incompatible anchor data for index: " .. tostring(index))
        return true
    end

    STATE.anchor.activeAnchorIndex = index

    local duration = CONFIG.CAMERA_MODES.ANCHOR.DURATION
    if STATE.lastUsedAnchor == index and TransitionManager.isTransitioning(ANCHOR_TRANSITION_ID) then
        duration = 0.2
    end

    if STATE.mode.name then
        ModeManager.disableMode()
    end

    local startState = Spring.GetCameraState()
    local easingFunc = CameraAnchor.getEasingFunction(easingType)
    local startVel, _, startRotVel, _ = VelocityTracker.getCurrentVelocity()

    -- Setup for positional interpolation
    local posStartTangent = CameraCommons.vectorMultiply(startVel, duration)
    local posEndTangent = { x = 0, y = 0, z = 0 }

    -- Setup for the Hermite rotation path (the "feel good" path)
    local endPos = {x = newTargetState.position.px, y = newTargetState.position.py, z = newTargetState.position.pz}
    local initialEndLookAtTarget
    if newTargetState.target.type == "unit" and Spring.ValidUnitID(newTargetState.target.data) then
        local uX, uY, uZ = Spring.GetUnitPosition(newTargetState.target.data)
        if uX then initialEndLookAtTarget = { x = uX, y = uY, z = uZ } end
    else
        initialEndLookAtTarget = newTargetState.target.data
    end

    if not initialEndLookAtTarget then
        Log:warn("Anchor target for index " .. index .. " is invalid. Aborting transition.")
        STATE.anchor.activeAnchorIndex = nil
        return true
    end

    local finalDirState = CameraCommons.focusOnPoint(endPos, initialEndLookAtTarget, 1.0, 1.0)
    local startRot = { rx = startState.rx, ry = startState.ry, rz = startState.rz }
    local endRot = { rx = finalDirState.rx, ry = finalDirState.ry, rz = startState.rz }

    -- Normalize yaw for shortest path
    local diff_ry = endRot.ry - startRot.ry
    if diff_ry > math.pi then
        endRot.ry = endRot.ry - PI2
    elseif diff_ry < -math.pi then
        endRot.ry = endRot.ry + PI2
    end

    local rotStartTangent = {
        rx = (startRotVel.x or 0) * duration,
        ry = (startRotVel.y or 0) * duration,
        rz = (startRotVel.z or 0) * duration,
    }
    local rotEndTangent = { rx = 0, ry = 0, rz = 0 }

    TransitionManager.force({
        id = ANCHOR_TRANSITION_ID,
        duration = duration,
        respectGameSpeed = false,
        easingFn = easingFunc,
        onUpdate = function(raw_progress, eased_progress)
            -- 1. Interpolate position
            local currentPos = Util.hermiteInterpolate(startState, newTargetState.position, posStartTangent, posEndTangent, raw_progress)

            -- 2. Calculate the "feel good" rotation using the Hermite curve
            local hermiteRx, hermiteRy, hermiteRz = Util.hermiteInterpolateRotation(startRot, endRot, rotStartTangent, rotEndTangent, raw_progress)

            -- 3. Calculate the "accurate" rotation by looking at the live target
            local liveLookAtTarget
            if newTargetState.target.type == "unit" and Spring.ValidUnitID(newTargetState.target.data) then
                local uX, uY, uZ = Spring.GetUnitPosition(newTargetState.target.data)
                if uX then liveLookAtTarget = { x = uX, y = uY, z = uZ } end
            else
                liveLookAtTarget = newTargetState.target.data
            end

            local finalRx, finalRy, finalRz = hermiteRx, hermiteRy, hermiteRz

            if liveLookAtTarget then
                local focusDirState = CameraCommons.focusOnPoint(currentPos, liveLookAtTarget, 1.0, 1.0)
                if focusDirState then
                    -- 4. Blend from the "feel good" rotation to the "accurate" rotation
                    finalRx = CameraCommons.lerp(hermiteRx, focusDirState.rx, eased_progress)
                    finalRy = angleLerp(hermiteRy, focusDirState.ry, eased_progress)
                    finalRz = hermiteRz -- Keep the roll from the Hermite path
                end
            end

            -- 5. Assemble and set the camera state
            local camState = {
                px = currentPos.x, py = currentPos.y, pz = currentPos.z,
                rx = finalRx, ry = finalRy, rz = finalRz,
                fov = CameraCommons.lerp(startState.fov, newTargetState.fov, eased_progress)
            }
            Spring.SetCameraState(camState, 0)
        end,
        onComplete = function()
            Log:debug("Anchor: Transition complete.")
            STATE.anchor.activeAnchorIndex = nil
        end
    })

    STATE.lastUsedAnchor = index
    return true
end

--- Action handler for setting anchor easing type
---@param easing string Parameters from the action command
---@return boolean success Always returns true
function CameraAnchor.setEasing(easing)
    if Util.isTurboBarCamDisabled() then
        return true
    end

    if easing and EasingFunctions[easing] then
        STATE.anchor.easing = easing
        Log:info("Set anchor easing type to: " .. tostring(easing))
    else
        STATE.anchor.easing = "none"
        Log:info("Invalid easing: " .. tostring(easing) .. ". Valid values: none, in, out, inout")
    end

    return true
end

function CameraAnchor.save(id)
    if Util.isTurboBarCamDisabled() then
        return false
    end
    return CameraAnchorPersistence.saveToFile(id, false)
end

function CameraAnchor.load(id)
    if Util.isTurboBarCamDisabled() then
        return false
    end
    return CameraAnchorPersistence.loadFromFile(id)
end

--- Toggles the visualization of anchor look-at points.
function CameraAnchor.toggleVisualization()
    if Util.isTurboBarCamDisabled() then
        return
    end

    STATE.anchor.visualizationEnabled = not STATE.anchor.visualizationEnabled
    Log:info("Camera anchor visualization " .. (STATE.anchor.visualizationEnabled and "enabled" or "disabled"))
end

--- Draws the anchor visualizations. This should be called from DrawWorld.
function CameraAnchor.draw()
    CameraAnchorVisualization.draw()
end

---@see ModifiableParams
---@see Util#adjustParams
function CameraAnchor.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end

    Util.adjustParams(params, 'ANCHOR', function()
        CONFIG.CAMERA_MODES.ANCHOR.DURATION = 2
    end)
end

return CameraAnchor