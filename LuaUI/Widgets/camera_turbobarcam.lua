function widget:GetInfo()
    return {
        name = "Tactical Ultra-Responsive Brilliant Optics for BAR Camera",
        desc = "Smooths the view, so you don’t have to.",
        author = "SuperKitowiec",
        date = "Mar 2025",
        license = "GNU GPL, v2 or later",
        layer = 1,
        enabled = true,
        version = 1.4,
        handler = true,
    }
end

---@class Main just for navigation in IDE

---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type FeatureModules
local FeatureModules = VFS.Include("LuaUI/TurboBarCam/features.lua")
---@type CoreModules
local CoreModules = VFS.Include("LuaUI/TurboBarCam/core.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type Actions
local Actions = VFS.Include("LuaUI/TurboBarCam/standalone/actions.lua").Actions
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/standalone/settings_manager.lua").SettingsManager
---@type ProjectileTracker
local ProjectileTracker = VFS.Include("LuaUI/TurboBarCam/standalone/projectile_tracker.lua").ProjectileTracker

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log
local WidgetControl = CoreModules.WidgetControl
local FPSCamera = FeatureModules.FPSCamera
local UpdateManager = CoreModules.UpdateManager
local SelectionManager = CoreModules.SelectionManager
local cameraStateOnInit = Spring.GetCameraState()

--------------------------------------------------------------------------------
-- SPRING ENGINE CALLINS
--------------------------------------------------------------------------------

function widget:Initialize()
    -- Widget starts in disabled state, user must enable it manually
    STATE.enabled = false

    -- it's required in settings_manager unfortunately
    WG.TurboBarCam.FeatureModules = FeatureModules
    Actions.registerAllActions()

    -- external hooks
    WG.TurboBarCam.isInControl = function()
        return STATE.enabled and STATE.tracking.mode ~= nil
    end
    WG.TurboBarCam.isUnitSelectionAllowed = function()
        return STATE.allowPlayerCamUnitSelection
    end

    Log.info("Loaded - use /turbobarcam_toggle to enable.\n[TurboBarCam] Loaded with log level: " .. CONFIG.DEBUG.LOG_LEVEL)
end

---@param selectedUnits number[] Array of selected unit IDs
function widget:SelectionChanged(selectedUnits)
    SelectionManager.handleSelectionChanged(selectedUnits)
end

function widget:Update()
    UpdateManager.processCycle()
end

function widget:GameFrame(frame)
    ProjectileTracker.update(frame)
end

function widget:Shutdown()
    -- Make sure we clean up
    if STATE.enabled then
        WidgetControl.disable()
    end
    WG.TurboBarCam = nil
    -- refresh units command bar to remove custom command
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits > 0 then
        Spring.SelectUnitArray(selectedUnits)
    end
    --make sure that camera mode is restored
    Spring.SetCameraState({ mode = cameraStateOnInit.mode, name = cameraStateOnInit.name })
end

---@param cmdID number Command ID
---@param cmdParams table Command parameters
---@param _ table Command options (unused)
---@return boolean handled Whether the command was handled
function widget:CommandNotify(cmdID, cmdParams, _)
    if cmdID == CONFIG.COMMANDS.SET_FIXED_LOOK_POINT then
        return FPSCamera.setFixedLookPoint(cmdParams)
    end
    return false
end

function widget:CommandsChanged()
    if Util.isTurboBarCamDisabled() then
        return
    end
    if Util.isModeDisabled("fps") then
        return
    end

    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits > 0 then
        local customCommands = widgetHandler.customCommands
        customCommands[#customCommands + 1] = FPSCamera.COMMAND_DEFINITION
    end
end