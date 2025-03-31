# Tactical Ultra-Responsive Rotation & Brilliant Optics for BAR Camera (TURBO_BAR_CAM)

An advanced camera control suite for Beyond All Reason, featuring smooth transitions, unit tracking, FPS mode, orbital view, spectator controls, and fixed point tracking.

## Overview

TURBO_BAR_CAM provides a comprehensive camera control system with multiple specialized modes for both players and spectators. It enables fluid camera movements, unit-centered views, and cinematic transitions between saved camera positions.

## Features

- **Camera Anchors**: Save and recall camera positions with smooth transitions
- **Unit-centered Cameras**: Multiple tracking modes that follow units
- **FPS Mode**: View the game from a unit's perspective with adjustable offsets
- **Orbiting Camera**: Circle around units with adjustable speed
- **Fixed Point Tracking**: Follow a unit while keeping the camera pointed at a specific location
- **Free Camera Mode**: Manually control camera direction while following a unit
- **Spectator Tools**: Group and select units when spectating
- **Auto-orbit**: Automatically transition to orbit view when units are stationary

## How to install
- Download turbo_bar_cam_vX.zip
- Extract it in data folder 
- It should look like this after extracting:
```
BAR install folder/
└── data/
    └── LuaUI/
        ├── Widgets/
        └── TURBOBARCAM/
```
-- enable "Tactical Ultra-Responsive Rotation & Brilliant Optics for BAR Camera" in-game

## Getting Started

By default, TURBO_BAR_CAM is loaded but disabled. To enable it:

```
/toggle_camera_suite
```

Once enabled, the camera will center on the map and switch to FPS mode. Now you can use all the features described below.

## Commands and Keybindings

### Widget Control

| Command | Description                                |
|---------|--------------------------------------------|
| `/toggle_camera_suite` | Enable or disable the TURBO_BAR_CAM widget |

### Camera Anchors

| Command | Description |
|---------|-------------|
| `/set_smooth_camera_anchor [0-9]` | Save current camera position as an anchor |
| `/focus_smooth_camera_anchor [0-9]` | Smoothly transition to a saved camera anchor |
| `/decrease_smooth_camera_duration` | Decrease transition duration between anchors |
| `/increase_smooth_camera_duration` | Increase transition duration between anchors |
| `/focus_anchor_and_track [0-9]` | Move to anchor position and track selected unit |

### FPS Camera

| Command | Description |
|---------|-------------|
| `/toggle_fps_camera` | Toggle FPS camera mode for selected unit |
| `/fps_height_offset_up` | Increase camera height offset |
| `/fps_height_offset_down` | Decrease camera height offset |
| `/fps_forward_offset_up` | Increase forward offset (move camera forward) |
| `/fps_forward_offset_down` | Decrease forward offset (move camera backward) |
| `/fps_side_offset_right` | Increase right side offset |
| `/fps_side_offset_left` | Increase left side offset |
| `/fps_rotation_right` | Rotate camera right |
| `/fps_rotation_left` | Rotate camera left |
| `/fps_toggle_free_cam` | Toggle free camera control (mouse look) |
| `/fps_reset_defaults` | Reset all offsets to default values |
| `/set_fixed_look_point` | Select a point or unit which will be focused by camera |
| `/clear_fixed_look_point` | Clear fixed look point and return to normal FPS view |

### Tracking Camera

| Command | Description |
|---------|-------------|
| `/toggle_tracking_camera` | Toggle tracking camera (follows selected unit) |

### Orbiting Camera

| Command | Description |
|---------|-------------|
| `/toggle_orbiting_camera` | Toggle orbiting camera around selected unit |
| `/orbit_speed_up` | Increase orbit speed |
| `/orbit_speed_down` | Decrease orbit speed |
| `/orbit_reset_defaults` | Reset orbit settings to defaults |

### Spectator Tools

| Command | Description |
|---------|-------------|
| `/spec_unit_group set [1-9]` | Set a spectator unit group from selected units |
| `/spec_unit_group select [1-9]` | Select all units from a spectator unit group |
| `/spec_unit_group clear [1-9]` | Clear a spectator unit group |

## Camera Modes

### Camera Anchors

Camera anchors allow you to save camera positions and smoothly transition between them. They're especially useful for spectating and for quickly switching between different areas of the battlefield.

**Usage Example**:
1. Position your camera where you want
2. `/set_smooth_camera_anchor 1` (saves the position as anchor 1)
3. Move camera elsewhere
4. `/focus_smooth_camera_anchor 1` (smoothly transitions back to anchor 1)

### FPS Camera

The FPS camera attaches to a unit and follows its movements, providing a first-person-like perspective. You can adjust height, forward/backward position, side offset, and rotation to get the perfect view.

**Usage Example**:
1. Select a unit
2. `/toggle_fps_camera` (camera attaches to the unit)
3. Use offset commands to adjust the view

### Fixed Point Tracking

While in FPS mode, you can set a fixed point for the camera to look at, which is useful for keeping your focus on a specific area while your unit moves around.

**Usage Example**:
1. Enable FPS camera for a unit
2. Click the "Look point" command from the order menu
3. Click on a location or unit you want to focus on

### Free Camera Mode

Free camera mode allows you to manually control the camera direction while still following a unit's position.

**Usage Example**:
1. Enable FPS camera for a unit
2. `/fps_toggle_free_cam` (enables mouse control of camera)
3. Use mouse to look around while still following the unit

### Tracking Camera

The tracking camera follows a selected unit but doesn't change the camera's height or rotation unless you move it manually. It's useful for following units while maintaining your preferred viewing angle.

**Usage Example**:
1. Select a unit
2. `/toggle_tracking_camera` (camera will track the unit)

### Orbiting Camera

The orbiting camera circles around a selected unit at a configurable speed. It's especially useful for inspecting units or watching battles from different angles.

**Usage Example**:
1. Select a unit
2. `/toggle_orbiting_camera` (camera starts orbiting)
3. Use speed adjustments to change orbit speed

### Auto-orbit

When enabled, auto-orbit automatically transitions from FPS mode to orbiting when a unit stops moving for a configurable period. When the unit starts moving again, it transitions back to FPS mode.

## Spectator Features

TURBO_BAR_CAM includes special features for spectators, including the ability to create and manage unit groups. While spectators cannot directly control units, this feature allows for quickly switching between tracked units without having to find them on the map again.

**Usage Example**:
1. When spectating, select units you want to track frequently
2. `/spec_unit_group set 1` (saves selected units as group 1)
3. Later, `/spec_unit_group select 1` (selects all units from group 1)
4. Use any tracking feature with the newly selected units

**Note**: Spectator unit groups only work in spectator mode, and are particularly useful for quickly switching between important units during casts or when analyzing games.

## Tips and Tricks

- Use camera anchors with different transition durations for cinematic effects
- Combine anchors with tracking for powerful spectating tools
- Free camera mode works great with fixed point tracking
- FPS camera settings are remembered per unit type
- Auto-orbit provides nice visual variety during gameplay

## Configuration

The widget comes with sensible defaults, but you can modify many settings in the `camera_turbobarcam_config.lua` file to customize the experience to your preferences.

## Acknowledgments

TURBO_BAR_CAM was created by [SuperKitowiec](https://www.youtube.com/@superkitowiec2) for the Beyond All Reason community.


---

*Note: This widget is still under development. Features and commands may change in future updates.*