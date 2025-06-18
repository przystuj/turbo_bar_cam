---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CameraAnchorPersistence = ModuleManager.CameraAnchorPersistence(function(m) CameraAnchorPersistence = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "CameraAnchor")
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

--- Loads default anchors for current map when first launching widget
function CameraAnchor.initialize()
    if STATE.anchor.initialized then
        return
    end
    CameraAnchor.load("default")
    STATE.anchor.initialized = true
end

function CameraAnchor.set(id)
    if Utils.isTurboBarCamDisabled() then return end
    if not id or id == "" then Log:warn("CameraAnchor.set: Invalid anchor ID."); return end

    local camState = Spring.GetCameraState()
    local camPos = { x = camState.px, y = camState.py, z = camState.pz }
    local existingAnchor = STATE.anchor.points[id]

    if existingAnchor then
        local distSq = MathUtils.vector.distanceSq(camPos, {x=existingAnchor.position.px, y=existingAnchor.position.py, z=existingAnchor.position.pz})
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
    local isForcedSmoothing = false
    if STATE.active.anchor.lastUsedAnchor == id then
        duration = 0.2
        isForcedSmoothing = true
    end

    STATE.active.anchor.lastUsedAnchor = id
    if STATE.active.mode.name then ModeManager.disableMode() end

    local camTarget = {
        position = {x=anchorData.position.px, y=anchorData.position.py, z=anchorData.position.pz},
        lookAt = anchorData.target,
        euler = anchorData.rotation,
        smoothTimePos = duration,
        smoothTimeRot = duration / 4,
        isForcedSmoothing = isForcedSmoothing,
    }

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