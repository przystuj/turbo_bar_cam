-- Type definitions for TURBOBARCAM modules
-- This file centralizes all type annotations for easier imports

---@class CoreModules
---@field Commons CameraCommons
---@field Movement CameraMovement
---@field Transition CameraTransition
---@field FreeCam FreeCam
---@field WidgetControl WidgetControl
---@field SelectionManager SelectionManager
---@field Actions Actions
---@field UpdateManager UpdateManager

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
---@field Util Util
---@field Tracking TrackingManager
---@field ClusterMathUtils ClusterMathUtils
---@field DBSCAN DBSCAN

---@class AllModules
---@field Core CoreModules
---@field Common CommonModules
---@field Features FeatureModules
---@field Context WidgetContext
