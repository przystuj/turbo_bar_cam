function widget:GetInfo()
    return {
        name = "Tactical Ultra-Responsive Rotation & Brilliant Optics for BAR Camera",
        desc = "Advanced camera control suite with smooth transitions, unit tracking, FPS mode, orbital view, spectator controls, and fixed point tracking. Features include camera anchors, dynamic offsets, free camera mode, auto-orbit, and spectator unit groups.",
        author = "SuperKitowiec",
        date = "Mar 2025",
        license = "GNU GPL, v2 or later",
        layer = 0,
        enabled = true,
        version = 1,
        handler = true,
    }
end

-- Load modules
---@type Types
local _ = VFS.Include("LuaUI/TURBOBARCAM/types.lua")
---@type {CONFIG: CONFIG, STATE: STATE}
local TurboConfig = VFS.Include("LuaUI/TURBOBARCAM/config/config.lua")
---@type {Commons: CameraCommons, Util: Util, Movement: CameraMovement, Transition: CameraTransition, FreeCam: FreeCam, Tracking: TrackingManager, WidgetControl: WidgetControl}
local TurboCore = VFS.Include("LuaUI/TURBOBARCAM/core.lua")
---@type {FPSCamera: FPSCamera, TrackingCamera: TrackingCamera, OrbitingCamera: OrbitingCamera, CameraAnchor: CameraAnchor}
local TurboFeatures = VFS.Include("LuaUI/TURBOBARCAM/features.lua")

-- Initialize shorthand references
local CONFIG = TurboConfig.CONFIG
local STATE = TurboConfig.STATE
local Util = TurboCore.Util
local WidgetControl = TurboCore.WidgetControl
local FPSCamera = TurboFeatures.FPSCamera
local Actions = TurboCore.Actions
local UpdateManager = TurboCore.UpdateManager
local SelectionManager = TurboCore.SelectionManager

-- Create a modules container for passing to managers
local Modules = {
    Core = TurboCore,
    Features = TurboFeatures
}

--------------------------------------------------------------------------------
-- SPRING ENGINE CALLINS
--------------------------------------------------------------------------------

---@param selectedUnits number[] Array of selected unit IDs
function widget:SelectionChanged(selectedUnits)
    SelectionManager.handleSelectionChanged(selectedUnits)
end

function widget:Update()
    UpdateManager.processCycle(Modules)
end

function widget:Initialize()
    -- Widget starts in disabled state, user must enable it manually
    STATE.enabled = false

    -- Initialize the managers with modules reference
    UpdateManager.setModules(Modules)
    SelectionManager.setModules(Modules)

    -- Register all action handlers
    Actions.registerAllActions(Modules)

    Util.debugEcho("TURBOBARCAM loaded but disabled. Use /toggle_camera_suite to enable.")
end

function widget:Shutdown()
    -- Make sure we clean up
    if STATE.enabled then
        WidgetControl.disable()
    end
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
    if not STATE.enabled then
        return
    end

    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits > 0 then
        local customCommands = widgetHandler.customCommands
        customCommands[#customCommands + 1] = FPSCamera.COMMAND_DEFINITION
    end
end