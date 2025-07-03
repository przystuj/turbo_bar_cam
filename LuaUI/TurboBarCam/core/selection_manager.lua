---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "SelectionManager")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local UnitFollowCamera = ModuleManager.UnitFollowCamera(function(m) UnitFollowCamera = m end)
local SettingsManager = ModuleManager.SettingsManager(function(m) SettingsManager = m end)

---@class SelectionManager
local SelectionManager = {}

--- Handles selection changes
---@param selectedUnits number[] Array of selected unit IDs
function SelectionManager.handleSelectionChanged(selectedUnits)
    if Utils.isTurboBarCamDisabled() then
        return
    end

    -- If no units are selected and tracking is active, start grace period
    if #selectedUnits == 0 then
        if STATE.active.mode.name then
            -- Store the current tracked unit ID
            STATE.active.mode.lastUnitID = STATE.active.mode.unitID

            -- Start grace period timer (1 second)
            STATE.active.mode.graceTimer = Spring.GetTimer()
        end
        return
    end

    -- If units are selected, cancel any active grace period
    if STATE.active.mode.graceTimer then
        STATE.active.mode.graceTimer = nil
    end

    -- Get the first selected unit
    local unitID = selectedUnits[1]

    -- Update tracking if it's enabled
    if STATE.active.mode.name and STATE.active.mode.unitID ~= unitID then
        -- Save settings for the old unit before switching
        SettingsManager.saveModeSettings(STATE.active.mode.name, STATE.active.mode.unitID)

        if STATE.active.mode.name == 'unit_follow' then
            UnitFollowCamera.handleSelectNewUnit()
        end

        -- Switch tracking to the new unit
        STATE.active.mode.unitID = unitID
        STATE.active.mode.group_tracking.unitIDs = selectedUnits

        -- Load settings for the new unit
        SettingsManager.loadModeSettings(STATE.active.mode.name, unitID)

        Log:trace("Tracking switched to unit " .. unitID)
    end
end

return SelectionManager