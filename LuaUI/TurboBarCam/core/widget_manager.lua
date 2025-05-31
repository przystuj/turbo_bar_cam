---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type CameraQuickControls
local CameraQuickControls = VFS.Include("LuaUI/TurboBarCam/standalone/camera_quick_controls.lua")

local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG
local Util = CommonModules.Util
local Log = CommonModules.Log
local CameraCommons = CommonModules.CameraCommons
local ModeManager = CommonModules.ModeManager

---@class WidgetManager
local WidgetManager = {}

--- Enables the widget
function WidgetManager.enable()
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
    WidgetManager.switchToFpsCamera()
    CameraQuickControls.initialize()
    Log.debug("Enabled")
end

--- Disables the widget
function WidgetManager.disable()
    if Util.isTurboBarCamDisabled() then
        return
    end
    ModeManager.disableMode()

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
    Log.debug("Disabled")
end

--- Toggles the widget state
---@return boolean success Always returns true
function WidgetManager.toggle()
    if STATE.enabled then
        WidgetManager.disable()
    else
        WidgetManager.enable()
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
function WidgetManager.switchToFpsCamera()
    local selectedUnits = Spring.GetSelectedUnits()

    if #selectedUnits > 0 then
        local x, _, z = Spring.GetUnitPosition(selectedUnits[1])
        local fpsState = CameraCommons.getDefaultUnitView(x, z)
        Spring.SetCameraState(fpsState, 1)
    end
    Spring.SendCommands("viewfps")
    Spring.SetCameraState({ fov = 45 }, 1)
end

function WidgetManager.toggleDebug()
    local logLevelCycle = {
        INFO = "DEBUG",
        DEBUG = "TRACE",
        TRACE = "INFO"
    }
    CONFIG.DEBUG.LOG_LEVEL = logLevelCycle[CONFIG.DEBUG.LOG_LEVEL] or "INFO"
    Log.info("Log level: " .. CONFIG.DEBUG.LOG_LEVEL)
    return true
end


--- When spectating with Player Camera it mimics unit selection of the player
--- When this is set to true then that behaviour is disabled
function WidgetManager.toggleLockUnitSelection()
    STATE.allowPlayerCamUnitSelection = not STATE.allowPlayerCamUnitSelection
    Log.info("Unit selection is " .. (STATE.allowPlayerCamUnitSelection and "unlocked" or "locked"))
    return true
end

--- By default when you track unit and you don't have anything selected then tracking is disabled after 1s
--- This allows you to track units and then deselect it
function WidgetManager.toggleRequireUnitSelection()
    CONFIG.ALLOW_TRACKING_WITHOUT_SELECTION = not CONFIG.ALLOW_TRACKING_WITHOUT_SELECTION
    Log.info("Tracking without selected unit is " .. (CONFIG.ALLOW_TRACKING_WITHOUT_SELECTION and "enabled" or "disabled"))
    return true
end

--- Sets a value in the CONFIG table using a string path.
-- If the path doesn't exist, it creates the necessary nested tables.
-- @param path The string path (e.g., "CAMERA_MODES.FPS.OFFSETS.UP").
-- @param value The value to set at the specified path.
function WidgetManager.changeConfig(path, value)
    local segments = Util.splitPath(path)
    local currentTable = CONFIG
    local segmentCount = #segments

    -- Iterate through the path segments, except the last one
    for i = 1, segmentCount - 1 do
        local segment = segments[i]

        -- If the next level doesn't exist or isn't a table, create it
        if not currentTable[segment] or type(currentTable[segment]) ~= "table" then
            currentTable[segment] = {}
        end

        -- Move down to the next level
        currentTable = currentTable[segment]
    end

    -- Set the value at the final level using the last segment
    if segmentCount > 0 then
        local lastSegment = segments[segmentCount]
        Log.debug(string.format("Changing %s=%s to %s", path, currentTable[lastSegment], value))
        currentTable[lastSegment] = value
    else
        -- Handle cases where the path might be empty, though this usually indicates an error.
        Log.debug("Attempted to change config with an empty path.")
    end
end

function WidgetManager.toggleZoom()
    if Util.isTurboBarCamDisabled() then
        return
    end
    local cycle = { [45] = 24, [24] = 12, [12] = 45 }
    local camState = Spring.GetCameraState()
    local fov = cycle[camState.fov] or 45
    Spring.SetCameraState({fov = fov}, 1)
end

function WidgetManager.setFov(fov)
    if Util.isTurboBarCamDisabled() then
        return
    end
    local camState = Spring.GetCameraState()
    if camState.fov == fov then
        return
    end
    Spring.SetCameraState({fov = fov}, 1)
end

return WidgetManager