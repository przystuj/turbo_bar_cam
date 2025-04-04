-- Actions module for TURBOBARCAM
-- Handles registering action handlers for all camera modules

---@class Actions
local Actions = {}
local w = widget

--- Register all camera action handlers
---@param modules AllModules
function Actions.registerAllActions(modules)
    local Features = modules.Features
    local Core = modules.Core
    local Context = modules.Context
    local Common = modules.Common
    local STATE = Context.WidgetState.STATE

    Actions.coreActions(Core, STATE, Common)
    Actions.fpsActions(Features)
    Actions.anchorActions(Features)
    Actions.trackingCameraActions(Features)
    Actions.specGroupsActions(Features)
    Actions.orbitActions(Features)
    Actions.overviewActions(Features)
    Actions.I18N()
end

--- Helper function to register an action handler
---@param actionName string Action name
---@param flags string Action flags
---@param handler function Action handler function
function Actions.registerAction(actionName, flags, handler)
    w.widgetHandler.actionHandler:AddAction(w, actionName, handler, nil, flags)
end

---@param Core CoreModules
---@param STATE WidgetState
---@param Common CommonModules
function Actions.coreActions(Core, STATE, Common)
    Actions.registerAction("turbobarcam_toggle", 'tp',
            function()
                Core.WidgetControl.toggle()
                return true
            end)
    Actions.registerAction("turbobarcam_debug", 'tp',
            function()
                local logLevelCycle = {
                    INFO = "DEBUG",
                    DEBUG = "TRACE",
                    TRACE = "INFO"
                }
                STATE.logLevel = logLevelCycle[STATE.logLevel] or "INFO"
                Common.Util.echo("Log level: " .. STATE.logLevel)
                return true
            end)
end

---@param Features FeatureModules
function Actions.fpsActions(Features)
    -- FPS camera actions
    Actions.registerAction("turbobarcam_toggle_fps_camera", 'tp',
            function()
                Features.FPSCamera.toggle()
                return true
            end, nil)

    Actions.registerAction("turbobarcam_fps_adjust_params", 'pR',
            function(_, params)
                Features.FPSCamera.adjustParams(params)
                return false
            end)

    Actions.registerAction("turbobarcam_fps_toggle_free_cam", 'tp',
            function()
                Features.FPSCamera.toggleFreeCam()
                return true
            end)

    --- turbobarcam_fps_set_fixed_look_point is an ui action so it's not listed here
    Actions.registerAction("turbobarcam_fps_clear_fixed_look_point", 'tp',
            function()
                Features.FPSCamera.clearFixedLookPoint()
                return false
            end)
end

---@param Features FeatureModules
function Actions.anchorActions(Features)
    Actions.registerAction("turbobarcam_anchor_set", 'tp',
            function(_, index)
                Features.CameraAnchor.set(index)
                return true
            end)

    Actions.registerAction("turbobarcam_anchor_focus", 'tp',
            function(_, index)
                Features.CameraAnchor.focus(index)
                return true
            end)

    Actions.registerAction("turbobarcam_anchor_focus_while_tracking", 'tp',
            function(_, index)
                Features.CameraAnchor.focusAndTrack(index)
                return true
            end)

    Actions.registerAction("turbobarcam_anchor_adjust_params", 'pR',
            function(_, params)
                Features.CameraAnchor.adjustParams(params)
                return false
            end)
end

---@param Features FeatureModules
function Actions.trackingCameraActions(Features)
    Actions.registerAction("turbobarcam_toggle_tracking_camera", 'tp',
            function()
                Features.TrackingCamera.toggle()
                return true
            end)
end

---@param Features FeatureModules
function Actions.specGroupsActions(Features)
    Actions.registerAction("turbobarcam_spec_unit_group", 'tp',
            function(_, params)
                Features.SpecGroups.handleCommand(params)
                return true
            end)
end

---@param Features FeatureModules
function Actions.orbitActions(Features)
    Actions.registerAction("turbobarcam_toggle_orbiting_camera", 'tp',
            function()
                Features.OrbitingCamera.toggle()
                return true
            end)

    Actions.registerAction("turbobarcam_orbit_adjust_params", 'pR',
            function(_, params)
                Features.OrbitingCamera.adjustParams(params)
                return false
            end)
end

---@param Features FeatureModules
function Actions.overviewActions(Features)
    Actions.registerAction("turbobarcam_overview_toggle", 'tp',
            function()
                Features.TurboOverviewCamera.toggle()
                return true
            end)

    Actions.registerAction("turbobarcam_overview_change_zoom", 'tp',
            function()
                Features.TurboOverviewCamera.toggleZoom()
                return true
            end)

    Actions.registerAction("turbobarcam_overview_move_camera", 'tp',
            function()
                Features.TurboOverviewCamera.moveToTarget()
                return true
            end)

    -- Group Tracking camera actions
    Actions.registerAction("turbobarcam_follow_camera_toggle", 'tp',
            function()
                Features.GroupTrackingCamera.toggle()
                return true
            end)
end

function Actions.I18N()
    Spring.I18N.load({
        en = {
            ["ui.orderMenu.turbobarcam_fps_set_fixed_look_point"] = "Look point",
            ["ui.orderMenu.turbobarcam_fps_set_fixed_look_point_tooltip"] = "Click on a location to focus camera on while following unit.",
        }
    })
end

return {
    Actions = Actions
}