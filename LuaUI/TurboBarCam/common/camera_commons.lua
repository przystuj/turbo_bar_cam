---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "CameraCommons")
local MathUtils = ModuleManager.MathUtils(function(m) MathUtils = m end)

---@class CameraCommons
local CameraCommons = {}

--- Interpolates points along a sphere. `preserveHeight` uses XZ plane for spherical path while lerping height.
function CameraCommons.sphericalInterpolate(center, startPos, endPos, factor, preserveHeight)
    local vec = MathUtils.vector
    -- Calculate vectors from center
    local startVec = vec.subtract(startPos, center)
    local endVec = vec.subtract(endPos, center)

    -- Save initial heights if preserving
    local startRelativeY = startVec.y
    local endRelativeY = endVec.y

    if preserveHeight then
        startVec.y = 0
        endVec.y = 0
    end

    local startDist = vec.magnitude(startVec)
    local endDist = vec.magnitude(endVec)

    local startDir = vec.normalize(startVec)
    local endDir = vec.normalize(endVec)

    local dot = vec.dot(startDir, endDir)
    dot = math.max(-1.0, math.min(1.0, dot))

    if dot > 0.9999 or factor >= 1 then
        return CameraCommons.lerpVector(startPos, endPos, factor)
    end

    local angle = math.acos(dot)
    local sinAngle = math.sin(angle)

    local w1 = math.sin((1 - factor) * angle) / sinAngle
    local w2 = math.sin(factor * angle) / sinAngle

    local resultDir = vec.normalize({
        x = startDir.x * w1 + endDir.x * w2,
        y = startDir.y * w1 + endDir.y * w2,
        z = startDir.z * w1 + endDir.z * w2
    })

    local resultDist = startDist * (1 - factor) + endDist * factor
    local result = vec.add(center, vec.multiply(resultDir, resultDist))

    if preserveHeight then
        local relativeY = startRelativeY * (1 - factor) + endRelativeY * factor
        result.y = center.y + relativeY
    end

    return result
end

--- Calculates camera direction vector and rotation angles to look from camPos to targetPos.
function CameraCommons.calculateCameraDirectionToThePoint(camPos, targetPos)
    local cPos = {x = camPos.x or camPos.px, y = camPos.y or camPos.py, z = camPos.z or camPos.pz}
    local direction = MathUtils.vector.subtract(targetPos, cPos)
    local length = MathUtils.vector.magnitude(direction)

    if length < 1e-5 then
        return { dx = 0, dy = 0, dz = -1, rx = math.pi / 2, ry = 0, rz = 0 }
    end

    local dirNorm = MathUtils.vector.multiply(direction, 1 / length)
    local rx = math.acos(math.max(-1.0, math.min(1.0, dirNorm.y)))
    local ry = math.atan2(dirNorm.x, -dirNorm.z)

    return { dx = dirNorm.x, dy = dirNorm.y, dz = dirNorm.z, rx = rx, ry = ry, rz = 0 }
end

--============================================================================--
--=                                Interpolation                             =--
--============================================================================--

function CameraCommons.lerp(current, target, factor)
    if current == nil or target == nil or factor == nil then
        return current or target
    end
    return current + (target - current) * factor
end

function CameraCommons.lerpVector(v1, v2, t)
    return {
        x = CameraCommons.lerp(v1.x, v2.x, t),
        y = CameraCommons.lerp(v1.y, v2.y, t),
        z = CameraCommons.lerp(v1.z, v2.z, t)
    }
end

function CameraCommons.lerpAngle(current, target, factor)
    if current == nil or target == nil or factor == nil then
        return current or target
    end
    local diff = target - current
    local twoPi = 2 * math.pi
    if diff > math.pi then
        diff = diff - twoPi
    elseif diff < -math.pi then
        diff = diff + twoPi
    end
    return current + diff * factor
end

function CameraCommons.getAngleDiff(a1, a2)
    local diff = a2 - a1
    while diff > math.pi do diff = diff - 2 * math.pi end
    while diff < -math.pi do diff = diff + 2 * math.pi end
    return diff
end

function CameraCommons.getDefaultUnitView(x, z)
    local camState = {
        mode = 0, -- FPS camera mode
        name = "fps",
        fov = 45
    }

    local cameraHeight = 1280
    local offsetDistance = 1024
    local lookdownAngle = 2.4

    -- Set common camera properties
    camState.px = x
    camState.py = cameraHeight
    camState.rx = lookdownAngle
    camState.ry = 0

    -- Check if forward position would exceed map boundaries
    local forwardPosition = z + offsetDistance
    if forwardPosition >= Game.mapSizeZ * 0.95 then
        camState.pz = z - offsetDistance
        camState.ry = camState.ry + math.pi -- Rotate 180 degrees
        Log:trace("Boundary detected, positioning camera behind unit")
    else
        -- Normal positioning in front of unit
        camState.pz = forwardPosition
        Log:trace("Normal positioning in front of unit")
    end
    return camState
end

return CameraCommons
