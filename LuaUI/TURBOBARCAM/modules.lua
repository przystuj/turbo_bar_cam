-- Type definitions for TURBOBARCAM modules
-- This file centralizes all type annotations for easier imports

---@class CoreModules
---@field WidgetControl WidgetControl
---@field UpdateManager UpdateManager
---@field SelectionManager SelectionManager

---@class FeatureModules
---@field FPSCamera FPSCamera
---@field UnitTrackingCamera UnitTrackingCamera
---@field OrbitingCamera OrbitingCamera
---@field CameraAnchor CameraAnchor
---@field SpecGroups SpecGroups
---@field TurboOverviewCamera TurboOverviewCamera
---@field GroupTrackingCamera GroupTrackingCamera

---@class WidgetContext
---@field WidgetState WidgetStateModule
---@field WidgetConfig WidgetConfigModule

---@class CommonModules
---@field CameraCommons CameraCommons
---@field Util UtilsModule
---@field Tracking TrackingManager

---@class AllModules
---@field Core CoreModules
---@field Common CommonModules
---@field Features FeatureModules
---@field Context WidgetContext
