function widget:GetInfo()
    return {
        name = "Tactical Ultra-Responsive Brilliant Optics for BAR Camera",
        desc = "Smooths the view, so you don’t have to.",
        author = "SuperKitowiec",
        date = "Mar 2025",
        license = "GNU GPL, v2 or later",
        layer = 1,
        enabled = true,
        version = 1.2,
        handler = true,
    }
end

---@class Main just for navigation in IDE

---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type FeatureModules
local TurboFeatures = VFS.Include("LuaUI/TurboBarCam/features.lua")
---@type CoreModules
local TurboCore = VFS.Include("LuaUI/TurboBarCam/core.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type Actions
local Actions = VFS.Include("LuaUI/TurboBarCam/standalone/actions.lua").Actions

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local WidgetControl = TurboCore.WidgetControl
local FPSCamera = TurboFeatures.FPSCamera
local UpdateManager = TurboCore.UpdateManager
local SelectionManager = TurboCore.SelectionManager

--------------------------------------------------------------------------------
-- SPRING ENGINE CALLINS
--------------------------------------------------------------------------------

---@param selectedUnits number[] Array of selected unit IDs
function widget:SelectionChanged(selectedUnits)
    SelectionManager.handleSelectionChanged(selectedUnits)
end

function widget:Update()
    UpdateManager.processCycle()
end

function widget:Initialize()
    -- Widget starts in disabled state, user must enable it manually
    STATE.enabled = false
    Actions.registerAllActions()
    WG.TurboBarCam.isInControl = function()
        return STATE.enabled and STATE.tracking.mode ~= nil
    end
    Log.info("Loaded - use /turbobarcam_toggle to enable.\n[TurboBarCam] Loaded with log level: " .. CONFIG.DEBUG.LOG_LEVEL)
end

function widget:Shutdown()
    -- Make sure we clean up
    if STATE.enabled then
        WidgetControl.disable()
    end
    WG.TurboBarCam = nil
    -- refresh units command bar to remove custom command
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits > 0 then
        Spring.SelectUnitArray(selectedUnits)
    end
end

---@param cmdID number Command ID
---@param cmdParams table Command parameters
---@param _ table Command options (unused)
---@return boolean handled Whether the command was handled
function widget:CommandNotify(cmdID, cmdParams, _)
    if cmdID == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT then
        return FPSCamera.setFixedLookPoint(cmdParams)
    end
    return false
end

function widget:CommandsChanged()
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("fps") then
        return
    end

    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits > 0 then
        local customCommands = widgetHandler.customCommands
        customCommands[#customCommands + 1] = FPSCamera.COMMAND_DEFINITION
    end
end