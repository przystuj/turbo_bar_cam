-- Main module file that imports and exposes all camera modes
-- This file serves as the interface for all camera modules

-- Import widget control
---@type {WidgetControl: WidgetControl}
local WidgetControlModule = VFS.Include("LuaUI/TURBOBARCAM/core/widget_control.lua")

-- Import transition module
---@type {CameraTransition: CameraTransition}
local CameraTransitionModule = VFS.Include("LuaUI/TURBOBARCAM/core/transition.lua")

-- Import camera feature modules
---@type {FPSCamera: FPSCamera}
local FPSCameraModule = VFS.Include("LuaUI/TURBOBARCAM/features/fps/fps.lua")
---@type {TrackingCamera: TrackingCamera}
local TrackingCameraModule = VFS.Include("LuaUI/TURBOBARCAM/features/tracking/tracking.lua")
---@type {OrbitingCamera: OrbitingCamera}
local OrbitingCameraModule = VFS.Include("LuaUI/TURBOBARCAM/features/orbit/orbit.lua")
---@type {CameraAnchor: CameraAnchor}
local CameraAnchorModule = VFS.Include("LuaUI/TURBOBARCAM/features/anchors/anchors.lua")
-- Uncomment these when implemented
---@type {SpecGroups: SpecGroups}
local SpecGroupsModule = VFS.Include("LuaUI/TURBOBARCAM/features/spec_groups/spec_groups.lua")
---@type {TurboOverviewCamera: TurboOverviewCamera}
local TurboOverviewCameraModule = VFS.Include("LuaUI/TURBOBARCAM/features/overview/overview.lua")

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