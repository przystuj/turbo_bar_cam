---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type FeatureModules
local Features = VFS.Include("LuaUI/TurboBarCam/features.lua")
---@type MouseManager
local MouseManager = VFS.Include("LuaUI/TurboBarCam/standalone/mouse_manager.lua").MouseManager

local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log

---@class CameraQuickControls
local CameraQuickControls = {}

-- Initialization function - registers global mouse controls
function CameraQuickControls.initialize()
    -- Register with mouse manager for global controls (no mode)
    MouseManager.registerMode('global')

    -- Middle mouse button (MMB) for orbit point tracking
    MouseManager.onMMB('global', function(x, y)
        -- Only handle if no other mode is active or we're toggling an existing mode
        if not STATE.tracking.mode or STATE.tracking.mode == 'orbit' then
            Features.OrbitingCamera.togglePointOrbit()
        end
    end)

    Log.info("Camera quick controls initialized")
end

-- Cleanup function if needed
function CameraQuickControls.shutdown()
    -- Unregister mode if needed
    -- MouseManager.unregisterMode('global')
end

return {
    CameraQuickControls = CameraQuickControls
}