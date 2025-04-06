---@type {Util: UtilsModule}
local UtilsModule = VFS.Include("LuaUI/TURBOBARCAM/common/utils.lua")
---@type {TrackingManager: TrackingManager}
local TrackingModule = VFS.Include("LuaUI/TURBOBARCAM/common/tracking_manager.lua")
---@type {CameraCommons: CameraCommons}
local CameraCommons = VFS.Include("LuaUI/TURBOBARCAM/common/camera_commons.lua")

---@return CommonModules
return {
    CameraCommons = CameraCommons.CameraCommons,
    Util = UtilsModule.Util,
    TrackingManager = TrackingModule.TrackingManager,
}