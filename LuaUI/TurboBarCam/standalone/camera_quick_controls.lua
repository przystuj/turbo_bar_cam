---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local MouseManager = ModuleManager.MouseManager(function(m) MouseManager = m end)
local OrbitingCamera = ModuleManager.OrbitingCamera(function(m) OrbitingCamera = m end)

---@class CameraQuickControls
local CameraQuickControls = {}

local function togglePointOrbit()
    -- Only handle if no other mode is active or we're toggling an existing mode
    if not STATE.mode.name or STATE.mode.name == 'orbit' then
        OrbitingCamera.togglePointOrbit()
    end
end

-- Initialization function - registers global mouse controls
function CameraQuickControls.initialize()
    MouseManager.registerMode('global')
    MouseManager.registerMode('orbit')

    -- Middle mouse button (MMB) for orbit point tracking
    MouseManager.onDoubleMMB('global', togglePointOrbit)
    MouseManager.onDoubleMMB('orbit', togglePointOrbit)

    Log:info("Camera quick controls initialized")
end

return CameraQuickControls