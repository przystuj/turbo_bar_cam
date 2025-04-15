---@type {FPSCamera: FPSCamera}
local FPSCameraModule = VFS.Include("LuaUI/TurboBarCam/features/fps/fps.lua")
---@type {UnitTrackingCamera: UnitTrackingCamera}
local TrackingCameraModule = VFS.Include("LuaUI/TurboBarCam/features/unit_tracking/unit_tracking.lua")
---@type {OrbitingCamera: OrbitingCamera}
local OrbitingCameraModule = VFS.Include("LuaUI/TurboBarCam/features/orbit/orbit.lua")
---@type {CameraAnchor: CameraAnchor}
local CameraAnchorModule = VFS.Include("LuaUI/TurboBarCam/features/anchors/anchor.lua")
---@type {SpecGroups: SpecGroups}
local SpecGroupsModule = VFS.Include("LuaUI/TurboBarCam/features/spec_groups/spec_groups.lua")
---@type {TurboOverviewCamera: TurboOverviewCamera}
local TurboOverviewCameraModule = VFS.Include("LuaUI/TurboBarCam/features/overview/overview.lua")
---@type {GroupTrackingCamera: GroupTrackingCamera}
local GroupTrackingCameraModule = VFS.Include("LuaUI/TurboBarCam/features/group_tracking/group_tracking.lua")
---@type {ProjectileCamera: ProjectileCamera}
local ProjectileCameraModule = VFS.Include("LuaUI/TurboBarCam/features/projectile_camera/projectile_camera.lua")

---@return FeatureModules
return {
    FPSCamera = FPSCameraModule.FPSCamera,
    UnitTrackingCamera = TrackingCameraModule.UnitTrackingCamera,
    OrbitingCamera = OrbitingCameraModule.OrbitingCamera,
    CameraAnchor = CameraAnchorModule.CameraAnchor,
    SpecGroups = SpecGroupsModule.SpecGroups,
    TurboOverviewCamera = TurboOverviewCameraModule.TurboOverviewCamera,
    GroupTrackingCamera = GroupTrackingCameraModule.GroupTrackingCamera,
    ProjectileCamera = ProjectileCameraModule.ProjectileCamera,
}