---@type {Log: Log}
local LogModule = VFS.Include("LuaUI/TurboBarCam/common/log.lua")
---@type {Util: Util}
local UtilsModule = VFS.Include("LuaUI/TurboBarCam/common/utils.lua")
---@type {ModeManager: ModeManager}
local TrackingModule = VFS.Include("LuaUI/TurboBarCam/common/mode_manager.lua")
---@type {CameraCommons: CameraCommons}
local CameraCommonsModule = VFS.Include("LuaUI/TurboBarCam/common/camera_commons.lua")

---@return CommonModules
return {
    CameraCommons = CameraCommonsModule.CameraCommons,
    Util = UtilsModule.Util,
    Log = LogModule.Log,
    ModeManager = TrackingModule.ModeManager,
}