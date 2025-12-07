---@type RulesUnsyncedCallins
widget = widget

---@class Main just for navigation in IDE
function widget:GetInfo()
    return {
        name    = "Tactical Ultra-Responsive Brilliant Optics for BAR Camera",
        desc    = "Smooths the view, so you don’t have to.",
        author  = "SuperKitowiec",
        date    = "Mar 2025",
        license = "GNU GPL, v2 or later",
        layer   = -1,
        enabled = true,
        version = "2.1.0",
        handler = true,
    }
end

WG.TurboBarCam = {}
WG.TurboBarCam.ModuleManager = VFS.Include("LuaUI/TurboBarCam/module_manager.lua")

---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "Main")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local DebugUtils = ModuleManager.DebugUtils(function(m) DebugUtils = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local Actions = ModuleManager.Actions(function(m) Actions = m end)
local ProjectileTracker = ModuleManager.ProjectileTracker(function(m) ProjectileTracker = m end)
local ProjectileCamera = ModuleManager.ProjectileCamera(function(m) ProjectileCamera = m end)
local WidgetManager = ModuleManager.WidgetManager(function(m) WidgetManager = m end)
local UpdateManager = ModuleManager.UpdateManager(function(m) UpdateManager = m end)
local SelectionManager = ModuleManager.SelectionManager(function(m) SelectionManager = m end)
local UnitFollowCamera = ModuleManager.UnitFollowCamera(function(m) UnitFollowCamera = m end)
local DollyCam = ModuleManager.DollyCam(function(m) DollyCam = m end)
local CameraAnchor = ModuleManager.CameraAnchor(function(m) CameraAnchor = m end)
local SettingsManager = ModuleManager.SettingsManager(function(m) SettingsManager = m end)

--------------------------------------------------------------------------------
-- SPRING ENGINE CALLINS
--------------------------------------------------------------------------------
local function setupApi()
    ---@class TurboBarCamAPI
    WG.TurboBarCam.API = {
        ToggleTurboBarCam = WidgetManager.toggle,
        handleCameraBroadcastEvent = function(cameraState)
            Spring.SetCameraState(CameraCommons.convertSpringToFPSCameraState(cameraState), 1)
        end,
        isUnitSelectionAllowed = function()
            return STATE.allowPlayerCamUnitSelection
        end,
        forceFpsCamera = function()
            return STATE.enabled
        end,
        isInControl = function()
            return STATE.enabled and STATE.active.mode.name ~= nil
        end,
        stop = function()
            WidgetManager.stop()
        end,
        loadSettings = function(name, id, default, direct)
            if not STATE.settings.storages[name] then
                return nil
            end
            return SettingsManager.loadUserSetting(name, id, default, direct)
        end,
        saveErrorInfo = function(message, traceback)
            STATE.error = {}
            STATE.error.message = message
            STATE.error.traceback = traceback
        end,
        getAllTrackedProjectiles = function()
            return ProjectileTracker.getAllTrackedProjectiles()
        end,
        startTrackingProjectile = function(projectileId, mode)
            return ProjectileCamera.startTrackingProjectile(projectileId, mode)
        end,
    }
end


function widget:Initialize()
    -- Widget starts in disabled state, user must enable it manually
    STATE.enabled = false
    Actions.registerAllActions()
    setupApi()
    ProjectileTracker.initialize()
    Log:info("Loaded - Enable with /turbobarcam_toggle")
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
    if Spring.IsGUIHidden() == false and not Utils.isTurboBarCamDisabled() then
        DollyCam.draw()
        CameraAnchor.draw()
    end
end

function widget:Shutdown()
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
    if Utils.isTurboBarCamDisabled() then
        return
    end
    if Utils.isModeDisabled("unit_follow") then
        return
    end

    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits > 0 then
        local customCommands = widgetHandler.customCommands
        customCommands[#customCommands + 1] = UnitFollowCamera.COMMAND_DEFINITION
    end
end

if CONFIG and CONFIG.DEBUG and CONFIG.DEBUG.TRACE_BACK then
    for name, func in pairs(widget) do
        if type(func) == "function" and name ~= "GetInfo" then
            widget[name] = DebugUtils.wrapInTrace(func, name)
        end
    end
end
