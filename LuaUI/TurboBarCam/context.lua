WG.TurboBarCam = WG.TurboBarCam or {}

VFS.Include("LuaUI/TurboBarCam/context/config.lua")
VFS.Include("LuaUI/TurboBarCam/context/state.lua")

---@return WidgetContext
return {
    CONFIG = WG.TurboBarCam.CONFIG,
    STATE = WG.TurboBarCam.STATE
}