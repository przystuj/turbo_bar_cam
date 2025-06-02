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
local CameraCommons = CommonModules.CameraCommons
local ModeManager = CommonModules.ModeManager

---@type MouseManager
local MouseManager = VFS.Include("LuaUI/TurboBarCam/standalone/mouse_manager.lua")
---@type Scheduler
local Scheduler = VFS.Include("LuaUI/TurboBarCam/standalone/scheduler.lua")
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/core/settings_manager.lua")
---@type VelocityTracker
local VelocityTracker = VFS.Include("LuaUI/TurboBarCam/standalone/velocity_tracker.lua")
---@type TransitionManager
local TransitionManager = VFS.Include("LuaUI/TurboBarCam/core/transition_manager.lua")

---@class UpdateManager
local UpdateManager = {}

--- Processes the main update cycle
function UpdateManager.processCycle(dt)
    if Util.isTurboBarCamDisabled() then
        return
    end

    if STATE.reloadFeatures then
        Features.FPSCamera = VFS.Include("LuaUI/TurboBarCam/features/fps/fps.lua").FPSCamera
        Features.OrbitingCamera = VFS.Include("LuaUI/TurboBarCam/features/orbit/orbit.lua").OrbitingCamera
        --Features.CameraAnchor = VFS.Include("LuaUI/TurboBarCam/features/anchors/anchor.lua").CameraAnchor
        Features.UnitTrackingCamera = VFS.Include("LuaUI/TurboBarCam/features/unit_tracking/unit_tracking.lua").UnitTrackingCamera
        --Features.ProjectileCamera = VFS.Include("LuaUI/TurboBarCam/features/projectile_camera/projectile_camera.lua").ProjectileCamera
        STATE.reloadFeatures = false
    end

    -- Handle camera velocity tracking
    VelocityTracker.update()

    SettingsManager.update()

    -- Handle scheduled tasks
    Scheduler.handleSchedules()

    -- Handle transitions
    TransitionManager.update(dt)

    MouseManager.update()

    -- Handle tracking grace period
    UpdateManager.handleTrackingGracePeriod()

    -- Handle fixed point command activation
    Features.FPSCamera.checkFixedPointCommandActivation()

    Features.ProjectileCamera.checkAndActivate()

    -- Handle camera updates based on current mode
    UpdateManager.updateCameraMode(dt)
end

--- Handles tracking grace period
---@return boolean stateChanged Whether tracking state changed
function UpdateManager.handleTrackingGracePeriod()
    if CONFIG.ALLOW_TRACKING_WITHOUT_SELECTION then
        STATE.mode.graceTimer = Spring.GetTimer()
        return
    end
    if STATE.mode.graceTimer and STATE.mode.name and STATE.mode.name ~= "overview" and STATE.mode.name ~= "waypointEditor" then
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.mode.graceTimer)

        -- Skip grace period for point tracking
        if STATE.mode.targetType == STATE.TARGET_TYPES.POINT then
            STATE.mode.graceTimer = Spring.GetTimer()
            return
        end

        -- If grace period expired (1 second), disable tracking for unit targets
        if elapsed > 1.0 and not UpdateManager.isSpectating() then
            ModeManager.disableMode()
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

--- Updates the camera based on current mode
function UpdateManager.updateCameraMode(dt)
    Spring.SendCommands("viewfps")

    if STATE.anchorQueue and STATE.anchorQueue.active then
        Features.CameraAnchor.updateQueue(dt)
    elseif STATE.transition.active then
        Features.CameraAnchor.update(dt)
    elseif STATE.dollyCam.isNavigating then
        Features.DollyCam.update(dt)
    elseif STATE.mode.name == 'fps' then
        Features.FPSCamera.update(dt)
    elseif STATE.mode.name == 'unit_tracking' then
        Features.UnitTrackingCamera.update(dt)
    elseif STATE.mode.name == 'orbit' then
        Features.OrbitingCamera.update(dt)
    elseif STATE.mode.name == 'overview' then
        Features.TurboOverviewCamera.update(dt)
    elseif STATE.mode.name == 'group_tracking' then
        Features.GroupTrackingCamera.update(dt)
    elseif STATE.mode.name == 'projectile_camera' then
        Features.ProjectileCamera.update(dt)
    end
end

function UpdateManager.reload()
    Log.debug("reload")
    STATE.reloadFeatures = true
end

return UpdateManager