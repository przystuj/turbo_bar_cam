-- Main module file that imports and exposes all camera modes
-- This file serves as the interface for all camera modules

-- Import all mode modules
---@type {WidgetControl: WidgetControl}
local WidgetControlModule = VFS.Include("LuaUI/TURBOBARCAM/modes/camera_turbobarcam_widget_control.lua")
---@type {CameraTransition: CameraTransition}
local CameraTransitionModule = VFS.Include("LuaUI/TURBOBARCAM/modes/camera_turbobarcam_transition.lua")
---@type {FPSCamera: FPSCamera}
local FPSCameraModule = VFS.Include("LuaUI/TURBOBARCAM/modes/camera_turbobarcam_fps.lua")
---@type {TrackingCamera: TrackingCamera}
local TrackingCameraModule = VFS.Include("LuaUI/TURBOBARCAM/modes/camera_turbobarcam_tracking.lua")
---@type {OrbitingCamera: OrbitingCamera}
local OrbitingCameraModule = VFS.Include("LuaUI/TURBOBARCAM/modes/camera_turbobarcam_orbiting.lua")
---@type {CameraAnchor: CameraAnchor}
local CameraAnchorModule = VFS.Include("LuaUI/TURBOBARCAM/modes/camera_turbobarcam_anchor.lua")
---@type {SpecGroups: SpecGroups}
local SpecGroupsModule = VFS.Include("LuaUI/TURBOBARCAM/modes/camera_turbobarcam_spec_groups.lua")
---@type {TurboOverviewCamera: TurboOverviewCamera}
local TurboOverviewCameraModule = VFS.Include("LuaUI/TURBOBARCAM/modes/camera_turbobarcam_overview.lua")

-- Export all camera mode modules
return {
    WidgetControl = WidgetControlModule.WidgetControl,
    CameraTransition = CameraTransitionModule.CameraTransition,
    FPSCamera = FPSCameraModule.FPSCamera,
    TrackingCamera = TrackingCameraModule.TrackingCamera,
    OrbitingCamera = OrbitingCameraModule.OrbitingCamera,
    CameraAnchor = CameraAnchorModule.CameraAnchor,
    SpecGroups = SpecGroupsModule.SpecGroups,
    TurboOverviewCamera = TurboOverviewCameraModule.TurboOverviewCamera,
}
