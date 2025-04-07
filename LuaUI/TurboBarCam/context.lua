-- This file serves as the interface for widget context - state and config

---@type {WidgetConfig: WidgetConfigModule}
local WidgetConfig = VFS.Include("LuaUI/TurboBarCam/context/config.lua")
---@type {WidgetState: WidgetStateModule}
local WidgetState = VFS.Include("LuaUI/TurboBarCam/context/state.lua")

---@return WidgetContext
return {
    WidgetConfig = WidgetConfig,
    WidgetState = WidgetState
}