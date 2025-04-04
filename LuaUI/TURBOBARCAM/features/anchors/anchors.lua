-- Camera Anchor module for TURBOBARCAM
-- Load modules
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CommonModules
local TurboCommons = VFS.Include("LuaUI/TURBOBARCAM/common.lua")
---@type CoreModules
local TurboCore = VFS.Include("LuaUI/TURBOBARCAM/core.lua")

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE
local Util = TurboCommons.Util
local Tracking = TurboCommons.Tracking
local CameraTransition = TurboCore.Transition

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
        local currentState = Spring.GetCameraState()
        -- Ensure the anchor is in FPS mode
        currentState.mode = 0
        currentState.name = "fps"
        STATE.anchors[index] = currentState
        Util.echo("Saved camera anchor: " .. index)
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
    Tracking.disableTracking()

    -- Cancel transition if we click the same anchor we're currently moving to
    if STATE.transition.active and STATE.transition.currentAnchorIndex == index then
        STATE.transition.active = false
        STATE.transition.currentAnchorIndex = nil
        Util.debugEcho("Transition canceled")
        return true
    end

    -- Cancel any in-progress transition when starting a new one
    if STATE.transition.active then
        STATE.transition.active = false
        Util.debugEcho("Canceled previous transition")
    end

    -- Check if we should do an instant transition (duration = 0)
    if CONFIG.TRANSITION.DURATION <= 0 then
        -- Instant camera jump
        local targetState = Util.deepCopy(STATE.anchors[index])
        -- Ensure the target state is in FPS mode
        targetState.mode = 0
        targetState.name = "fps"
        Spring.SetCameraState(targetState, 0)
        Util.debugEcho("Instantly jumped to camera anchor: " .. index)
        return true
    end

    -- Start transition
    CameraTransition.start(STATE.anchors[index], CONFIG.TRANSITION.DURATION)
    STATE.transition.currentAnchorIndex = index
    Util.debugEcho("Loading camera anchor: " .. index)
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
        Util.debugEcho("Invalid or unset camera anchor: " .. (index or "nil"))
        return true
    end

    -- Store the anchor we're moving to
    STATE.lastUsedAnchor = index

    -- Get the selected unit to track
    local selectedUnits = Spring.GetSelectedUnits()

    if (STATE.tracking.mode ~= 'unit_tracking' and STATE.tracking.mode ~= 'fps') or not STATE.tracking.unitID then
        Util.debugEcho("No unit was tracked during focused anchor transition")
        -- Just do a normal anchor transition
        return CameraAnchor.focus(index)
    end

    local unitID = selectedUnits[1]
    if not Spring.ValidUnitID(unitID) then
        Util.debugEcho("Invalid unit for tracking during anchor transition")
        -- Just do a normal anchor transition
        return CameraAnchor.focus(index)
    end

    -- Cancel any in-progress transitions
    if STATE.transition.active then
        STATE.transition.active = false
        Util.debugEcho("Canceled previous transition")
    end

    -- Disable any existing tracking modes to avoid conflicts
    if not STATE.tracking.mode then
        Tracking.disableTracking()
    end

    -- Create a specialized transition that maintains focus on the unit
    local startState = Spring.GetCameraState()
    local endState = Util.deepCopy(STATE.anchors[index])

    -- Ensure both states are in FPS mode
    startState.mode = 0
    startState.name = "fps"
    endState.mode = 0
    endState.name = "fps"

    -- Enable tracking camera on the unit
    STATE.tracking.mode = 'unit_tracking'
    STATE.tracking.unitID = unitID
    STATE.tracking.lastCamDir = { x = 0, y = 0, z = 0 }
    STATE.tracking.lastRotation = { rx = 0, ry = 0, rz = 0 }

    local unitX, unitY, unitZ = Spring.GetUnitPosition(unitID)
    local targetPos = { x = unitX, y = unitY, z = unitZ }

    -- Set up the transition
    STATE.transition.steps = CameraTransition.createPositionTransition(startState, STATE.anchors[index], CONFIG.TRANSITION.DURATION, targetPos)
    STATE.transition.currentStepIndex = 1
    STATE.transition.startTime = Spring.GetTimer()
    STATE.transition.active = true
    STATE.transition.currentAnchorIndex = index

    Util.debugEcho("Moving to anchor " .. index .. " while tracking unit " .. unitID)
    return true
end

---@see ModifiableParams
---@see UtilsModule#adjustParams
function CameraAnchor.adjustParams(params)
    if Util.isTurboBarCamDisabled() then
        return
    end

    Util.adjustParams(params, 'ANCHORS', function() CONFIG.TRANSITION.DURATION = 2 end)
end

return {
    CameraAnchor = CameraAnchor
}