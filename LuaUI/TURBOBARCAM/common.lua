---@type {Util: Util}
local UtilsModule = VFS.Include("LuaUI/TURBOBARCAM/common/utils.lua")
---@type {TrackingManager: TrackingManager}
local TrackingModule = VFS.Include("LuaUI/TURBOBARCAM/common/tracking.lua")

---@return CommonModules
return {
    Util = UtilsModule.Util,
    Tracking = TrackingModule.TrackingManager,
}