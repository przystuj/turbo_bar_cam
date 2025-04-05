-- This file serves as the interface for all camera modules

---@type {FPSCamera: FPSCamera}
local FPSCameraModule = VFS.Include("LuaUI/TURBOBARCAM/features/fps/fps.lua")
---@type {UnitTrackingCamera: UnitTrackingCamera}
local TrackingCameraModule = VFS.Include("LuaUI/TURBOBARCAM/features/unit_tracking/unit_tracking.lua")
---@type {OrbitingCamera: OrbitingCamera}
local OrbitingCameraModule = VFS.Include("LuaUI/TURBOBARCAM/features/orbit/orbit.lua")
---@type {CameraAnchor: CameraAnchor}
local CameraAnchorModule = VFS.Include("LuaUI/TURBOBARCAM/features/anchors/anchors.lua")
---@type {SpecGroups: SpecGroups}
local SpecGroupsModule = VFS.Include("LuaUI/TURBOBARCAM/features/spec_groups/spec_groups.lua")
---@type {TurboOverviewCamera: TurboOverviewCamera}
local TurboOverviewCameraModule = VFS.Include("LuaUI/TURBOBARCAM/features/overview/overview.lua")
---@type {GroupTrackingCamera: GroupTrackingCamera}
local GroupTrackingCameraModule = VFS.Include("LuaUI/TURBOBARCAM/features/group_tracking/group_tracking.lua")

---@return FeatureModules
return {
    FPSCamera = FPSCameraModule.FPSCamera,
    UnitTrackingCamera = TrackingCameraModule.UnitTrackingCamera,
    OrbitingCamera = OrbitingCameraModule.OrbitingCamera,
    CameraAnchor = CameraAnchorModule.CameraAnchor,
    SpecGroups = SpecGroupsModule.SpecGroups,
    TurboOverviewCamera = TurboOverviewCameraModule.TurboOverviewCamera,
    GroupTrackingCamera = GroupTrackingCameraModule.GroupTrackingCamera,
}