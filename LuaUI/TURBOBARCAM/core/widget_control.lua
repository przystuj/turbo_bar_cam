-- Widget Control module for TURBOBARCAM
-- Load modules
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CommonModules
local TurboCommons = VFS.Include("LuaUI/TURBOBARCAM/common.lua")

local STATE = WidgetContext.WidgetState.STATE
local Util = TurboCommons.Util
local Tracking = TurboCommons.Tracking

---@class WidgetControl
local WidgetControl = {}

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
    WidgetControl.switchToFpsCamera()
    STATE.enabled = true
    Util.debugEcho("Enabled")
end

--- Disables the widget
function WidgetControl.disable()
    if Util.isTurboBarCamDisabled() then
        return
    end
    Tracking.disableTracking()

    if STATE.transition.active then
        STATE.transition.active = false
    end

    -- Reset configuration
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 1)

    -- Restore original camera state
    if STATE.originalCameraState then
        Util.setCameraState(STATE.originalCameraState, true, "WidgetControl.disable")
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
    local springState = Spring.GetCameraState()
    local selectedUnits = Spring.GetSelectedUnits()
    local x, z
    local useUnitPos = false

    if #selectedUnits > 0 then
        x, _, z = Spring.GetUnitPosition(selectedUnits[1])
        useUnitPos = true
    end

    -- Check if we're actually switching from Spring camera mode
    if springState.mode ~= 2 then
        -- Not coming from spring camera, just switch to FPS mode
        local newState = {}
        newState.mode = 0
        newState.name = "fps"
        newState.fov = 45
        Util.setCameraState(springState, true, "WidgetControl.switchToFpsCamera")
        return
    end

    -- first flip camera down in spring mode to avoid strange behaviours when switching to fps
    Util.setCameraState({ rx = math.pi, dx = 0, dy = -1, dz = 0 }, true, "WidgetControl.switchToFpsCamera")

    -- Create a new state for FPS camera
    local fpsState = {
        mode = 0, -- FPS camera mode
        name = "fps",
        fov = 45
    }

    if useUnitPos then
        -- Get map dimensions and calculate camera parameters
        local cameraHeight = 1280
        local offsetDistance = 1024
        local lookdownAngle = 2.4

        -- Set common camera properties
        fpsState.px = x
        fpsState.py = cameraHeight
        fpsState.rx = lookdownAngle
        fpsState.ry = 0

        -- Check if forward position would exceed map boundaries
        local forwardPosition = z + offsetDistance
        if forwardPosition >= Game.mapSizeZ * 0.95 then
            -- 95% safety margin
            -- Position camera behind the unit instead
            fpsState.pz = z - offsetDistance
            fpsState.ry = fpsState.ry + math.pi -- Rotate 180 degrees
            Util.traceEcho("Boundary detected, positioning camera behind unit")
        else
            -- Normal positioning in front of unit
            fpsState.pz = forwardPosition
            Util.traceEcho("Normal positioning in front of unit")
        end

        Util.traceEcho("Camera height: " .. cameraHeight)
        Util.traceEcho("Offset distance: " .. offsetDistance)
    else
        -- Calculate position based on spring camera state
        fpsState.py = springState.py + springState.dist * 0.986 -- Height adjustment
        fpsState.pz = springState.pz + springState.dist * 0.0014 -- Slight forward adjustment
    end

    Util.setCameraState(fpsState, true, "WidgetControl.switchToFpsCamera")
end

return {
    WidgetControl = WidgetControl
}