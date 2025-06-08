---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local Log = ModuleManager.Log(function(m) Log = m end)

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
                    Log:warn("Error in " .. name .. ": " .. tostring(err))
                    Log:warn(debug.traceback("", 2))
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