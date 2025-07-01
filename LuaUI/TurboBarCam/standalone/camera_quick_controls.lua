---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONSTANTS = ModuleManager.CONSTANTS(function(m) CONSTANTS = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "CameraQuickControls")
local MouseManager = ModuleManager.MouseManager(function(m) MouseManager = m end)
local OrbitingCamera = ModuleManager.OrbitingCamera(function(m) OrbitingCamera = m end)

---@class CameraQuickControls
local CameraQuickControls = {}

local function togglePointOrbit()
    Log:debug("toggle p")
    -- Only handle if no other mode is active or we're toggling an existing mode
    if not STATE.active.mode.name or STATE.active.mode.name == CONSTANTS.MODE.ORBIT then
        OrbitingCamera.togglePointOrbit()
    end
end

-- Initialization function - registers global mouse controls
function CameraQuickControls.initialize()
    MouseManager.registerMode('global')
    MouseManager.registerMode(CONSTANTS.MODE.ORBIT)

    -- Middle mouse button (MMB) for orbit point tracking
    MouseManager.onDoubleMMB('global', togglePointOrbit)
    MouseManager.onDoubleMMB(CONSTANTS.MODE.ORBIT, togglePointOrbit)

    Log:info("Camera quick controls initialized")
end

return CameraQuickControls