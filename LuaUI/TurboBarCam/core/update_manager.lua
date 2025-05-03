---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type FeatureModules
local Features = VFS.Include("LuaUI/TurboBarCam/features.lua")

local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG
local Util = CommonModules.Util
local Log = CommonModules.Log
local TrackingManager = CommonModules.TrackingManager

---@type MouseManager
local MouseManager = VFS.Include("LuaUI/TurboBarCam/standalone/mouse_manager.lua").MouseManager
---@type Scheduler
local Scheduler = VFS.Include("LuaUI/TurboBarCam/standalone/scheduler.lua").Scheduler
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/settings/settings_manager.lua").SettingsManager

---@class UpdateManager
local UpdateManager = {}

--- Processes the main update cycle
function UpdateManager.processCycle()
    if Util.isTurboBarCamDisabled() then
        return
    end

    SettingsManager.update()

    Scheduler.handleSchedules()

    MouseManager.update()

    -- Handle tracking grace period
    UpdateManager.handleTrackingGracePeriod()

    -- Handle mode transitions
    UpdateManager.handleModeTransitions()

    -- Handle fixed point command activation
    Features.FPSCamera.checkFixedPointCommandActivation()

    Features.ProjectileCamera.checkAndActivate()

    -- Handle camera updates based on current mode
    UpdateManager.updateCameraMode()
end

--- Handles tracking grace period
---@return boolean stateChanged Whether tracking state changed
function UpdateManager.handleTrackingGracePeriod()
    if CONFIG.ALLOW_TRACKING_WITHOUT_SELECTION then
        STATE.tracking.graceTimer = Spring.GetTimer()
        return
    end
    if STATE.tracking.graceTimer and STATE.tracking.mode and STATE.tracking.mode ~= "overview" then
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.graceTimer)

        -- Skip grace period for point tracking
        if STATE.tracking.targetType == STATE.TARGET_TYPES.POINT then
            STATE.tracking.graceTimer = Spring.GetTimer()
            return
        end

        -- If grace period expired (1 second), disable tracking for unit targets
        if elapsed > 1.0 and not UpdateManager.isSpectating() then
            TrackingManager.disableTracking()
            Log.debug("Camera tracking disabled - no units selected")
            return
        end
    end
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
    if STATE.tracking.isModeTransitionInProgress and not STATE.tracking.mode then
        -- We're transitioning to free camera
        -- Just let the transition time out
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.transitionStartTime)
        if elapsed > 1.0 then
            STATE.tracking.isModeTransitionInProgress = false
        end
    end
end

--- Updates the camera based on current mode
function UpdateManager.updateCameraMode()
    Spring.SendCommands("viewfps")

    if STATE.anchorQueue and STATE.anchorQueue.active then
        Features.CameraAnchor.updateQueue()
    elseif STATE.transition.active then
        Features.CameraAnchor.update()
    else
        -- Normal camera updates based on current mode
        if STATE.tracking.mode == 'fps' then
            Features.FPSCamera.update()
        elseif STATE.tracking.mode == 'unit_tracking' then
            Features.UnitTrackingCamera.update()
        elseif STATE.tracking.mode == 'orbit' then
            Features.OrbitingCamera.update()
        elseif STATE.tracking.mode == 'overview' then
            Features.TurboOverviewCamera.update()
        elseif STATE.tracking.mode == 'group_tracking' then
            Features.GroupTrackingCamera.update()
        elseif STATE.tracking.mode == 'projectile_camera' then
            Features.ProjectileCamera.update()
        end
    end
end

return {
    UpdateManager = UpdateManager
}