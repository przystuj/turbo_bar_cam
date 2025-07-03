---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local CameraAnchor = ModuleManager.CameraAnchor(function(m) CameraAnchor = m end)
local DollyCam = ModuleManager.DollyCam(function(m) DollyCam = m end)
local UnitFollowCamera = ModuleManager.UnitFollowCamera(function(m) UnitFollowCamera = m end)
local UnitTrackingCamera = ModuleManager.UnitTrackingCamera(function(m) UnitTrackingCamera = m end)
local OrbitingCamera = ModuleManager.OrbitingCamera(function(m) OrbitingCamera = m end)
local OverviewCamera = ModuleManager.OverviewCamera(function(m) OverviewCamera = m end)
local GroupTrackingCamera = ModuleManager.GroupTrackingCamera(function(m) GroupTrackingCamera = m end)
local ProjectileCamera = ModuleManager.ProjectileCamera(function(m) ProjectileCamera = m end)
local SpecGroups = ModuleManager.SpecGroups(function(m) SpecGroups = m end)
local WidgetManager = ModuleManager.WidgetManager(function(m) WidgetManager = m end)
local DebugUtils = ModuleManager.DebugUtils(function(m) DebugUtils = m end)
local CameraTestRunner = ModuleManager.CameraTestRunner(function(m) CameraTestRunner = m end)


---@class Actions
local Actions = {}
local w = widget

--- Register all camera action handlers
function Actions.registerAllActions()
    Actions.coreActions()
    Actions.dollyCamActions()
    Actions.unitFollowActions()
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
    Actions.registerAction("turbobarcam_dev_test", 'tp',
            function(_, param)
                CameraTestRunner.start(param)
                return true
            end)

    Actions.registerAction("turbobarcam_toggle", 'tp',
            function()
                WidgetManager.toggle()
                return true
            end)

    Actions.registerAction("turbobarcam_debug", 'tp',
            function()
                return WidgetManager.toggleDebug()
            end)

    Actions.registerAction("turbobarcam_toggle_playercam_selection", 'tp',
            function()
                return WidgetManager.toggleLockUnitSelection()
            end)

    Actions.registerAction("turbobarcam_toggle_require_unit_selection", 'tp',
            function()
                WidgetManager.toggleRequireUnitSelection()
                return true
            end)

    Actions.registerAction("turbobarcam_toggle_zoom", 'p',
            function()
                WidgetManager.toggleZoom()
                return true
            end)

    Actions.registerAction("turbobarcam_set_fov", 'tp',
            function(_, param)
                WidgetManager.setFov(param)
                return true
            end)

    Actions.registerAction("turbobarcam_stop_tracking", 'tp',
            function()
                WidgetManager.stop()
                return false
            end)

    Actions.registerAction("turbobarcam_dev_config", 't',
            function(_, params, args)
                WidgetManager.changeConfig(args[1], args[2])
                return false
            end)
end

function Actions.dollyCamActions()
    Actions.registerAction("turbobarcam_dollycam_add", 'tp',
            function()
                DollyCam.addCurrentPositionToRoute()
                return true
            end)

    Actions.registerAction("turbobarcam_dollycam_edit_lookat", 'tp',
            function()
                DollyCam.setWaypointLookAtUnit()
                return true
            end)

    Actions.registerAction("turbobarcam_dollycam_edit_speed", 'tp',
            function(_, params)
                DollyCam.setWaypointTargetSpeed(params)
                return true
            end)

    Actions.registerAction("turbobarcam_dollycam_toggle_editor", 'tp',
            function()
                DollyCam.toggleWaypointEditor()
                return true
            end)

    Actions.registerAction("turbobarcam_dollycam_move_waypoint", 'tp',
            function(_, _, args)
                DollyCam.moveSelectedWaypoint(args[1], args[2]) -- axis, value
                return false
            end)

    Actions.registerAction("turbobarcam_dollycam_toggle_navigation", 'tp',
            function(_, params)
                DollyCam.toggleNavigation(params)
                return true
            end)

    Actions.registerAction("turbobarcam_dollycam_adjust_speed", 'tp',
            function(_, param)
                DollyCam.adjustSpeed(param)
                return false
            end)

    Actions.registerAction("turbobarcam_dollycam_toggle_direction", 'tp',
            function(_, param)
                DollyCam.toggleDirection()
                return false
            end)

    Actions.registerAction("turbobarcam_dollycam_save", 'tp',
            function(_, param)
                DollyCam.saveRoute(param)
                return true
            end)

    Actions.registerAction("turbobarcam_dollycam_load", 'tp',
            function(_, param)
                DollyCam.loadRoute(param)
                return true
            end)

    Actions.registerAction("turbobarcam_dollycam_test", 'tp',
            function(_, param)
                DollyCam.test(param)
                return true
            end)

end

function Actions.unitFollowActions()
    Actions.registerAction("turbobarcam_toggle_unit_follow_camera", 'tp',
            function()
                UnitFollowCamera.toggle()
                return true
            end, nil)

    Actions.registerAction("turbobarcam_unit_follow_toggle_combat_mode", 'tp',
            function()
                UnitFollowCamera.toggleCombatMode()
                return true
            end, nil)

    Actions.registerAction("turbobarcam_unit_follow_adjust_params", 'tR',
            function(_, params)
                UnitFollowCamera.adjustParams(params)
                return false
            end)

    --- turbobarcam_unit_follow_set_fixed_look_point is an ui action so it's not listed here
    Actions.registerAction("turbobarcam_unit_follow_clear_fixed_look_point", 'tp',
            function()
                UnitFollowCamera.clearFixedLookPoint()
                return false
            end)

    Actions.registerAction("turbobarcam_unit_follow_clear_weapon_selection", 'tp',
            function()
                UnitFollowCamera.clearWeaponSelection()
                return false
            end)

    Actions.registerAction("turbobarcam_unit_follow_next_weapon", 'tp',
            function()
                UnitFollowCamera.nextWeapon()
                return true
            end)
end

function Actions.projectileActions()
    Actions.registerAction("turbobarcam_projectile_camera_follow", 'tp',
            function()
                ProjectileCamera.followProjectile()
                return true
            end)

    Actions.registerAction("turbobarcam_projectile_camera_track", 'tp',
            function()
                ProjectileCamera.trackProjectile()
                return true
            end)

    -- Projectile camera parameter adjustments
    Actions.registerAction("turbobarcam_projectile_adjust_params", 'tR',
            function(_, params)
                ProjectileCamera.adjustParams(params)
                return false
            end)
end

function Actions.anchorActions()
    Actions.registerAction("turbobarcam_anchor_set", 't',
            function(_, index)
                CameraAnchor.set(index)
                return true
            end)

    Actions.registerAction("turbobarcam_anchor_focus", 't',
            function(_, index)
                CameraAnchor.focus(index)
                return true
            end)

    Actions.registerAction("turbobarcam_anchor_adjust_params", 'tR',
            function(_, params)
                CameraAnchor.adjustParams(params)
                return false
            end)

    Actions.registerAction("turbobarcam_anchor_save", 't',
            function(_, params)
                return CameraAnchor.save(params, true)
            end)

    Actions.registerAction("turbobarcam_anchor_load", 't',
            function(_, params)
                return CameraAnchor.load(params)
            end)

    Actions.registerAction("turbobarcam_anchor_toggle_visualization", 't',
            function()
                return CameraAnchor.toggleVisualization()
            end)

    Actions.registerAction("turbobarcam_anchor_update_all_durations", 't',
            function()
                return CameraAnchor.updateAllDurations()
            end)

    Actions.registerAction("turbobarcam_anchor_toggle_type", 't',
            function(_, params)
                return CameraAnchor.toggleLookAt(params)
            end)

    Actions.registerAction("turbobarcam_anchor_delete", 't',
            function(_, params)
                return CameraAnchor.delete(params)
            end)
end

function Actions.trackingCameraActions()
    Actions.registerAction("turbobarcam_toggle_tracking_camera", 'tp',
            function()
                UnitTrackingCamera.toggle()
                return true
            end)

    Actions.registerAction("turbobarcam_tracking_camera_adjust_params", 'tR',
            function(_, params)
                UnitTrackingCamera.adjustParams(params)
                return false
            end)
end

function Actions.specGroupsActions()
    Actions.registerAction("turbobarcam_spec_unit_group", 'tp',
            function(_, _, args)
                SpecGroups.handleCommand(args[1], args[2])
                return true
            end)
end

function Actions.orbitActions()
    Actions.registerAction("turbobarcam_orbit_toggle", 'tp',
            function()
                OrbitingCamera.toggle()
                return true
            end)

    Actions.registerAction("turbobarcam_orbit_adjust_params", 'tR',
            function(_, params)
                OrbitingCamera.adjustParams(params)
                return false
            end)

    Actions.registerAction("turbobarcam_orbit_toggle_point", 'tp',
            function()
                OrbitingCamera.togglePointOrbit()
                return true
            end)

    Actions.registerAction("turbobarcam_orbit_toggle_pause", 'tp',
            function()
                OrbitingCamera.togglePauseOrbit()
                return true
            end)

    Actions.registerAction("turbobarcam_orbit_save", 'tp',
            function(_, param)
                OrbitingCamera.saveOrbit(param)
                return true
            end)

    Actions.registerAction("turbobarcam_orbit_load", 'tp',
            function(_, param)
                OrbitingCamera.loadOrbit(param)
                return true
            end)
end

function Actions.overviewActions()
    Actions.registerAction("turbobarcam_overview_toggle", 'tp',
            function()
                OverviewCamera.toggle()
                return true
            end)

    Actions.registerAction("turbobarcam_overview_change_height", 'tp',
            function(_, amount)
                OverviewCamera.changeHeightAndMove(amount)
                return false
            end)

    -- Move camera to target
    Actions.registerAction("turbobarcam_overview_move_camera", 'pr',
            function()
                OverviewCamera.moveToTarget()
                return true
            end)
end

function Actions.groupTrackingActions()
    Actions.registerAction("turbobarcam_toggle_group_tracking_camera", 'tp',
            function()
                GroupTrackingCamera.toggle()
                return true
            end, nil)

    Actions.registerAction("turbobarcam_group_tracking_adjust_params", 'tR',
            function(_, params)
                GroupTrackingCamera.adjustParams(params)
                return false
            end)
end

function Actions.I18N()
    Spring.I18N.load({
        en = {
            ["ui.orderMenu.turbobarcam_unit_follow_set_fixed_look_point"]         = "Look point",
            ["ui.orderMenu.turbobarcam_unit_follow_set_fixed_look_point_tooltip"] = "Click on a point/unit to focus camera on",
        }
    })
end

--- Helper function to register an action handler
---@param actionName string Action name
---@param flags string Action flags
---@param handler function Action handler function
function Actions.registerAction(actionName, flags, handler)
    w.widgetHandler.actionHandler:AddAction(w, actionName, DebugUtils.wrapInTrace(handler, actionName), nil, flags)
end

return Actions