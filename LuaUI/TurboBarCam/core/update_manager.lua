---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local Util = ModuleManager.Util(function(m) Util = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local SettingsManager = ModuleManager.SettingsManager(function(m) SettingsManager = m end)
local TransitionManager = ModuleManager.TransitionManager(function(m) TransitionManager = m end)
local MouseManager = ModuleManager.MouseManager(function(m) MouseManager = m end)
local Scheduler = ModuleManager.Scheduler(function(m) Scheduler = m end)
local VelocityTracker = ModuleManager.VelocityTracker(function(m) VelocityTracker = m end)
local CameraAnchor = ModuleManager.CameraAnchor(function(m) CameraAnchor = m end)
local DollyCam = ModuleManager.DollyCam(function(m) DollyCam = m end)
local FPSCamera = ModuleManager.FPSCamera(function(m) FPSCamera = m end)
local UnitTrackingCamera = ModuleManager.UnitTrackingCamera(function(m) UnitTrackingCamera = m end)
local OrbitingCamera = ModuleManager.OrbitingCamera(function(m) OrbitingCamera = m end)
local OverviewCamera = ModuleManager.OverviewCamera(function(m) OverviewCamera = m end)
local GroupTrackingCamera = ModuleManager.GroupTrackingCamera(function(m) GroupTrackingCamera = m end)
local ProjectileCamera = ModuleManager.ProjectileCamera(function(m) ProjectileCamera = m end)

---@class UpdateManager
local UpdateManager = {}

--- Processes the main update cycle
function UpdateManager.processCycle(dt)
    if Util.isTurboBarCamDisabled() then
        return
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
    FPSCamera.checkFixedPointCommandActivation()

    ProjectileCamera.checkAndActivate()

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
            Log:debug("Camera tracking disabled - no units selected")
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

    if STATE.transition.active then
        CameraAnchor.update(dt)
    elseif STATE.dollyCam.isNavigating then
        DollyCam.update(dt)
    elseif STATE.mode.name == 'fps' then
        FPSCamera.update(dt)
    elseif STATE.mode.name == 'unit_tracking' then
        UnitTrackingCamera.update(dt)
    elseif STATE.mode.name == 'orbit' then
        OrbitingCamera.update(dt)
    elseif STATE.mode.name == 'overview' then
        OverviewCamera.update(dt)
    elseif STATE.mode.name == 'group_tracking' then
        GroupTrackingCamera.update(dt)
    elseif STATE.mode.name == 'projectile_camera' then
        ProjectileCamera.update(dt)
    end
end

return UpdateManager