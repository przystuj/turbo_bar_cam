-- Widget Control module for TURBOBARCAM
-- Load modules
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CommonModules
local TurboCommons = VFS.Include("LuaUI/TURBOBARCAM/common.lua")

local STATE = WidgetContext.WidgetState.STATE
local Util = TurboCommons.Util

---@class WidgetControl
local WidgetControl = {}

local function switchToFpsCamera()
    -- Get current camera state
    local springState = Spring.GetCameraState()

    -- Check if we're actually switching from Spring camera mode
    if springState.mode ~= 2 then
        -- Not coming from spring camera, just switch to FPS mode
        local newState = {}
        newState.mode = 0
        newState.name = "fps"
        newState.fov = 45
        Spring.SetCameraState(springState, 1)
        return
    end

    Spring.SetCameraState({rx = math.pi}, 0.1)

    -- Create a new state for FPS camera
    local fpsState = {}

    Util.traceEcho("Mapping spring height to fps height")

    -- Adjust the position directly in the state
    fpsState.py = springState.py + springState.dist * 0.986 -- this is magic number which makes fps camera height perfectly match the spring height
    fpsState.pz = springState.pz + (springState.dist * 0.0014)

    -- Set FPS mode properties
    fpsState.mode = 0
    fpsState.name = "fps"
    fpsState.fov = 45

    Util.traceEcho(STATE.originalCameraState)
    Spring.SetCameraState(fpsState, 1)
    Util.traceEcho(Spring.GetCameraState())
end

--- Enables the widget
function WidgetControl.enable()
    if STATE.enabled then
        Util.debugEcho("Already enabled")
        return
    end

    -- Save current camera state before enabling
    STATE.originalCameraState = Spring.GetCameraState()
    Util.traceEcho("Original camera mode=" .. STATE.originalCameraState.mode)

    -- Set required configuration
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 0)
    switchToFpsCamera()
    STATE.enabled = true
    Util.debugEcho("Enabled")
end

--- Disables the widget
function WidgetControl.disable()
    if not STATE.enabled then
        Util.debugEcho("Already disabled")
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
        Spring.SetCameraState(STATE.originalCameraState, 1)
        STATE.originalCameraState = nil
    end

    STATE.enabled = false
    Util.debugEcho("Disabled")
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