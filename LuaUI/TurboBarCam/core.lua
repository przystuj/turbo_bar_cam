---@type WidgetManager
local WidgetManager = VFS.Include("LuaUI/TurboBarCam/core/widget_manager.lua")
---@type UpdateManager
local UpdateManager = VFS.Include("LuaUI/TurboBarCam/core/update_manager.lua")
---@type SelectionManager
local SelectionManager = VFS.Include("LuaUI/TurboBarCam/core/selection_manager.lua")

---@return CoreModules
return {
    WidgetManager = WidgetManager,
    UpdateManager = UpdateManager,
    SelectionManager = SelectionManager,
}