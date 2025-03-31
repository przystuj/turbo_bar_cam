-- Main module file that imports and exposes all camera modes
-- This file serves as the interface for all camera modules

-- Import all mode modules
---@type {WidgetControl: WidgetControl}
local WidgetControlModule = VFS.Include("LuaUI/Widgets/TURBOBARCAM/modes/widget_control.lua")
---@type {CameraTransition: CameraTransition}
local CameraTransitionModule = VFS.Include("LuaUI/Widgets/TURBOBARCAM/modes/camera_transition.lua")
---@type {FPSCamera: FPSCamera}
local FPSCameraModule = VFS.Include("LuaUI/Widgets/TURBOBARCAM/modes/fps_camera.lua")
---@type {TrackingCamera: TrackingCamera}
local TrackingCameraModule = VFS.Include("LuaUI/Widgets/TURBOBARCAM/modes/tracking_camera.lua")
---@type {OrbitingCamera: OrbitingCamera}
local OrbitingCameraModule = VFS.Include("LuaUI/Widgets/TURBOBARCAM/modes/orbiting_camera.lua")
---@type {CameraAnchor: CameraAnchor}
local CameraAnchorModule = VFS.Include("LuaUI/Widgets/TURBOBARCAM/modes/camera_anchor.lua")
---@type {SpecGroups: SpecGroups}
local SpecGroupsModule = VFS.Include("LuaUI/Widgets/TURBOBARCAM/modes/spec_groups.lua")

-- Export all camera mode modules
return {
    WidgetControl = WidgetControlModule.WidgetControl,
    CameraTransition = CameraTransitionModule.CameraTransition,
    FPSCamera = FPSCameraModule.FPSCamera,
    TrackingCamera = TrackingCameraModule.TrackingCamera,
    OrbitingCamera = OrbitingCameraModule.OrbitingCamera,
    CameraAnchor = CameraAnchorModule.CameraAnchor,
    SpecGroups = SpecGroupsModule.SpecGroups
}
