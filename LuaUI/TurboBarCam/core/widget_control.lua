---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type CameraQuickControls
local CameraQuickControls = VFS.Include("LuaUI/TurboBarCam/standalone/camera_quick_controls.lua").CameraQuickControls

local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons
local TrackingManager = CommonModules.TrackingManager

---@class WidgetControl
local WidgetControl = {}

--- Enables the widget
function WidgetControl.enable()
    if STATE.enabled then
        Log.trace("Already enabled")
        return
    end

    -- Save current camera state before enabling
    -- using direct Spring call as camera manager isn't active yet
    STATE.originalCameraState = Spring.GetCameraState()

    -- Set required configuration
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 0)
    STATE.enabled = true
    WidgetControl.switchToFpsCamera()
    CameraQuickControls.initialize()
    Log.debug("Enabled")
end

--- Disables the widget
function WidgetControl.disable()
    if Util.isTurboBarCamDisabled() then
        return
    end
    TrackingManager.disableTracking()
    CameraManager.shutdown()

    if STATE.transition.active then
        STATE.transition.active = false
    end

    -- Reset configuration
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 1)

    -- Restore original camera state
    if STATE.originalCameraState then
        -- using direct Spring call to ensure it happens
        Spring.SetCameraState(STATE.originalCameraState, 1)
        STATE.originalCameraState = nil
    end

    STATE.enabled = false
    CameraQuickControls.shutdown()
    Log.debug("Disabled")
end

--- Toggles the widget state
---@return boolean success Always returns true
function WidgetControl.toggle()
    if STATE.enabled then
        WidgetControl.disable()
    else
        WidgetControl.enable()
    end
    return true
end

--- Transitions the camera from Spring (overhead) mode to FPS mode
--- When units are selected:
--- 1. Positions the camera relative to the first selected unit
--- 2. Calculates an appropriate height based on the unit's size
--- 3. Places the camera in front of the unit (or behind if near map edge)
--- 4. Sets a downward viewing angle to see the unit and surrounding area
--- When no units are selected:
--- 1. Maintains a similar viewing area as the current camera
--- 2. Calculates position based on current Spring camera parameters
--- Special handling:
--- First flips the Spring camera downward briefly to prevent visual glitches
function WidgetControl.switchToFpsCamera()
    local selectedUnits = Spring.GetSelectedUnits()

    if #selectedUnits > 0 then
        local x, _, z = Spring.GetUnitPosition(selectedUnits[1])
        local fpsState = CameraCommons.getDefaultUnitView(x, z)
        Spring.SetCameraState(fpsState, 1)
    end
    Spring.SendCommands("viewfps")
    Spring.SetCameraState({ fov = 45 }, 1)
end

function WidgetControl.toggleDebug()
    local logLevelCycle = {
        INFO = "DEBUG",
        DEBUG = "TRACE",
        TRACE = "INFO"
    }
    CONFIG.DEBUG.LOG_LEVEL = logLevelCycle[CONFIG.DEBUG.LOG_LEVEL] or "INFO"
    Log.info("Log level: " .. CONFIG.DEBUG.LOG_LEVEL)
    return true
end

function WidgetControl.toggleLockUnitSelection()
    STATE.allowPlayerCamUnitSelection = not STATE.allowPlayerCamUnitSelection
    Log.info("Unit selection is " .. (STATE.allowPlayerCamUnitSelection and "unlocked" or "locked"))
    return true
end

return {
    WidgetControl = WidgetControl
}