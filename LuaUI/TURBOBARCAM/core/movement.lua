-- Movement Camera module for TURBOBARCAM
-- Load modules
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CommonModules
local TurboCommons = VFS.Include("LuaUI/TURBOBARCAM/common.lua")

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local Util = TurboCommons.Util

---@class CameraMovement
local CameraMovement = {}

--- Calculates a position for orbit-style camera placement
---@param targetPoint table Target point {x, y, z}
---@param angle number Angle in radians
---@param distance number Distance from target
---@param height number Height above ground
---@return table position Position on orbit path {x, y, z}
function CameraMovement.calculateOrbitPosition(targetPoint, angle, distance, height)
    return {
        x = targetPoint.x + distance * math.sin(angle),
        y = targetPoint.y + height,
        z = targetPoint.z + distance * math.cos(angle)
    }
end

--- Calculates movement angle between two positions
---@param targetPoint table Target point {x, y, z}
---@param position table Position {x, y, z}
---@return number angle Angle in radians
function CameraMovement.calculateMovementAngle(targetPoint, position)
    return math.atan2(position.x - targetPoint.x, position.z - targetPoint.z)
end

--- Updates camera rotation based on cursor position
---@param state table State object with cursor tracking properties
---@return boolean updated Whether rotation was updated
function CameraMovement.updateCursorTracking(state)
    -- Get current mouse position
    local mouseX, mouseY = Spring.GetMouseState()
    local screenWidth, screenHeight = Spring.GetViewGeometry()

    -- Calculate normalized cursor position (-1 to 1) from screen center
    local normalizedX = (mouseX - (screenWidth / 2)) / (screenWidth / 2)
    local normalizedY = (mouseY - (screenHeight / 2)) / (screenHeight / 2)

    -- Calculate distance from center (0-1 range)
    local distanceFromCenter = math.sqrt(normalizedX * normalizedX + normalizedY * normalizedY)

    -- Buffer zone in screen center - no rotation in this area
    if distanceFromCenter < CONFIG.CAMERA_MODES.TURBO_OVERVIEW.BUFFER_ZONE then
        -- Inside buffer zone, no rotation adjustment needed
        return false
    end

    -- Calculate gradual rotation multiplier based on distance from buffer zone
    -- This creates a smooth ramp-up from buffer edge to screen edge
    local availableRange = 1.0 - CONFIG.CAMERA_MODES.TURBO_OVERVIEW.BUFFER_ZONE
    local distanceBeyondBuffer = distanceFromCenter - CONFIG.CAMERA_MODES.TURBO_OVERVIEW.BUFFER_ZONE

    -- Apply quadratic/cubic easing for smoother acceleration
    -- This gives a more natural feel with gradual start and stronger finish
    local gradualMultiplier = (distanceBeyondBuffer / availableRange) ^ 2

    -- Check if cursor is at the very edge for maximum speed
    local EDGE_THRESHOLD = 0.05
    local thresholdPixelsX = screenWidth * EDGE_THRESHOLD
    local thresholdPixelsY = screenHeight * EDGE_THRESHOLD

    local isAtEdge = mouseX < thresholdPixelsX or
            mouseX > screenWidth - thresholdPixelsX or
            mouseY < thresholdPixelsY or
            mouseY > screenHeight - thresholdPixelsY

    -- Apply edge multiplier on top of gradual multiplier if at the edge
    local finalMultiplier = gradualMultiplier
    if isAtEdge then
        finalMultiplier = gradualMultiplier * state.edgeRotationMultiplier
    end

    -- Calculate rotation speeds based on cursor position and gradual multiplier
    local rySpeed = normalizedX * state.maxRotationSpeed * finalMultiplier
    local rxSpeed = -normalizedY * state.maxRotationSpeed * finalMultiplier

    -- Update target rotations
    state.targetRy = state.targetRy + rySpeed
    state.targetRx = state.targetRx + rxSpeed

    -- Normalize angles
    state.targetRy = Util.normalizeAngle(state.targetRy)

    -- Vertical rotation constraint
    state.targetRx = math.max(math.pi / 2, math.min(math.pi, state.targetRx))
    
    return true
end

--- Gets cursor world position
---@return table|nil position {x, y, z} or nil if cursor not over map
function CameraMovement.getCursorWorldPosition()
    local mx, my = Spring.GetMouseState()
    local _, pos = Spring.TraceScreenRay(mx, my, true)

    if pos then
        return { x = pos[1], y = pos[2], z = pos[3] }
    else
        -- Return center of map if cursor is not over the map
        return { x = Game.mapSizeX / 2, y = 0, z = Game.mapSizeZ / 2 }
    end
end

--- Applies smooth camera movement to a target position
---@param currentPos table Current position {x, y, z}
---@param targetPos table Target position {x, y, z}
---@param smoothFactor number Smoothing factor (0-1)
---@return table newPos New smoothed position {x, y, z}
function CameraMovement.smoothMove(currentPos, targetPos, smoothFactor)
    return {
        x = Util.smoothStep(currentPos.x, targetPos.x, smoothFactor),
        y = Util.smoothStep(currentPos.y, targetPos.y, smoothFactor),
        z = Util.smoothStep(currentPos.z, targetPos.z, smoothFactor)
    }
end

--- Converts rotation angles to direction vector
---@param rx number X rotation (pitch)
---@param ry number Y rotation (yaw)
---@return table direction Direction vector {dx, dy, dz}
function CameraMovement.rotationToDirection(rx, ry)
    local cosRx = math.cos(rx)
    local dx = math.sin(ry) * cosRx
    local dz = math.cos(ry) * cosRx
    local dy = math.sin(rx)
    
    return {
        dx = dx,
        dy = dy,
        dz = dz
    }
end

--- Creates a camera state based on position and rotation
---@param position table Position {x, y, z}
---@param rx number X rotation (pitch)
---@param ry number Y rotation (yaw)
---@return table cameraState Camera state
function CameraMovement.createCameraState(position, rx, ry)
    local dir = CameraMovement.rotationToDirection(rx, ry)
    
    return {
        mode = 0,
        name = "fps",
        -- Position
        px = position.x,
        py = position.y,
        pz = position.z,
        -- Direction
        dx = dir.dx,
        dy = dir.dy,
        dz = dir.dz,
        -- Rotation
        rx = rx,
        ry = ry,
        rz = 0
    }
end

--- Prepares camera to look at a specified point
---@param cameraPos table Camera position {x, y, z}
---@param targetPos table Target position to look at {x, y, z}
---@param lastRotation table Last rotation values {rx, ry, rz}
---@param smoothFactor number Smoothing factor for rotation
---@return table cameraState Camera state
function CameraMovement.createLookAtState(cameraPos, targetPos, lastRotation, smoothFactor)
    -- Calculate look direction
    local lookDir = Util.calculateLookAtPoint(cameraPos, targetPos)
    
    -- Smooth rotations
    local rx = lastRotation and Util.smoothStep(lastRotation.rx, lookDir.rx, smoothFactor) or lookDir.rx
    local ry = lastRotation and Util.smoothStepAngle(lastRotation.ry, lookDir.ry, smoothFactor) or lookDir.ry
    
    -- Return camera state
    return {
        mode = 0,
        name = "fps",
        -- Position
        px = cameraPos.x,
        py = cameraPos.y,
        pz = cameraPos.z,
        -- Direction
        dx = lookDir.dx,
        dy = lookDir.dy,
        dz = lookDir.dz,
        -- Rotation
        rx = rx,
        ry = ry,
        rz = 0
    }
end

return {
    CameraMovement = CameraMovement
}