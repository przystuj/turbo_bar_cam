---@type CoreModules
local CoreModules = VFS.Include("LuaUI/TurboBarCam/core.lua")
---@type FeatureModules
local FeatureModules = VFS.Include("LuaUI/TurboBarCam/features.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager

---@class Actions
local Actions = {}
local w = widget

--- Register all camera action handlers
function Actions.registerAllActions()
    Actions.coreActions()
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

    Actions.registerAction("turbobarcam_fps_follow_projectile", 'tp',
            function()
                FeatureModules.FPSCamera.toggleFollowProjectile()
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
    Actions.registerAction("turbobarcam_toggle_orbiting_camera", 'tp',
            function()
                FeatureModules.OrbitingCamera.toggle()
                return true
            end)

    Actions.registerAction("turbobarcam_orbit_adjust_params", 'pR',
            function(_, params)
                FeatureModules.OrbitingCamera.adjustParams(params)
                return false
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
                return true
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