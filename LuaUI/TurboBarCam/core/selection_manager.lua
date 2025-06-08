---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
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
        if STATE.mode.name then
            -- Store the current tracked unit ID
            STATE.mode.lastUnitID = STATE.mode.unitID

            -- Start grace period timer (1 second)
            STATE.mode.graceTimer = Spring.GetTimer()
        end
        return
    end

    -- If units are selected, cancel any active grace period
    if STATE.mode.graceTimer then
        STATE.mode.graceTimer = nil
    end

    -- Get the first selected unit
    local unitID = selectedUnits[1]

    -- Update tracking if it's enabled
    if STATE.mode.name and STATE.mode.unitID ~= unitID then
        -- Save settings for the old unit before switching
        SettingsManager.saveModeSettings(STATE.mode.name, STATE.mode.unitID)

        if STATE.mode.name == 'unit_follow' then
            UnitFollowCamera.handleSelectNewUnit()
            STATE.mode.unit_follow.lastUnitProjectileID = nil
            STATE.mode.unit_follow.projectileTrackingEnabled = false
            STATE.mode.unit_follow.lastProjectilePosition = nil
        end

        -- Switch tracking to the new unit
        STATE.mode.unitID = unitID
        STATE.mode.group_tracking.unitIDs = selectedUnits

        -- Load settings for the new unit
        SettingsManager.loadModeSettings(STATE.mode.name, unitID)

        Log:trace("Tracking switched to unit " .. unitID)
    end
end

return SelectionManager