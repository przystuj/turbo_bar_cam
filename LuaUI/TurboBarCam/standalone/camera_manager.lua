---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log
---@type Util
local Util = VFS.Include("LuaUI/TurboBarCam/common/utils.lua").Util

---@class CameraManager
local CameraManager = {}

function CameraManager.toggleZoom()
    if Util.isTurboBarCamDisabled() then
        return
    end

    local cycle = {
        [45] = 24,
        [24] = 12,
        [12] = 45
    }
    local camState = CameraManager.getCameraState("WidgetControl.toggleZoom")
    local fov = cycle[camState.fov] or 45
    CameraManager.setCameraState({fov = fov}, 1, "WidgetControl.toggleZoom")
end

function CameraManager.setFov(fov)
    if Util.isTurboBarCamDisabled() then
        return
    end

    local camState = CameraManager.getCameraState("WidgetControl.setFov")
    if camState.fov == fov then
        return
    end
    CameraManager.setCameraState({fov = fov}, 1, "WidgetControl.setFov")
end

--- Get the current camera state (with time-based cache)
---@param source string Source of the getCameraState call for tracking
---@return table cameraState The current camera state
function CameraManager.getCameraState(source)
    assert(source, "Source parameter is required for getCameraState")
    return Spring.GetCameraState()
end

--- Apply camera state with optional smoothing
---@param cameraState table Camera state to apply
---@param smoothing number Smoothing factor (0 for no smoothing, 1 for full smoothing)
---@param source string Source of the setCameraState call for tracking
function CameraManager.setCameraState(cameraState, smoothing, source)
    assert(source, "Source parameter is required for setCameraState")

    -- Apply the camera state
    Spring.SetCameraState(cameraState, smoothing)
end

return {
    CameraManager = CameraManager
}