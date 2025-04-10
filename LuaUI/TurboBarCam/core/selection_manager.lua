---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local TrackingManager = CommonModules.TrackingManager

---@class SelectionManager
local SelectionManager = {}

--- Handles selection changes
---@param selectedUnits number[] Array of selected unit IDs
function SelectionManager.handleSelectionChanged(selectedUnits)
    if Util.isTurboBarCamDisabled() then
        return
    end

    -- If no units are selected and tracking is active, start grace period
    if #selectedUnits == 0 then
        if STATE.tracking.mode then
            -- Store the current tracked unit ID
            STATE.tracking.lastUnitID = STATE.tracking.unitID

            -- Start grace period timer (1 second)
            STATE.tracking.graceTimer = Spring.GetTimer()
        end
        return
    end

    -- If units are selected, cancel any active grace period
    if STATE.tracking.graceTimer then
        STATE.tracking.graceTimer = nil
    end

    -- Get the first selected unit
    local unitID = selectedUnits[1]

    -- Update tracking if it's enabled
    if STATE.tracking.mode and STATE.tracking.unitID ~= unitID then
        TrackingManager.saveModeSettings(STATE.tracking.mode, STATE.tracking.unitID)

        -- Switch tracking to the new unit
        STATE.tracking.unitID = unitID
        STATE.tracking.group.unitIDs = selectedUnits

        TrackingManager.loadModeSettings(STATE.tracking.mode, unitID)
        Log.debug("Tracking switched to unit " .. unitID)
    end
end

return {
    SelectionManager = SelectionManager
}