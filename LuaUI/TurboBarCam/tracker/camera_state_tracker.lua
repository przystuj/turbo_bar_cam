---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local Util = ModuleManager.Util(function(m) Util = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local QuaternionUtils = ModuleManager.QuaternionUtils(function(m) QuaternionUtils = m end)

---@class CameraStateTracker
local CameraStateTracker = {}

--- Initializes the new camera state structure.
local function initializeState()
    STATE.camera = {
        position = {x = 0, y = 0, z = 0},
        orientation = QuaternionUtils.identity(),
        euler = {rx = 0, ry = 0, rz = 0},
        velocity = {x = 0, y = 0, z = 0},
        angularVelocityEuler = {x = 0, y = 0, z = 0}, -- Represents rotational delta in rad/s
        history = {},
        maxHistorySize = 10,
        lastUpdateTime = Spring.GetTimer(),
    }
    Log:trace("CameraStateTracker initialized.")
end

--- The main update function, called every frame.
function CameraStateTracker.update(dt)
    if not STATE.camera then initializeState() end

    local cs = STATE.camera
    local rawCamState = Spring.GetCameraState()
    local currentTime = Spring.GetTimer()

    local currentRecord = {
        pos = { x = rawCamState.px, y = rawCamState.py, z = rawCamState.pz },
        euler = { rx = rawCamState.rx, ry = rawCamState.ry, rz = rawCamState.rz },
        time = currentTime,
    }

    table.insert(cs.history, 1, currentRecord)
    if #cs.history > cs.maxHistorySize then
        table.remove(cs.history)
    end

    if #cs.history > 1 then
        local oldestRecord = cs.history[#cs.history]
        local totalDt = Spring.DiffTimers(currentTime, oldestRecord.time)

        if totalDt > 0.01 then
            local posDelta = CameraCommons.vectorSubtract(currentRecord.pos, oldestRecord.pos)
            cs.velocity = CameraCommons.vectorMultiply(posDelta, 1 / totalDt)

            cs.angularVelocityEuler = {
                x = CameraCommons.getAngleDiff(oldestRecord.euler.rx, currentRecord.euler.rx) / totalDt,
                y = CameraCommons.getAngleDiff(oldestRecord.euler.ry, currentRecord.euler.ry) / totalDt,
                z = CameraCommons.getAngleDiff(oldestRecord.euler.rz, currentRecord.euler.rz) / totalDt,
            }
        end
    end

    cs.position = currentRecord.pos
    cs.euler = currentRecord.euler
    cs.orientation = QuaternionUtils.fromEuler(cs.euler.rx, cs.euler.ry)

    -- Backward Compatibility Support
    STATE.cameraVelocity.currentVelocity = cs.velocity
    STATE.cameraVelocity.currentRotationalVelocity = cs.angularVelocityEuler
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

function CameraStateTracker.getAngularVelocityEuler()
    return STATE.camera and STATE.camera.angularVelocityEuler
end

return CameraStateTracker