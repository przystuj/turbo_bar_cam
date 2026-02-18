---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "SelectionManager")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local WorldUtils = ModuleManager.WorldUtils(function(m) WorldUtils = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local UnitFollowCamera = ModuleManager.UnitFollowCamera(function(m) UnitFollowCamera = m end)
local ProjectileCamera = ModuleManager.ProjectileCamera(function(m) ProjectileCamera = m end)
local SettingsManager = ModuleManager.SettingsManager(function(m) SettingsManager = m end)

---@class SelectionManager
local SelectionManager = {}

--- Handles selection changes
---@param selectedUnits number[] Array of selected unit IDs
function SelectionManager.handleSelectionChanged(selectedUnits)
    if Utils.isTurboBarCamDisabled() then
        return
    end

    SelectionManager.updateLastUnitPosition()

    -- If no units are selected and tracking is active, start grace period
    if #selectedUnits == 0 then
        if STATE.active.mode.name then
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
        UnitFollowCamera.handleSelectNewUnit(unitID)
        ProjectileCamera.handleSelectNewUnit()

        -- Switch tracking to the new unit
        STATE.active.mode.unitID = unitID
        STATE.active.mode.group_tracking.unitIDs = selectedUnits

        -- Load settings for the new unit
        SettingsManager.loadModeSettings(STATE.active.mode.name, unitID)

        Log:trace("Tracking switched to unit " .. unitID)
    end
end

--- Updates the last unit position in core state
function SelectionManager.updateLastUnitPosition()
    local unitID = STATE.active.mode.unitID
    if not unitID or not Spring.ValidUnitID(unitID) then
        return
    end

    local x, y, z, front, up, right = WorldUtils.getUnitVectors(unitID)
    if x then
        local selectionState = STATE.core.selection
        selectionState.lastUnitID = unitID
        selectionState.lastUnitPosition.x = x
        selectionState.lastUnitPosition.y = y
        selectionState.lastUnitPosition.z = z
        selectionState.lastUpdateTime = Spring.GetTimer()

        -- Update orientation (store as indexed vectors)
        TableUtils.syncTable(selectionState.lastUnitFront, front)
        TableUtils.syncTable(selectionState.lastUnitUp, up)
        TableUtils.syncTable(selectionState.lastUnitRight, right)
    end
end

return SelectionManager
