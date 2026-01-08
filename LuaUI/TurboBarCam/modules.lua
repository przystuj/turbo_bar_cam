---@class SimpleModuleAliases
---@field Actions fun(hook: fun(module: Actions)):Actions
---@field CameraAnchor fun(hook: fun(module: CameraAnchor)):CameraAnchor
---@field CameraAnchorPersistence fun(hook: fun(module: CameraAnchorPersistence)):CameraAnchorPersistence
---@field CameraAnchorVisualization fun(hook: fun(module: CameraAnchorVisualization)):CameraAnchorVisualization
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
---@field UnitFollowPersistence fun(hook: fun(module: UnitFollowPersistence)):UnitFollowPersistence
---@field UnitFollowTargeting fun(hook: fun(module: UnitFollowTargeting)):UnitFollowTargeting
---@field GroupTrackingCamera fun(hook: fun(module: GroupTrackingCamera)):GroupTrackingCamera
---@field GroupTrackingUtils fun(hook: fun(module: GroupTrackingUtils)):GroupTrackingUtils
---@field ModeManager fun(hook: fun(module: ModeManager)):ModeManager
---@field MouseManager fun(hook: fun(module: MouseManager)):MouseManager
---@field OrbitCameraUtils fun(hook: fun(module: OrbitCameraUtils)):OrbitCameraUtils
---@field OrbitingCamera fun(hook: fun(module: OrbitingCamera)):OrbitingCamera
---@field OrbitPersistence fun(hook: fun(module: OrbitPersistence)):OrbitPersistence
---@field PersistentStorage fun(hook: fun(module: PersistentStorage)):PersistentStorage
---@field ProjectileCamera fun(hook: fun(module: ProjectileCamera)):ProjectileCamera
---@field ProjectileCameraPersistence fun(hook: fun(module: ProjectileCameraPersistence)):ProjectileCameraPersistence
---@field ProjectileCameraUtils fun(hook: fun(module: ProjectileCameraUtils)):ProjectileCameraUtils
---@field ProjectileTracker fun(hook: fun(module: ProjectileTracker)):ProjectileTracker
---@field SelectionManager fun(hook: fun(module: SelectionManager)):SelectionManager
---@field Scheduler fun(hook: fun(module: Scheduler)):Scheduler
---@field SettingsManager fun(hook: fun(module: SettingsManager)):SettingsManager
---@field SpecGroups fun(hook: fun(module: SpecGroups)):SpecGroups
---@field STATE fun(hook: fun(module: WidgetState)):WidgetState
---@field CONSTANTS fun(hook: fun(module: Constants)):Constants
---@field UnitTrackingCamera fun(hook: fun(module: UnitTrackingCamera)):UnitTrackingCamera
---@field UpdateManager fun(hook: fun(module: UpdateManager)):UpdateManager
---@field WidgetManager fun(hook: fun(module: WidgetManager)):WidgetManager
---@field QuaternionUtils fun(hook: fun(module: QuaternionUtils)):QuaternionUtils
---@field CameraStateTracker fun(hook: fun(module: CameraStateTracker )):CameraStateTracker
---@field CameraDriver fun(hook: fun(module: CameraDriver)):CameraDriver
---@field DebugUtils fun(hook: fun(module: DebugUtils)):DebugUtils
---@field MathUtils fun(hook: fun(module: MathUtils)):MathUtils
---@field ParamUtils fun(hook: fun(module: ParamUtils)):ParamUtils
---@field TableUtils fun(hook: fun(module: TableUtils)):TableUtils
---@field Utils fun(hook: fun(module: Utils)):Utils
---@field WorldUtils fun(hook: fun(module: WorldUtils)):WorldUtils
---@field CameraTestRunner fun(hook: fun(module: CameraTestRunner)):CameraTestRunner

---@class ModuleAliases : SimpleModuleAliases
---@field Log fun(hook: fun(module: LoggerInstance), prefix: string|nil):Log

---@class SimpleModules
local SimpleModules = {
    Actions = "actions.lua",

    CameraCommons = "common/camera_commons.lua",
    ModeManager = "common/mode_manager.lua",
    EasingFunctions = "common/easing_functions.lua",

    CONFIG = "context/config.lua",
    STATE = "context/state.lua",
    CONSTANTS = "context/constants.lua",

    SelectionManager = "core/selection_manager.lua",
    SettingsManager = "core/settings_manager.lua",
    UpdateManager = "core/update_manager.lua",
    WidgetManager = "core/widget_manager.lua",

    CameraDriver = "driver/camera_driver.lua",
    MathUtils = "driver/math_utils.lua",
    CameraStateTracker = "driver/camera_state_tracker.lua",
    QuaternionUtils = "driver/quaternion_utils.lua",

    CameraAnchor = "features/anchor/anchor.lua",
    CameraAnchorPersistence = "features/anchor/anchor_persistence.lua",
    CameraAnchorVisualization = "features/anchor/anchor_visualization.lua",
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
    UnitFollowTargeting = "features/unit_follow/unit_follow_targeting.lua",
    UnitFollowPersistence = "features/unit_follow/unit_follow_persistence.lua",
    GroupTrackingCamera = "features/group_tracking/group_tracking.lua",
    OrbitCameraUtils = "features/orbit/orbit_utils.lua",
    OrbitingCamera = "features/orbit/orbit.lua",
    OrbitPersistence = "features/orbit/orbit_persistence.lua",
    ProjectileCamera = "features/projectile_camera/projectile_camera.lua",
    ProjectileCameraPersistence = "features/projectile_camera/projectile_camera_persistence.lua",
    ProjectileCameraUtils = "features/projectile_camera/projectile_camera_utils.lua",
    SpecGroups = "features/spec_groups/spec_groups.lua",
    GroupTrackingUtils = "features/group_tracking/group_tracking_utils.lua",
    UnitTrackingCamera = "features/unit_tracking/unit_tracking.lua",

    PersistentStorage = "settings/persistent_storage.lua",

    CameraQuickControls = "standalone/camera_quick_controls.lua",
    CameraTracker = "standalone/camera_tracker.lua",
    MouseManager = "standalone/mouse_manager.lua",
    ProjectileTracker = "standalone/projectile_tracker.lua",
    Scheduler = "standalone/scheduler.lua",

    DebugUtils = "utils/debug_utils.lua",
    ParamUtils = "utils/param_utils.lua",
    TableUtils = "utils/table_utils.lua",
    Utils = "utils/utils.lua",
    WorldUtils = "utils/world_utils.lua",

    CameraTestRunner = "test/camera_test_runner.lua",
}

---@class ParametrisedModuleConfig
---@field path string The path to the module file.
---@field configure fun(baseModule: any, data: any):any A function that takes the base module and the data provided at call-site, and returns the configured module.

---@class ParametrisedModules
local ParametrisedModules = {
    ---@type ParametrisedModuleConfig
    Log = {
        path = "common/log.lua",
        configure = function(m, prefix)
            ---@type LoggerInstance
            local loggerInstance = m
            -- If data with a prefix is provided, return a new prefixed logger.
            if prefix then
                return loggerInstance:appendPrefix(prefix)
            end
            -- Otherwise, return the base logger unchanged.
            return loggerInstance
        end
    },
}

---@class Modules
local Modules = {
    SimpleModules = SimpleModules,
    ParametrisedModules = ParametrisedModules
}
return Modules
