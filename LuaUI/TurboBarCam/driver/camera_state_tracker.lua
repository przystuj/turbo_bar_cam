---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local QuaternionUtils = ModuleManager.QuaternionUtils(function(m) QuaternionUtils = m end)
local MathUtils = ModuleManager.MathUtils(function(m) MathUtils = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)

---@class CameraStateTracker
local CameraStateTracker = {}

--- The main update function, called every frame.
function CameraStateTracker.update(dt)
    if not STATE.active or not STATE.core.camera then return end

    local cameraSTATE = STATE.core.camera
    local raw = Spring.GetCameraState()
    local now = Spring.GetTimer()

    local currentRecord = {
        pos = { x = raw.px, y = raw.py, z = raw.pz },
        orient = QuaternionUtils.fromEuler(raw.rx, raw.ry),
        euler = { rx = raw.rx, ry = raw.ry, rz = raw.rz },
        time = now,
    }

    table.insert(cameraSTATE.history, 1, currentRecord)
    if #cameraSTATE.history > cameraSTATE.maxHistorySize then
        table.remove(cameraSTATE.history)
    end

    if #cameraSTATE.history > 1 then
        local oldest = cameraSTATE.history[#cameraSTATE.history]
        local totalDt = Spring.DiffTimers(now, oldest.time)

        if totalDt > 0.01 then
            cameraSTATE.velocity = MathUtils.vector.multiply(MathUtils.vector.subtract(currentRecord.pos, oldest.pos), 1 / totalDt)

            local deltaOrient = QuaternionUtils.multiply(currentRecord.orient, QuaternionUtils.inverse(oldest.orient))
            local rotVector = QuaternionUtils.log(deltaOrient)
            cameraSTATE.angularVelocity = MathUtils.vector.multiply({ x=rotVector.x, y=rotVector.y, z=rotVector.z}, 1 / totalDt)

            cameraSTATE.angularVelocityEuler = {
                x = CameraCommons.getAngleDiff(oldest.euler.rx, currentRecord.euler.rx) / totalDt,
                y = CameraCommons.getAngleDiff(oldest.euler.ry, currentRecord.euler.ry) / totalDt,
                z = CameraCommons.getAngleDiff(oldest.euler.rz, currentRecord.euler.rz) / totalDt,
            }
        end
    end

    cameraSTATE.position = currentRecord.pos
    cameraSTATE.orientation = currentRecord.orient
    cameraSTATE.euler = currentRecord.euler
end

--- Getters for safe access to camera state ---

function CameraStateTracker.getPosition()
    return TableUtils.deepCopy(STATE.core.camera.position)
end

function CameraStateTracker.getOrientation()
    return TableUtils.deepCopy(STATE.core.camera.orientation)
end

function CameraStateTracker.getVelocity()
    return TableUtils.deepCopy(STATE.core.camera.velocity)
end

function CameraStateTracker.getAngularVelocity()
    return TableUtils.deepCopy(STATE.core.camera.angularVelocity)
end

function CameraStateTracker.getEuler()
    return TableUtils.deepCopy(STATE.core.camera.euler)
end

return CameraStateTracker