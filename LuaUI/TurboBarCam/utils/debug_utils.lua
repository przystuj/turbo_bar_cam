local ModuleManager = WG.TurboBarCam.ModuleManager ---@type ModuleManager
local Log = ModuleManager.Log(function(m) Log = m end, "DebugUtils")

---@class DebugUtils
local DebugUtils = {}

function DebugUtils.wrapInTrace(func, name)
    return function(...)
        local args = { ... }
        local success, result = xpcall(
                function()
                    return func(unpack(args))
                end,
                function(err)
                    local API = WG.TurboBarCam.API ---@type TurboBarCamAPI
                    local message = "Error in " .. name .. ": " .. tostring(err)
                    local traceback = debug.traceback("", 2)
                    Log:warn(message)
                    Log:warn(traceback)
                    API.saveErrorInfo(message, traceback)
                    API.stop()
                    return nil
                end
        )
        if not success then
            if name == "LayoutButtons" then
                return {}
            end
            return nil
        end
        return result
    end
end

return DebugUtils