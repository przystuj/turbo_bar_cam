-- Actions module for TURBOBARCAM
-- Handles registering action handlers for all camera modules

---@class Actions
local Actions = {}
local w = widget

-- Helper function to register an action handler
---@param actionName string Action name
---@param flags string Action flags
---@param handler function Action handler function
local function registerAction(actionName, flags, handler)
    w.widgetHandler.actionHandler:AddAction(w, actionName, handler, nil, flags)
end

-- Register all camera action handlers
---@param modules AllModules
function Actions.registerAllActions(modules)
    local Features = modules.Features
    local Core = modules.Core
    local Context = modules.Context

    -- Core widget actions
    registerAction("toggle_camera_suite", 'tp',
            function()
                Core.WidgetControl.toggle()
                return true
            end)

    -- Debug toggle
    registerAction("turbobarcam_toggle_debug", 'tp',
            function()
                Context.WidgetState.DEBUG = not Context.WidgetState.DEBUG
                local DEBUG = Context.WidgetState.DEBUG
                Core.Util.echo("DEBUG: " .. (DEBUG and "true" or "false"))
                return true
            end)

    -- Anchor actions
    registerAction("set_smooth_camera_anchor", 'tp',
            function(_, index)
                Features.CameraAnchor.set(index)
                return true
            end)

    registerAction("focus_smooth_camera_anchor", 'tp',
            function(_, index)
                Features.CameraAnchor.focus(index)
                return true
            end)

    registerAction("decrease_smooth_camera_duration", 'p',
            function()
                Features.CameraAnchor.adjustDuration(-1)
                return true
            end)

    registerAction("increase_smooth_camera_duration", 'p',
            function()
                Features.CameraAnchor.adjustDuration(1)
                return true
            end)

    registerAction("focus_anchor_and_track", 'tp',
            function(_, index)
                Features.CameraAnchor.focusAndTrack(index)
                return true
            end)

    -- FPS camera actions
    registerAction("toggle_fps_camera", 'tp',
            function()
                Features.FPSCamera.toggle()
                return true
            end, nil)

    registerAction("fps_height_offset_up", 'pR',
            function()
                Features.FPSCamera.adjustOffset("height", 10)
                return true
            end)

    registerAction("fps_height_offset_down", 'pR',
            function()
                Features.FPSCamera.adjustOffset("height", -10)
                return true
            end)

    registerAction("fps_forward_offset_up", 'pR',
            function()
                Features.FPSCamera.adjustOffset("forward", 10)
                return true
            end)

    registerAction("fps_forward_offset_down", 'pR',
            function()
                Features.FPSCamera.adjustOffset("forward", -10)
                return true
            end)

    registerAction("fps_side_offset_right", 'pR',
            function()
                Features.FPSCamera.adjustOffset("side", 10)
                return true
            end)

    registerAction("fps_side_offset_left", 'pR',
            function()
                Features.FPSCamera.adjustOffset("side", -10)
                return true
            end)

    registerAction("fps_rotation_right", 'pR',
            function()
                Features.FPSCamera.adjustRotationOffset(0.1)
                return true
            end)

    registerAction("fps_rotation_left", 'pR',
            function()
                Features.FPSCamera.adjustRotationOffset(-0.1)
                return true
            end)

    registerAction("fps_toggle_free_cam", 'tp',
            function()
                Features.FPSCamera.toggleFreeCam()
                return true
            end)

    registerAction("fps_reset_defaults", 'tp',
            function()
                Features.FPSCamera.resetOffsets()
                return true
            end)

    registerAction("clear_fixed_look_point", 'tp',
            function()
                Features.FPSCamera.clearFixedLookPoint()
                return true
            end)

    -- Tracking camera actions
    registerAction("toggle_tracking_camera", 'tp',
            function()
                Features.TrackingCamera.toggle()
                return true
            end)

    -- Orbiting camera actions
    registerAction("toggle_orbiting_camera", 'tp',
            function()
                Features.OrbitingCamera.toggle()
                return true
            end)

    registerAction("orbit_speed_up", 'pR',
            function()
                Features.OrbitingCamera.adjustSpeed(0.0001)
                return true
            end)

    registerAction("orbit_speed_down", 'pR',
            function()
                Features.OrbitingCamera.adjustSpeed(-0.0001)
                return true
            end)

    registerAction("orbit_reset_defaults", 'tp',
            function()
                Features.OrbitingCamera.resetSettings()
                return true
            end)

    -- SpecGroups actions
    registerAction("spec_unit_group", 'tp',
            function(_, params)
                Features.SpecGroups.handleCommand(params)
                return true
            end)

    -- TurboOverview actions
    registerAction("turbo_overview_toggle", 'tp',
            function()
                Features.TurboOverviewCamera.toggle()
                return true
            end)

    registerAction("turbo_overview_change_zoom", 'tp',
            function()
                Features.TurboOverviewCamera.toggleZoom()
                return true
            end)

    registerAction("turbo_overview_move_camera", 'tp',
            function()
                Features.TurboOverviewCamera.moveToTarget()
                return true
            end)

    registerAction("turbo_overview_smoothing_up", 'pR',
            function()
                Features.TurboOverviewCamera.adjustSmoothing(0.01)
                return true
            end)

    registerAction("turbo_overview_smoothing_down", 'pR',
            function()
                Features.TurboOverviewCamera.adjustSmoothing(-0.01)
                return true
            end)

    -- Group Tracking camera actions
    registerAction("toggle_group_tracking_camera", 'tp',
            function()
                Features.GroupTrackingCamera.toggle()
                return true
            end)

    registerAction("group_tracking_distance_increase", 'pR',
            function()
                local config = CONFIG.CAMERA_MODES.GROUP_TRACKING
                config.DEFAULT_DISTANCE = config.DEFAULT_DISTANCE + 50
                Util.debugEcho("Group tracking default distance increased to: " .. config.DEFAULT_DISTANCE)
                return true
            end)

    registerAction("group_tracking_distance_decrease", 'pR',
            function()
                local config = CONFIG.CAMERA_MODES.GROUP_TRACKING
                config.DEFAULT_DISTANCE = math.max(config.MIN_DISTANCE, config.DEFAULT_DISTANCE - 50)
                Util.debugEcho("Group tracking default distance decreased to: " .. config.DEFAULT_DISTANCE)
                return true
            end)

    registerAction("group_tracking_cutoff_increase", 'tp',
            function()
                local config = CONFIG.CAMERA_MODES.GROUP_TRACKING
                config.OUTLIER_CUTOFF_FACTOR = config.OUTLIER_CUTOFF_FACTOR + 0.5
                Util.debugEcho("Group tracking outlier cutoff increased to: " .. config.OUTLIER_CUTOFF_FACTOR)
                return true
            end)

    registerAction("group_tracking_cutoff_decrease", 'tp',
            function()
                local config = CONFIG.CAMERA_MODES.GROUP_TRACKING
                config.OUTLIER_CUTOFF_FACTOR = math.max(1.0, config.OUTLIER_CUTOFF_FACTOR - 0.5)
                Util.debugEcho("Group tracking outlier cutoff decreased to: " .. config.OUTLIER_CUTOFF_FACTOR)
                return true
            end)

    registerAction("group_tracking_height_increase", 'pR',
            function()
                local config = CONFIG.CAMERA_MODES.GROUP_TRACKING
                config.DEFAULT_HEIGHT_FACTOR = config.DEFAULT_HEIGHT_FACTOR + 0.1
                Util.debugEcho("Group tracking height factor increased to: " .. config.DEFAULT_HEIGHT_FACTOR)
                return true
            end)

    registerAction("group_tracking_height_decrease", 'pR',
            function()
                local config = CONFIG.CAMERA_MODES.GROUP_TRACKING
                config.DEFAULT_HEIGHT_FACTOR = math.max(0.1, config.DEFAULT_HEIGHT_FACTOR - 0.1)
                Util.debugEcho("Group tracking height factor decreased to: " .. config.DEFAULT_HEIGHT_FACTOR)
                return true
            end)

    registerAction("group_tracking_backward_increase", 'pR',
            function()
                local config = CONFIG.CAMERA_MODES.GROUP_TRACKING
                config.BACKWARD_FACTOR = config.BACKWARD_FACTOR + 0.1
                Util.debugEcho("Group tracking backward factor increased to: " .. config.BACKWARD_FACTOR)
                return true
            end)

    registerAction("group_tracking_backward_decrease", 'pR',
            function()
                local config = CONFIG.CAMERA_MODES.GROUP_TRACKING
                config.BACKWARD_FACTOR = math.max(1.0, config.BACKWARD_FACTOR - 0.1)
                Util.debugEcho("Group tracking backward factor decreased to: " .. config.BACKWARD_FACTOR)
                return true
            end)

    -- Load translations
    Spring.I18N.load({
        en = {
            ["ui.orderMenu.set_fixed_look_point"] = "Look point",
            ["ui.orderMenu.set_fixed_look_point_tooltip"] = "Click on a location to focus camera on while following unit.",
        }
    })
end

return {
    Actions = Actions
}