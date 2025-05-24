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
local TrackingManager = CommonModules.TrackingManager

---@type MouseManager
local MouseManager = VFS.Include("LuaUI/TurboBarCam/standalone/mouse_manager.lua").MouseManager
---@type Scheduler
local Scheduler = VFS.Include("LuaUI/TurboBarCam/standalone/scheduler.lua").Scheduler
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/settings/settings_manager.lua").SettingsManager
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua")

---@class UpdateManager
local UpdateManager = {}

--- Processes the main update cycle
function UpdateManager.processCycle(dt)
    if Util.isTurboBarCamDisabled() then
        return
    end

    -- Update CameraManager (handles velocity tracking internally)
    CameraManager.update()

    if STATE.reloadFeatures then
        Features.OrbitingCamera = VFS.Include("LuaUI/TurboBarCam/features/orbit/orbit.lua").OrbitingCamera
        Features.CameraAnchor = VFS.Include("LuaUI/TurboBarCam/features/anchors/anchor.lua").CameraAnchor
        Features.UnitTrackingCamera = VFS.Include("LuaUI/TurboBarCam/features/unit_tracking/unit_tracking.lua").UnitTrackingCamera
        Features.ProjectileCamera = VFS.Include("LuaUI/TurboBarCam/features/projectile_camera/projectile_camera.lua").ProjectileCamera
        STATE.reloadFeatures = false
    end

    SettingsManager.update()

    Scheduler.handleSchedules()

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
        STATE.tracking.graceTimer = Spring.GetTimer()
        return
    end
    if STATE.tracking.graceTimer and STATE.tracking.mode and STATE.tracking.mode ~= "overview" and STATE.tracking.mode ~= "waypointEditor" then
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
function UpdateManager.handleDisabledMode()
    -- If we're in a mode transition but not tracking any unit,
    -- then we're transitioning back to normal camera from a tracking mode
    CameraCommons.handleModeTransition(1,1)
end

local function printAverageDt()
    -- Initialize STATE.perf if it doesn't exist
    if not STATE.perf then
        STATE.perf = {
            dtSum = 0,
            frameCount = 0,
            lastReportTime = Spring.GetTimer(),
            averageDt = 0
        }
    end

    -- Get current dt value (passed to this function)
    local dt = Spring.GetFrameTimeOffset()

    -- Accumulate dt and increment frame count
    STATE.perf.dtSum = STATE.perf.dtSum + dt
    STATE.perf.frameCount = STATE.perf.frameCount + 1

    -- Check if 3 seconds have passed
    local currentTime = Spring.GetTimer()
    local timeDiff = Spring.DiffTimers(currentTime, STATE.perf.lastReportTime)

    if timeDiff >= 3.0 then
        -- Calculate average dt
        STATE.perf.averageDt = STATE.perf.dtSum / STATE.perf.frameCount

        -- Log or display the average dt
        Log.debug(string.format("Average dt over last 3s: %.6f seconds (from %d frames)",
                STATE.perf.averageDt, STATE.perf.frameCount))

        -- Reset counters
        STATE.perf.dtSum = 0
        STATE.perf.frameCount = 0
        STATE.perf.lastReportTime = currentTime
    end
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
    elseif not STATE.tracking.mode then
        UpdateManager.handleDisabledMode(dt)
    elseif STATE.tracking.mode == 'fps' then
        Features.FPSCamera.update(dt)
    elseif STATE.tracking.mode == 'unit_tracking' then
        Features.UnitTrackingCamera.update(dt)
    elseif STATE.tracking.mode == 'orbit' then
        Features.OrbitingCamera.update(dt)
    elseif STATE.tracking.mode == 'overview' then
        Features.TurboOverviewCamera.update(dt)
    elseif STATE.tracking.mode == 'group_tracking' then
        Features.GroupTrackingCamera.update(dt)
    elseif STATE.tracking.mode == 'projectile_camera' then
        Features.ProjectileCamera.update(dt)
    end
end

function UpdateManager.reload()
    Log.debug("reload")
    STATE.reloadFeatures = true
end

return {
    UpdateManager = UpdateManager
}