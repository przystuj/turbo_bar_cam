-- This file imports and exposes all core functionality modules

-- Import core modules
---@type {WidgetControl: WidgetControl}
local WidgetControlModule = VFS.Include("LuaUI/TURBOBARCAM/core/widget_control.lua")
---@type {UpdateManager: UpdateManager}
local UpdateManager = VFS.Include("LuaUI/TURBOBARCAM/core/update.lua")
---@type {SelectionManager: SelectionManager}
local SelectionManager = VFS.Include("LuaUI/TURBOBARCAM/core/selection.lua")

-- Export all core modules
---@return CoreModules
return {
    WidgetControl = WidgetControlModule.WidgetControl,
    UpdateManager = UpdateManager.UpdateManager,
    SelectionManager = SelectionManager.SelectionManager,
}