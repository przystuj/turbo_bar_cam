---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local QuaternionUtils = ModuleManager.QuaternionUtils(function(m) QuaternionUtils = m end)

---@class CameraStateTracker
local CameraStateTracker = {}

--- The main update function, called every frame.
function CameraStateTracker.update(dt)
    if not STATE.camera then return end

    local cs = STATE.camera
    local raw = Spring.GetCameraState()
    local now = Spring.GetTimer()

    local currentRecord = {
        pos = { x = raw.px, y = raw.py, z = raw.pz },
        orient = QuaternionUtils.fromEuler(raw.rx, raw.ry),
        euler = { rx = raw.rx, ry = raw.ry, rz = raw.rz },
        time = now,
    }

    table.insert(cs.history, 1, currentRecord)
    if #cs.history > cs.maxHistorySize then
        table.remove(cs.history)
    end

    if #cs.history > 1 then
        local oldest = cs.history[#cs.history]
        local totalDt = Spring.DiffTimers(now, oldest.time)

        if totalDt > 0.01 then
            -- Positional Velocity
            cs.velocity = CameraCommons.vectorMultiply(CameraCommons.vectorSubtract(currentRecord.pos, oldest.pos), 1 / totalDt)

            -- Angular Velocity (as a rotation vector)
            local deltaOrient = QuaternionUtils.multiply(currentRecord.orient, QuaternionUtils.inverse(oldest.orient))
            local rotVector = QuaternionUtils.log(deltaOrient)
            cs.angularVelocity = CameraCommons.vectorMultiply({x=rotVector.x, y=rotVector.y, z=rotVector.z}, 1 / totalDt)

            -- Angular Velocity (Euler angles)
            cs.angularVelocityEuler = {
                x = CameraCommons.getAngleDiff(oldest.euler.rx, currentRecord.euler.rx) / totalDt,
                y = CameraCommons.getAngleDiff(oldest.euler.ry, currentRecord.euler.ry) / totalDt,
                z = CameraCommons.getAngleDiff(oldest.euler.rz, currentRecord.euler.rz) / totalDt,
            }
        end
    end

    cs.position = currentRecord.pos
    cs.orientation = currentRecord.orient
    cs.euler = currentRecord.euler
end

--- Getters for safe access to camera state ---

function CameraStateTracker.getPosition()
    return STATE.camera and STATE.camera.position
end

function CameraStateTracker.getOrientation()
    return STATE.camera and STATE.camera.orientation
end

function CameraStateTracker.getEuler()
    return STATE.camera and STATE.camera.euler
end

function CameraStateTracker.getVelocity()
    return STATE.camera and STATE.camera.velocity
end

function CameraStateTracker.getAngularVelocity()
    return STATE.camera and STATE.camera.angularVelocity
end

function CameraStateTracker.getAngularVelocityEuler()
    return STATE.camera and STATE.camera.angularVelocityEuler
end

return CameraStateTracker