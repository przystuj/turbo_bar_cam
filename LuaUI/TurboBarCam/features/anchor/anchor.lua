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

---@class CameraAnchor
local CameraAnchor = {}

local ANCHOR_TRANSITION_ID = "CameraAnchor.universalTransition"

--- Sets a camera anchor
---@param index number Anchor index
---@return boolean success Always returns true for widget handler
function CameraAnchor.set(index)
    if Util.isTurboBarCamDisabled() then
        return
    end

    index = tonumber(index)
    if index and index >= 0 then
        STATE.anchor.points[index] = Spring.GetCameraState()
        Log:info("Saved camera anchor: " .. index)
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
    if not (index and index >= 0 and newTargetState) then
        return true
    end

    local duration = CONFIG.CAMERA_MODES.ANCHOR.DURATION
    -- If we click the same anchor we're already moving to, speed up the transition
    if STATE.lastUsedAnchor == index and TransitionManager.isTransitioning(ANCHOR_TRANSITION_ID) then
        duration = 0.2
    end

    -- Disable any active camera modes before starting anchor transition.
    if STATE.mode.name then
        ModeManager.disableMode()
    end

    local startState = Spring.GetCameraState()
    local easingFunc = CameraAnchor.getEasingFunction(easingType)
    local startVel, _, startRotVel, _ = VelocityTracker.getCurrentVelocity()

    -- Positional tangents
    local posStartTangent = CameraCommons.vectorMultiply(startVel, duration)
    local posEndTangent = { x = 0, y = 0, z = 0 }

    -- Setup rotation tables for the interpolator
    local startRot = { rx = startState.rx or 0, ry = startState.ry or 0, rz = startState.rz or 0 }
    local endRot = { rx = newTargetState.rx or 0, ry = newTargetState.ry or 0, rz = newTargetState.rz or 0 }
    local rotStartTangent = {
        rx = (startRotVel.x or 0) * duration,
        ry = (startRotVel.y or 0) * duration,
        rz = (startRotVel.z or 0) * duration,
    }
    local rotEndTangent = { rx = 0, ry = 0, rz = 0 }


    TransitionManager.force({
        id = ANCHOR_TRANSITION_ID,
        duration = duration,
        easingFn = easingFunc,
        onUpdate = function(raw_progress, eased_progress)
            Log:debug("Anchor: Moving towards " .. index)
            -- Positional interpolation
            local pos = Util.hermiteInterpolate(startState, newTargetState, posStartTangent, posEndTangent, raw_progress)

            -- Rotational interpolation
            local finalRx, finalRy, finalRz = Util.hermiteInterpolateRotation(startRot, endRot, rotStartTangent, rotEndTangent, raw_progress)

            -- Final camera state assembly
            local camState = {
                px = pos.x, py = pos.y, pz = pos.z,
                rx = finalRx, ry = finalRy, rz = finalRz,
                fov = CameraCommons.lerp(startState.fov, newTargetState.fov, eased_progress)
            }
            Spring.SetCameraState(camState, 0)
        end,
        onComplete = function()
            Log:debug("Anchor: Transition complete.")
        end
    })

    -- Update the last used anchor index to prevent re-triggering on the same frame.
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

    -- Set current easing type based on parameter
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