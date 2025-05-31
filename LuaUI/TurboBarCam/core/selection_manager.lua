---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type FPSCamera
local FPSCamera = VFS.Include("LuaUI/TurboBarCam/features/fps/fps.lua").FPSCamera
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/core/settings_manager.lua")

local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log

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
        local oldIdentifier = SettingsManager.chooseIdentifier(STATE.mode.name, STATE.mode.unitID)
        if oldIdentifier then
            SettingsManager.saveModeSettings(STATE.mode.name, STATE.mode.unitID)
        end

        if STATE.mode.name == 'fps' then
            FPSCamera.handleSelectNewUnit()
            STATE.mode.fps.lastUnitProjectileID = nil
            STATE.mode.fps.projectileTrackingEnabled = false
            STATE.mode.fps.lastProjectilePosition = nil
        end

        -- Switch tracking to the new unit
        STATE.mode.unitID = unitID
        STATE.mode.group_tracking.unitIDs = selectedUnits

        -- Load settings for the new unit
        local newIdentifier = SettingsManager.chooseIdentifier(STATE.mode.name, unitID)
        if newIdentifier then
            SettingsManager.loadModeSettings(STATE.mode.name, unitID)
        end

        Log.trace("Tracking switched to unit " .. unitID)
    end
end

return SelectionManager