# TURBOBARCAM - Tactical Ultra-Responsive Brilliant Optics for BAR Camera

An advanced camera control suite for Beyond All Reason, featuring smooth transitions, unit tracking, FPS mode, orbital view, spectator controls, and fixed point tracking.

## Overview

TURBOBARCAM provides a comprehensive camera control system with multiple specialized modes for both players and spectators. It enables fluid camera movements, unit-centered views, and cinematic transitions between saved camera positions.

## Features

- **Camera Anchors**: Save and recall camera positions with smooth transitions
- **FPS Camera**: View the game from a unit's perspective with adjustable offsets, free camera control, fixed point tracking, and auto-orbit features
- **Tracking Camera**: Follow selected unit while maintaining your preferred viewing angle
- **Orbiting Camera**: Circle around units with adjustable speed
- **Spectator Tools**: Group and select units when spectating
- **Overview Camera**: Top-down strategic view with custom zoom levels and cursor tracking (Work in Progress)
- **Group Tracking Camera**: Track a group of units with automatic clustering (Work in Progress)

## How to Install

- Download `turbobarcam_vX.zip`
- Extract it in your BAR data folder
- After extracting, your folder structure should look like this:
```
BAR install folder/
└── data/
    └── LuaUI/
        ├── Widgets/
        └── TURBOBARCAM/
```
- Enable "Tactical Ultra-Responsive Brilliant Optics for BAR Camera" in-game

## Getting Started

By default, TURBOBARCAM is loaded but disabled. To enable it:

```
/turbobarcam_toggle
```

When you enable TURBOBARCAM:
- If you have a unit selected, the camera will automatically zoom in on that unit in FPS mode
- If no unit is selected, it will switch to FPS mode without moving the camera position

## Default Keybindings

TURBOBARCAM comes with a default set of keybindings. To use them, add the following line to the end of your `uikeys.txt` file (located in your Spring directory):

```
keyload     luaui/TURBOBARCAM/turbobarcam.uikeys.txt
```

## Commands and Keybindings

### Default Keybinds

TURBOBARCAM comes with a default set of keybindings. To use them, add the following line to the end of your `uikeys.txt` file:

```
keyload     luaui/TURBOBARCAM/turbobarcam.uikeys.txt
```

Here's a summary of the default keybinds:

| Key                       | Action | Description |
|---------------------------|--------|-------------|
| **General Controls**      |
| Numpad .                  | Toggle TURBOBARCAM | Enable/disable the camera suite |
| Ctrl+Numpad .             | Toggle widget | Alternative way to toggle the widget |
| **Camera Anchors**        |
| Ctrl+F1 to F4             | Set anchor 1-4 | Save current camera position as anchors 1-4 |
| F1 to F4                  | Focus anchor 1-4 | Transition to saved anchor positions 1-4 |
| Shift+F1 to F4            | Focus and track 1-4 | Move to anchor and track selected unit |
| Ctrl+Shift+Numpad -       | Decrease transition duration | Make transitions between anchors faster |
| Ctrl+Shift+Numpad +       | Increase transition duration | Make transitions between anchors slower |
| **FPS Camera**            |
| Numpad 1                  | Toggle FPS camera | Attach camera to selected unit in FPS mode |
| Numpad 8                  | Forward/Up | Move camera forward and slightly down |
| Numpad 5                  | Backward/Down | Move camera backward and slightly up |
| Ctrl+Numpad 8             | Height up | Increase camera height |
| Ctrl+Numpad 5             | Height down | Decrease camera height |
| Numpad 6                  | Side right | Move camera right |
| Numpad 4                  | Side left | Move camera left |
| Numpad 7                  | Rotate left | Rotate camera left |
| Numpad 9                  | Rotate right | Rotate camera right |
| Ctrl+Numpad 1             | Reset FPS | Reset all FPS camera offsets to defaults |
| Numpad /                  | Set look point | Select a fixed point for camera to look at |
| Numpad *                  | Clear look point | Return to normal unit following mode |
| **Unit Tracking Camera**  |
| Numpad 3                  | Toggle unit tracking | Follow selected unit, maintaining camera angle |
| Ctrl+Numpad 3             | Reset tracking | Reset tracking camera parameters |
| Numpad 8                  | Height up | Increase look-at point height |
| Numpad 5                  | Height down | Decrease look-at point height |
| **Orbiting Camera**       |
| Numpad 2                  | Toggle orbit camera | Circle around selected unit |
| Numpad 5                  | Decrease orbit | Decrease height and distance |
| Numpad 8                  | Increase orbit | Increase height and distance |
| Numpad 9                  | Speed up | Increase orbit speed |
| Numpad 7                  | Speed down | Decrease orbit speed |
| **Group Tracking Camera** |
| Numpad 0                  | Toggle group tracking | Track selected group of units |
| Numpad 5                  | Decrease distance/height | Move camera closer and lower |
| Numpad 8                  | Increase distance/height | Move camera farther and higher |
| Numpad 6                  | Orbit right | Rotate camera position right |
| Numpad 4                  | Orbit left | Rotate camera position left |
| Numpad 7                  | Decrease smoothing | Make camera movements more responsive |
| Numpad 9                  | Increase smoothing | Make camera movements smoother |
| Ctrl+Numpad 0             | Reset group tracking | Reset all group tracking settings |
| **Overview Camera**       |
| End                       | Toggle overview camera | Enable strategic overview mode |
| PageDown                  | Move to cursor | Move camera to cursor position |
| Delete                    | Change zoom level | Cycle through zoom levels |
| **Spectator Groups**      |
| Ctrl+Insert               | Set group 1 | Save selected units as spectator group 1 |
| Insert                    | Select group 1 | Select units from spectator group 1 |
| Ctrl+Home                 | Set group 2 | Save selected units as spectator group 2 |
| Home                      | Select group 2 | Select units from spectator group 2 |
| Ctrl+PageUp               | Set group 3 | Save selected units as spectator group 3 |
| PageUp                    | Select group 3 | Select units from spectator group 3 |

## Command Reference

### Core Commands

| Command | Description |
|---------|-------------|
| `/turbobarcam_toggle` | Enable or disable the TURBOBARCAM widget |
| `/turbobarcam_debug` | Toggle debug mode for troubleshooting |

### Camera Anchors

| Command | Description |
|---------|-------------|
| `/turbobarcam_anchor_set [0-9]` | Save current camera position as an anchor |
| `/turbobarcam_anchor_focus [0-9]` | Smoothly transition to a saved camera anchor |
| `/turbobarcam_anchor_focus_while_tracking [0-9]` | Move to anchor position while tracking selected unit |
| `/turbobarcam_anchor_adjust_params [action];[param],[value]` | Adjust anchor parameters (see Parameter Adjustment System) |

### FPS Camera

| Command | Description |
|---------|-------------|
| `/turbobarcam_toggle_fps_camera` | Toggle FPS camera mode for selected unit |
| `/turbobarcam_fps_adjust_params [action];[param],[value]` | Adjust FPS camera parameters (see Parameter Adjustment System) |
| `/turbobarcam_fps_toggle_free_cam` | Toggle free camera control (mouse look) |
| `/turbobarcam_fps_set_fixed_look_point` | Select a point or unit which will be focused by camera |
| `/turbobarcam_fps_clear_fixed_look_point` | Clear fixed look point and return to normal FPS view |

### Tracking Camera

| Command | Description |
|---------|-------------|
| `/turbobarcam_toggle_tracking_camera` | Toggle tracking camera (follows selected unit) |
| `/turbobarcam_tracking_camera_adjust_params [action];[param],[value]` | Adjust tracking camera parameters (see Parameter Adjustment System) |

### Orbiting Camera

| Command | Description |
|---------|-------------|
| `/turbobarcam_toggle_orbiting_camera` | Toggle orbiting camera around selected unit |
| `/turbobarcam_orbit_adjust_params [action];[param],[value]` | Adjust orbit parameters (see Parameter Adjustment System) |

### Overview Camera

| Command | Description |
|---------|-------------|
| `/turbobarcam_overview_toggle` | Toggle overview camera mode |
| `/turbobarcam_overview_change_zoom` | Cycle through zoom levels |
| `/turbobarcam_overview_move_camera` | Move camera to cursor position with steering |
| `/turbobarcam_overview_adjust_params [action];[param],[value]` | Adjust overview camera parameters (see Parameter Adjustment System) |

### Group Tracking Camera

| Command | Description |
|---------|-------------|
| `/turbobarcam_toggle_group_tracking_camera` | Toggle group tracking for selected units |
| `/turbobarcam_group_tracking_adjust_params [action];[param],[value]` | Adjust group tracking parameters (see Parameter Adjustment System) |

### Spectator Tools

| Command | Description |
|---------|-------------|
| `/turbobarcam_spec_unit_group set [1-9]` | Set a spectator unit group from selected units |
| `/turbobarcam_spec_unit_group select [1-9]` | Select all units from a spectator unit group |
| `/turbobarcam_spec_unit_group clear [1-9]` | Clear a spectator unit group |

## Parameter Adjustment System

TURBOBARCAM includes a powerful parameter adjustment system that allows you to fine-tune camera behaviors. You can adjust these parameters using keybinds or commands.

### Adjustment Format

The general format for adjustments is:
```
turbobarcam_[mode]_adjust_params [action];[param],[value];[param2],[value2]...
```

Where:
- `[mode]` is the camera mode (fps, orbit, tracking_camera, group_tracking, etc.)
- `[action]` is one of:
  - `add`: change a value by the specified amount (can be negative)
  - `set`: directly set a parameter to a specific value
  - `reset`: restore all parameters to defaults
- `[param]` is the parameter name
- `[value]` is the amount to change or the absolute value to set

### Adjustable Parameters

#### FPS Camera Parameters
- `HEIGHT`: Camera height above unit (range: 0+, default: 60)
- `FORWARD`: Forward/backward offset (negative = behind unit, default: -300)
- `SIDE`: Left/right offset (negative = left, default: 0)
- `ROTATION`: Horizontal rotation in radians (default: 0)
- `MOUSE_SENSITIVITY`: Sensitivity for free camera mode (range: 0.0001-0.01, default: 0.003)

**Important**: When you rotate the camera using the `ROTATION` parameter, the `FORWARD` and `SIDE` parameters will still work relative to the unit's orientation, not the camera's view direction. This means they might appear to work in unexpected directions after rotation, as they're tied to the unit's coordinate system rather than what you see on screen.

#### Orbit Camera Parameters
- `HEIGHT`: Camera height above unit (range: 100+, changes with unit type)
- `DISTANCE`: Orbit radius (range: 100+, default: 800)
- `SPEED`: Orbit speed in radians per frame (range: -0.005 to 0.005, default: 0.0005)

#### Unit Tracking Parameters
- `HEIGHT`: Look-at point height offset (range: -500 to 400, default: 0)

#### Group Tracking Parameters
- `EXTRA_DISTANCE`: Additional distance beyond calculated value (range: -1000 to 3000, default: 0)
- `EXTRA_HEIGHT`: Additional height beyond calculated value (range: -1000 to 3000, default: 0)
- `ORBIT_OFFSET`: Orbit angle offset in radians (range: -3.14 to 3.14, default: 0)
- `SMOOTHING.POSITION`: Position smoothing factor (range: 0.001-0.2, default: 0.03, lower = smoother)
- `SMOOTHING.ROTATION`: Rotation smoothing factor (range: 0.001-0.2, default: 0.01, lower = smoother)
- `SMOOTHING.STABLE_POSITION`: Smoothing for when units are barely moving (range: 0.001-0.2, default: 0.01)
- `SMOOTHING.STABLE_ROTATION`: Rotation smoothing for when units are barely moving (range: 0.001-0.2, default: 0.005)

#### Anchor Parameters
- `DURATION`: Transition time in seconds (range: 0+, default: 2.0, 0 = instant transition)

#### Overview Camera Parameters
- `DEFAULT_SMOOTHING`: Camera movement smoothing (range: 0.001-0.5, default: 0.05)
- `FORWARD_VELOCITY`: Movement speed (range: 1-20, default: 5)
- `MAX_ROTATION_SPEED`: Maximum rotation speed (range: 0.001-0.05, default: 0.015)
- `BUFFER_ZONE`: Center screen dead zone (range: 0-0.5, default: 0.10)

## Example Adjustments

```
/turbobarcam_fps_adjust_params add;HEIGHT,10;FORWARD,-20
```
This increases camera height by 10 and moves it back by 20.

```
/turbobarcam_orbit_adjust_params add;SPEED,0.0002
```
This increases orbit speed by 0.0002 radians per frame.

```
/turbobarcam_fps_adjust_params reset
```
This resets all FPS camera parameters to their default values.

```
/turbobarcam_anchor_adjust_params set;DURATION,0
```
This sets anchor transitions to instant (no smooth transition).

## Camera Modes

### Camera Anchors

Camera anchors allow you to save camera positions and smoothly transition between them. They're especially useful for spectating and for quickly switching between different areas of the battlefield.

**Usage Example**:
1. Position your camera where you want
2. `/turbobarcam_anchor_set 1` (saves the position as anchor 1)
3. Move camera elsewhere
4. `/turbobarcam_anchor_focus 1` (smoothly transitions back to anchor 1)

**Focus While Tracking**:
The `turbobarcam_anchor_focus_while_tracking` command has different behaviors depending on the current state:
- If FPS, orbit, or unit tracking is active: Camera moves to the anchor position while continuing to look at the tracked unit
- If no tracking mode is enabled: Behaves like a regular transition to the anchor

### FPS Camera

The FPS camera attaches to a unit and follows its movements, providing a first-person-like perspective. You can adjust height, forward/backward position, side offset, and rotation to get the perfect view.

**Usage Example**:
1. Select a unit
2. `/turbobarcam_toggle_fps_camera` (camera attaches to the unit)
3. Use adjustment commands to adjust the view

**Auto-orbit**:
When enabled, auto-orbit automatically transitions from FPS mode to orbiting when a unit stops moving for a configurable period. When the unit starts moving again, it transitions back to FPS mode. Think of it as an "idle animation" for the camera that adds visual interest when units are stationary.

**Free Camera Mode**:
While in FPS mode, you can toggle free camera control that allows you to manually control the camera direction while still following a unit's position.

**Usage Example**:
1. While in FPS mode for a unit
2. `/turbobarcam_fps_toggle_free_cam` (enables mouse control of camera)
3. Use mouse to look around while still following the unit

**Fixed Point Tracking**:
While in FPS mode, you can set a fixed point for the camera to look at, which is useful for keeping your focus on a specific area while your unit moves around.

**Usage Example**:
1. While in FPS mode for a unit
2. Click the "Look point" command from the order menu or use the bound key
3. Click on a location or unit you want to focus on

You can bind the `turbobarcam_fps_set_fixed_look_point` command to a key for quicker access when selecting fixed look points.

### Tracking Camera

The tracking camera follows a selected unit but doesn't change the camera's height or rotation unless you move it manually. It's useful for following units while maintaining your preferred viewing angle.

**Usage Example**:
1. Select a unit
2. `/turbobarcam_toggle_tracking_camera` (camera will track the unit)

### Orbiting Camera

The orbiting camera circles around a selected unit at a configurable speed. It's especially useful for inspecting units or watching battles from different angles.

**Usage Example**:
1. Select a unit
2. `/turbobarcam_toggle_orbiting_camera` (camera starts orbiting)
3. Use speed adjustments to change orbit speed

### Overview Camera (Work in Progress)

The overview camera provides a strategic top-down view with multiple zoom levels and cursor-based rotation. It's perfect for getting a better understanding of the battlefield layout.

**Usage Example**:
1. `/turbobarcam_overview_toggle` (enables overview mode)
2. `/turbobarcam_overview_change_zoom` (cycles through zoom levels)
3. `/turbobarcam_overview_move_camera` (moves camera to cursor position with smooth tracking)

**Note**: The overview camera is still under development and may be completely redesigned in future versions.

### Group Tracking Camera (Work in Progress)

The group tracking camera follows multiple selected units, automatically calculating the center of mass and ideal viewing distance. It's perfect for keeping track of a squad or group of units.

**Usage Example**:
1. Select multiple units
2. `/turbobarcam_toggle_group_tracking_camera` (enables group tracking)
3. Use adjustment commands to fine-tune the view

**Note**: The group tracking camera is still being refined. It may have issues with units that rotate frequently (like "stationary" aircraft) and may undergo significant changes in future versions.

### Auto-orbit

When enabled in the CONFIG settings, auto-orbit automatically transitions from FPS mode to orbiting when a unit stops moving for a configurable period. When the unit starts moving again, it transitions back to FPS mode.

## Spectator Features

TURBOBARCAM includes special features for spectators, including the ability to create and manage unit groups. While spectators cannot directly control units, this feature allows for quickly switching between tracked units without having to find them on the map again.

**Usage Example**:
1. When spectating, select units you want to track frequently
2. `/spec_unit_group set 1` (saves selected units as group 1)
3. Later, `/spec_unit_group select 1` (selects all units from group 1)
4. Use any tracking feature with the newly selected units

**Note**: Spectator unit groups only work in spectator mode, and are particularly useful for quickly switching between important units during casts or when analyzing games.

## Multi-Mode Keybinding

Since mode-specific actions only work when the corresponding mode is active, you can bind different actions for different modes to the same key. For example, you could bind numpad 8 to increase height in FPS mode, adjust distance in orbit mode, and change zoom in overview mode.

## Tips and Tricks

- Use camera anchors with different transition durations for cinematic effects
- Combine anchors with tracking for powerful spectating tools
- Free camera mode works great with fixed point tracking
- FPS camera settings are remembered per unit type
- The overview camera's smoothing can be adjusted for more responsive or cinematic movement
- Auto-orbit provides nice visual variety during gameplay
- In group tracking mode, try different orbit offsets to find the best angle
- Bind common adjustments to easily accessible keys for quick fine-tuning
- When a unit gets below your camera in FPS mode, you can briefly flip to orbit mode and back to quickly reposition behind it
- Set the anchor transition duration to 0 for instant camera jumps

## Configuration

The widget comes with sensible defaults, but you can modify many settings in the `camera_turbobarcam_config.lua` file to customize the experience to your preferences.

## Acknowledgments

TURBOBARCAM was created by [SuperKitowiec](https://www.youtube.com/@superkitowiec2) for the Beyond All Reason community.

---

*Note: This widget is under active development. Features and commands may change in future updates. v1.1*