# TurboBarCam - Tactical Ultra-Responsive Brilliant Optics for BAR Camera

An advanced camera control suite for Beyond All Reason, featuring smooth transitions, unit tracking, FPS mode, orbital view, spectator controls, and more.

## Overview

TurboBarCam provides a comprehensive camera control system with multiple specialized modes for both players and spectators. It enables fluid camera movements, unit-centered views, and cinematic transitions between saved camera positions.

## Features

- **Camera Anchors**: Save and recall camera positions with smooth transitions
- **FPS Camera**: View the game from a unit's perspective with adjustable offsets, free camera control, and fixed point tracking
- **Tracking Camera**: Follow selected units while maintaining your preferred viewing angle
- **Orbiting Camera**: Circle around units with adjustable speed and height
- **Group Tracking Camera**: Track a group of units with automatic clustering
- **Overview Camera**: Top-down strategic view with custom zoom levels and cursor tracking
- **Projectile Camera**: Follow projectiles fired from units
- **Spectator Tools**: Group and select units when spectating

## Installation

1. Download `turbobarcam_vX.zip`
2. Extract it in your BAR data folder
3. After extracting, your folder structure should look like:
```
BAR install folder/
└── data/
    └── LuaUI/
        ├── Widgets/
        └── TurboBarCam/
```
4. Enable "Tactical Ultra-Responsive Brilliant Optics for BAR Camera" in-game

## Getting Started

By default, TurboBarCam is loaded but disabled. To enable it:

```
/turbobarcam_toggle
```

## Default Keybindings

To use the default keybindings, add this line to your `uikeys.txt` file:

```
keyload     luaui/TurboBarCam/turbobarcam.uikeys.txt
```

### Key Bindings Summary

| Key | Action |
|-----|--------|
| **General** |
| Numpad . | Toggle TurboBarCam |
| Ctrl+Numpad . | Toggle player unit selection |
| PageUp | Toggle FOV/zoom |
| **Camera Anchors** |
| Ctrl+F1 to F4 | Set camera anchor 1-4 |
| Shift+F1 to F4 | Focus and track anchor 1-4 |
| Ctrl+Shift+Numpad -/+ | Adjust anchor duration |
| **Single Unit Tracking** |
| Numpad 3 | Toggle tracking camera |
| Ctrl+Numpad 3 | Reset tracking parameters |
| Numpad 8/5 | Adjust height (+/-) |
| **Orbit Camera** |
| Numpad 2 | Toggle orbiting camera |
| Numpad 5/8 | Adjust height and distance |
| Numpad 4/6 | Adjust height only |
| Numpad 7/9 | Adjust orbit speed |
| **FPS Camera** |
| Numpad 1 | Toggle FPS camera |
| Numpad 8/5 | Move forward/backward |
| Numpad 4/6 | Move left/right |
| Numpad 7/9 | Rotate left/right |
| Ctrl+Numpad 8/5 | Adjust height |
| Ctrl+Numpad 1 | Reset FPS parameters |
| Numpad * | Clear fixed look point |
| Numpad / | Set fixed look point |
| Delete | Clear weapon selection |
| PageDown | Next weapon |
| **Spectator Groups** |
| Ctrl+Insert | Set spectator group 1 |
| Insert | Select spectator group 1 |
| **Overview Camera** |
| Home | Toggle overview |
| Insert | Move camera |
| Delete | Change zoom |
| **Group Tracking** |
| Numpad 0 | Toggle group tracking |
| Numpad 5/8 | Adjust distance/height |
| Numpad 4/6 | Adjust orbit offset |
| Numpad 7/9 | Adjust smoothing |
| Ctrl+Numpad 0 | Reset group tracking |
| **Projectile Tracking** |
| End | Toggle projectile camera |
| Numpad 8/5 | Adjust distance |
| Numpad 7/9 | Adjust look ahead |
| Numpad 4/6 | Adjust height |

## Parameter Adjustment System

TurboBarCam includes a system to fine-tune camera behaviors using the following format:

```
turbobarcam_[mode]_adjust_params [action];[param],[value];...
```

Where:
- `[mode]` is the camera mode (fps, orbit, tracking_camera, etc.)
- `[action]` is `add`, `set`, or `reset`
- `[param]` is the parameter name
- `[value]` is the amount to change or the value to set

### Key Adjustable Parameters

#### FPS Camera
- `HEIGHT`: Camera height above unit
- `FORWARD`: Forward/backward offset
- `SIDE`: Left/right offset
- `ROTATION`: Horizontal rotation in radians
- `WEAPON_FORWARD/HEIGHT/SIDE`: Weapon position offsets

#### Orbit Camera
- `HEIGHT`: Camera height above unit
- `DISTANCE`: Orbit radius
- `SPEED`: Orbit speed in radians per frame

#### Unit Tracking
- `HEIGHT`: Look-at point height offset

#### Group Tracking
- `EXTRA_DISTANCE`: Additional distance beyond calculated value
- `EXTRA_HEIGHT`: Additional height beyond calculated
- `ORBIT_OFFSET`: Orbit angle offset
- `SMOOTHING`: Various smoothing parameters

#### Anchor
- `DURATION`: Transition time in seconds

#### Projectile Camera
- `DISTANCE`: Distance from projectile
- `HEIGHT`: Height above projectile
- `LOOK_AHEAD`: Forward tracking distance

## Example Adjustments

```
/turbobarcam_fps_adjust_params add;HEIGHT,10;FORWARD,-20
```
Increases camera height by 10 and moves it back by 20.

```
/turbobarcam_orbit_adjust_params add;SPEED,0.0002
```
Increases orbit speed.

```
/turbobarcam_fps_adjust_params reset
```
Resets all FPS camera parameters to defaults.

## Camera Modes Overview

### Camera Anchors
Save positions and transition between them. Use with tracking for advanced spectating.

### FPS Camera
Attaches to a unit for a first-person perspective with adjustable offsets and angles. Supports weapon selection for combat view.

### Tracking Camera
Follows a unit while maintaining your viewing angle.

### Orbiting Camera
Circles around a unit at configurable speed and height.

### Group Tracking Camera
Follows multiple units, calculating center of mass and ideal viewing distance.

### Overview Camera
Strategic top-down view with zoom levels and cursor-based rotation.

### Projectile Camera
Follows projectiles fired from units, with configurable distance and angle.

## Spectator Features

Create and manage unit groups for quickly switching between tracked units:

```
/turbobarcam_spec_unit_group set 1    # Save selected units as group 1
/turbobarcam_spec_unit_group select 1 # Select all units from group 1
```

## Tips

- Bind different actions for different modes to the same key
- Camera anchors with different transition durations create cinematic effects
- FPS camera settings are remembered per unit type
- Set anchor transition duration to 0 for instant camera jumps

---

*Created by [SuperKitowiec](https://www.youtube.com/@superkitowiec2) for the Beyond All Reason community*