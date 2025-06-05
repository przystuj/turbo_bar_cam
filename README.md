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
- `[mode]` is the camera mode (fps, orbit, tracking_camera, etc.)
- `[action]` is `add`, `set`, or `reset`
- `[param]` is the parameter name
- `[value]` is the amount to change or the value to set
