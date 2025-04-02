-- Type definitions for TURBOBARCAM modules
-- This file centralizes all type annotations for easier imports

---@class CoreModules
---@field Commons CameraCommons
---@field Util Util
---@field Movement CameraMovement
---@field Transition CameraTransition
---@field FreeCam FreeCam
---@field Tracking TrackingManager
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

---@class ConfigModule
---@field Config {CONFIG: CONFIG, STATE: STATE}

---@class AllModules
---@field Core CoreModules
---@field Features FeatureModules
---@field ConfigModule

return {}