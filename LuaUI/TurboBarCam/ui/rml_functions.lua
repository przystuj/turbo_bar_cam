---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type CoreModules
local CoreModules = VFS.Include("LuaUI/TurboBarCam/core.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Log = CommonModules.Log

-- Expose UI functions to be called from RML
WG.TurboBarCam.UI = WG.TurboBarCam.UI or {}

-- RML-callable function to toggle TurboBarCam
function WG.TurboBarCam.UI.ToggleTurboBarCam()
    CoreModules.WidgetControl.toggle()
end

-- RML-callable function to toggle specific camera mode
function WG.TurboBarCam.UI.ToggleMode(mode)
    if mode and STATE.enabled then
        local actionName = "turbobarcam_toggle_" .. mode
        
        -- Execute the action through Spring
        Spring.SendCommands(actionName)
    else
        Log.info("[UI] Could not toggle mode - TurboBarCam not enabled or mode invalid")
    end
end
