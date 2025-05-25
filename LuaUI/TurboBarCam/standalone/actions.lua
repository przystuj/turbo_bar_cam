---@type CoreModules
local CoreModules = VFS.Include("LuaUI/TurboBarCam/core.lua")
---@type FeatureModules
local FeatureModules = VFS.Include("LuaUI/TurboBarCam/features.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua")

---@class Actions
local Actions = {}
local w = widget

--- Register all camera action handlers
function Actions.registerAllActions()
    Actions.coreActions()
    Actions.dollyCamActions()
    Actions.fpsActions()
    Actions.anchorActions()
    Actions.trackingCameraActions()
    Actions.specGroupsActions()
    Actions.orbitActions()
    Actions.overviewActions()
    Actions.groupTrackingActions()
    Actions.projectileActions()
    Actions.I18N()
end

function Actions.coreActions()
    Actions.registerAction("turbobarcam_reload_module", 'tp',
            function()
                CoreModules.UpdateManager.reload()
                return true
            end)

    Actions.registerAction("turbobarcam_toggle", 'tp',
            function()
                CoreModules.WidgetControl.toggle()
                return true
            end)

    Actions.registerAction("turbobarcam_debug", 'tp',
            function()
                return CoreModules.WidgetControl.toggleDebug()
            end)

    Actions.registerAction("turbobarcam_toggle_playercam_selection", 'tp',
            function()
                return CoreModules.WidgetControl.toggleLockUnitSelection()
            end)

    Actions.registerAction("turbobarcam_toggle_zoom", 'p',
            function()
                CameraManager.toggleZoom()
                return true
            end)

    Actions.registerAction("turbobarcam_set_fov", 'tp',
            function(_, param)
                CameraManager.setFov(param)
                return true
            end)

    Actions.registerAction("turbobarcam_toggle_require_unit_selection", 'tp',
            function()
                CoreModules.WidgetControl.toggleRequireUnitSelection()
                return true
            end)

    Actions.registerAction("turbobarcam_stop_tracking", 'tp',
            function()
                CommonModules.TrackingManager.disableMode()
                return false
            end)
end

function Actions.dollyCamActions()
    Actions.registerAction("turbobarcam_dollycam_add", 'tp',
            function()
                FeatureModules.DollyCam.addCurrentPositionToRoute()
                return true
            end)

    Actions.registerAction("turbobarcam_dollycam_edit_lookat", 'tp',
            function()
                FeatureModules.DollyCam.setWaypointLookAtUnit()
                return true
            end)

    Actions.registerAction("turbobarcam_dollycam_edit_speed", 'tp',
            function(_, params)
                FeatureModules.DollyCam.setWaypointTargetSpeed(params)
                return true
            end)

    Actions.registerAction("turbobarcam_dollycam_toggle_editor", 'tp',
            function()
                FeatureModules.DollyCam.toggleWaypointEditor()
                return true
            end)

    Actions.registerAction("turbobarcam_dollycam_move_waypoint", 'tp',
            function(_, _, args)
                FeatureModules.DollyCam.moveSelectedWaypoint(args[1], args[2]) -- axis, value
                return false
            end)

    Actions.registerAction("turbobarcam_dollycam_toggle_navigation", 'tp',
            function(_, params)
                FeatureModules.DollyCam.toggleNavigation(params)
                return true
            end)

    Actions.registerAction("turbobarcam_dollycam_adjust_speed", 'tp',
            function(_, param)
                FeatureModules.DollyCam.adjustSpeed(param)
                return false
            end)

    Actions.registerAction("turbobarcam_dollycam_toggle_direction", 'tp',
            function(_, param)
                FeatureModules.DollyCam.toggleDirection()
                return false
            end)

    Actions.registerAction("turbobarcam_dollycam_save", 'tp',
            function(_, param)
                FeatureModules.DollyCam.saveRoute(param)
                return true
            end)

    Actions.registerAction("turbobarcam_dollycam_load", 'tp',
            function(_, param)
                FeatureModules.DollyCam.loadRoute(param)
                return true
            end)

    Actions.registerAction("turbobarcam_dollycam_test", 'tp',
            function(_, param)
                FeatureModules.DollyCam.test(param)
                return true
            end)

end


function Actions.fpsActions()
    -- FPS camera actions
    Actions.registerAction("turbobarcam_toggle_fps_camera", 'tp',
            function()
                FeatureModules.FPSCamera.toggle()
                return true
            end, nil)

    Actions.registerAction("turbobarcam_fps_toggle_combat_mode", 'tp',
            function()
                FeatureModules.FPSCamera.toggleCombatMode()
                return true
            end, nil)

    Actions.registerAction("turbobarcam_fps_adjust_params", 'pR',
            function(_, params)
                FeatureModules.FPSCamera.adjustParams(params)
                return false
            end)

    Actions.registerAction("turbobarcam_fps_toggle_free_cam", 'tp',
            function()
                FeatureModules.FPSCamera.toggleFreeCam()
                return true
            end)

    --- turbobarcam_fps_set_fixed_look_point is an ui action so it's not listed here
    Actions.registerAction("turbobarcam_fps_clear_fixed_look_point", 'tp',
            function()
                FeatureModules.FPSCamera.clearFixedLookPoint()
                return false
            end)

    Actions.registerAction("turbobarcam_fps_clear_weapon_selection", 'tp',
            function()
                FeatureModules.FPSCamera.clearWeaponSelection()
                return false
            end)

    Actions.registerAction("turbobarcam_fps_next_weapon", 'tp',
            function()
                FeatureModules.FPSCamera.nextWeapon()
                return true
            end)
end


function Actions.projectileActions()
    Actions.registerAction("turbobarcam_projectile_camera_follow", 'tp',
            function()
                FeatureModules.ProjectileCamera.followProjectile()
                return true
            end)

    Actions.registerAction("turbobarcam_projectile_camera_track", 'tp',
            function()
                FeatureModules.ProjectileCamera.trackProjectile()
                return true
            end)

    -- Projectile camera parameter adjustments
    Actions.registerAction("turbobarcam_projectile_adjust_params", 'pR',
            function(_, params)
                FeatureModules.ProjectileCamera.adjustParams(params)
                return false
            end)
end


function Actions.anchorActions()
    Actions.registerAction("turbobarcam_anchor_set", 'tp',
            function(_, index)
                FeatureModules.CameraAnchor.set(index)
                return true
            end)

    Actions.registerAction("turbobarcam_anchor_focus", 'tp',
            function(_, index)
                FeatureModules.CameraAnchor.focus(index)
                return true
            end)

    Actions.registerAction("turbobarcam_anchor_focus_while_tracking", 'tp',
            function(_, index)
                FeatureModules.CameraAnchor.focusAndTrack(index)
                return true
            end)

    Actions.registerAction("turbobarcam_anchor_adjust_params", 'pR',
            function(_, params)
                FeatureModules.CameraAnchor.adjustParams(params)
                return false
            end)

    Actions.registerAction("turbobarcam_anchor_easing", 'tp',
            function(_, params)
                FeatureModules.CameraAnchor.setEasing(params)
                return false
            end)

    Actions.registerAction("turbobarcam_anchor_save", 'tp',
            function(_, params)
                return FeatureModules.CameraAnchor.save(params, true)
            end)

    Actions.registerAction("turbobarcam_anchor_load", 'tp',
            function(_, params)
                return FeatureModules.CameraAnchor.load(params)
            end)
end


function Actions.trackingCameraActions()
    Actions.registerAction("turbobarcam_toggle_tracking_camera", 'tp',
            function()
                FeatureModules.UnitTrackingCamera.toggle()
                return true
            end)

    Actions.registerAction("turbobarcam_tracking_camera_adjust_params", 'pR',
            function(_, params)
                FeatureModules.UnitTrackingCamera.adjustParams(params)
                return false
            end)
end


function Actions.specGroupsActions()
    Actions.registerAction("turbobarcam_spec_unit_group", 'tp',
            function(_, params)
                FeatureModules.SpecGroups.handleCommand(params)
                return true
            end)
end


function Actions.orbitActions()
    Actions.registerAction("turbobarcam_orbit_toggle", 'tp',
            function()
                FeatureModules.OrbitingCamera.toggle()
                return true
            end)

    Actions.registerAction("turbobarcam_orbit_adjust_params", 'pR',
            function(_, params)
                FeatureModules.OrbitingCamera.adjustParams(params)
                return false
            end)

    Actions.registerAction("turbobarcam_orbit_toggle_point", 'tp',
            function()
                FeatureModules.OrbitingCamera.togglePointOrbit()
                return true
            end)

    Actions.registerAction("turbobarcam_orbit_toggle_pause", 'tp',
            function()
                FeatureModules.OrbitingCamera.togglePauseOrbit()
                return true
            end)

    Actions.registerAction("turbobarcam_orbit_save", 'tp',
            function(_, param)
                FeatureModules.OrbitingCamera.saveOrbit(param)
                return true
            end)

    Actions.registerAction("turbobarcam_orbit_load", 'tp',
            function(_, param)
                FeatureModules.OrbitingCamera.loadOrbit(param)
                return true
            end)
end


function Actions.overviewActions()
    Actions.registerAction("turbobarcam_overview_toggle", 'tp',
            function()
                FeatureModules.TurboOverviewCamera.toggle()
                return true
            end)

    Actions.registerAction("turbobarcam_overview_change_height", 'tp',
            function(_, amount)
                FeatureModules.TurboOverviewCamera.changeHeightAndMove(amount)
                return false
            end)

    -- Move camera to target
    Actions.registerAction("turbobarcam_overview_move_camera", 'pr',
            function()
                FeatureModules.TurboOverviewCamera.moveToTarget()
                return true
            end)
end


function Actions.groupTrackingActions()
    Actions.registerAction("turbobarcam_toggle_group_tracking_camera", 'tp',
            function()
                FeatureModules.GroupTrackingCamera.toggle()
                return true
            end, nil)

    Actions.registerAction("turbobarcam_group_tracking_adjust_params", 'pR',
            function(_, params)
                FeatureModules.GroupTrackingCamera.adjustParams(params)
                return false
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

--- Helper function to register an action handler
---@param actionName string Action name
---@param flags string Action flags
---@param handler function Action handler function
function Actions.registerAction(actionName, flags, handler)
    w.widgetHandler.actionHandler:AddAction(w, actionName, handler, nil, flags)
end

return {
    Actions = Actions
}