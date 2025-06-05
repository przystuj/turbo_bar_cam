---@class ModuleAliases
---@field Actions fun(hook: fun(module: Actions)):Actions
---@field CameraAnchor fun(hook: fun(module: CameraAnchor)):CameraAnchor
---@field CameraAnchorPersistence fun(hook: fun(module: CameraAnchorPersistence)):CameraAnchorPersistence
---@field CameraAnchorUtils fun(hook: fun(module: CameraAnchorUtils)):CameraAnchorUtils
---@field CameraCommons fun(hook: fun(module: CameraCommons)):CameraCommons
---@field CameraQuickControls fun(hook: fun(module: CameraQuickControls)):CameraQuickControls
---@field CameraTracker fun(hook: fun(module: CameraTracker)):CameraTracker
---@field CONFIG fun(hook: fun(module: WidgetConfig)):WidgetConfig
---@field DBSCAN fun(hook: fun(module: DBSCAN)):DBSCAN
---@field DollyCam fun(hook: fun(module: DollyCam)):DollyCam
---@field DollyCamDataStructures fun(hook: fun(module: DollyCamDataStructures)):DollyCamDataStructures
---@field DollyCamEditor fun(hook: fun(module: DollyCamEditor)):DollyCamEditor
---@field DollyCamNavigator fun(hook: fun(module: DollyCamNavigator)):DollyCamNavigator
---@field DollyCamPathPlanner fun(hook: fun(module: DollyCamPathPlanner)):DollyCamPathPlanner
---@field DollyCamVisualization fun(hook: fun(module: DollyCamVisualization)):DollyCamVisualization
---@field DollyCamWaypointEditor fun(hook: fun(module: DollyCamWaypointEditor)):DollyCamWaypointEditor
---@field EasingFunctions fun(hook: fun(module: EasingFunctions)):EasingFunctions
---@field UnitFollowCamera fun(hook: fun(module: UnitFollowCamera)):UnitFollowCamera
---@field UnitFollowUtils fun(hook: fun(module: UnitFollowUtils)):UnitFollowUtils
---@field UnitFollowCombatMode fun(hook: fun(module: UnitFollowCombatMode)):UnitFollowCombatMode
---@field UnitFollowTargetingSmoothing fun(hook: fun(module: UnitFollowTargetingSmoothing)):UnitFollowTargetingSmoothing
---@field UnitFollowTargetingUtils fun(hook: fun(module: UnitFollowTargetingUtils)):UnitFollowTargetingUtils
---@field UnitFollowPersistence fun(hook: fun(module: UnitFollowPersistence)):UnitFollowPersistence
---@field UnitFollowFreeCam fun(hook: fun(module: UnitFollowFreeCam)):UnitFollowFreeCam
---@field GroupTrackingCamera fun(hook: fun(module: GroupTrackingCamera)):GroupTrackingCamera
---@field GroupTrackingUtils fun(hook: fun(module: GroupTrackingUtils)):GroupTrackingUtils
---@field Log fun(hook: fun(module: Log)):Log
---@field ModeManager fun(hook: fun(module: ModeManager)):ModeManager
---@field MouseManager fun(hook: fun(module: MouseManager)):MouseManager
---@field MovementUtils fun(hook: fun(module: MovementUtils)):MovementUtils
---@field OrbitCameraUtils fun(hook: fun(module: OrbitCameraUtils)):OrbitCameraUtils
---@field OrbitingCamera fun(hook: fun(module: OrbitingCamera)):OrbitingCamera
---@field OrbitPersistence fun(hook: fun(module: OrbitPersistence)):OrbitPersistence
---@field OverviewCamera fun(hook: fun(module: OverviewCamera)):OverviewCamera
---@field OverviewCameraUtils fun(hook: fun(module: OverviewCameraUtils)):OverviewCameraUtils
---@field PersistentStorage fun(hook: fun(module: PersistentStorage)):PersistentStorage
---@field ProjectileCamera fun(hook: fun(module: ProjectileCamera)):ProjectileCamera
---@field ProjectileCameraPersistence fun(hook: fun(module: ProjectileCameraPersistence)):ProjectileCameraPersistence
---@field ProjectileCameraUtils fun(hook: fun(module: ProjectileCameraUtils)):ProjectileCameraUtils
---@field ProjectileTracker fun(hook: fun(module: ProjectileTracker)):ProjectileTracker
---@field RotationUtils fun(hook: fun(module: RotationUtils)):RotationUtils
---@field SelectionManager fun(hook: fun(module: SelectionManager)):SelectionManager
---@field Scheduler fun(hook: fun(module: Scheduler)):Scheduler
---@field SettingsManager fun(hook: fun(module: SettingsManager)):SettingsManager
---@field SpecGroups fun(hook: fun(module: SpecGroups)):SpecGroups
---@field STATE fun(hook: fun(module: WidgetState)):WidgetState
---@field TransitionManager fun(hook: fun(module: TransitionManager)):TransitionManager
---@field TransitionUtil fun(hook: fun(module: TransitionUtil)):TransitionUtil
---@field UnitTrackingCamera fun(hook: fun(module: UnitTrackingCamera)):UnitTrackingCamera
---@field UpdateManager fun(hook: fun(module: UpdateManager)):UpdateManager
---@field Util fun(hook: fun(module: Util)):Util
---@field VelocityTracker fun(hook: fun(module: VelocityTracker)):VelocityTracker
---@field WidgetManager fun(hook: fun(module: WidgetManager)):WidgetManager

---@class Modules
local Modules = {
    Actions = "actions.lua",

    CameraCommons = "common/camera_commons.lua",
    CONFIG = "context/config.lua",
    Log = "common/log.lua",
    ModeManager = "common/mode_manager.lua",
    STATE = "context/state.lua",
    Util = "common/utils.lua",
    EasingFunctions = "common/easing_functions.lua",

    SelectionManager = "core/selection_manager.lua",
    SettingsManager = "core/settings_manager.lua",
    TransitionManager = "core/transition_manager.lua",
    UpdateManager = "core/update_manager.lua",
    WidgetManager = "core/widget_manager.lua",

    CameraAnchor = "features/anchor/anchor.lua",
    CameraAnchorPersistence = "features/anchor/anchor_persistence.lua",
    CameraAnchorUtils = "features/anchor/anchor_utils.lua",
    DBSCAN = "features/group_tracking/dbscan.lua",
    DollyCam = "features/dollycam/dollycam.lua",
    DollyCamDataStructures = "features/dollycam/dollycam_data_structures.lua",
    DollyCamEditor = "features/dollycam/dollycam_editor.lua",
    DollyCamNavigator = "features/dollycam/dollycam_navigator.lua",
    DollyCamPathPlanner = "features/dollycam/dollycam_path_planner.lua",
    DollyCamVisualization = "features/dollycam/dollycam_visualization.lua",
    DollyCamWaypointEditor = "features/dollycam/dollycam_waypoint_editor.lua",
    UnitFollowCamera = "features/unit_follow/unit_follow.lua",
    UnitFollowUtils = "features/unit_follow/unit_follow_utils.lua",
    UnitFollowCombatMode = "features/unit_follow/unit_follow_combat_mode.lua",
    UnitFollowTargetingSmoothing = "features/unit_follow/unit_follow_targeting_smoothing.lua",
    UnitFollowTargetingUtils = "features/unit_follow/unit_follow_combat_targeting_utils.lua",
    UnitFollowPersistence = "features/unit_follow/unit_follow_persistence.lua",
    UnitFollowFreeCam = "features/unit_follow/unit_follow_free_camera.lua",
    GroupTrackingCamera = "features/group_tracking/group_tracking.lua",
    MovementUtils = "features/overview/movement_utils.lua",
    OrbitCameraUtils = "features/orbit/orbit_utils.lua",
    OrbitingCamera = "features/orbit/orbit.lua",
    OrbitPersistence = "features/orbit/orbit_persistence.lua",
    OverviewCamera = "features/overview/overview.lua",
    OverviewCameraUtils = "features/overview/overview_utils.lua",
    ProjectileCamera = "features/projectile_camera/projectile_camera.lua",
    ProjectileCameraPersistence = "features/projectile_camera/projectile_camera_persistence.lua",
    ProjectileCameraUtils = "features/projectile_camera/projectile_camera_utils.lua",
    RotationUtils = "features/overview/rotation_utils.lua",
    SpecGroups = "features/spec_groups/spec_groups.lua",
    GroupTrackingUtils = "features/group_tracking/group_tracking_utils.lua",
    UnitTrackingCamera = "features/unit_tracking/unit_tracking.lua",

    PersistentStorage = "settings/persistent_storage.lua",

    CameraQuickControls = "standalone/camera_quick_controls.lua",
    CameraTracker = "standalone/camera_tracker.lua",
    MouseManager = "standalone/mouse_manager.lua",
    ProjectileTracker = "standalone/projectile_tracker.lua",
    Scheduler = "standalone/scheduler.lua",
    TransitionUtil = "standalone/transition_util.lua",
    VelocityTracker = "standalone/velocity_tracker.lua",
}
return Modules