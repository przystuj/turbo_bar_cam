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
    local Common = modules.Common
    local CONFIG = Context.WidgetConfig.CONFIG
    local STATE = Context.WidgetConfig.STATE

    -- Core widget actions
    registerAction("turbobarcam_toggle", 'tp',
            function()
                Core.WidgetControl.toggle()
                return true
            end)
    registerAction("turbobarcam_debug", 'tp',
            function()
                STATE.DEBUG = not STATE.DEBUG
                local DEBUG = STATE.DEBUG
                Common.Util.echo("DEBUG: " .. (DEBUG and "true" or "false"))
                return true
            end)

    -- Anchor actions
    registerAction("turbobarcam_set_smooth_camera_anchor", 'tp',
            function(_, index)
                Features.CameraAnchor.set(index)
                return true
            end)

    registerAction("turbobarcam_focus_smooth_camera_anchor", 'tp',
            function(_, index)
                Features.CameraAnchor.focus(index)
                return true
            end)

    registerAction("turbobarcam_decrease_smooth_camera_duration", 'p',
            function()
                Features.CameraAnchor.adjustDuration(-1)
                return true
            end)

    registerAction("turbobarcam_increase_smooth_camera_duration", 'p',
            function()
                Features.CameraAnchor.adjustDuration(1)
                return true
            end)

    registerAction("turbobarcam_focus_anchor_and_track", 'tp',
            function(_, index)
                Features.CameraAnchor.focusAndTrack(index)
                return true
            end)

    -- FPS camera actions
    registerAction("turbobarcam_toggle_fps_camera", 'tp',
            function()
                Features.FPSCamera.toggle()
                return true
            end, nil)

    registerAction("turbobarcam_fps_height_offset_up", 'pR',
            function()
                Features.FPSCamera.adjustOffset("height", 10)
                return true
            end)

    registerAction("turbobarcam_fps_height_offset_down", 'pR',
            function()
                Features.FPSCamera.adjustOffset("height", -10)
                return true
            end)

    registerAction("turbobarcam_fps_forward_offset_up", 'pR',
            function()
                Features.FPSCamera.adjustOffset("forward", 10)
                return true
            end)

    registerAction("turbobarcam_fps_forward_offset_down", 'pR',
            function()
                Features.FPSCamera.adjustOffset("forward", -10)
                return true
            end)

    registerAction("turbobarcam_fps_side_offset_right", 'pR',
            function()
                Features.FPSCamera.adjustOffset("side", 10)
                return true
            end)

    registerAction("turbobarcam_fps_side_offset_left", 'pR',
            function()
                Features.FPSCamera.adjustOffset("side", -10)
                return true
            end)

    registerAction("turbobarcam_fps_rotation_right", 'pR',
            function()
                Features.FPSCamera.adjustRotationOffset(0.1)
                return true
            end)

    registerAction("turbobarcam_fps_rotation_left", 'pR',
            function()
                Features.FPSCamera.adjustRotationOffset(-0.1)
                return true
            end)

    registerAction("turbobarcam_fps_toggle_free_cam", 'tp',
            function()
                Features.FPSCamera.toggleFreeCam()
                return true
            end)

    registerAction("turbobarcam_fps_reset_defaults", 'tp',
            function()
                Features.FPSCamera.resetOffsets()
                return true
            end)

    registerAction("turbobarcam_clear_fixed_look_point", 'tp',
            function()
                Features.FPSCamera.clearFixedLookPoint()
                return true
            end)

    -- Tracking camera actions
    registerAction("turbobarcam_toggle_tracking_camera", 'tp',
            function()
                Features.TrackingCamera.toggle()
                return true
            end)

    -- Orbiting camera actions
    registerAction("turbobarcam_toggle_orbiting_camera", 'tp',
            function()
                Features.OrbitingCamera.toggle()
                return true
            end)

    registerAction("turbobarcam_orbit_adjust_params", 'pR',
            function(_, params)
                Features.OrbitingCamera.adjustParams(params)
                return false
            end)

    -- SpecGroups actions
    registerAction("turbobarcam_spec_unit_group", 'tp',
            function(_, params)
                Features.SpecGroups.handleCommand(params)
                return true
            end)

    -- TurboOverview actions
    registerAction("turbobarcam_overview_toggle", 'tp',
            function()
                Features.TurboOverviewCamera.toggle()
                return true
            end)

    registerAction("turbobarcam_overview_change_zoom", 'tp',
            function()
                Features.TurboOverviewCamera.toggleZoom()
                return true
            end)

    registerAction("turbobarcam_overview_move_camera", 'tp',
            function()
                Features.TurboOverviewCamera.moveToTarget()
                return true
            end)

    -- Group Tracking camera actions
    registerAction("turbobarcam_follow_camera_toggle", 'tp',
            function()
                Features.GroupTrackingCamera.toggle()
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