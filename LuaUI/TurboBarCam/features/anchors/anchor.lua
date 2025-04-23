---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type CameraAnchorUtils
local CameraAnchorUtils = VFS.Include("LuaUI/TurboBarCam/features/anchors/anchor_utils.lua").CameraAnchorUtils

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local TrackingManager = CommonModules.TrackingManager

---@class CameraAnchor
local CameraAnchor = {}

--- Sets a camera anchor
---@param index number Anchor index (0-9)
---@return boolean success Always returns true for widget handler
function CameraAnchor.set(index)
    if Util.isTurboBarCamDisabled() then
        return
    end

    index = tonumber(index)
    if index and index >= 0 and index <= 9 then
        STATE.anchors[index] = CameraManager.getCameraState("CameraAnchor.set")
        Log.info("Saved camera anchor: " .. index)
    end
    return
end

--- Focuses on a camera anchor with smooth transition
---@param index number Anchor index (0-9)
---@return boolean success Always returns true for widget handler
function CameraAnchor.focus(index)
    if Util.isTurboBarCamDisabled() then
        return true
    end

    index = tonumber(index)
    if not (index and index >= 0 and index <= 9 and STATE.anchors[index]) then
        return true
    end

    -- Store the anchor we're moving to
    STATE.lastUsedAnchor = index

    if STATE.tracking.mode then
        TrackingManager.disableTracking()
    end

    -- Cancel transition if we click the same anchor we're currently moving to
    if STATE.transition.active and STATE.transition.currentAnchorIndex == index then
        STATE.transition.active = false
        STATE.transition.currentAnchorIndex = nil
        Log.trace("Transition canceled")
        return true
    end

    -- Cancel any in-progress transition when starting a new one
    if STATE.transition.active then
        STATE.transition.active = false
        Log.trace("Canceled previous transition")
    end

    -- Check if we should do an instant transition (duration = 0)
    if CONFIG.CAMERA_MODES.ANCHOR.DURATION <= 0 then
        -- Instant camera jump
        local targetState = Util.deepCopy(STATE.anchors[index])
        -- Ensure the target state is in FPS mode
        CameraManager.setCameraState(targetState, 0, "CameraAnchor.focus")
        Log.trace("Instantly jumped to camera anchor: " .. index)
        return true
    end

    -- Start transition
    CameraAnchorUtils.start(STATE.anchors[index], CONFIG.CAMERA_MODES.ANCHOR.DURATION)
    STATE.transition.currentAnchorIndex = index
    Log.trace("Loading camera anchor: " .. index)
    return true
end

--- Focuses on an anchor while tracking a unit
---@param index number Anchor index (0-9)
---@return boolean success Always returns true for widget handler
function CameraAnchor.focusAndTrack(index)
    if Util.isTurboBarCamDisabled() then
        return true
    end

    index = tonumber(index)
    if not (index and index >= 0 and index <= 9 and STATE.anchors[index]) then
        Log.debug("Invalid or unset camera anchor: " .. (index or "nil"))
        return true
    end

    -- Store the anchor we're moving to
    STATE.lastUsedAnchor = index

    -- Check if current mode is compatible with tracking during anchor focus
    local isCompatibleMode = false
    for _, mode in ipairs(CONFIG.CAMERA_MODES.ANCHOR.COMPATIBLE_MODES) do
        if STATE.tracking.mode == mode then
            isCompatibleMode = true
            break
        end
    end

    -- If not in a compatible tracking mode or no unit is being tracked, do normal focus
    if not isCompatibleMode or not STATE.tracking.unitID then
        Log.trace("No unit was tracked during focused anchor transition")
        -- Just do a normal anchor transition
        return CameraAnchor.focus(index)
    end

    local unitID = STATE.tracking.unitID
    if not Spring.ValidUnitID(unitID) then
        Log.trace("Invalid unit for tracking during anchor transition")
        -- Just do a normal anchor transition
        return CameraAnchor.focus(index)
    end

    -- Cancel any in-progress transitions
    if STATE.transition.active then
        STATE.transition.active = false
        Log.trace("Canceled previous transition")
    end

    -- Disable any existing tracking modes to avoid conflicts
    if STATE.tracking.mode then
        TrackingManager.disableTracking()
    end

    -- Create a specialized transition that maintains focus on the unit
    local startState = CameraManager.getCameraState("CameraAnchor.focusAndTrack")

    -- Enable tracking camera on the unit
    STATE.tracking.mode = 'unit_tracking'
    STATE.tracking.unitID = unitID
    STATE.tracking.lastCamDir = { x = 0, y = 0, z = 0 }
    STATE.tracking.lastRotation = { rx = 0, ry = 0, rz = 0 }

    local unitX, unitY, unitZ = Spring.GetUnitPosition(unitID)
    local targetPos = { x = unitX, y = unitY, z = unitZ }

    -- Set up the transition
    STATE.transition.steps = CameraAnchorUtils.createPositionTransition(startState, STATE.anchors[index], CONFIG.CAMERA_MODES.ANCHOR.DURATION, targetPos)
    STATE.transition.currentStepIndex = 1
    STATE.transition.startTime = Spring.GetTimer()
    STATE.transition.active = true
    STATE.transition.currentAnchorIndex = index

    Log.trace("Moving to anchor " .. index .. " while tracking unit " .. unitID)
    return true
end

function CameraAnchor.update()
    if not STATE.transition.active then
        return
    end

    local now = Spring.GetTimer()

    -- Calculate current progress
    local elapsed = Spring.DiffTimers(now, STATE.transition.startTime)
    local targetProgress = math.min(elapsed / CONFIG.CAMERA_MODES.ANCHOR.DURATION, 1.0)

    -- Determine which step to use based on progress
    local totalSteps = #STATE.transition.steps
    local targetStep = math.max(1, math.min(totalSteps, math.ceil(targetProgress * totalSteps)))

    -- Only update if we need to move to a new step
    if targetStep > STATE.transition.currentStepIndex then
        STATE.transition.currentStepIndex = targetStep

        -- Apply the camera state for this step
        local camState = STATE.transition.steps[STATE.transition.currentStepIndex]

        -- Apply the base camera state (position)
        CameraManager.setCameraState(camState, 1, "CameraTransition.update")

        -- Check if we've reached the end
        if STATE.transition.currentStepIndex >= totalSteps then
            STATE.transition.active = false
            STATE.transition.currentAnchorIndex = nil
            Log.trace("transition complete")

            local currentState = CameraManager.getCameraState("CameraAnchor.update")
            Log.debug(string.format("currentState.rx=%.3f currentState.ry=%.3f",
                    currentState.rx or 0, currentState.rx or 0))
        end
    end
end

---@see ModifiableParams
---@see Util#adjustParams
function CameraAnchor.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end

    Util.adjustParams(params, 'ANCHOR', function() CONFIG.CAMERA_MODES.ANCHOR.DURATION = 2 end)
end

return {
    CameraAnchor = CameraAnchor
}