---@type {Log: Log}
local LogModule = VFS.Include("LuaUI/TURBOBARCAM/common/log.lua")
---@type {Util: Util}
local UtilsModule = VFS.Include("LuaUI/TURBOBARCAM/common/utils.lua")
---@type {TrackingManager: TrackingManager}
local TrackingModule = VFS.Include("LuaUI/TURBOBARCAM/common/tracking_manager.lua")
---@type {CameraCommons: CameraCommons}
local CameraCommonsModule = VFS.Include("LuaUI/TURBOBARCAM/common/camera_commons.lua")

---@return CommonModules
return {
    CameraCommons = CameraCommonsModule.CameraCommons,
    Util = UtilsModule.Util,
    Log = LogModule.Log,
    TrackingManager = TrackingModule.TrackingManager,
}