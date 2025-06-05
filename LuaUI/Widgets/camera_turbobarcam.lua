---@class Main just for navigation in IDE
function widget:GetInfo()
    return {
        name    = "Tactical Ultra-Responsive Brilliant Optics for BAR Camera",
        desc    = "Smooths the view, so you don’t have to.",
        author  = "SuperKitowiec",
        date    = "Mar 2025",
        license = "GNU GPL, v2 or later",
        layer   = 1,
        enabled = true,
        version = 1.8,
        handler = true,
    }
end

WG.TurboBarCam = {}
WG.TurboBarCam.ModuleManager = WG.TurboBarCam.ModuleManager or VFS.Include("LuaUI/TurboBarCam/module_manager.lua")

---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local Util = ModuleManager.Util(function(m) Util = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local Actions = ModuleManager.Actions(function(m) Actions = m end)
local ProjectileTracker = ModuleManager.ProjectileTracker(function(m) ProjectileTracker = m end)
local WidgetManager = ModuleManager.WidgetManager(function(m) WidgetManager = m end)
local UpdateManager = ModuleManager.UpdateManager(function(m) UpdateManager = m end)
local SelectionManager = ModuleManager.SelectionManager(function(m) SelectionManager = m end)
local UnitFollowCamera = ModuleManager.UnitFollowCamera(function(m) UnitFollowCamera = m end)
local DollyCam = ModuleManager.DollyCam(function(m) DollyCam = m end)

local cameraStateOnInit = Spring.GetCameraState()

--------------------------------------------------------------------------------
-- SPRING ENGINE CALLINS
--------------------------------------------------------------------------------

function widget:Initialize()
    cameraStateOnInit = Spring.GetCameraState()
    -- Widget starts in disabled state, user must enable it manually
    STATE.enabled = false

    Actions.registerAllActions()

    -- external hooks
    WG.TurboBarCam.isInControl = function()
        return STATE.enabled and STATE.mode.name ~= nil
    end
    WG.TurboBarCam.forceFpsCamera = function()
        return STATE.enabled
    end
    WG.TurboBarCam.isUnitSelectionAllowed = function()
        return STATE.allowPlayerCamUnitSelection
    end
    WG.TurboBarCam.handleCameraBroadcastEvent = function(cameraState)
        Spring.SetCameraState(CameraCommons.convertSpringToFPSCameraState(cameraState), 1)
    end

    Log:info("Loaded - use /turbobarcam_toggle to enable. Log level: " .. CONFIG.DEBUG.LOG_LEVEL)
end

---@param selectedUnits number[] Array of selected unit IDs
function widget:SelectionChanged(selectedUnits)
    SelectionManager.handleSelectionChanged(selectedUnits)
end

function widget:Update(dt)
    UpdateManager.processCycle(dt)
end

function widget:GameFrame(frame)
    ProjectileTracker.update(frame)
end

function widget:DrawWorld()
    if Spring.IsGUIHidden() == false then
        DollyCam.draw()
    end
end

function widget:Shutdown()
    --make sure that camera mode is restored
    Spring.SetCameraState({ mode = cameraStateOnInit.mode, name = cameraStateOnInit.name })
    -- refresh units command bar to remove custom command
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits > 0 then
        Spring.SelectUnitArray(selectedUnits)
    end
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 1)
    Spring.SetConfigInt("FPSClampPos", 1)
    Spring.SetConfigInt("FPSFOV", STATE.originalFpsCameraFov or 45)
    if STATE.enabled then
        WidgetManager.disable()
    end
    WG.TurboBarCam = nil
end

---@param cmdID number Command ID
---@param cmdParams table Command parameters
---@param _ table Command options (unused)
---@return boolean handled Whether the command was handled
function widget:CommandNotify(cmdID, cmdParams, _)
    if cmdID == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT then
        return UnitFollowCamera.setFixedLookPoint(cmdParams)
    end
    return false
end

function widget:CommandsChanged()
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("unit_follow") then
        return
    end

    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits > 0 then
        local customCommands = widgetHandler.customCommands
        customCommands[#customCommands + 1] = UnitFollowCamera.COMMAND_DEFINITION
    end
end

if CONFIG and CONFIG.DEBUG and CONFIG.DEBUG.TRACE_BACK then
    local function wrapWithTrace(func, name)
        return function(...)
            local args = { ... }
            local success, result = xpcall(
                    function()
                        return func(unpack(args))
                    end,
                    function(err)
                        Log:warn("[TurboBar] Error in " .. name .. ": " .. tostring(err))
                        Log:warn(debug.traceback("", 2))
                        return nil
                    end
            )
            if not success then
                -- fallback return values for known callins that MUST return something
                if name == "LayoutButtons" then
                    return {}
                end
                return nil
            end
            return result
        end
    end

    for name, func in pairs(widget) do
        if type(func) == "function" and name ~= "GetInfo" then
            widget[name] = wrapWithTrace(func, name)
        end
    end
end