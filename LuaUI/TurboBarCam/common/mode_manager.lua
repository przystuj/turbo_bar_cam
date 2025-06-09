---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local TableUtils = ModuleManager.TableUtils(function(m) TableUtils = m end)
local WorldUtils = ModuleManager.WorldUtils(function(m) WorldUtils = m end)
local SettingsManager = ModuleManager.SettingsManager(function(m) SettingsManager = m end)
local TransitionManager = ModuleManager.TransitionManager(function(m) TransitionManager = m end)
local CameraTracker = ModuleManager.CameraTracker(function(m) CameraTracker = m end)

---@class ModeManager
local ModeManager = {}

--- Resets the isModeInitialized flag for a given feature's state.
--- Assumes feature state is under STATE.active.mode.<modeNameKey>
---@param modeNameKey string The key for the mode (e.g., "unit_follow", "unit_tracking", "overview")
local function resetFeatureInitializationFlag(modeNameKey)
    if modeNameKey and STATE.active.mode[modeNameKey] then
        local featureState = STATE.active.mode[modeNameKey]
        if featureState.isModeInitialized ~= nil then
            -- Check if the flag exists
            featureState.isModeInitialized = false
            Log:trace("ModeManager: Reset isModeInitialized for mode: " .. modeNameKey)
        end
    end
end

--- Initializes a new mode or target.
---@param newModeName string Name of the mode to initialize (e.g., 'unit_follow', 'unit_tracking')
---@param target any The target to track (unitID number or point table {x,y,z})
---@param targetTypeString string|nil Target type string (e.g., "UNIT", "POINT")
---@param automaticMode boolean|nil True if this is an automatic transition
---@param optionalTargetCameraState table|nil Optional camera state for the feature to transition towards.
---@return boolean success Whether the mode was set up successfully.
function ModeManager.initializeMode(newModeName, target, targetTypeString, automaticMode, optionalTargetCameraState)
    if Utils.isTurboBarCamDisabled() then
        return false
    end

    local validTarget, finalValidType
    if targetTypeString then
        validTarget = target
        finalValidType = targetTypeString -- Assuming targetTypeString is one of STATE.TARGET_TYPES
    else
        validTarget, finalValidType = WorldUtils.validateTarget(target) -- validateTarget returns type from STATE.TARGET_TYPES
    end

    if finalValidType == STATE.TARGET_TYPES.NONE then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            validTarget = selectedUnits[1]
            finalValidType = STATE.TARGET_TYPES.UNIT
        else
            Log:warn("ModeManager: No valid target for initializeMode: " .. newModeName)
            return false
        end
    end

    local allowReinit = optionalTargetCameraState ~= nil

    if STATE.active.mode.name == newModeName and finalValidType == STATE.TARGET_TYPES.UNIT and
            finalValidType == STATE.active.mode.targetType and validTarget == STATE.active.mode.unitID and
            not allowReinit and not TransitionManager.isTransitioning() then
        SettingsManager.saveModeSettings(newModeName, STATE.active.mode.unitID)
        ModeManager.disableMode()
        Log:trace("ModeManager: Toggled off mode " .. newModeName .. " for unit " .. validTarget)
        return false
    end

    if STATE.active.mode.name ~= newModeName and not automaticMode then
        ModeManager.disableMode()
    else
        if STATE.active.mode.name then
            resetFeatureInitializationFlag(STATE.active.mode.name)
        end
    end

    Log:debug("ModeManager: Initializing mode: " .. newModeName)
    STATE.active.mode.name = newModeName
    STATE.active.mode.targetType = finalValidType

    STATE.active.mode.initialCameraStateForModeEntry = Spring.GetCameraState()
    STATE.active.mode.optionalTargetCameraStateForModeEntry = optionalTargetCameraState

    if finalValidType == STATE.TARGET_TYPES.UNIT then
        STATE.active.mode.unitID = validTarget
        local x, y, z = Spring.GetUnitPosition(validTarget)
        STATE.active.mode.targetPoint = { x = x, y = y, z = z }
        STATE.active.mode.lastTargetPoint = { x = x, y = y, z = z }
        SettingsManager.loadModeSettings(newModeName, validTarget)
    else
        -- STATE.TARGET_TYPES.POINT
        STATE.active.mode.targetPoint = validTarget
        STATE.active.mode.lastTargetPoint = TableUtils.deepCopy(validTarget)
        STATE.active.mode.unitID = nil
        SettingsManager.loadModeSettings(newModeName, validTarget)
    end

    resetFeatureInitializationFlag(newModeName)

    CameraTracker.updateLastKnownCameraState(Spring.GetCameraState())
    Spring.SelectUnitArray(Spring.GetSelectedUnits())
    return true
end

--- Disables active camera mode and resets relevant state.
function ModeManager.disableMode()
    if STATE.active.mode.name then
        Log:debug("ModeManager: Disabling mode: " .. (STATE.active.mode.name or "None"))
    end
    TransitionManager.stopAll()

    if STATE.active.mode.name then
        if STATE.active.mode.targetType == STATE.TARGET_TYPES.UNIT then
            SettingsManager.saveModeSettings(STATE.active.mode.name, STATE.active.mode.unitID)
        elseif STATE.active.mode.targetType == STATE.TARGET_TYPES.POINT then
            SettingsManager.saveModeSettings(STATE.active.mode.name, "point")
        end
    end

    -- Reset modes to default state
    Utils.syncTable(STATE.active, STATE.DEFAULT.active)
end

return ModeManager