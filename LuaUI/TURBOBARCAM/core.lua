-- This file imports and exposes all core functionality modules

-- Import core modules
---@type {CameraCommons: CameraCommons}
local CameraCommons = VFS.Include("LuaUI/TURBOBARCAM/core/camera_commons.lua")
---@type {CameraTransition: CameraTransition}
local TransitionModule = VFS.Include("LuaUI/TURBOBARCAM/core/transition.lua")
---@type {WidgetControl: WidgetControl}
local WidgetControlModule = VFS.Include("LuaUI/TURBOBARCAM/core/widget_control.lua")
---@type {Actions: Actions}
local Actions = VFS.Include("LuaUI/TURBOBARCAM/core/actions.lua")
---@type {UpdateManager: UpdateManager}
local UpdateManager = VFS.Include("LuaUI/TURBOBARCAM/core/update.lua")
---@type {SelectionManager: SelectionManager}
local SelectionManager = VFS.Include("LuaUI/TURBOBARCAM/core/selection.lua")

-- Export all core modules
---@return CoreModules
return {
    CameraCommons = CameraCommons.CameraCommons,
    Transition = TransitionModule.CameraTransition,
    WidgetControl = WidgetControlModule.WidgetControl,
    Actions = Actions.Actions,
    UpdateManager = UpdateManager.UpdateManager,
    SelectionManager = SelectionManager.SelectionManager,
}