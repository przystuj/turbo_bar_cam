-- Widget Control module for TURBOBARCAM
---@type {CONFIG: CONFIG, STATE: STATE}
local TurboConfig = VFS.Include("LuaUI/TURBOBARCAM/camera_turbobarcam_config.lua")
---@type {Util: Util}
local TurboUtils = VFS.Include("LuaUI/TURBOBARCAM/camera_turbobarcam_utils.lua")

local STATE = TurboConfig.STATE
local Util = TurboUtils.Util

---@class WidgetControl
local WidgetControl = {}

--- Enables the widget
function WidgetControl.enable()
    if STATE.enabled then
        Util.debugEcho("TURBOBARCAM is already enabled")
        return
    end

    -- Save current camera state before enabling
    STATE.originalCameraState = Spring.GetCameraState()

    -- Set required configuration
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 0)

    -- Get map dimensions to position camera properly
    local mapX = Game.mapSizeX
    local mapZ = Game.mapSizeZ

    -- Calculate center of map
    local centerX = mapX / 2
    local centerZ = mapZ / 2

    -- Calculate good height to view the entire map
    -- Using the longer dimension to ensure everything is visible
    local mapDiagonal = math.sqrt(mapX * mapX + mapZ * mapZ)
    local viewHeight = mapDiagonal / 3

    -- Switch to FPS camera mode and center on map
    local camStatePatch = {
        name = "fps",
        mode = 0, -- FPS camera mode
        px = centerX,
        py = viewHeight,
        pz = centerZ,
        rx = math.pi, -- Slightly tilted for better perspective
    }
    Spring.SetCameraState(camStatePatch, 0.5)

    STATE.enabled = true
    Util.debugEcho("TURBOBARCAM enabled - camera centered on map")
end

--- Disables the widget
function WidgetControl.disable()
    if not STATE.enabled then
        Util.debugEcho("TURBOBARCAM is already disabled")
        return
    end

    -- Reset any active features
    if STATE.tracking.mode then
        Util.disableTracking()
    end

    if STATE.transition.active then
        STATE.transition.active = false
    end

    -- Reset configuration
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 1)

    -- Restore original camera state
    if STATE.originalCameraState then
        Spring.SetCameraState(STATE.originalCameraState, 0.5)
        STATE.originalCameraState = nil
    end

    STATE.enabled = false
    Util.debugEcho("TURBOBARCAM disabled")
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

return {
    WidgetControl = WidgetControl
}
