---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua")
---@type Util
local Util = VFS.Include("LuaUI/TurboBarCam/common/utils.lua")
---@type ModeManager
local ModeManager = VFS.Include("LuaUI/TurboBarCam/common/mode_manager.lua")
---@type CameraCommons
local CameraCommons = VFS.Include("LuaUI/TurboBarCam/common/camera_commons.lua")

---@return CommonModules
return {
    CameraCommons = CameraCommons,
    Util = Util,
    Log = Log,
    ModeManager = ModeManager,
}