-- Update module for TURBOBARCAM
-- Handles camera system updates and callbacks
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TURBOBARCAM/common.lua")
local STATE = WidgetContext.WidgetState.STATE
local Util = CommonModules.Util
local TrackingManager = CommonModules.Tracking

---@class UpdateManager
local UpdateManager = {}

--- Checks if the player is currently spectating
---@return boolean isSpectator Whether the player is spectating
function UpdateManager.isSpectating()
    -- Check if we're a spectator
    local _, _, spec = Spring.GetPlayerInfo(Spring.GetMyPlayerID())
    STATE.specGroups.isSpectator = spec
    return spec
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
            Util.debugEcho("Camera tracking disabled - no units selected (after grace period)")
            return true
        end
    end

    return false
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
---@param modules AllModules
function UpdateManager.updateCameraMode(modules)
    if not modules then
        return
    end

    ---@type FeatureModules
    local Features = modules.Features
    local Core = modules.Core

    -- First handle active transitions, which override normal camera updates
    if STATE.transition.active then
        Core.Transition.update()
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

--- Initializes modules reference for internal use
---@param modules AllModules
function UpdateManager.setModules(modules)
    UpdateManager.modules = modules
end

--- Processes the main update cycle
---@param modules AllModules
function UpdateManager.processCycle(modules)
    if Util.isTurboBarCamDisabled() then
        return
    end

    -- Store modules for internal use if not already set
    if not UpdateManager.modules then
        UpdateManager.setModules(modules)
    end

    -- Handle tracking grace period
    UpdateManager.handleTrackingGracePeriod()

    -- Handle mode transitions
    UpdateManager.handleModeTransitions()

    -- Check for fixed point command activation
    if modules and modules.Features then
        modules.Features.FPSCamera.checkFixedPointCommandActivation()
    end

    -- Handle camera updates
    UpdateManager.updateCameraMode(modules)
end

return {
    UpdateManager = UpdateManager
}