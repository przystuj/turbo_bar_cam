# TurboBarCam Keybinds

This document outlines the available actions for TurboBarCam, their descriptions, parameters, and configured keybinds.

## General Controls

| Action | <div style="width:400px">Description</div> | <div style="width:400px">Keybind</div> | Parameters |
|---|---|---|---|
| **Set FOV**<br>`turbobarcam_set_fov` | Sets the camera's Field of View (FOV) to a specific value. | N/A | `fov_value` (numeric, e.g., `45`) |
| **Stop Camera Tracking**<br>`turbobarcam_stop_tracking` | Disables any active TurboBarCam mode and returns to default camera control. | `Esc` | N/A |
| **Toggle Debug Log Level**<br>`turbobarcam_debug` | Toggles the debug logging level for the widget, cycling through INFO, DEBUG, and TRACE levels. | N/A | N/A |
| **Toggle Require Unit Selection for Tracking**<br>`turbobarcam_toggle_require_unit_selection` | Toggles whether unit tracking modes (like Unit Follow, Orbit) can remain active even if no unit is currently selected. If this is disabled (default), tracking usually stops shortly after deselecting the unit. | N/A | N/A |
| **Toggle TurboBarCam**<br>`turbobarcam_toggle` | Toggles the entire TurboBarCam widget on or off. | `numpad.` | N/A |
| **Toggle Zoom (FOV)**<br>`turbobarcam_toggle_zoom` | Cycles through predefined Field of View (FOV) values, effectively zooming the camera in or out. | `Home` | N/A |

## Anchor Point Mode

| Action | <div style="width:400px">Description</div> | <div style="width:400px">Keybind</div> | Parameters |
|---|---|---|---|
| **Adjust Anchor Params**<br>`turbobarcam_anchor_adjust_params` | Adjusts parameters for the Camera Anchor mode, such as transition duration. Actions can be 'add', 'set', or 'reset'. |  `Ctrl+Shift+numpad- add;DURATION,-1`<br> `Ctrl+Shift+numpad+ add;DURATION,1` | `action;param,value;...` (e.g., `add;DURATION,0.5` or `set;DURATION,3` or `reset`). Available param: `DURATION`. |
| **Focus Anchor**<br>`turbobarcam_anchor_focus` | Smoothly transitions the camera to a previously saved anchor point. |  `Shift+F1 1`<br> `Shift+F2 2`<br> `Shift+F3 3`<br> `Shift+F4 4` | `index` (numeric, e.g., 1) |
| **Focus Anchor & Track**<br>`turbobarcam_anchor_focus_while_tracking` | Transitions to a camera anchor while attempting to keep the currently tracked unit (if any from a compatible mode) in view. If no unit is tracked or mode is incompatible, behaves like 'Focus Anchor'. |  `Ctrl+Shift+F1 1`<br> `Ctrl+Shift+F2 2`<br> `Ctrl+Shift+F3 3`<br> `Ctrl+Shift+F4 4` | `index` (numeric, e.g., 1) |
| **Load Anchors**<br>`turbobarcam_anchor_load` | Loads a set of camera anchor points from the storage, specific to the current map. | N/A | `id` (string, identifier for the saved anchor set, e.g., `my_favorite_spots`) |
| **Save Anchors**<br>`turbobarcam_anchor_save` | Saves the current set of camera anchor points to the storage, specific to the current map. | N/A | `id` (string, identifier for saving the anchor set, e.g., `my_battle_views`) |
| **Set Anchor**<br>`turbobarcam_anchor_set` | Saves the current camera position and state as a numbered anchor point. |  `Ctrl+F1 1`<br> `Ctrl+F2 2`<br> `Ctrl+F3 3`<br> `Ctrl+F4 4` | `index` (numeric, e.g., 1) |
| **Set Anchor Easing**<br>`turbobarcam_anchor_easing` | Sets the easing function for camera anchor transitions, affecting the acceleration and deceleration of the movement. | N/A | `none|in|out|inout` (e.g., `inout` for smooth start and end) |

## DollyCam Mode

| Action | <div style="width:400px">Description</div> | <div style="width:400px">Keybind</div> | Parameters |
|---|---|---|---|
| **Add Waypoint**<br>`turbobarcam_dollycam_add` | Adds the current camera position as a new waypoint to the DollyCam route or edits the selected waypoint if in editor mode. | N/A | N/A |
| **Adjust Speed**<br>`turbobarcam_dollycam_adjust_speed` | Adjusts the navigation speed of the DollyCam when a route is active. Accepts values from -1.0 (full reverse) to 1.0 (full forward). |  `numpad6 0.1`<br> `numpad4 -0.1` | `speed` (numeric, -1.0 to 1.0) |
| **Load Route**<br>`turbobarcam_dollycam_load` | Loads a DollyCam route from the storage, specific to the current map. | N/A | `name` (string, identifier of the route to load) |
| **Move Waypoint**<br>`turbobarcam_dollycam_move_waypoint` | Moves the currently selected DollyCam waypoint along a specified axis (X, Y, or Z) by a given amount when in editor mode. |  `numpad5 x -10`<br> `numpad8 x 10`<br> `Ctrl+numpad5 y -10`<br> `Ctrl+numpad8 y 10`<br> `numpad4 z -10`<br> `numpad6 z 10` | `axis` (`x`|`y`|`z`), `value` (numeric amount, e.g., `x,100` or `z,-50`) |
| **Save Route**<br>`turbobarcam_dollycam_save` | Saves the current DollyCam route to the storage, specific to the current map. | N/A | `name` (string, identifier for saving the route) |
| **Set Waypoint LookAt**<br>`turbobarcam_dollycam_edit_lookat` | Sets the selected DollyCam waypoint to look at the currently selected unit. If no unit is selected, it might clear the look-at target. | N/A | None (uses selected unit) |
| **Set Waypoint Speed**<br>`turbobarcam_dollycam_edit_speed` | Sets the target speed for the selected waypoint in the DollyCam editor. Use '1' to reset to default speed. | N/A | `speed_multiplier` (numeric, e.g., `0.5` for half speed, `2` for double speed, `1` to reset) |
| **Test Route**<br>`turbobarcam_dollycam_test` | Loads a predefined DollyCam route named 'test' for development or demonstration purposes. | `Ctrl+\` | N/A |
| **Toggle Direction**<br>`turbobarcam_dollycam_toggle_direction` | Toggles the playback direction (forward/reverse) of the currently active DollyCam navigation. | `numpad5` | N/A |
| **Toggle Editor**<br>`turbobarcam_dollycam_toggle_editor` | Toggles the DollyCam waypoint editor mode on or off. Allows for creation and modification of camera paths. | `Ctrl+[` | N/A |
| **Toggle Navigation**<br>`turbobarcam_dollycam_toggle_navigation` | Starts or stops the DollyCam navigation along the currently defined route. Optionally can start without immediate camera control. | `Ctrl+]` | `noCam` (optional boolean string: `true` to start without taking camera control, `false` or absent for normal start) |

## Unit Follow Mode

| Action | <div style="width:400px">Description</div> | <div style="width:400px">Keybind</div> | Parameters |
|---|---|---|---|
| **Adjust Params**<br>`turbobarcam_unit_follow_adjust_params` | Adjusts parameters for the Unit Follow mode, such as camera offsets in default/combat/weapon modes and mouse sensitivity. Actions can be 'add', 'set', or 'reset'. |  `Ctrl+numpad1 reset`<br> `numpad8 add;DEFAULT.FORWARD,5`<br> `numpad5 add;DEFAULT.FORWARD,-5`<br> `numpad9 add;DEFAULT.HEIGHT,5`<br> `numpad7 add;DEFAULT.HEIGHT,-5`<br> `numpad6 add;DEFAULT.SIDE,5`<br> `numpad4 add;DEFAULT.SIDE,-5`<br> `Ctrl+numpad7 add;DEFAULT.ROTATION,0.1`<br> `Ctrl+numpad9 add;DEFAULT.ROTATION,-0.1`<br> `numpad8 add;COMBAT.FORWARD,5`<br> `numpad5 add;COMBAT.FORWARD,-5`<br> `numpad9 add;COMBAT.HEIGHT,5`<br> `numpad7 add;COMBAT.HEIGHT,-5`<br> `numpad6 add;COMBAT.SIDE,5`<br> `numpad4 add;COMBAT.SIDE,-5`<br> `Ctrl+numpad7 add;COMBAT.ROTATION,0.1`<br> `Ctrl+numpad9 add;COMBAT.ROTATION,-0.1`<br> `numpad8 add;WEAPON.FORWARD,5`<br> `numpad5 add;WEAPON.FORWARD,-5`<br> `numpad9 add;WEAPON.HEIGHT,5`<br> `numpad7 add;WEAPON.HEIGHT,-5`<br> `numpad6 add;WEAPON.SIDE,5`<br> `numpad4 add;WEAPON.SIDE,-5`<br> `Ctrl+numpad7 add;WEAPON.ROTATION,0.1`<br> `Ctrl+numpad9 add;WEAPON.ROTATION,-0.1` | `action;param,value;...` (e.g., `add;DEFAULT.HEIGHT,10` or `set;MOUSE_SENSITIVITY,0.5` or `reset`). Params: `DEFAULT.HEIGHT/FORWARD/SIDE/ROTATION`, `COMBAT.HEIGHT/FORWARD/SIDE/ROTATION`, `WEAPON.HEIGHT/FORWARD/SIDE/ROTATION`, `MOUSE_SENSITIVITY`. |
| **Clear Look Point**<br>`turbobarcam_unit_follow_clear_fixed_look_point` | Clears any fixed look point or unit target that the camera is currently focused on, returning to default forward view. | `numpad*` | N/A |
| **Clear Weapon**<br>`turbobarcam_unit_follow_clear_weapon_selection` | Clears the currently selected weapon in combat mode, stopping any specific weapon aiming. | `Ctrl+PageDown` | N/A |
| **Next Weapon**<br>`turbobarcam_unit_follow_next_weapon` | Cycles to the next available weapon of the unit in combat mode for aiming. | `PageDown` | N/A |
| **Set Look Point**<br>`turbobarcam_unit_follow_set_fixed_look_point` | Activates target selection mode. Click on a point on the map or a unit to make the camera continuously look at that target while following the primary unit. | `numpad/` | None (activates UI command for map/unit click) |
| **Toggle Combat Mode**<br>`turbobarcam_unit_follow_toggle_combat_mode` | Toggles combat mode, which may change camera offsets and enable weapon-specific aiming. | `End` | N/A |
| **Toggle Free Cam**<br>`turbobarcam_unit_follow_toggle_free_cam` | Toggles free camera mouse look in mode, allowing manual control of the camera direction independent of unit heading. | N/A | N/A |
| **Toggle Unit Follow**<br>`turbobarcam_toggle_unit_follow_camera` | Toggles Unit Follow camera mode. Attaches the camera to the currently selected unit. If already in mode for that unit, it disables it. | `numpad1` | None (uses selected unit) |

## Group Tracking Mode

| Action | <div style="width:400px">Description</div> | <div style="width:400px">Keybind</div> | Parameters |
|---|---|---|---|
| **Adjust Group Track Params**<br>`turbobarcam_group_tracking_adjust_params` | Adjusts parameters for the Group Tracking Camera mode, such as camera distance, height, orbit offset, and smoothing factors. Actions can be 'add', 'set', or 'reset'. |  `numpad5 add;EXTRA_DISTANCE,15`<br> `numpad8 add;EXTRA_DISTANCE,-15`<br> `Ctrl+numpad8 add;EXTRA_HEIGHT,5`<br> `Ctrl+numpad5 add;EXTRA_HEIGHT,-5`<br> `numpad4 add;ORBIT_OFFSET,0.01`<br> `numpad6 add;ORBIT_OFFSET,-0.01`<br> `numpad7 add;SMOOTHING.POSITION,-0.002;SMOOTHING.STABLE_POSITION,-0.002`<br> `numpad9 add;SMOOTHING.POSITION,0.002;SMOOTHING.STABLE_POSITION,0.002`<br> `Ctrl+numpad0 reset`<br> `Ctrl+numpad9 set;SMOOTHING.POSITION,0.2;SMOOTHING.STABLE_POSITION,0.2;SMOOTHING.ROTATION,0.2;SMOOTHING.STABLE_ROTATION,0.2`<br> `Ctrl+numpad7 set;SMOOTHING.POSITION,0.03;SMOOTHING.STABLE_POSITION,0.03;SMOOTHING.ROTATION,0.03;SMOOTHING.STABLE_ROTATION,0.03` | `action;param,value;...` (e.g., `add;EXTRA_DISTANCE,100` or `reset`). Params: `EXTRA_DISTANCE`, `EXTRA_HEIGHT`, `ORBIT_OFFSET`, `SMOOTHING.POSITION/ROTATION`, `SMOOTHING.STABLE_POSITION/ROTATION`. |
| **Toggle Group Tracking**<br>`turbobarcam_toggle_group_tracking_camera` | Toggles the Group Tracking Camera mode. Tracks the center of mass of the currently selected units. If already tracking, it disables the mode. | `numpad0` | None (uses selected units) |

## Orbit Mode

| Action | <div style="width:400px">Description</div> | <div style="width:400px">Keybind</div> | Parameters |
|---|---|---|---|
| **Adjust Orbit Params**<br>`turbobarcam_orbit_adjust_params` | Adjusts parameters for the Orbit Camera mode, such as orbit height, distance, and rotation speed. Actions can be 'add', 'set', or 'reset'. |  `Ctrl+numpad2 reset`<br> `numpad5 add;DISTANCE,20`<br> `numpad8 add;DISTANCE,-20`<br> `numpad9 add;HEIGHT,20`<br> `numpad7 add;HEIGHT,-20`<br> `numpad6 add;SPEED,0.01`<br> `numpad4 add;SPEED,-0.01` | `action;param,value;...` (e.g., `add;SPEED,0.0002` or `reset`). Params: `HEIGHT`, `DISTANCE`, `SPEED`. |
| **Load Orbit Config**<br>`turbobarcam_orbit_load` | Loads a saved orbit camera configuration (including target type, ID/position, speed, distance, height, angle, and paused state) for a specific ID, map-dependent. | N/A | `orbitId` (string, identifier of the saved orbit configuration) |
| **Save Orbit Config**<br>`turbobarcam_orbit_save` | Saves the current orbit camera configuration (target, parameters, and state) to a specified ID, map-dependent. | N/A | `orbitId` (string, identifier to save the orbit configuration) |
| **Toggle Orbit Camera (Point)**<br>`turbobarcam_orbit_toggle_point` | Toggles the Orbit Camera mode around a point on the map (cursor position). | N/A | None (uses cursor position) |
| **Toggle Orbit Camera (Unit)**<br>`turbobarcam_orbit_toggle` | Toggles the Orbit Camera mode for the selected unit. If already orbiting the unit, it disables the mode. | `numpad2` | None (uses selected unit) |
| **Toggle Orbit Pause**<br>`turbobarcam_orbit_toggle_pause` | Toggles pausing and resuming the camera's movement in Orbit Camera mode. | N/A | N/A |

## Overview Mode

| Action | <div style="width:400px">Description</div> | <div style="width:400px">Keybind</div> | Parameters |
|---|---|---|---|
| **Overview: Change Height**<br>`turbobarcam_overview_change_height` | Changes the height level of the Overview Camera by a given amount (positive to zoom out, negative to zoom in) and moves the camera to maintain focus. |  `numpad8 1`<br> `numpad5 -1` | `amount` (numeric, e.g., `1` to increase height level, `-1` to decrease) |
| **Overview: Move to Cursor**<br>`turbobarcam_overview_move_camera` | Moves the Overview Camera to focus on the current cursor position on the map. Typically used with mouse bindings. | N/A | None (uses cursor position) |
| **Toggle Overview Camera**<br>`turbobarcam_overview_toggle` | Toggles the Overview Camera mode, providing a top-down strategic view. Focuses on selected unit or cursor position. | `PageUp` | N/A |

## Projectile Camera Mode

| Action | <div style="width:400px">Description</div> | <div style="width:400px">Keybind</div> | Parameters |
|---|---|---|---|
| **Adjust Projectile Cam Params**<br>`turbobarcam_projectile_adjust_params` | Adjusts parameters for the Projectile Camera mode, such as camera distance, height, and look-ahead factor. Actions can be 'add', 'set', or 'reset'. |  `Ctrl+Delete reset`<br> `Ctrl+Insert reset`<br> `numpad8 add;STATIC.OFFSET_HEIGHT,20;FOLLOW.DISTANCE,-20`<br> `numpad5 add;STATIC.OFFSET_HEIGHT,-20;FOLLOW.DISTANCE,20`<br> `numpad9 add;STATIC.LOOK_AHEAD,20;FOLLOW.LOOK_AHEAD,20`<br> `numpad7 add;STATIC.LOOK_AHEAD,-20;FOLLOW.LOOK_AHEAD,-20`<br> `numpad6 add;STATIC.OFFSET_SIDE,5;FOLLOW.HEIGHT,5`<br> `numpad4 add;STATIC.OFFSET_SIDE,-5;FOLLOW.HEIGHT,-5`<br> `Ctrl+numpad4 add;DECELERATION_PROFILE.DURATION,-0.1`<br> `Ctrl+numpad7 add;DECELERATION_PROFILE.DURATION,0.1`<br> `Ctrl+numpad5 add;DECELERATION_PROFILE.INITIAL_BRAKING,-100`<br> `Ctrl+numpad8 add;DECELERATION_PROFILE.INITIAL_BRAKING,100`<br> `Ctrl+numpad6 add;DECELERATION_PROFILE.PATH_ADHERENCE,-0.1`<br> `Ctrl+numpad9 add;DECELERATION_PROFILE.PATH_ADHERENCE,0.1` | `action;param,value;...` (e.g., `add;DISTANCE,50` or `reset`). Params: `DISTANCE`, `HEIGHT`, `LOOK_AHEAD`. |
| **Follow Projectile (Moving Cam)**<br>`turbobarcam_projectile_camera_follow` | Activates Projectile Camera in 'follow' sub-mode. The camera moves with the projectile, attempting to keep it in frame. | `Delete` | None (tracks projectile from currently watched/selected unit) |
| **Track Projectile (Static Cam)**<br>`turbobarcam_projectile_camera_track` | Activates Projectile Camera in 'static' sub-mode. The camera stays at its initial position and rotates to track the projectile. | `Insert` | None (tracks projectile from currently watched/selected unit) |

## Unit Tracking Mode

| Action | <div style="width:400px">Description</div> | <div style="width:400px">Keybind</div> | Parameters |
|---|---|---|---|
| **Adjust Unit Track Params**<br>`turbobarcam_tracking_camera_adjust_params` | Adjusts parameters for the Unit Tracking Camera, primarily the vertical height offset at which the camera looks towards the unit. Actions can be 'add', 'set', or 'reset'. |  `Ctrl+numpad3 reset`<br> `numpad8 add;HEIGHT,20`<br> `numpad5 add;HEIGHT,-20` | `action;param,value;...` (e.g., `add;HEIGHT,50` or `reset`). Available param: `HEIGHT`. |
| **Toggle Unit Tracking**<br>`turbobarcam_toggle_tracking_camera` | Toggles the Unit Tracking Camera mode. Follows the selected unit while attempting to maintain the current camera angle and distance, smoothly adjusting to unit movements. | `numpad3` | None (uses selected unit) |

## Spectator Actions

| Action | <div style="width:400px">Description</div> | <div style="width:400px">Keybind</div> | Parameters |
|---|---|---|---|
| **Spectator Unit Group**<br>`turbobarcam_spec_unit_group` | Manages spectator unit groups. Allows setting a group with selected units, selecting units from a group, or clearing a group. Requires spectator mode. | N/A | `set|select|clear` `groupId` (e.g., `set 1` or `select 1`) |
| **Toggle PlayerCam Selection Lock**<br>`turbobarcam_toggle_playercam_selection` | Toggles whether unit selection is locked or follows the spectated player's selection when the game's Player Camera view is active. | `Ctrl+numpad.` | N/A |

## Development Actions

| Action | <div style="width:400px">Description</div> | <div style="width:400px">Keybind</div> | Parameters |
|---|---|---|---|
| **Dev: Change Config**<br>`turbobarcam_dev_config` | Allows live modification of widget configuration values for development and tweaking. Use with caution as incorrect values can cause errors. | N/A | `path_to_config_value` `new_value` (e.g, `CAMERA_MODES.UNIT_FOLLOW.OFFSETS.UP 25`) |
| **Dev: Reload Widget**<br>`turbobarcam_dev_reload` | Hot reloads widget files without losing the current state, useful for development to apply code changes instantly. | N/A | N/A |
