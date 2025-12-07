---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CONSTANTS = ModuleManager.CONSTANTS(function(m) CONSTANTS = m end)
local CameraAnchorPersistence = ModuleManager.CameraAnchorPersistence(function(m) CameraAnchorPersistence = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "CameraAnchor")
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local CameraAnchorVisualization = ModuleManager.CameraAnchorVisualization(function(m) CameraAnchorVisualization = m end)
local CameraDriver = ModuleManager.CameraDriver(function(m) CameraDriver = m end)
local ParamUtils = ModuleManager.ParamUtils(function(m) ParamUtils = m end)
local MathUtils = ModuleManager.MathUtils(function(m) MathUtils = m end)

---@class CameraAnchor
local CameraAnchor = {}

local SET_POSITION_THRESHOLD_SQ = 100

local function getLookAtTargetFromRaycast(startState)
    local vsx, vsy = Spring.GetViewGeometry()
    local _, groundPos = Spring.TraceScreenRay(vsx / 2, vsy / 2, true)
    if groundPos then
        return { x = groundPos[1], y = groundPos[2], z = groundPos[3] }
    else
        local camDir = { Spring.GetCameraDirection() }
        local DISTANCE = 10000
        return {
            x = startState.px + camDir[1] * DISTANCE,
            y = startState.py + camDir[2] * DISTANCE,
            z = startState.pz + camDir[3] * DISTANCE
        }
    end
end

local function toggleAnchorTarget(anchor, anchorId)
    local camState = Spring.GetCameraState()
    if anchor.target then
        anchor.target = nil
        anchor.rotation = { rx = camState.rx, ry = camState.ry }
        Log:info("Anchor " .. anchorId .. ": Switched to Simple (free look).")
    else
        anchor.rotation = nil
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            anchor.target = { type = CONSTANTS.TARGET_TYPE.UNIT, data = selectedUnits[1] }
            Log:info("Anchor " .. anchorId .. ": Switched to LookAt Unit (" .. selectedUnits[1] .. ").")
        else
            anchor.target = { type = CONSTANTS.TARGET_TYPE.POINT, data = getLookAtTargetFromRaycast(camState) }
            Log:info("Anchor " .. anchorId .. ": Switched to LookAt Point.")
        end
    end
end

---@param step number +1 for next, -1 for previous
local function cycleAnchor(step)
    if Utils.isTurboBarCamDisabled() then
        return false
    end

    local currentIndex = STATE.active.anchor.lastUsedAnchor or 0

    local newIndex = currentIndex + step
    if newIndex > #STATE.anchor.points then
        newIndex = 1
    elseif newIndex < 1 then
        newIndex = #STATE.anchor.points
    end

    CameraAnchor.focus(newIndex)
    return true
end

--- Loads default anchors for current map when first launching widget
function CameraAnchor.initialize()
    if STATE.anchor.initialized then
        return
    end
    if Utils.isTurboBarCamDisabled() then
        return false
    end
    STATE.anchor.initialized = true
    CameraAnchorPersistence.loadFromFile("default", true)
end

function CameraAnchor.set(id)
    if Utils.isTurboBarCamDisabled() then return end

    local numId = tonumber(id)
    if not numId then
        Log:warn("Invalid anchor ID: '" .. tostring(id) .. "'. ID must be a number.");
        return
    end
    id = numId

    local camState = Spring.GetCameraState()
    local camPos = { x = camState.px, y = camState.py, z = camState.pz }
    local existingAnchor = STATE.anchor.points[id]
    local currentDuration = CONFIG.CAMERA_MODES.ANCHOR.DURATION

    if existingAnchor then
        local distSq = MathUtils.vector.distanceSq(camPos, { x = existingAnchor.position.px, y = existingAnchor.position.py, z = existingAnchor.position.pz })
        if distSq < SET_POSITION_THRESHOLD_SQ then
            toggleAnchorTarget(existingAnchor, id)
            existingAnchor.duration = currentDuration
            return
        end
    end

    ---@class AnchorPoint
    STATE.anchor.points[id] = {
        position = { px = camState.px, py = camState.py, pz = camState.pz },
        rotation = { rx = camState.rx, ry = camState.ry },
        duration = currentDuration,
    }
    Log:info("Anchor " .. id .. ": Simple anchor created/updated.")
end

function CameraAnchor.focus(id)
    if Utils.isTurboBarCamDisabled() then return true end

    if id == "next" then
        return cycleAnchor(1)
    elseif id == "prev" then
        return cycleAnchor(-1)
    end

    id = tonumber(id)

    local anchorData = STATE.anchor.points[id]
    if not (anchorData and anchorData.position) then
        Log:warn("No anchor data found for ID: " .. tostring(id))
        return true
    end

    if STATE.active.mode.name then
        ModeManager.disableMode()
    end

    local duration = anchorData.duration or CONFIG.CAMERA_MODES.ANCHOR.DURATION

    if CONFIG.CAMERA_MODES.ANCHOR.SINGLE_DURATION_MODE then
        duration = CONFIG.CAMERA_MODES.ANCHOR.DURATION
    end

    local cameraDriverJob = CameraDriver.prepare()
    cameraDriverJob.position = { x = anchorData.position.px, y = anchorData.position.py, z = anchorData.position.pz }
    cameraDriverJob.targetEuler = anchorData.rotation
    cameraDriverJob.positionSmoothing = duration
    cameraDriverJob.rotationSmoothing = duration
    if anchorData.target then
        cameraDriverJob.setTarget(anchorData.target.type, anchorData.target.data)
        cameraDriverJob.rotationSmoothing = cameraDriverJob.rotationSmoothing / 10
    end
    -- If we're already moving to this anchor, the second press should snap instantly.
    if STATE.active.anchor.lastUsedAnchor == id and STATE.core.driver.target.position then
        cameraDriverJob.isSnap = true
    end

    cameraDriverJob.run()
    STATE.active.anchor.lastUsedAnchor = id
    return true
end

function CameraAnchor.delete(id)
    if Utils.isTurboBarCamDisabled() then return false end
    id = tonumber(id)
    if not STATE.anchor.points[id] then
        Log:warn("Invalid anchor ID: " .. tostring(id));
        return false
    end

    STATE.anchor.points[id] = nil
    Log:info("Anchor " .. id .. " deleted.")

    if STATE.active.anchor.lastUsedAnchor == id then
        STATE.active.anchor.lastUsedAnchor = nil
    end

    return true
end

function CameraAnchor.toggleLookAt(id)
    if Utils.isTurboBarCamDisabled() then return false end
    id = tonumber(id)
    local anchor = STATE.anchor.points[id]
    if not anchor then
        Log:warn("Invalid anchor ID: " .. tostring(id));
        return false
    end
    toggleAnchorTarget(anchor, id)
    return true
end

function CameraAnchor.save(id)
    if Utils.isTurboBarCamDisabled() then return false end
    id = tonumber(id)
    return CameraAnchorPersistence.saveToFile(id)
end

function CameraAnchor.load(id)
    if Utils.isTurboBarCamDisabled() then return false end
    id = tonumber(id)
    return CameraAnchorPersistence.loadFromFile(id)
end

function CameraAnchor.toggleVisualization()
    if Utils.isTurboBarCamDisabled() then return end
    STATE.active.anchor.visualizationEnabled = not STATE.active.anchor.visualizationEnabled
    Log:info("Camera anchor visualization " .. (STATE.active.anchor.visualizationEnabled and "enabled" or "disabled"))
    return true
end

function CameraAnchor.draw()
    CameraAnchorVisualization.draw()
end

function CameraAnchor.toggleSingleDuration()
    CONFIG.CAMERA_MODES.ANCHOR.SINGLE_DURATION_MODE = not CONFIG.CAMERA_MODES.ANCHOR.SINGLE_DURATION_MODE
end

function CameraAnchor.adjustParams(params)
    if Utils.isTurboBarCamDisabled() then return end
    ParamUtils.adjustParams(params, 'ANCHOR', function()
        CONFIG.CAMERA_MODES.ANCHOR.DURATION = 2
    end)
end

--- Updates all existing anchors to use the current default transition duration.
function CameraAnchor.updateAllDurations()
    if Utils.isTurboBarCamDisabled() then return end
    local currentDuration = CONFIG.CAMERA_MODES.ANCHOR.DURATION
    local updatedCount = 0
    for _, anchorData in pairs(STATE.anchor.points) do
        anchorData.duration = currentDuration
        updatedCount = updatedCount + 1
    end
    if updatedCount > 0 then
        Log:info("Updated duration for " .. updatedCount .. " anchor(s) to " .. currentDuration .. "s.")
    else
        Log:debug("No anchors to update.")
    end
end

return CameraAnchor
