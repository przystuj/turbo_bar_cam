---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local CONSTANTS = ModuleManager.CONSTANTS(function(m) CONSTANTS = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "CombinedCamera")
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)

---@class CombinedCamera
local CombinedCamera = {}

---@param nextMode string Mode which will be activated when position or orientation mode are disabled
function CombinedCamera.toggle(positionMode, orientationMode, nextMode)
    if Utils.isTurboBarCamDisabled() then
        return
    end

    local selectedUnits = Spring.GetSelectedUnits()

    if #selectedUnits == 0 then
        return
    end
    local selectedUnitID = selectedUnits[1]

    if ModeManager.initializeMode('combined', selectedUnitID, CONSTANTS.TARGET_TYPE.UNIT) then
        STATE.active.mode.combined.positionMode = positionMode
        STATE.active.mode.combined.orientationMode = orientationMode
        STATE.active.mode.combined.nextMode = nextMode
    end
end

---@param positionJob DriverJob
---@param orientationJob DriverJob
function CombinedCamera.update(positionJob, orientationJob)
    if STATE.active.mode.name ~= 'combined' then
        return
    end

    if not positionJob and not orientationJob then
        return
    elseif positionJob and not orientationJob then
        positionJob.run()
    elseif orientationJob and not positionJob then
        orientationJob.run()
    else
        orientationJob.position = positionJob.position
        orientationJob.positionSmoothing = positionJob.positionSmoothing
        orientationJob.run()
    end
end

return CombinedCamera
