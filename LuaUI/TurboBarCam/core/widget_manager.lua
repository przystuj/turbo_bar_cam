---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "WidgetManager")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local CameraQuickControls = ModuleManager.CameraQuickControls(function(m) CameraQuickControls = m end)
local CameraDriver = ModuleManager.CameraDriver(function(m) CameraDriver = m end)

---@class WidgetManager
local WidgetManager = {}

local function restoreOriginalCameraState()
    if STATE.originalCameraState then
        local camMode = STATE.originalCameraState.mode
        if camMode == 0 then
            Spring.SendCommands('viewfps')
        elseif camMode == 1 then
            Spring.SendCommands('viewta')
        elseif camMode == 2 then
            Spring.SendCommands('viewspring')
        elseif camMode == 3 then
            Spring.SendCommands('viewrot')
        elseif camMode == 4 then
            Spring.SendCommands('viewfree')
        end
        Spring.SetCameraState(STATE.originalCameraState, 1)
        STATE.originalCameraState = nil
    end
end

--- Enables the widget
function WidgetManager.enable()
    if STATE.enabled then
        Log:trace("Already enabled")
        return
    end

    -- Save current camera state before enabling
    STATE.originalCameraState = Spring.GetCameraState()
    STATE.originalFpsCameraFov = Spring.GetConfigInt("FPSFOV", 45)

    -- Set required configuration
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 0)
    Spring.SetConfigInt("FPSClampPos", 0)
    Spring.SetConfigInt("FPSFOV", 45)

    STATE.enabled = true
    STATE.error = nil
    WidgetManager.switchToFpsCamera()
    CameraQuickControls.initialize()
    Log:info("Enabled")
end

--- Disables the widget
function WidgetManager.disable()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    STATE.core = TableUtils.deepCopy(STATE.DEFAULT.core)
    ModeManager.disableMode()

    -- Reset configuration
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 1)
    Spring.SetConfigInt("FPSClampPos", 1)
    Spring.SetConfigInt("FPSFOV", STATE.originalFpsCameraFov or 45)

    restoreOriginalCameraState()

    STATE.enabled = false
    Log:info("Disabled")
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
    --Spring.SetCameraState({ fov = 45 }, 0)
    Spring.SendCommands("viewfps")
end

function WidgetManager.toggleDebug()
    local logLevelCycle = {
        INFO = "DEBUG",
        DEBUG = "TRACE",
        TRACE = "INFO"
    }
    CONFIG.DEBUG.LOG_LEVEL = logLevelCycle[CONFIG.DEBUG.LOG_LEVEL] or "INFO"
    Log:info("Log level: " .. CONFIG.DEBUG.LOG_LEVEL)
    return true
end


--- When spectating with Player Camera it mimics unit selection of the player
--- When this is set to true then that behaviour is disabled
function WidgetManager.toggleLockUnitSelection()
    STATE.allowPlayerCamUnitSelection = not STATE.allowPlayerCamUnitSelection
    Log:info("Unit selection is " .. (STATE.allowPlayerCamUnitSelection and "unlocked" or "locked"))
    return true
end

--- By default when you track unit and you don't have anything selected then tracking is disabled after 1s
--- This allows you to track units and then deselect it
function WidgetManager.toggleRequireUnitSelection()
    CONFIG.ALLOW_TRACKING_WITHOUT_SELECTION = not CONFIG.ALLOW_TRACKING_WITHOUT_SELECTION
    Log:info("Tracking without selected unit is " .. (CONFIG.ALLOW_TRACKING_WITHOUT_SELECTION and "enabled" or "disabled"))
    return true
end

--- Sets a value in the CONFIG table using a string path.
-- If the path doesn't exist, it creates the necessary nested tables.
-- @param path The string path (e.g., "CAMERA_MODES.UNIT_FOLLOW.OFFSETS.UP").
-- @param value The value to set at the specified path.
function WidgetManager.changeConfig(path, value)
    local segments = Utils.splitPath(path)
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
        value = tonumber(value) or value
        Log:debug(string.format("Changing %s=%s to %s", path, currentTable[lastSegment], value))
        currentTable[lastSegment] = value
    else
        -- Handle cases where the path might be empty, though this usually indicates an error.
        Log:debug("Attempted to change config with an empty path.")
    end
end

function WidgetManager.toggleZoom()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    local cycle = { [45] = 24, [24] = 45 }
    local camState = Spring.GetCameraState()
    local fov = cycle[camState.fov] or 45
    Spring.SetCameraState({fov = fov}, 1)
end

function WidgetManager.setFov(fov)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    local camState = Spring.GetCameraState()
    if camState.fov == fov then
        return
    end
    Spring.SetCameraState({fov = fov}, 1)
end

function WidgetManager.stop()
    if Utils.isTurboBarCamDisabled() then
        return
    end
    Log:debug("Stop")
    ModeManager.disableMode()
    CameraDriver.stop()
end

return WidgetManager