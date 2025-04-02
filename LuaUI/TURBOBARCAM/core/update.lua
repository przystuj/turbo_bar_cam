-- Update module for TURBOBARCAM
-- Handles camera system updates and callbacks
---@type {CONFIG: CONFIG, STATE: STATE}
local TurboConfig = VFS.Include("LuaUI/TURBOBARCAM/config/config.lua")
local STATE = TurboConfig.STATE

---@class UpdateManager
local UpdateManager = {}

--- Handles tracking grace period
---@return boolean stateChanged Whether tracking state changed
function UpdateManager.handleTrackingGracePeriod()
    if STATE.tracking.graceTimer and STATE.tracking.mode then
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.graceTimer)

        -- If grace period expired (1 second), disable tracking
        if elapsed > 1.0 then
            -- Get the utility from the passed modules because of circular dependency issues
            local Util = UpdateManager.modules and UpdateManager.modules.Core and
                    UpdateManager.modules.Core.Util

            if Util then
                Util.disableTracking()
                Util.debugEcho("Camera tracking disabled - no units selected (after grace period)")
                return true
            end
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

--- Handles delayed callbacks
---@return boolean executed Whether a callback was executed
function UpdateManager.handleDelayedCallbacks()
    if STATE.delayed.frame and Spring.GetGameFrame() >= STATE.delayed.frame then
        if STATE.delayed.callback then
            STATE.delayed.callback()
            STATE.delayed.frame = nil
            STATE.delayed.callback = nil
            return true
        end
    end

    return false
end

--- Updates the camera based on current mode
---@param modules table All camera modules (TurboFeatures, TurboCore)
function UpdateManager.updateCameraMode(modules)
    if not modules then
        return
    end

    local Features = modules.Features
    local Core = modules.Core

    -- First handle active transitions, which override normal camera updates
    if STATE.transition.active then
        Core.Transition.update()
    else
        -- Normal camera updates based on current mode
        if STATE.tracking.mode == 'fps' or STATE.tracking.mode == 'fixed_point' then
            -- Check for auto-orbit
            Features.OrbitingCamera.checkUnitMovement()

            if STATE.orbit.autoOrbitActive then
                -- Handle auto-orbit camera update
                Features.OrbitingCamera.updateAutoOrbit()
            else
                -- Normal FPS update
                Features.FPSCamera.update()
            end
        elseif STATE.tracking.mode == 'tracking_camera' then
            Features.TrackingCamera.update()
        elseif STATE.tracking.mode == 'orbit' then
            Features.OrbitingCamera.update()
        elseif STATE.tracking.mode == 'turbo_overview' then
            Features.TurboOverviewCamera.update()
        end
    end
end

--- Initializes modules reference for internal use
---@param modules table Modules object containing Features and Core
function UpdateManager.setModules(modules)
    UpdateManager.modules = modules
end

--- Processes the main update cycle
---@param modules table All camera modules (TurboFeatures, TurboCore)
function UpdateManager.processCycle(modules)
    if not STATE.enabled then
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

    -- Handle delayed callbacks
    UpdateManager.handleDelayedCallbacks()
end

return {
    UpdateManager = UpdateManager
}