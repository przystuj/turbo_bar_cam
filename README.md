# TurboBarCam - Tactical Ultra-Responsive Brilliant Optics for BAR Camera

An advanced camera control suite for Beyond All Reason, featuring smooth transitions, unit tracking, FPS mode, orbital view, spectator controls, and more.

## Overview

TurboBarCam provides a comprehensive camera control system with multiple specialized modes for both players and spectators. It enables fluid camera movements, unit-centered views, and cinematic transitions between saved camera positions.

## Features

- **Camera Anchors**: Save and recall camera positions with smooth transitions and chaining
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
| Shift+F1 to F4 | Focus anchor 1-4 |
| Ctrl+Shift+F1 to F4 | Focus and track anchor 1-4 |
| Ctrl+Shift+Numpad -/+ | Adjust anchor duration |
| **Single Unit Tracking** |
| Numpad 3 | Toggle tracking camera |
| Numpad 8/5 | Adjust height (+/-) |
| Ctrl+Numpad 3 | Reset tracking parameters |
| **Orbit Camera** |
| Numpad 2 | Toggle orbiting camera |
| Numpad 5/8 | Adjust height and distance |
| Numpad 4/6 | Adjust height only |
| Numpad 7/9 | Adjust orbit speed |
| **FPS Camera** |
| Numpad 1 | Toggle FPS camera |
| Numpad 8/5 | Move forward/backward |
| Numpad 4/6 | Move left/right |
| Numpad 7/9 | Adjust height |
| Ctrl+Numpad 7/9 | Rotate camera |
| Numpad * | Clear fixed look point |
| Numpad / | Set fixed look point |
| End | Toggle combat mode |
| PageDown | Next weapon |
| Ctrl+PageDown | Clear weapon selection |
| Ctrl+Numpad 1 | Reset FPS parameters |
| **Overview Camera** |
| PageUp | Toggle overview |
| Numpad 8/5 | Change zoom level |
| **Group Tracking** |
| Numpad 0 | Toggle group tracking |
| Numpad 5/8 | Adjust distance |
| Ctrl+Numpad 8/5 | Adjust height |
| Numpad 4/6 | Adjust orbit offset |
| Numpad 7/9 | Adjust smoothing |
| Ctrl+Numpad 0 | Reset group tracking |
| **Projectile Camera** |
| Delete | Follow projectile (moving camera) |
| Insert | Track projectile (static camera) |
| Numpad 8/5 | Adjust distance |
| Numpad 7/9 | Adjust look ahead |
| Numpad 4/6 | Adjust height |

### Unbound Actions

The following actions are available but not bound to keys by default:

1. **General**
    - `turbobarcam_debug` - Toggle debug level

2. **FPS Camera**
    - `turbobarcam_fps_toggle_free_cam` - Toggle free camera mode in FPS view

3. **Anchor Queue System**
    - `turbobarcam_anchor_queue_set` - Set a new camera queue
    - `turbobarcam_anchor_queue_add` - Add to existing camera queue
    - `turbobarcam_anchor_queue_reset` - Clear camera queue
    - `turbobarcam_anchor_queue_start` - Start camera queue playback
    - `turbobarcam_anchor_save` - Save camera queue to file
    - `turbobarcam_anchor_load` - Load camera queue from file
    - `turbobarcam_anchor_queue_debug` - Print debug info for current queue
    - `turbobarcam_anchor_queue_speed` - Adjust queue time curve
    - `turbobarcam_anchor_queue_stop` - Stop camera queue playback

4. **Overview Camera**
    - `turbobarcam_overview_move_camera` - Move overview camera to target

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

**FPS Camera**
- PEACE.HEIGHT/FORWARD/SIDE/ROTATION: Normal view offsets
- COMBAT.HEIGHT/FORWARD/SIDE/ROTATION: Combat mode offsets
- WEAPON.HEIGHT/FORWARD/SIDE/ROTATION: Active firing offsets
- MOUSE_SENSITIVITY: Mouse look sensitivity

**Orbit Camera**
- HEIGHT: Camera height
- DISTANCE: Orbit radius
- SPEED: Rotation speed (-0.005 to 0.005)

**Unit Tracking**
- HEIGHT: Look-at height offset (-2000 to 2000)

**Group Tracking**
- EXTRA_DISTANCE: Additional distance (-1000 to 3000)
- EXTRA_HEIGHT: Additional height (-1000 to 3000)
- ORBIT_OFFSET: Angle offset (-3.14 to 3.14 rad)
- SMOOTHING.POSITION/ROTATION: Camera smoothing
- SMOOTHING.STABLE_POSITION/ROTATION: Stability smoothing

**Anchor**
- DURATION: Transition time

**Projectile Camera**
- DISTANCE: Camera distance (0 to 1000)
- HEIGHT: Camera height (-1000 to 1000)
- LOOK_AHEAD: Forward tracking distance (0 to 1000)

Examples:
```
/turbobarcam_fps_adjust_params add;PEACE.HEIGHT,10;PEACE.FORWARD,-20
/turbobarcam_orbit_adjust_params add;SPEED,0.0002
/turbobarcam_group_tracking_adjust_params set;SMOOTHING.POSITION,0.05
/turbobarcam_fps_adjust_params reset
```

# Camera Queue Quick Guide

## Save Camera Positions
- `/turbobarcam_anchor_set 1` - Save current camera position as anchor 1
- `/turbobarcam_anchor_set 2` - Save another position as anchor 2
- Continue with anchors 3-9 as needed

## Create Camera Path
Use queue notation: `anchor_id,transition_time;anchor_id,transition_time;anchor_id`

Example: `/turbobarcam_anchor_queue_set 1,3;2,5;3`
- Start at anchor 1
- Move to anchor 2 in 3 seconds
- Move to anchor 3 in 5 seconds

## Queue Controls
- `/turbobarcam_anchor_queue_start` - Start camera movement
- `/turbobarcam_anchor_queue_stop` - Stop movement
- `/turbobarcam_anchor_queue_speed dramatic` - Apply speed profile
- `/turbobarcam_anchor_queue_reset` - Clear the queue

## Save/Load to File (saved per map)
- `/turbobarcam_anchor_save mypath` - Save queue
- `/turbobarcam_anchor_load mypath` - Load queue
- `/turbobarcam_anchor_queue_start mypath dramatic` - Load, override profile, and start

## Build Queue Incrementally
```
/turbobarcam_anchor_queue_reset
/turbobarcam_anchor_queue_add 1,3
/turbobarcam_anchor_queue_add 2,5
/turbobarcam_anchor_queue_add 3
```

---

*Created by [SuperKitowiec](https://www.youtube.com/@superkitowiec2) for the Beyond All Reason community*