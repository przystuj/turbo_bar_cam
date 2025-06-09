---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)

---@class CameraTracker
local CameraTracker = {}

--- Updates last known camera position and direction.
---@param camState table Camera state that was applied {px,py,pz, dx,dy,dz, rx,ry,rz}
function CameraTracker.updateLastKnownCameraState(camState)
    STATE.active.mode.lastCamPos.x = camState.px
    STATE.active.mode.lastCamPos.y = camState.py
    STATE.active.mode.lastCamPos.z = camState.pz
    STATE.active.mode.lastCamDir.x = camState.dx
    STATE.active.mode.lastCamDir.y = camState.dy
    STATE.active.mode.lastCamDir.z = camState.dz
    STATE.active.mode.lastRotation.rx = camState.rx
    STATE.active.mode.lastRotation.ry = camState.ry
    STATE.active.mode.lastRotation.rz = camState.rz
end

return CameraTracker
