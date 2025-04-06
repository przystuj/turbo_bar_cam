---@type Spring
Spring = Spring
---@type Widget
widget = widget
---@type WeaponDefs
WeaponDefs = WeaponDefs

function widget:GetInfo()
    return {
        name = "Tactical Ultra-Responsive Brilliant Optics for BAR Camera",
        desc = "Advanced camera control suite with smooth transitions, unit tracking, FPS mode, orbital view, spectator controls, and more.",
        author = "SuperKitowiec",
        date = "Mar 2025",
        license = "GNU GPL, v2 or later",
        layer = 1,
        enabled = true,
        version = 1.1,
        handler = true,
    }
end

---@class Main just for navigation in IDE

---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type FeatureModules
local TurboFeatures = VFS.Include("LuaUI/TURBOBARCAM/features.lua")
---@type CoreModules
local TurboCore = VFS.Include("LuaUI/TURBOBARCAM/core.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TURBOBARCAM/common.lua")
---@type Actions
local Actions = VFS.Include("LuaUI/TURBOBARCAM/standalone/actions.lua").Actions

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

function widget:Update(frame)
    UpdateManager.processCycle(frame)
end

function widget:Initialize()
    -- Widget starts in disabled state, user must enable it manually
    STATE.enabled = false
    Actions.registerAllActions()
    Log.info("Loaded - use /turbobarcam_toggle to enable.\n[TURBOBARCAM] Loaded with log level: " .. CONFIG.DEBUG.LOG_LEVEL)
end

function widget:Shutdown()
    -- Make sure we clean up
    if STATE.enabled then
        WidgetControl.disable()
    end
    WG.TURBOBARCAM = nil
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