# TurboBarCam Keybinds

This document outlines the available actions for TurboBarCam, their descriptions, configured keybinds, and parameters used in those keybinds.

## General Controls

| Action | <div style="width:400px">Description</div> | <div style="width:200px">Keybind</div> | <div style="width:200px">Parameters</div> |
|---|---|---|---|
| **Set FOV**<br>`turbobarcam_set_fov` | Sets the camera's Field of View (FOV) to a specific value. | N/A | N/A |
| **Stop Camera Tracking**<br>`turbobarcam_stop_tracking` | Disables any active TurboBarCam mode and returns to default camera control. | `Esc` | N/A |
| **Toggle Debug Log Level**<br>`turbobarcam_debug` | Toggles the debug logging level for the widget, cycling through INFO, DEBUG, and TRACE levels. | N/A | N/A |
| **Toggle Require Unit Selection for Tracking**<br>`turbobarcam_toggle_require_unit_selection` | Toggles whether unit tracking modes (like Unit Follow, Orbit) can remain active even if no unit is currently selected. If this is disabled (default), tracking usually stops shortly after deselecting the unit. | N/A | N/A |
| **Toggle TurboBarCam**<br>`turbobarcam_toggle` | Toggles the entire TurboBarCam widget on or off. | `numpad.` | N/A |
| **Toggle Zoom (FOV)**<br>`turbobarcam_toggle_zoom` | Cycles through predefined Field of View (FOV) values, effectively zooming the camera in or out. | `Home` | N/A |

## Anchor Point Mode

| Action | <div style="width:400px">Description</div> | <div style="width:200px">Keybind</div> | <div style="width:200px">Parameters</div> |
|---|---|---|---|
| **Adjust Anchor Params**<br>`turbobarcam_anchor_adjust_params` | Adjusts parameters for the Camera Anchor mode, such as transition duration. Actions can be 'add', 'set', or 'reset'. | `Ctrl+Shift+numpad-`<br/>`Ctrl+Shift+numpad+` | `add;DURATION,-1`<br/>`add;DURATION,1` |
| **Delete anchor**<br>`turbobarcam_anchor_delete` | Deletes the anchor by id | N/A | N/A |
| **Focus Anchor**<br>`turbobarcam_anchor_focus` | Smoothly transitions the camera to a previously saved anchor point. | `Shift+F1`<br/>`Shift+F2`<br/>`Shift+F3`<br/>`Shift+F4`<br/>`Shift+F5`<br/>`Shift+F6` | `1`<br/>`2`<br/>`3`<br/>`4`<br/>`5`<br/>`6` |
| **Load Anchors**<br>`turbobarcam_anchor_load` | Loads a set of camera anchor points from the storage, specific to the current map. | N/A | N/A |
| **Save Anchors**<br>`turbobarcam_anchor_save` | Saves the current set of camera anchor points to the storage, specific to the current map. | N/A | N/A |
| **Set Anchor**<br>`turbobarcam_anchor_set` | Saves the current camera position and state as a numbered anchor point. | `Ctrl+F1`<br/>`Ctrl+F2`<br/>`Ctrl+F3`<br/>`Ctrl+F4`<br/>`Ctrl+F5`<br/>`Ctrl+F6` | `1`<br/>`2`<br/>`3`<br/>`4`<br/>`5`<br/>`6` |
| **Sync anchors duration**<br>`turbobarcam_anchor_update_all_durations` | Sets all anchors to the same duration (the one you can control with duration adjustment) | `Ctrl+Shift+Alt+numpad+` | N/A |
| **Toggle Single Duration Mode**<br>`turbobarcam_anchor_toggle_single_duration_mode` | Toggles the single anchor duration mode. When enabled all anchors will have the same duration. | N/A | N/A |
| **Toggle Type**<br>`turbobarcam_anchor_toggle_type` | Toggles the anchor type. | N/A | N/A |
| **Toggle anchors HUD**<br>`turbobarcam_anchor_toggle_visualization` | Toggle anchors HUD (Shows them as points in the game) | `Ctrl+Shift+Alt+numpad-` | N/A |

## DollyCam Mode

| Action | <div style="width:400px">Description</div> | <div style="width:200px">Keybind</div> | <div style="width:200px">Parameters</div> |
|---|---|---|---|
| **Add Waypoint**<br>`turbobarcam_dollycam_add` | Adds the current camera position as a new waypoint to the DollyCam route or edits the selected waypoint if in editor mode. | N/A | N/A |
| **Adjust Speed**<br>`turbobarcam_dollycam_adjust_speed` | Adjusts the navigation speed of the DollyCam when a route is active. Accepts values from -1.0 (full reverse) to 1.0 (full forward). | `numpad6`<br/>`numpad4` | `0.1`<br/>`-0.1` |
| **Load Route**<br>`turbobarcam_dollycam_load` | Loads a DollyCam route from the storage, specific to the current map. | N/A | N/A |
| **Move Waypoint**<br>`turbobarcam_dollycam_move_waypoint` | Moves the currently selected DollyCam waypoint along a specified axis (X, Y, or Z) by a given amount when in editor mode. | `numpad5`<br/>`numpad8`<br/>`Ctrl+numpad5`<br/>`Ctrl+numpad8`<br/>`numpad4`<br/>`numpad6` | `x -10`<br/>`x 10`<br/>`y -10`<br/>`y 10`<br/>`z -10`<br/>`z 10` |
| **Save Route**<br>`turbobarcam_dollycam_save` | Saves the current DollyCam route to the storage, specific to the current map. | N/A | N/A |
| **Set Waypoint LookAt**<br>`turbobarcam_dollycam_edit_lookat` | Sets the selected DollyCam waypoint to look at the currently selected unit. If no unit is selected, it might clear the look-at target. | N/A | N/A |
| **Set Waypoint Speed**<br>`turbobarcam_dollycam_edit_speed` | Sets the target speed for the selected waypoint in the DollyCam editor. Use '1' to reset to default speed. | N/A | N/A |
| **Test Route**<br>`turbobarcam_dollycam_test` | Loads a predefined DollyCam route named 'test' for development or demonstration purposes. | `Ctrl+\` | N/A |
| **Toggle Direction**<br>`turbobarcam_dollycam_toggle_direction` | Toggles the playback direction (forward/reverse) of the currently active DollyCam navigation. | `numpad5` | N/A |
| **Toggle Editor**<br>`turbobarcam_dollycam_toggle_editor` | Toggles the DollyCam waypoint editor mode on or off. Allows for creation and modification of camera paths. | `Ctrl+[` | N/A |
| **Toggle Navigation**<br>`turbobarcam_dollycam_toggle_navigation` | Starts or stops the DollyCam navigation along the currently defined route. Optionally can start without immediate camera control. | `Ctrl+]` | N/A |

## Unit Follow Mode

| Action | <div style="width:400px">Description</div> | <div style="width:200px">Keybind</div> | <div style="width:200px">Parameters</div> |
|---|---|---|---|
| **Adjust Params**<br>`turbobarcam_unit_follow_adjust_params` | Adjusts parameters for the Unit Follow mode, such as camera offsets in default/combat/weapon modes and mouse sensitivity. Actions can be 'add', 'set', or 'reset'. | `Ctrl+numpad1`<br/>`numpad8`<br/>`numpad5`<br/>`numpad9`<br/>`numpad7`<br/>`numpad6`<br/>`numpad4`<br/>`Ctrl+numpad7`<br/>`Ctrl+numpad9`<br/>`numpad8`<br/>`numpad5`<br/>`numpad9`<br/>`numpad7`<br/>`numpad6`<br/>`numpad4`<br/>`Ctrl+numpad7`<br/>`Ctrl+numpad9`<br/>`numpad8`<br/>`numpad5`<br/>`numpad9`<br/>`numpad7`<br/>`numpad6`<br/>`numpad4`<br/>`Ctrl+numpad7`<br/>`Ctrl+numpad9` | `reset`<br/>`add;DEFAULT.FORWARD,5`<br/>`add;DEFAULT.FORWARD,-5`<br/>`add;DEFAULT.HEIGHT,5`<br/>`add;DEFAULT.HEIGHT,-5`<br/>`add;DEFAULT.SIDE,5`<br/>`add;DEFAULT.SIDE,-5`<br/>`add;DEFAULT.ROTATION,0.1`<br/>`add;DEFAULT.ROTATION,-0.1`<br/>`add;COMBAT.FORWARD,5`<br/>`add;COMBAT.FORWARD,-5`<br/>`add;COMBAT.HEIGHT,5`<br/>`add;COMBAT.HEIGHT,-5`<br/>`add;COMBAT.SIDE,5`<br/>`add;COMBAT.SIDE,-5`<br/>`add;COMBAT.ROTATION,0.1`<br/>`add;COMBAT.ROTATION,-0.1`<br/>`add;WEAPON.FORWARD,5`<br/>`add;WEAPON.FORWARD,-5`<br/>`add;WEAPON.HEIGHT,5`<br/>`add;WEAPON.HEIGHT,-5`<br/>`add;WEAPON.SIDE,5`<br/>`add;WEAPON.SIDE,-5`<br/>`add;WEAPON.ROTATION,0.1`<br/>`add;WEAPON.ROTATION,-0.1` |
| **Clear Look Point**<br>`turbobarcam_unit_follow_clear_fixed_look_point` | Clears any fixed look point or unit target that the camera is currently focused on, returning to default forward view. | `numpad*` | N/A |
| **Clear Weapon**<br>`turbobarcam_unit_follow_clear_weapon_selection` | Clears the currently selected weapon in combat mode, stopping any specific weapon aiming. | `Ctrl+PageDown` | N/A |
| **Next Weapon**<br>`turbobarcam_unit_follow_next_weapon` | Cycles to the next available weapon of the unit in combat mode for aiming. | `PageDown` | N/A |
| **Set Look Point**<br>`turbobarcam_unit_follow_set_fixed_look_point` | Activates target selection mode. Click on a point on the map or a unit to make the camera continuously look at that target while following the primary unit. | `numpad/` | N/A |
| **Toggle Combat Mode**<br>`turbobarcam_unit_follow_toggle_combat_mode` | Toggles combat mode, which may change camera offsets and enable weapon-specific aiming. | `End` | N/A |
| **Toggle Unit Follow**<br>`turbobarcam_toggle_unit_follow_camera` | Toggles Unit Follow camera mode. Attaches the camera to the currently selected unit. If already in mode for that unit, it disables it. | `numpad1` | N/A |

## Group Tracking Mode

| Action | <div style="width:400px">Description</div> | <div style="width:200px">Keybind</div> | <div style="width:200px">Parameters</div> |
|---|---|---|---|
| **Adjust Group Track Params**<br>`turbobarcam_group_tracking_adjust_params` | Adjusts parameters for the Group Tracking Camera mode, such as camera distance, height, orbit offset, and smoothing factors. Actions can be 'add', 'set', or 'reset'. | `numpad5`<br/>`numpad8`<br/>`Ctrl+numpad8`<br/>`Ctrl+numpad5`<br/>`numpad4`<br/>`numpad6`<br/>`numpad7`<br/>`numpad9`<br/>`Ctrl+numpad0`<br/>`Ctrl+numpad9`<br/>`Ctrl+numpad7` | `add;EXTRA_DISTANCE,15`<br/>`add;EXTRA_DISTANCE,-15`<br/>`add;EXTRA_HEIGHT,5`<br/>`add;EXTRA_HEIGHT,-5`<br/>`add;ORBIT_OFFSET,0.01`<br/>`add;ORBIT_OFFSET,-0.01`<br/>`add;SMOOTHING.POSITION,-1;SMOOTHING.STABLE_POSITION,-1`<br/>`add;SMOOTHING.POSITION,1;SMOOTHING.STABLE_POSITION,1`<br/>`reset`<br/>`set;SMOOTHING.POSITION,1;SMOOTHING.STABLE_POSITION,1;SMOOTHING.ROTATION,1;SMOOTHING.STABLE_ROTATION,1`<br/>`set;SMOOTHING.POSITION,20;SMOOTHING.STABLE_POSITION,20;SMOOTHING.ROTATION,20;SMOOTHING.STABLE_ROTATION,20` |
| **Toggle Group Tracking**<br>`turbobarcam_toggle_group_tracking_camera` | Toggles the Group Tracking Camera mode. Tracks the center of mass of the currently selected units. If already tracking, it disables the mode. | `numpad0` | N/A |

## Orbit Mode

| Action | <div style="width:400px">Description</div> | <div style="width:200px">Keybind</div> | <div style="width:200px">Parameters</div> |
|---|---|---|---|
| **Adjust Orbit Params**<br>`turbobarcam_orbit_adjust_params` | Adjusts parameters for the Orbit Camera mode, such as orbit height, distance, and rotation speed. Actions can be 'add', 'set', or 'reset'. | `Ctrl+numpad2`<br/>`numpad5`<br/>`numpad8`<br/>`numpad9`<br/>`numpad7`<br/>`numpad6`<br/>`numpad4` | `reset`<br/>`add;DISTANCE,20`<br/>`add;DISTANCE,-20`<br/>`add;HEIGHT,20`<br/>`add;HEIGHT,-20`<br/>`add;SPEED,0.01`<br/>`add;SPEED,-0.01` |
| **Load Orbit Config**<br>`turbobarcam_orbit_load` | Loads a saved orbit camera configuration (including target type, ID/position, speed, distance, height, angle, and paused state) for a specific ID, map-dependent. | N/A | N/A |
| **Save Orbit Config**<br>`turbobarcam_orbit_save` | Saves the current orbit camera configuration (target, parameters, and state) to a specified ID, map-dependent. | N/A | N/A |
| **Toggle Orbit Camera (Point)**<br>`turbobarcam_orbit_toggle_point` | Toggles the Orbit Camera mode around a point on the map (cursor position). | N/A | N/A |
| **Toggle Orbit Camera (Unit)**<br>`turbobarcam_orbit_toggle` | Toggles the Orbit Camera mode for the selected unit. If already orbiting the unit, it disables the mode. | `numpad2` | N/A |
| **Toggle Orbit Pause**<br>`turbobarcam_orbit_toggle_pause` | Toggles pausing and resuming the camera's movement in Orbit Camera mode. | N/A | N/A |

## Projectile Camera Mode

| Action | <div style="width:400px">Description</div> | <div style="width:200px">Keybind</div> | <div style="width:200px">Parameters</div> |
|---|---|---|---|
| **Adjust Projectile Cam Params**<br>`turbobarcam_projectile_adjust_params` | Adjusts parameters for the Projectile Camera mode, such as camera distance, height, and look-ahead factor. Actions can be 'add', 'set', or 'reset'. | `Ctrl+Delete`<br/>`Ctrl+Insert`<br/>`numpad8`<br/>`numpad5`<br/>`numpad9`<br/>`numpad7`<br/>`numpad6`<br/>`numpad4`<br/>`Ctrl+numpad4`<br/>`Ctrl+numpad7`<br/>`Ctrl+numpad5`<br/>`Ctrl+numpad8`<br/>`Ctrl+numpad6`<br/>`Ctrl+numpad9` | `reset`<br/>`reset`<br/>`add;STATIC.OFFSET_HEIGHT,20;FOLLOW.DISTANCE,-20`<br/>`add;STATIC.OFFSET_HEIGHT,-20;FOLLOW.DISTANCE,20`<br/>`add;STATIC.LOOK_AHEAD,20;FOLLOW.LOOK_AHEAD,20`<br/>`add;STATIC.LOOK_AHEAD,-20;FOLLOW.LOOK_AHEAD,-20`<br/>`add;STATIC.OFFSET_SIDE,5;FOLLOW.HEIGHT,5`<br/>`add;STATIC.OFFSET_SIDE,-5;FOLLOW.HEIGHT,-5`<br/>`add;DECELERATION_PROFILE.DURATION,-0.1`<br/>`add;DECELERATION_PROFILE.DURATION,0.1`<br/>`add;DECELERATION_PROFILE.INITIAL_BRAKING,-100`<br/>`add;DECELERATION_PROFILE.INITIAL_BRAKING,100`<br/>`add;DECELERATION_PROFILE.PATH_ADHERENCE,-0.1`<br/>`add;DECELERATION_PROFILE.PATH_ADHERENCE,0.1` |
| **Cycle Nukes**<br>`turbobarcam_projectile_camera_cycle` | Cycles to the next projectile of globally tracked units. (currently, only nukes) | `PageUp` | `forward static` |
| **Follow Projectile (Moving Cam)**<br>`turbobarcam_projectile_camera_follow` | Activates Projectile Camera in 'follow' sub-mode. The camera moves with the projectile, attempting to keep it in frame. | `Delete` | N/A |
| **Toggle Mode**<br>`turbobarcam_projectile_camera_toggle_mode` | Toggles the projectile camera mode. | `Ctrl+PageUp` | N/A |
| **Track Projectile (Static Cam)**<br>`turbobarcam_projectile_camera_track` | Activates Projectile Camera in 'static' sub-mode. The camera stays at its initial position and rotates to track the projectile. | `Insert` | N/A |

## Unit Tracking Mode

| Action | <div style="width:400px">Description</div> | <div style="width:200px">Keybind</div> | <div style="width:200px">Parameters</div> |
|---|---|---|---|
| **Adjust Unit Track Params**<br>`turbobarcam_tracking_camera_adjust_params` | Adjusts parameters for the Unit Tracking Camera, primarily the vertical height offset at which the camera looks towards the unit. Actions can be 'add', 'set', or 'reset'. | `Ctrl+numpad3`<br/>`numpad8`<br/>`numpad5` | `reset`<br/>`add;HEIGHT,20`<br/>`add;HEIGHT,-20` |
| **Toggle Unit Tracking**<br>`turbobarcam_toggle_tracking_camera` | Toggles the Unit Tracking Camera mode. Follows the selected unit while attempting to maintain the current camera angle and distance, smoothly adjusting to unit movements. | `numpad3` | N/A |

## Spectator Actions

| Action | <div style="width:400px">Description</div> | <div style="width:200px">Keybind</div> | <div style="width:200px">Parameters</div> |
|---|---|---|---|
| **Spectator Unit Group**<br>`turbobarcam_spec_unit_group` | Manages spectator unit groups. Allows setting a group with selected units, selecting units from a group, or clearing a group. Requires spectator mode. | N/A | N/A |
| **Toggle PlayerCam Selection Lock**<br>`turbobarcam_toggle_playercam_selection` | Toggles whether unit selection is locked or follows the spectated player's selection when the game's Player Camera view is active. | N/A | N/A |

## Development Actions

| Action | <div style="width:400px">Description</div> | <div style="width:200px">Keybind</div> | <div style="width:200px">Parameters</div> |
|---|---|---|---|
| **Dev: Change Config**<br>`turbobarcam_dev_config` | Allows live modification of widget configuration values for development and tweaking. Use with caution as incorrect values can cause errors. | N/A | N/A |
