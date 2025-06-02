---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua")
---@type Util
local Util = VFS.Include("LuaUI/TurboBarCam/common/utils.lua")
---@type SettingsManager
local SettingsManager = VFS.Include("LuaUI/TurboBarCam/core/settings_manager.lua")
---@type TransitionManager
local TransitionManager = VFS.Include("LuaUI/TurboBarCam/core/transition_manager.lua")
---@type CameraTracker
local CameraTracker = VFS.Include("LuaUI/TurboBarCam/standalone/camera_tracker.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE

---@class ModeManager
local ModeManager = {}

--- Resets the isModeInitialized flag for a given feature's state.
--- Assumes feature state is under STATE.mode.<modeNameKey>
---@param modeNameKey string The key for the mode (e.g., "fps", "unit_tracking", "overview")
local function resetFeatureInitializationFlag(modeNameKey)
    if modeNameKey and STATE.mode[modeNameKey] then
        local featureState = STATE.mode[modeNameKey]
        if featureState.isModeInitialized ~= nil then
            -- Check if the flag exists
            featureState.isModeInitialized = false
            Log.trace("ModeManager: Reset isModeInitialized for mode: " .. modeNameKey)
        end
    end
end

--- Initializes a new mode or target.
---@param newModeName string Name of the mode to initialize (e.g., 'fps', 'unit_tracking')
---@param target any The target to track (unitID number or point table {x,y,z})
---@param targetTypeString string|nil Target type string (e.g., "UNIT", "POINT")
---@param automaticMode boolean|nil True if this is an automatic transition
---@param optionalTargetCameraState table|nil Optional camera state for the feature to transition towards.
---@return boolean success Whether the mode was set up successfully.
function ModeManager.initializeMode(newModeName, target, targetTypeString, automaticMode, optionalTargetCameraState)
    if Util.isTurboBarCamDisabled() then
        return false
    end

    local validTarget, finalValidType
    if targetTypeString then
        validTarget = target
        finalValidType = targetTypeString -- Assuming targetTypeString is one of STATE.TARGET_TYPES
    else
        validTarget, finalValidType = Util.validateTarget(target) -- validateTarget returns type from STATE.TARGET_TYPES
    end

    if finalValidType == STATE.TARGET_TYPES.NONE then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            validTarget = selectedUnits[1]
            finalValidType = STATE.TARGET_TYPES.UNIT
        else
            Log.warn("ModeManager: No valid target for initializeMode: " .. newModeName)
            return false
        end
    end

    local allowReinit = optionalTargetCameraState ~= nil

    if STATE.mode.name == newModeName and finalValidType == STATE.TARGET_TYPES.UNIT and
            finalValidType == STATE.mode.targetType and validTarget == STATE.mode.unitID and
            not allowReinit and not TransitionManager.isTransitioning() then
        SettingsManager.saveModeSettings(newModeName, STATE.mode.unitID)
        ModeManager.disableMode()
        Log.trace("ModeManager: Toggled off mode " .. newModeName .. " for unit " .. validTarget)
        return false
    end

    if STATE.mode.name ~= newModeName and not automaticMode then
        ModeManager.disableMode()
    else
        if STATE.mode.name then
            resetFeatureInitializationFlag(STATE.mode.name)
        end
    end

    Log.debug("ModeManager: Initializing mode: " .. newModeName)
    STATE.mode.name = newModeName
    STATE.mode.targetType = finalValidType

    STATE.mode.initialCameraStateForModeEntry = Spring.GetCameraState()
    STATE.mode.optionalTargetCameraStateForModeEntry = optionalTargetCameraState

    if finalValidType == STATE.TARGET_TYPES.UNIT then
        STATE.mode.unitID = validTarget
        local x, y, z = Spring.GetUnitPosition(validTarget)
        STATE.mode.targetPoint = { x = x, y = y, z = z }
        STATE.mode.lastTargetPoint = { x = x, y = y, z = z }
        SettingsManager.loadModeSettings(newModeName, validTarget)
    else
        -- STATE.TARGET_TYPES.POINT
        STATE.mode.targetPoint = validTarget
        STATE.mode.lastTargetPoint = Util.deepCopy(validTarget)
        STATE.mode.unitID = nil
        SettingsManager.loadModeSettings(newModeName, "point")
    end

    resetFeatureInitializationFlag(newModeName)

    CameraTracker.updateLastKnownCameraState(Spring.GetCameraState())
    Spring.SelectUnitArray(Spring.GetSelectedUnits())
    return true
end

--- Disables active camera mode and resets relevant state.
function ModeManager.disableMode()
    if STATE.mode.name then
        Log.debug("ModeManager: Disabling active mode: " .. (STATE.mode.name or "None"))
    end
    TransitionManager.stopAll()

    if STATE.mode.name then
        if STATE.mode.targetType == STATE.TARGET_TYPES.UNIT then
            SettingsManager.saveModeSettings(STATE.mode.name, STATE.mode.unitID)
        elseif STATE.mode.targetType == STATE.TARGET_TYPES.POINT then
            SettingsManager.saveModeSettings(STATE.mode.name, "point")
        end
    end

    STATE.mode.name = nil
    STATE.mode.targetType = STATE.TARGET_TYPES.NONE
    STATE.mode.unitID = nil
    STATE.mode.targetPoint = nil
    STATE.mode.lastTargetPoint = nil

    STATE.mode.initialCameraStateForModeEntry = nil
    STATE.mode.optionalTargetCameraStateForModeEntry = nil

    -- Legacy transition flags (being phased out)
    STATE.mode.isModeTransitionInProgress = false
    STATE.mode.transitionProgress = nil

    -- Reset modes to default state
    STATE.mode = Util.deepCopy(STATE.DEFAULT.mode)

    -- Old anchor queue and transition state (assuming these are top-level in STATE)
    if STATE.anchorQueue then
        STATE.anchorQueue.active = false
    end
    if STATE.transition then
        STATE.transition.active = false
    end -- Old anchor system

    -- DollyCam (assuming top-level in STATE)
    STATE.dollyCam = { route = { points = {} }, isNavigating = false }
end

return ModeManager