function widget:GetInfo()
    return {
        name = "Tactical Ultra-Responsive Rotation & Brilliant Optics for BAR Camera",
        desc = "Advanced camera control suite with smooth transitions, unit tracking, FPS mode, orbital view, spectator controls, and fixed point tracking. Features include camera anchors, dynamic offsets, free camera mode, auto-orbit, and spectator unit groups.",
        author = "SuperKitowiec",
        date = "Mar 2025",
        license = "GNU GPL, v2 or later",
        layer = 0,
        enabled = true,
        version = 1,
        handler = true,
    }
end

-- Load modules
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type FeatureModules
local TurboFeatures = VFS.Include("LuaUI/TURBOBARCAM/features.lua")
---@type CoreModules
local TurboCore = VFS.Include("LuaUI/TURBOBARCAM/core.lua")
---@type CommonModules
local TurboCommons = VFS.Include("LuaUI/TURBOBARCAM/common.lua")

---@type AllModules
local AllModules = {
    Context = WidgetContext,
    Features = TurboFeatures,
    Core = TurboCore,
    Common = TurboCommons,
}

-- Initialize shorthand references
local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE
local Util = TurboCommons.Util
local WidgetControl = TurboCore.WidgetControl
local FPSCamera = TurboFeatures.FPSCamera
local Actions = TurboCore.Actions
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
    UpdateManager.processCycle(AllModules)
end

function widget:Initialize()
    -- Widget starts in disabled state, user must enable it manually
    STATE.enabled = false

    WG.TURBOBARCAM.Util = AllModules.Common.Util

    -- Initialize the managers with modules reference
    UpdateManager.setModules(AllModules)
    SelectionManager.setModules(AllModules)

    -- Register all action handlers
    Actions.registerAllActions(AllModules)

    Util.debugEcho("TURBOBARCAM loaded but disabled. Use /toggle_camera_suite to enable.")
end

function widget:Shutdown()
    -- Make sure we clean up
    if STATE.enabled then
        WidgetControl.disable()
    end
    WG.TURBOBARCAM = nil
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
    if not STATE.enabled then
        return
    end

    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits > 0 then
        local customCommands = widgetHandler.customCommands
        customCommands[#customCommands + 1] = FPSCamera.COMMAND_DEFINITION
    end
end