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

local function togglePointOrbit()
    -- Only handle if no other mode is active or we're toggling an existing mode
    if not STATE.mode.name or STATE.mode.name == 'orbit' then
        Features.OrbitingCamera.togglePointOrbit()
    end
end

-- Initialization function - registers global mouse controls
function CameraQuickControls.initialize()
    MouseManager.registerMode('global')
    MouseManager.registerMode('orbit')

    -- Middle mouse button (MMB) for orbit point tracking
    MouseManager.onDoubleMMB('global', togglePointOrbit)
    MouseManager.onDoubleMMB('orbit', togglePointOrbit)

    Log.info("Camera quick controls initialized")
end

return {
    CameraQuickControls = CameraQuickControls
}