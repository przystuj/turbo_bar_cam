---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CameraAnchorPersistence = ModuleManager.CameraAnchorPersistence(function(m) CameraAnchorPersistence = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local CameraAnchorVisualization = ModuleManager.CameraAnchorVisualization(function(m) CameraAnchorVisualization = m end)
local CameraDriver = ModuleManager.CameraDriver(function(m) CameraDriver = m end)
local ParamUtils = ModuleManager.ParamUtils(function(m) ParamUtils = m end)

---@class CameraAnchor
local CameraAnchor = {}

local SET_POSITION_THRESHOLD_SQ = 100

local function getLookAtTargetFromRaycast(startState)
    local vsx, vsy = Spring.GetViewGeometry()
    local _, groundPos = Spring.TraceScreenRay(vsx / 2, vsy / 2, true)
    if groundPos then
        return { x = groundPos[1], y = groundPos[2], z = groundPos[3] }
    else
        local camDir = {Spring.GetCameraDirection()}
        local DISTANCE = 10000
        return {
            x = startState.px + camDir[1] * DISTANCE,
            y = startState.py + camDir[2] * DISTANCE,
            z = startState.pz + camDir[3] * DISTANCE
        }
    end
end

--- Calculates the required spring tightness to complete a transition in a given duration.
---@param duration number The desired duration in seconds.
---@return number tightness The calculated spring tightness (k).
---@return number damping The calculated critical damping value (d).
local function getSpringParamsFromDuration(duration)
    if duration <= 0.01 then
        return 500, 45 -- Return high values for a near-instant snap
    end
    local SETTLING_CONSTANT = 6.6

    local omega = SETTLING_CONSTANT / duration
    local tightness = omega * omega
    local damping = 2 * omega -- for critical damping (d = 2 * sqrt(k))

    return tightness, damping
end

function CameraAnchor.set(id)
    if Utils.isTurboBarCamDisabled() then return end
    if not id or id == "" then Log:warn("CameraAnchor.set: Invalid anchor ID."); return end

    local camState = Spring.GetCameraState()
    local camPos = { x = camState.px, y = camState.py, z = camState.pz }
    local existingAnchor = STATE.anchor.points[id]

    if existingAnchor then
        local distSq = CameraCommons.distanceSquared(camPos, {x=existingAnchor.position.px, y=existingAnchor.position.py, z=existingAnchor.position.pz})
        if distSq < SET_POSITION_THRESHOLD_SQ then
            if existingAnchor.target then
                existingAnchor.target = nil
                existingAnchor.rotation = { rx = camState.rx, ry = camState.ry }
                Log:info("Anchor '" .. id .. "': Look-at point removed.")
            else
                existingAnchor.rotation = nil
                local selectedUnits = Spring.GetSelectedUnits()
                if #selectedUnits > 0 then
                    existingAnchor.target = { type = "unit", data = selectedUnits[1] }
                    Log:info("Anchor '" .. id .. "': Look-at point added (unit " .. selectedUnits[1] .. ").")
                else
                    existingAnchor.target = { type = "point", data = getLookAtTargetFromRaycast(camState) }
                    Log:info("Anchor '" .. id .. "': Look-at point added.")
                end
            end
            return
        end
    end

    STATE.anchor.points[id] = {
        position = { px = camState.px, py = camState.py, pz = camState.pz },
        rotation = { rx = camState.rx, ry = camState.ry },
    }
    Log:info("Anchor '" .. id .. "': Simple anchor created/updated.")
end

function CameraAnchor.focus(id)
    if Utils.isTurboBarCamDisabled() then return true end
    if not id or id == "" then return true end

    local anchorData = STATE.anchor.points[id]
    if not (anchorData and anchorData.position) then
        Log:warn("No anchor data found for ID: " .. tostring(id))
        return true
    end

    local duration = CONFIG.CAMERA_MODES.ANCHOR.DURATION
    if STATE.lastUsedAnchor == id then
        duration = 0.2
    end

    STATE.lastUsedAnchor = id
    if STATE.active.mode.name then ModeManager.disableMode() end

    local camTarget = {
        position = {x=anchorData.position.px, y=anchorData.position.py, z=anchorData.position.pz},
        lookAt = anchorData.target,
        euler = anchorData.rotation,
        duration = duration,
    }

    Log:debug("Current camState", Spring.GetCameraState())
    Log:debug("Cam tracker pos|rot|vel|avel", STATE.active.camera.position, STATE.active.camera.orientation, STATE.active.camera.velocity, STATE.active.camera.angularVelocity)
    Log:debug("Set target to", camTarget)
    CameraDriver.setTarget(camTarget)
    return true
end

function CameraAnchor.save(id)
    if Utils.isTurboBarCamDisabled() then return false end
    return CameraAnchorPersistence.saveToFile(id)
end

function CameraAnchor.load(id)
    if Utils.isTurboBarCamDisabled() then return false end
    return CameraAnchorPersistence.loadFromFile(id)
end

function CameraAnchor.toggleVisualization()
    if Utils.isTurboBarCamDisabled() then return end
    STATE.active.anchor.visualizationEnabled = not STATE.active.anchor.visualizationEnabled
    Log:info("Camera anchor visualization " .. (STATE.active.anchor.visualizationEnabled and "enabled" or "disabled"))
end

function CameraAnchor.draw()
    CameraAnchorVisualization.draw()
end

function CameraAnchor.adjustParams(params)
    if Utils.isTurboBarCamDisabled() then return end
    ParamUtils.adjustParams(params, 'ANCHOR', function()
        CONFIG.CAMERA_MODES.ANCHOR.DURATION = 2
    end)
end

return CameraAnchor