-- Type definitions for TURBOBARCAM modules
-- This file centralizes all type annotations for easier imports

---@class CoreModules
---@field CameraCommons CameraCommons
---@field Transition CameraTransition
---@field WidgetControl WidgetControl
---@field Actions Actions
---@field UpdateManager UpdateManager
---@field SelectionManager SelectionManager

---@class FeatureModules
---@field FPSCamera FPSCamera
---@field TrackingCamera TrackingCamera
---@field OrbitingCamera OrbitingCamera
---@field CameraAnchor CameraAnchor
---@field SpecGroups SpecGroups
---@field TurboOverviewCamera TurboOverviewCamera
---@field GroupTrackingCamera GroupTrackingCamera

---@class WidgetContext
---@field WidgetState WidgetStateModule
---@field WidgetConfig WidgetConfigModule

---@class CommonModules
---@field Util UtilsModule
---@field Tracking TrackingManager
---@field ClusterMathUtils ClusterMathUtils
---@field DBSCAN DBSCAN

---@class AllModules
---@field Core CoreModules
---@field Common CommonModules
---@field Features FeatureModules
---@field Context WidgetContext
