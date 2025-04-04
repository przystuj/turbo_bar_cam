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

    local selectedUnits = Spring.GetSelectedUnits()

    local x, height, z
    local useUnitPos = false

    if #selectedUnits > 0 then
        x, _, z = Spring.GetUnitPosition(selectedUnits[1])
        height = Util.getUnitHeight(selectedUnits[1])
        useUnitPos = true
    end

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

    Spring.SetCameraState({ rx = math.pi }, 0.1) -- first flip camera down in spring mode to avoid strange behaviours when switching to fps


    -- Create a new state for FPS camera
    local fpsState = {}
    if useUnitPos then
        -- Get map dimensions
        local mapSizeX, mapSizeZ = Game.mapSizeX, Game.mapSizeZ

        -- Calculate potential position
        local potentialPz = z + height * 16

        -- Check if potential position exceeds map boundaries
        if potentialPz >= mapSizeZ * 0.95 then -- Using 95% as a safety margin
            fpsState.px = x
            fpsState.py = height * 20
            fpsState.pz = z - height * 16 -- Subtract instead of add
            fpsState.rx = 2.4
            fpsState.ry = springState.ry + math.pi -- Add 180 degrees
            Util.traceEcho("Boundary detected, rotating camera. Height: " .. height)
        else
            fpsState.px = x
            fpsState.py = height * 20
            fpsState.pz = z + height * 16
            fpsState.rx = 2.4
            Util.traceEcho("Normal positioning. Height: " .. height)
        end
    else
        fpsState.py = springState.py + springState.dist * 0.986 -- this is magic number which makes fps camera height perfectly match the spring height
        fpsState.pz = springState.pz + (springState.dist * 0.0014)
    end

    -- Set FPS mode properties
    fpsState.mode = 0
    fpsState.name = "fps"
    fpsState.fov = 45

    Spring.SetCameraState(fpsState, 1)
end

--- Enables the widget
function WidgetControl.enable()
    if STATE.enabled then
        Util.traceEcho("Already enabled")
        return
    end

    -- Save current camera state before enabling
    STATE.originalCameraState = Spring.GetCameraState()

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