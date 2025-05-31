---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")

local STATE = WidgetContext.STATE

---@class CameraTracker
local CameraTracker = {}

--- Updates last known camera position and direction.
---@param camState table Camera state that was applied {px,py,pz, dx,dy,dz, rx,ry,rz}
function CameraTracker.updateLastKnownCameraState(camState)
    STATE.mode.lastCamPos.x = camState.px
    STATE.mode.lastCamPos.y = camState.py
    STATE.mode.lastCamPos.z = camState.pz
    STATE.mode.lastCamDir.x = camState.dx
    STATE.mode.lastCamDir.y = camState.dy
    STATE.mode.lastCamDir.z = camState.dz
    STATE.mode.lastRotation.rx = camState.rx
    STATE.mode.lastRotation.ry = camState.ry
    STATE.mode.lastRotation.rz = camState.rz
end

return CameraTracker
