-- Selection handling module for TURBOBARCAM
-- Handles unit selection changes
---@type {CONFIG: CONFIG, STATE: STATE}
local TurboConfig = VFS.Include("LuaUI/TURBOBARCAM/config/config.lua")
local CONFIG = TurboConfig.CONFIG
local STATE = TurboConfig.STATE

---@class SelectionManager
local SelectionManager = {}

-- Store modules for internal use
SelectionManager.modules = nil

--- Initializes modules reference for internal use
---@param modules table Modules object containing Features and Core
function SelectionManager.setModules(modules)
    SelectionManager.modules = modules
end

--- Handles selection changes
---@param selectedUnits number[] Array of selected unit IDs
function SelectionManager.handleSelectionChanged(selectedUnits)
    if not STATE.enabled then
        return
    end
    
    -- Access utility functions
    local Util = SelectionManager.modules and SelectionManager.modules.Core and 
                 SelectionManager.modules.Core.Util
    
    if not Util then return end

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
        -- Save current offsets for the previous unit if in FPS mode
        if (STATE.tracking.mode == 'fps' or STATE.tracking.mode == 'fixed_point') and STATE.tracking.unitID then
            STATE.tracking.unitOffsets[STATE.tracking.unitID] = {
                height = CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT,
                forward = CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD,
                side = CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE,
                rotation = CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION
            }
        end

        -- Switch tracking to the new unit
        STATE.tracking.unitID = unitID

        -- For FPS mode, load appropriate offsets
        if STATE.tracking.mode == 'fps' or STATE.tracking.mode == 'fixed_point' then
            if STATE.tracking.unitOffsets[unitID] then
                -- Use saved offsets
                CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT = STATE.tracking.unitOffsets[unitID].height
                CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD = STATE.tracking.unitOffsets[unitID].forward
                CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE = STATE.tracking.unitOffsets[unitID].side
                CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION = STATE.tracking.unitOffsets[unitID].rotation or CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.ROTATION
                Util.debugEcho("Camera switched to unit " .. unitID .. " with saved offsets")
            else
                -- Get new default height for this unit
                local unitHeight = Util.getUnitHeight(unitID)
                CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.HEIGHT = unitHeight
                CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT = unitHeight
                CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.FORWARD
                CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.SIDE
                CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION = CONFIG.CAMERA_MODES.FPS.DEFAULT_OFFSETS.ROTATION

                -- Initialize storage for this unit
                STATE.tracking.unitOffsets[unitID] = {
                    height = CONFIG.CAMERA_MODES.FPS.OFFSETS.HEIGHT,
                    forward = CONFIG.CAMERA_MODES.FPS.OFFSETS.FORWARD,
                    side = CONFIG.CAMERA_MODES.FPS.OFFSETS.SIDE,
                    rotation = CONFIG.CAMERA_MODES.FPS.OFFSETS.ROTATION
                }

                Util.debugEcho("Camera switched to unit " .. unitID .. " with new offsets")
            end
        else
            Util.debugEcho("Tracking switched to unit " .. unitID)
        end
    end
end

return {
    SelectionManager = SelectionManager
}