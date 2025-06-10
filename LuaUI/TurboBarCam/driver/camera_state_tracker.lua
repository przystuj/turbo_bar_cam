---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local QuaternionUtils = ModuleManager.QuaternionUtils(function(m) QuaternionUtils = m end)

---@class CameraStateTracker
local CameraStateTracker = {}

--- The main update function, called every frame.
function CameraStateTracker.update(dt)
    if not STATE.active or not STATE.active.camera then return end

    local cs = STATE.active.camera
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
            cs.velocity = CameraCommons.vectorMultiply(CameraCommons.vectorSubtract(currentRecord.pos, oldest.pos), 1 / totalDt)

            local deltaOrient = QuaternionUtils.multiply(currentRecord.orient, QuaternionUtils.inverse(oldest.orient))
            local rotVector = QuaternionUtils.log(deltaOrient)
            cs.angularVelocity = CameraCommons.vectorMultiply({x=rotVector.x, y=rotVector.y, z=rotVector.z}, 1 / totalDt)

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

--- Sets the widget's internal camera state. Called by systems that directly manipulate the camera.
---@param pos table The new position {x, y, z}.
---@param orient table The new orientation {w, x, y, z}.
function CameraStateTracker.setCameraState(pos, orient)
    local cs = STATE.active.camera
    cs.position = pos
    cs.orientation = orient
    local eulerX, eulerY, eulerZ = QuaternionUtils.toEuler(orient)
    cs.euler = { rx = eulerX, ry = eulerY, rz = eulerZ }
end

--- Getters for safe access to camera state ---

function CameraStateTracker.getPosition()
    return STATE.active and STATE.active.camera and STATE.active.camera.position
end

function CameraStateTracker.getOrientation()
    return STATE.active and STATE.active.camera and STATE.active.camera.orientation
end

function CameraStateTracker.getVelocity()
    return STATE.active and STATE.active.camera and STATE.active.camera.velocity
end

function CameraStateTracker.getAngularVelocity()
    return STATE.active and STATE.active.camera and STATE.active.camera.angularVelocity
end

return CameraStateTracker