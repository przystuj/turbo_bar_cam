---@type LogBuilder
local LogBuilder = VFS.Include("LuaUI/TurboBarCommons/log_builder.lua")

---@class Log : LoggerInstance
local Log = LogBuilder.createInstance("TurboBarCam", function()
    ---@type WidgetConfig
    local CONFIG = WG.TurboBarCam.CONFIG
    return CONFIG and CONFIG.DEBUG.LOG_LEVEL or "INFO"
end)

return Log