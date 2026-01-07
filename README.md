# TurboBarCam - Tactical Ultra-Responsive Brilliant Optics for BAR Camera

An advanced camera control suite for Beyond All Reason, featuring smooth transitions, various unit tracking modes and more.

## Overview

TurboBarCam provides a comprehensive camera control system with multiple specialized modes for both players and spectators. It enables fluid camera movements, unit-centered views, and cinematic transitions between saved camera positions.

## Features

- **Camera Anchors**: Save and recall camera positions with smooth transitions and chaining
- **Follow Camera**: Follow unit maintaining its orientation
- **Tracking Camera**: Track selected units while maintaining your preferred viewing angle
- **Orbiting Camera**: Circle around units with adjustable speed and height
- **Group Tracking Camera**: Track a group of units with automatic clustering
- **Projectile Camera**: Follow projectiles fired from units

## Installation

1. Download `turbobarcam_vX.zip`
2. Extract it in your BAR data folder
3. After extracting, your folder structure should look like:
```
BAR install folder/
└── data/
    └── LuaUI/
        ├── RmlWidgets/
        ├── Widgets/
        └── TurboBarCam/
        └── TurboBarCommons/
```
4. Enable "Tactical Ultra-Responsive Brilliant Optics for BAR Camera" and "TurboBarCam UI" in-game

## Getting Started

By default, TurboBarCam is loaded but disabled. To enable it use the ui or this command:

```
/turbobarcam_toggle
```

## Default Keybindings

To use the [default keybindings](README_KEYBINDS.md), add this line to your `uikeys.txt` file:

```
keyload     luaui/TurboBarCam/turbobarcam.uikeys.txt
```

## Parameter Adjustment System

TurboBarCam includes a system to fine-tune camera behaviors using the following format:

```
turbobarcam_[mode]_adjust_params [action];[param],[value];...
```

Where:
- `[mode]` is the camera mode (unit_follow, orbit, tracking_camera, etc.)
- `[action]` is `add`, `set`, or `reset`
- `[param]` is the parameter name
- `[value]` is the amount to change or the value to set

## Changelog
#### 2.1.0
- Show widget errors in UI
- Global nuke monitoring - you can always track nuke projectile now (turbobarcam_projectile_camera_cycle, turbobarcam_projectile_camera_toggle_mode)
- Added help button in UI
#### 2.2.0
- Fixed group tracking camera
- Anchor sets saved without a name will be saved as default. Default sets are loaded automatically.
- Hide TurboBarCam UI when the game UI is disabled
- Added options to have single-duration anchors
- Added option in UI to disable unit indicators (selection highlight, command lines, etc)
- Added option to move to the next/previous anchor. 
  - turbobarcam_anchor_focus prev
  - turbobarcam_anchor_focus next
#### 2.3.0
- Add an option to reset the camera to the current anchor. If another camera mode is active, move smoothly. Otherwise snap to the anchor.
- UI – Add an option to hide minimap and chat
#### 2.4.0
- Removed Overview mode
- Attack state cooldown per unit type (how long the camera keeps looking at the last target)
  - turbobarcam_unit_follow_adjust_params set;ATTACK_STATE_COOLDOWN,5
