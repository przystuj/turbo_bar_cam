---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type FeatureModules
local Features = VFS.Include("LuaUI/TurboBarCam/features.lua")

local STATE = WidgetContext.WidgetState.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log

---@class UpdateManager
local UpdateManager = {}

--- Processes the main update cycle
function UpdateManager.processCycle()
    if Util.isTurboBarCamDisabled() then
        return
    end

    --local camState = CameraManager.getCameraState("UpdateManager.processCycle")
    --if camState.mode ~= 0 then
    --    Log.debug("Wrong camera mode. Disabling widget.")
    --    STATE.enabled = false
    --    return
    --end

    -- Handle tracking grace period
    UpdateManager.handleTrackingGracePeriod()

    -- Handle mode transitions
    UpdateManager.handleModeTransitions()

    -- Handle fixed point command activation
    Features.FPSCamera.checkFixedPointCommandActivation()

    -- Handle camera updates based on current mode
    UpdateManager.updateCameraMode()

    --Util.throttleExecution(function() CameraManager.printCallHistory() end, 2)
end

--- Handles tracking grace period
---@return boolean stateChanged Whether tracking state changed
function UpdateManager.handleTrackingGracePeriod()
    if STATE.tracking.graceTimer and STATE.tracking.mode and STATE.tracking.mode ~= "turbo_overview" then
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.graceTimer)

        -- If grace period expired (1 second), disable tracking
        if elapsed > 1.0 and not UpdateManager.isSpectating() then
            TrackingManager.disableTracking()
            Log.debug("Camera tracking disabled - no units selected (after grace period)")
            return true
        end
    end

    return false
end

--- Checks if the player is currently spectating
---@return boolean isSpectator Whether the player is spectating
function UpdateManager.isSpectating()
    -- Check if we're a spectator
    local _, _, spec = Spring.GetPlayerInfo(Spring.GetMyPlayerID())
    STATE.specGroups.isSpectator = spec
    return spec
end

--- Handles transitions between camera modes
function UpdateManager.handleModeTransitions()
    -- If we're in a mode transition but not tracking any unit,
    -- then we're transitioning back to normal camera from a tracking mode
    if STATE.tracking.modeTransition and not STATE.tracking.mode then
        -- We're transitioning to free camera
        -- Just let the transition time out
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.transitionStartTime)
        if elapsed > 1.0 then
            STATE.tracking.modeTransition = false
        end
    end
end

--- Updates the camera based on current mode
function UpdateManager.updateCameraMode()
    -- First handle active transitions, which override normal camera updates
    if STATE.transition.active then
        Features.CameraAnchor.update()
    else
        -- Normal camera updates based on current mode
        if STATE.tracking.mode == 'fps' or STATE.tracking.mode == 'fixed_point' then
            -- Check for auto-orbit
            Features.OrbitingCamera.handleAutoOrbit()

            if STATE.orbit.autoOrbitActive then
                -- Handle auto-orbit camera update
                Features.OrbitingCamera.updateAutoOrbit()
            else
                -- Normal FPS update
                Features.FPSCamera.update()
            end
        elseif STATE.tracking.mode == 'unit_tracking' then
            Features.UnitTrackingCamera.update()
        elseif STATE.tracking.mode == 'orbit' then
            Features.OrbitingCamera.update()
        elseif STATE.tracking.mode == 'turbo_overview' then
            Features.TurboOverviewCamera.update()
        elseif STATE.tracking.mode == 'group_tracking' then
            Features.GroupTrackingCamera.update()
        end
    end
end

return {
    UpdateManager = UpdateManager
}