if not RmlUi then
    return
end

local LogBuilder = VFS.Include("LuaUI/TurboBarCommons/logger_prototype.lua") ---@type LogBuilder
local Log ---@type Log

local widget = widget

-- Widget metadata
function widget:GetInfo()
    return {
        name = "TurboBarCam UI",
        desc = "UI for controlling the TurboBarCam camera system",
        author = "SuperKitowiec",
        date = "July 2025",
        license = "GNU GPL, v2 or later",
        layer = 0,
        enabled = true,
        version = 2,
        handler = true,
    }
end

local MODEL_NAME = "turbobarcam_model"
local document
local dm_handle ---@type UIDataModel
local initialized = false
local visible = true
local isLobbyVisible = false

local helpContext
local helpDocument

local function createWidgetEntry(name)
    return {
        name = name,
        isActive = function()
            local w = widgetHandler.knownWidgets[name];
            return (w and w.active) or false
        end,
        toggle = function() widgetHandler:ToggleWidget(name) end
    }
end

local function createOptionEntry(name, label, activeValue)
    activeValue = activeValue or 1
    return {
        name = name,
        label = label,
        isActive = function()
            return Spring.GetConfigInt(name, 0) == activeValue
        end,
        toggle = function()
            local newValue = (Spring.GetConfigInt(name, 0) == 0) and 1 or 0
            Spring.SetConfigInt(name, newValue)
            Spring.SendCommands("option " .. name .. " " .. newValue)
        end
    }
end

local function createValueOptionEntry(name, label, offValue, onValue)
    return {
        name = name,
        label = label,
        isActive = function() return Spring.GetConfigInt(name, offValue) == onValue end,
        toggle = function()
            local currentValue = Spring.GetConfigInt(name, offValue)
            local newValue = (currentValue == onValue) and offValue or onValue
            Spring.SetConfigInt(name, newValue)
            Spring.SendCommands("option " .. name .. " " .. newValue)
        end
    }
end

local recordingModeWidgets = {
    createWidgetEntry("Commands FX"),
    createWidgetEntry("Selected Units GL4"),
    createWidgetEntry("Health Bars GL4"),
    createWidgetEntry("Commander Name Tags"),
    createWidgetEntry("Spectator HUD"),
    createWidgetEntry("Metal Tracker"),
    createWidgetEntry("Order menu"),
    createWidgetEntry("Flanking Icons GL4"),
    createWidgetEntry("Unit Energy Icons"),
    createWidgetEntry("Self-Destruct Icons"),
    createWidgetEntry("Metalspots"),
    createWidgetEntry("Chat"),
    createWidgetEntry("Attack Range GL4"),
    createWidgetEntry("Defense Range GL4"),
    createWidgetEntry("Sensor Ranges Radar"),
    createWidgetEntry("Sensor Ranges LOS"),
    createWidgetEntry("Sensor Ranges Jammer"),
    createWidgetEntry("Sensor Ranges Sonar"),
    createWidgetEntry("Anti Ranges"),
    createWidgetEntry("AllyCursors"),
}

local recordingModeOptions = {
    createOptionEntry("minimap_minimized", "Minimap", 0),
    createOptionEntry("notifications_spoken", "Voice Notifications"),
    createOptionEntry("displaydps", "Show DPS"),
    createValueOptionEntry("uniticon_distance", "Unit Icons", 13000, 1750),
}

---@type WidgetState
local STATE
---@type WidgetConfig
local CONFIG
---@type TurboBarCamAPI
local API

local function deepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = deepCopy(orig_value)
        end
    else
        copy = orig
    end
    return copy
end

local function CallAction(_, action, condition)
    if condition == nil or condition then
        Spring.SendCommands(action)
    end
end

local function SetUnitFollowLookPoint(_)
    if CONFIG and CONFIG.COMMANDS then
        local cmdID = CONFIG.COMMANDS.SET_FIXED_LOOK_POINT
        local cmdDescIndex = Spring.GetCmdDescIndex(cmdID)
        if cmdDescIndex then
            Spring.SetActiveCommand(cmdDescIndex, 1, true, false, Spring.GetModKeyState())
        end
    end
end

local function ClearError()
    STATE.error = nil
end

local function CopyErrorToClipboard()
    Spring.SetClipboard(STATE.error.message .. "\n" .. STATE.error.traceback)
end

local function UpdateNewAnchorSetName(event)
    local params_map = event.parameters
    if params_map and params_map['value'] then
        dm_handle.anchors.newAnchorSetName = params_map['value']
    end
end

local function AdjustParam(_, mode, param_path, sign)
    local path_parts = {}
    for part in string.gmatch(param_path, "[^.]+") do
        table.insert(path_parts, part)
    end

    local adj_value_tbl = dm_handle.adjustments[mode]
    for i = 1, #path_parts do
        adj_value_tbl = adj_value_tbl[path_parts[i]]
    end
    local value = adj_value_tbl

    if sign == '-' then
        value = -value
    end
    local action = string.format("turbobarcam_%s_adjust_params add;%s,%s", mode, param_path, tostring(value))
    Spring.SendCommands(action)
end

local function StartTrackingProjectile(_, projectileId, mode)
    if not projectileId or not mode then
        return
    end
    API.startTrackingProjectile(projectileId, mode)
end

local function ResetParams(_, mode)
    local action = string.format("turbobarcam_%s_adjust_params reset", mode)
    Spring.SendCommands(action)
end

local function ToggleHelp(_)
    if helpDocument then
        -- If the help document exists, close it and clean up
        helpDocument:Close()
        helpDocument = nil
    else
        -- Otherwise, create a new context and load the keybinds document
        helpContext = RmlUi.CreateContext("shared")
        if not helpContext then
            Log:warn("Failed to create RmlUi context for help document.")
            return
        end

        helpDocument = helpContext:LoadDocument("LuaUI/RmlWidgets/gui_turbobarcam/rml/keybinds.rml")
        if not helpDocument then
            Log:warn("Failed to load help document: LuaUI/RmlWidgets/gui_turbobarcam/rml/keybinds.rml")
            helpContext = nil
            return
        end

        local closeButton = helpDocument:GetElementById("help-close-button")
        if closeButton then
            closeButton:AddEventListener('click', ToggleHelp)
        else
            Log:warn("Could not find close button in keybinds.rml")
        end

        helpDocument:Show()
    end
end

local function ToggleDebugInfo(_)
    dm_handle.isDebugFolded = not dm_handle.isDebugFolded
end

local function ToggleNukeTrackingInfo(_)
    dm_handle.isNukeTrackingFolded = not dm_handle.isNukeTrackingFolded
end

local function ToggleAnchorsInfo(_)
    dm_handle.isAnchorsFolded = not dm_handle.isAnchorsFolded
end

local function ToggleSavedAnchorSetsInfo(_)
    dm_handle.isSavedAnchorSetsFolded = not dm_handle.isSavedAnchorSetsFolded
end

local function ToggleRecordingModeInfo(_)
    dm_handle.isRecordingModeFolded = not dm_handle.isRecordingModeFolded
end

local function ToggleRecordingWidget(_, widgetName)
    for i = 1, #recordingModeWidgets do
        if recordingModeWidgets[i].name == widgetName then
            recordingModeWidgets[i].toggle()
            break
        end
    end
end

local function ToggleRecordingOption(_, optionName)
    for i = 1, #recordingModeOptions do
        if recordingModeOptions[i].name == optionName then
            recordingModeOptions[i].toggle()
            break
        end
    end
end

local function ToggleOptionsInfo(_)
    dm_handle.isOptionsFolded = not dm_handle.isOptionsFolded
end

local function ToggleRecordingModeAll(_)
    -- Determine if we should enable or disable all
    -- If any widget or option is active, we disable all.
    -- Otherwise we enable all.
    local anyActive = false
    for i = 1, #recordingModeWidgets do
        if recordingModeWidgets[i].isActive() then
            anyActive = true
            break
        end
    end
    if not anyActive then
        for i = 1, #recordingModeOptions do
            if recordingModeOptions[i].isActive() then
                anyActive = true
                break
            end
        end
    end

    local targetActive = not anyActive

    for i = 1, #recordingModeWidgets do
        if recordingModeWidgets[i].isActive() ~= targetActive then
            recordingModeWidgets[i].toggle()
        end
    end
    for i = 1, #recordingModeOptions do
        if recordingModeOptions[i].isActive() ~= targetActive then
            recordingModeOptions[i].toggle()
        end
    end
end

-- fixme doesnt see the functions from WG
local function LockUnitInfo(_)
    if WG['info'] and WG['info'].setCustomHover then
        Log:info("Lock unit info for ", STATE.active.mode.unitID)
        WG['info'].setCustomHover("unit", STATE.active.mode.unitID)
    end
end

local function UnlockUnitInfo(_)
    if WG['info'] and WG['info'].clearCustomHover then
        Log:info("Unlock unit info")
        WG['info'].clearCustomHover()
    end
end

local function FocusAnchor(_, anchorId)
    if not anchorId then return end
    Spring.SendCommands("turbobarcam_anchor_focus " .. tostring(anchorId))
end

local function SetAnchor(_, anchorId)
    if not anchorId then return end
    Spring.SendCommands("turbobarcam_anchor_set " .. tostring(anchorId))
end

local function DeleteAnchor(_, anchorId)
    if not anchorId then return end
    Spring.SendCommands("turbobarcam_anchor_delete " .. tostring(anchorId))
end

local function ToggleAnchorType(_, anchorId)
    if not anchorId then return end
    Spring.SendCommands("turbobarcam_anchor_toggle_type " .. tostring(anchorId))
end

local function ToggleAnchorVisualization(_)
    Spring.SendCommands("turbobarcam_anchor_toggle_visualization")
end

local function AdjustAnchorDuration(_, anchorId, sign)
    local _, ctrl, _, shift = Spring.GetModKeyState()
    local value = 1
    if shift then value = 5 end
    if ctrl then value = 20 end

    if sign == '-' then
        value = -value
    end

    if STATE.anchor.points[anchorId] and STATE.anchor.points[anchorId].duration then
        STATE.anchor.points[anchorId].duration = math.max(0.1, STATE.anchor.points[anchorId].duration + value)
    end
end

local function LoadAnchorSet(_, setId)
    if not setId then return end
    Spring.SendCommands("turbobarcam_anchor_load " .. setId)
end

local function SaveNewAnchorSet(_)
    local newAnchorSetName = dm_handle.anchors.newAnchorSetName or "default"
    Spring.SendCommands("turbobarcam_anchor_save " .. newAnchorSetName)
    dm_handle.anchors.newAnchorSetName = ""
end

local function SaveExistingAnchorSet(_, setId)
    if not setId then return end
    Spring.SendCommands("turbobarcam_anchor_save " .. setId)
end

local function SetNewAnchorDuration(event)
    local params_map = event.parameters
    if params_map and params_map['value'] then
        local value = tonumber(params_map['value'])
        if value then
            dm_handle.anchors.newAnchorDuration = value
            dm_handle.anchors.newAnchorDurationDisplay = string.format('%.1fs', value)
            local action = string.format("turbobarcam_anchor_adjust_params set;DURATION,%s", tostring(value))
            Spring.SendCommands(action)
        end
    end
end

local function AddNewAnchor(_)
    local maxId = 0
    if STATE.anchor and STATE.anchor.points then
        for id, _ in pairs(STATE.anchor.points) do
            local numId = tonumber(id)
            if numId and numId > maxId then
                maxId = numId
            end
        end
    end
    local newId = tostring(maxId + 1)
    Spring.SendCommands("turbobarcam_anchor_set " .. newId)
end

local function UpdateAllAnchorDurations(_)
    Spring.SendCommands("turbobarcam_anchor_update_all_durations")
end

local function findPlayerNameByTeamID(teamId)
    local name
    local aiName = Spring.GetGameRulesParam('ainame_' .. tostring(teamId))
    if aiName then
        name = aiName
    else
        local players = Spring.GetPlayerList(teamId)
        if players and #players > 0 then
            -- Default to first player name as a fallback
            name = Spring.GetPlayerInfo(players[1])

            for _, pID in ipairs(players) do
                local pname, active, isspec = Spring.GetPlayerInfo(pID)
                if active and not isspec then
                    name = pname
                    break -- Found active player, no need to continue
                end
            end
        end
    end
    return name or '?'
end

---@class UIDataModel
local initDataModel = {
    isTurboBarCamLoaded = false,
    status = "DISABLED",
    currentMode = "None",
    isEnabled = false,
    isNukeTrackingFolded = true,
    isOptionsFolded = true,
    isDebugFolded = true,
    isAnchorsFolded = true,
    isSavedAnchorSetsFolded = true,
    isRecordingModeFolded = true,
    playerCamSelectionActive = true,
    trackingWithoutSelectionActive = false,
    unitIndicatorsActive = false,
    chatAndMinimapHidden = false,
    nuke_tracking = {
        hasProjectiles = false,
        projectiles = {},
    },
    anchors = {
        anchors_list = {},
        activeAnchorId = -1,
        hasAnchors = false,
        visualizationEnabled = false,
        newAnchorSetName = "",
        newAnchorDuration = 10,
        newAnchorDurationDisplay = "10.0s",
        singleDurationMode = false,
    },
    error = { message = "", traceback = "" },
    showError = false,
    showTraceback = false,
    inFixedTargetSelectionMode = false,
    isFixedTargetModeActive = false,
    isWeaponCameraActive = false,
    savedAnchorSets = {},
    hasSavedAnchorSets = false,

    recording_mode = {
        widgets = {},
        options = {},
    },

    availableModes = {
        { id = "unit_follow", name = "Unit Follow", action = "turbobarcam_toggle_unit_follow_camera" },
        { id = "unit_tracking", name = "Unit Tracking", action = "turbobarcam_toggle_tracking_camera" },
        { id = "orbit", name = "Orbit", action = "turbobarcam_orbit_toggle" },
        { id = "group_tracking", name = "Group Tracking", action = "turbobarcam_toggle_group_tracking_camera" },
    },
    -- Parameter adjustment step values
    adjustments = {
        unit_follow = { DEFAULT = { HEIGHT = 5, FORWARD = 5, SIDE = 5, ROTATION = 0.1 } },
        unit_tracking = { HEIGHT = 20 },
        orbit = { DISTANCE = 20, HEIGHT = 20, SPEED = 0.01 },
        group_tracking = { EXTRA_DISTANCE = 15, EXTRA_HEIGHT = 5, ORBIT_OFFSET = 0.01 },
        anchor = { DURATION = 1 },
    },
    -- Pre-formatted strings for display
    display_params = {
        unit_follow = { DEFAULT = { HEIGHT = "0", FORWARD = "0", SIDE = "0" } },
        unit_tracking = { HEIGHT = "0" },
        orbit = { DISTANCE = "0", HEIGHT = "0", SPEED = "0.00" },
        group_tracking = { EXTRA_DISTANCE = "0", EXTRA_HEIGHT = "0", ORBIT_OFFSET = "0.00" },
    },
    -- Debug Info
    debug_log_level = "INFO",
    debug_pos_smooth = "",
    debug_rot_smooth = "",
    debug_velocity = "",
    debug_ang_velocity = "",
    debug_distance = "",
    debug_pos_complete = false,
    debug_rot_complete = false,
    isDriverActive = false,
    -- Simulation Info
    sim_position = "",
    sim_velocity = "",
    sim_orientation = "",
    sim_ang_velocity = "",
    -- Projectile Camera Info
    isProjectileCameraAvailable = false,
    isProjectileCameraActive = false,
    isProjectileCameraArmed = false,
    proj_cam_active = "",
    proj_cam_submode = "",
    proj_cam_prev_mode = "",
    proj_cam_status = "",
    proj_cam_impact_countdown = "",
    proj_cam_projectiles = {},
    proj_cam_projectiles_size = 0,
    proj_cam_track_button_active = false,
    proj_cam_follow_button_active = false,

    isUnitSelected = false,

    -- Event Handlers
    CallAction = CallAction,
    SetUnitFollowLookPoint = SetUnitFollowLookPoint,
    UpdateNewAnchorSetName = UpdateNewAnchorSetName,
    AdjustParam = AdjustParam,
    StartTrackingProjectile = StartTrackingProjectile,
    AdjustAnchorDuration = AdjustAnchorDuration,
    ResetParams = ResetParams,
    ToggleDebugInfo = ToggleDebugInfo,
    ToggleNukeTrackingInfo = ToggleNukeTrackingInfo,
    ToggleAnchorsInfo = ToggleAnchorsInfo,
    ToggleSavedAnchorSetsInfo = ToggleSavedAnchorSetsInfo,
    ToggleRecordingModeInfo = ToggleRecordingModeInfo,
    ToggleRecordingModeAll = ToggleRecordingModeAll,
    ToggleRecordingWidget = ToggleRecordingWidget,
    ToggleRecordingOption = ToggleRecordingOption,
    ToggleAnchorVisualization = ToggleAnchorVisualization,
    ToggleOptionsInfo = ToggleOptionsInfo,
    ToggleAnchorType = ToggleAnchorType,
    FocusAnchor = FocusAnchor,
    SetAnchor = SetAnchor,
    DeleteAnchor = DeleteAnchor,
    LoadAnchorSet = LoadAnchorSet,
    SaveNewAnchorSet = SaveNewAnchorSet,
    SaveExistingAnchorSet = SaveExistingAnchorSet,
    AddNewAnchor = AddNewAnchor,
    SetNewAnchorDuration = SetNewAnchorDuration,
    UpdateAllAnchorDurations = UpdateAllAnchorDurations,
    ClearError = ClearError,
    CopyErrorToClipboard = CopyErrorToClipboard,
    ToggleHelp = ToggleHelp,
    LockUnitInfo = LockUnitInfo,
    UnlockUnitInfo = UnlockUnitInfo,
}

local function getCleanMapName()
    local mapName = Game.mapName

    -- Remove version numbers at the end (patterns like 1.2.3 or V1.2.3)
    local cleanName = mapName:gsub("%s+[vV]?%d+%.?%d*%.?%d*$", "")

    return cleanName
end

-- Update data model with current TurboBarCam state and keybindings
local function updateDataModel()
    if not initialized or not dm_handle then
        return
    end

    if not WG.TurboBarCam then
        dm_handle.isTurboBarCamLoaded = false
        dm_handle.isEnabled = false
        return
    end
    dm_handle.isTurboBarCamLoaded = true

    STATE = WG.TurboBarCam.STATE
    CONFIG = WG.TurboBarCam.CONFIG
    API = WG.TurboBarCam.API

    dm_handle.debug_log_level = CONFIG.DEBUG.LOG_LEVEL

    -- Update status
    dm_handle.isEnabled = STATE.enabled or false
    dm_handle.status = dm_handle.isEnabled and "Enabled" or "Disabled"

    dm_handle.playerCamSelectionActive = STATE.allowPlayerCamUnitSelection or false
    dm_handle.trackingWithoutSelectionActive = CONFIG.ALLOW_TRACKING_WITHOUT_SELECTION or false

    local commandFXWidget = widgetHandler.knownWidgets['Commands FX']
    local selectedUnitsWidget = widgetHandler.knownWidgets['Selected Units GL4']
    local chatWidget = widgetHandler.knownWidgets['Chat']
    dm_handle.unitIndicatorsActive = (commandFXWidget and commandFXWidget.active) and (selectedUnitsWidget and selectedUnitsWidget.active) or false
    dm_handle.chatAndMinimapHidden = (chatWidget and not chatWidget.active) or false

    local widgets = {}
    for i = 1, #recordingModeWidgets do
        local widget = recordingModeWidgets[i]
        widgets[i] = {
            name = widget.name,
            isActive = widget.isActive()
        }
    end
    dm_handle.recording_mode.widgets = widgets

    local options = {}
    for i = 1, #recordingModeOptions do
        local option = recordingModeOptions[i]
        options[i] = {
            name = option.name,
            label = option.label,
            isActive = option.isActive()
        }
    end
    dm_handle.recording_mode.options = options

    -- Update current mode
    local currentMode = STATE.active.mode.name or "None"
    dm_handle.isProjectileCameraActive = STATE.active.mode.name == "projectile_camera"
    dm_handle.isProjectileCameraArmed = STATE.active.mode.projectile_camera.isArmed
    if dm_handle.isProjectileCameraActive then
        currentMode = STATE.active.mode.projectile_camera.previousMode
    end
    dm_handle.currentMode = currentMode

    local dp = dm_handle.display_params
    local cfg = CONFIG.CAMERA_MODES
    dp.unit_follow.DEFAULT.HEIGHT = string.format('%.0f', cfg.UNIT_FOLLOW.OFFSETS.DEFAULT.HEIGHT or 0)
    dp.unit_follow.DEFAULT.FORWARD = string.format('%.0f', cfg.UNIT_FOLLOW.OFFSETS.DEFAULT.FORWARD or 0)
    dp.unit_follow.DEFAULT.SIDE = string.format('%.0f', cfg.UNIT_FOLLOW.OFFSETS.DEFAULT.SIDE or 0)
    dp.orbit.DISTANCE = string.format('%.0f', cfg.ORBIT.OFFSETS.DISTANCE or 0)
    dp.orbit.HEIGHT = string.format('%.0f', cfg.ORBIT.OFFSETS.HEIGHT or 0)
    dp.orbit.SPEED = string.format('%.2f', cfg.ORBIT.OFFSETS.SPEED or 0)
    dp.group_tracking.EXTRA_DISTANCE = string.format('%.0f', cfg.GROUP_TRACKING.EXTRA_DISTANCE or 0)
    dp.group_tracking.EXTRA_HEIGHT = string.format('%.0f', cfg.GROUP_TRACKING.EXTRA_HEIGHT or 0)
    dp.group_tracking.ORBIT_OFFSET = string.format('%.2f', cfg.GROUP_TRACKING.ORBIT_OFFSET or 0)
    dm_handle.isUnitSelected = Spring.GetSelectedUnitsCount() > 0

    -- Update debug info
    local targetSTATE = STATE.core.driver.target
    local smoothingTransSTATE = STATE.core.driver.smoothingTransition
    local jobSTATE = STATE.core.driver.job
    local driverCONFIG = CONFIG.DRIVER

    local isPosTask = targetSTATE.position ~= nil
    local isRotTask = targetSTATE.euler ~= nil

    dm_handle.debug_pos_smooth = string.format("%.2f -> %.2f", smoothingTransSTATE.currentPositionSmoothing or 0, targetSTATE.positionSmoothing or 0)
    dm_handle.debug_rot_smooth = string.format("%.2f -> %.2f", smoothingTransSTATE.currentRotationSmoothing or 0, targetSTATE.rotationSmoothing or 0)

    dm_handle.debug_velocity = isPosTask and string.format("%.2f -> <%.2f", jobSTATE.velocityMagnitude or 0, driverCONFIG.VELOCITY_TARGET) or "N/A"
    dm_handle.debug_distance = isPosTask and string.format("%.2f -> <%.2f", jobSTATE.distance or 0, driverCONFIG.DISTANCE_TARGET) or "N/A"
    dm_handle.debug_ang_velocity = isRotTask and string.format("%.4f -> <%.4f", jobSTATE.angularVelocityMagnitude or 0, driverCONFIG.ANGULAR_VELOCITY_TARGET) or "N/A"

    dm_handle.debug_pos_complete = jobSTATE.isPositionComplete
    dm_handle.debug_rot_complete = jobSTATE.isRotationComplete
    dm_handle.isDriverActive = jobSTATE.isActive

    -- Update simulation info
    local sim = STATE.core.driver.simulation
    dm_handle.sim_position = string.format("x: %.1f, y: %.1f, z: %.1f", sim.position.x, sim.position.y, sim.position.z)
    dm_handle.sim_velocity = string.format("x: %.1f, y: %.1f, z: %.1f", sim.velocity.x, sim.velocity.y, sim.velocity.z)
    dm_handle.sim_orientation = string.format("rx: %.3f, ry: %.3f", sim.euler.rx, sim.euler.ry)
    dm_handle.sim_ang_velocity = string.format("x: %.3f, y: %.3f, z: %.3f", sim.angularVelocity.x, sim.angularVelocity.y, sim.angularVelocity.z)

    local isProjCamAvailable = false
    if currentMode ~= "None" then
        local compatibleModes = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.COMPATIBLE_MODES_FROM
        for _, mode in ipairs(compatibleModes) do
            if mode == currentMode then
                isProjCamAvailable = true
                break
            end
        end
    end

    dm_handle.isProjectileCameraAvailable = isProjCamAvailable

    if dm_handle.isProjectileCameraAvailable then
        local projCamState = STATE.active.mode.projectile_camera
        dm_handle.proj_cam_submode = projCamState.cameraMode or "N/A"
        dm_handle.proj_cam_prev_mode = projCamState.previousMode or "N/A"

        if projCamState.impactTime then
            dm_handle.proj_cam_status = "Impact"
            local impactDuration = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA.IMPACT_VIEW_DURATION
            local timeSinceImpact = Spring.DiffTimers(Spring.GetTimer(), projCamState.impactTime)
            local countdown = impactDuration - timeSinceImpact
            dm_handle.proj_cam_impact_countdown = string.format("%.2f", countdown > 0 and countdown or 0)
        else
            dm_handle.proj_cam_status = "Tracking"
            dm_handle.proj_cam_impact_countdown = ""
        end

        local unitID = STATE.active.mode.unitID
        local unitProjectiles = (unitID and STATE.core.projectileTracking.unitProjectiles[unitID] and STATE.core.projectileTracking.unitProjectiles[unitID].projectiles) or {}
        local sortedProjectiles = {}
        for _, p in ipairs(unitProjectiles) do
            table.insert(sortedProjectiles, p)
        end

        table.sort(sortedProjectiles, function(a, b)
            if type(a) ~= 'table' or type(b) ~= 'table' or not a.creationTime or not b.creationTime then
                return false
            end
            return a.creationTime > b.creationTime
        end)

        local selectedProjectiles = {}

        -- Insert new data
        for i = 1, math.min(3, #sortedProjectiles) do
            local p = sortedProjectiles[i]
            table.insert(selectedProjectiles, {
                id = p.id,
                pos = string.format("%.0f, %.0f, %.0f", p.position.x, p.position.y, p.position.z)
            })
        end

        dm_handle.proj_cam_projectiles = selectedProjectiles or {}
        dm_handle.proj_cam_projectiles_size = #selectedProjectiles

        local is_armed_or_active = dm_handle.isProjectileCameraArmed or dm_handle.isProjectileCameraActive
        dm_handle.proj_cam_track_button_active = is_armed_or_active and (dm_handle.proj_cam_submode == 'static')
        dm_handle.proj_cam_follow_button_active = is_armed_or_active and (dm_handle.proj_cam_submode == 'follow')
    else
        dm_handle.proj_cam_track_button_active = false
        dm_handle.proj_cam_follow_button_active = false
    end

    local allProjectiles = API.getAllTrackedProjectiles() or {}
    local projectiles_list = {}
    local projCamState = STATE.active.mode.projectile_camera

    for _, p in ipairs(allProjectiles) do
        local teamId = Spring.GetUnitTeam(p.ownerID)
        local r, g, b = Spring.GetTeamColor(teamId)
        local timeInAir = Spring.DiffTimers(Spring.GetTimer(), p.creationTime)
        local isCurrentlyTracked = projCamState.currentProjectileID == p.id

        table.insert(projectiles_list, {
            id = p.id,
            playerName = findPlayerNameByTeamID(teamId),
            playerColor = string.format("rgb(%d, %d, %d)", r * 255, g * 255, b * 255),
            timeInAir = string.format("%.1fs", timeInAir or 0),
            isTracked = isCurrentlyTracked and projCamState.cameraMode == 'static',
            isFollowed = isCurrentlyTracked and projCamState.cameraMode == 'follow',
        })
    end

    table.sort(projectiles_list, function(a, b) return (a.timeInAir or 0) > (b.timeInAir or 0) end)

    dm_handle.nuke_tracking.projectiles = projectiles_list
    dm_handle.nuke_tracking.hasProjectiles = #projectiles_list > 0

    -- Update Anchors
    local anchors_list = {}

    for id, anchorData in pairs(STATE.anchor.points) do
        local anchor_type = "Direction"
        if anchorData.target then
            if anchorData.target.type == "UNIT" then
                anchor_type = "Unit"
            elseif anchorData.target.type == "POINT" then
                anchor_type = "Point"
            end
        end

        table.insert(anchors_list, {
            id = id,
            duration = string.format("%.1fs", anchorData.duration or CONFIG.CAMERA_MODES.ANCHOR.DURATION),
            type = anchor_type,
        })
    end

    table.sort(anchors_list, function(a, b) return tonumber(a.id) < tonumber(b.id) end)
    dm_handle.anchors.anchors_list = anchors_list
    dm_handle.anchors.hasAnchors = #anchors_list > 0
    dm_handle.anchors.activeAnchorId = STATE.core.anchor.lastUsedAnchor or -1
    dm_handle.anchors.visualizationEnabled = STATE.active.anchor.visualizationEnabled or false

    dm_handle.anchors.singleDurationMode = CONFIG.CAMERA_MODES.ANCHOR.SINGLE_DURATION_MODE or false
    dm_handle.anchors.newAnchorDuration = CONFIG.CAMERA_MODES.ANCHOR.DURATION
    dm_handle.anchors.newAnchorDurationDisplay = string.format('%.1fs', CONFIG.CAMERA_MODES.ANCHOR.DURATION)

    -- Saved Anchor Sets
    local mapName = getCleanMapName()
    local mapPresets = API.loadSettings("anchors", mapName, {}, true) or {}
    local sets_list = {}
    for id, _ in pairs(mapPresets) do
        table.insert(sets_list, id)
    end
    table.sort(sets_list)
    dm_handle.savedAnchorSets = sets_list
    dm_handle.hasSavedAnchorSets = #sets_list > 0
    dm_handle.inFixedTargetSelectionMode = STATE.active.mode.unit_follow.inTargetSelectionMode
    dm_handle.isFixedTargetModeActive = STATE.active.mode.unit_follow.isFixedPointActive
    dm_handle.isWeaponCameraActive = STATE.active.mode.unit_follow.combatModeEnabled

    dm_handle.showError = STATE.error ~= nil
    if dm_handle.showError then
        dm_handle.showTraceback = STATE.error.traceback and true
        dm_handle.error.message = STATE.error.message or ""
        dm_handle.error.traceback = STATE.error.traceback or ""
    end
end

-- Widget initialization
function widget:Initialize()
    Log = LogBuilder.createInstance("TurboBarCamUI", function()
        return "DEBUG"
    end)
    -- Get RmlUi context through widget
    widget.rmlContext = RmlUi.CreateContext("shared")

    if not widget.rmlContext then
        Log:warn("Failed to create RmlUi context")
        return false
    end

    -- Open data model with all variables
    widget.rmlContext:RemoveDataModel(MODEL_NAME)
    dm_handle = widget.rmlContext:OpenDataModel(MODEL_NAME, initDataModel)

    if not dm_handle then
        Log:warn("Failed to open data model")
        return false
    end

    -- Load the document (passing the widget for events)
    document = widget.rmlContext:LoadDocument("LuaUI/RmlWidgets/gui_turbobarcam/rml/gui_turbobarcam.rml")

    if not document then
        Log:warn("Failed to load document")
        widget.rmlContext:RemoveDataModel(MODEL_NAME)
        return false
    end

    -- Setup document
    document:ReloadStyleSheet()
    document:Show()
    visible = true
    initialized = true

    if not WG.TurboBarCam then
        Log:warn("TurboBarCam is not initialized")
        return
    end

    WG.TurboBarCam.UI = {}

    STATE = WG.TurboBarCam.STATE
    CONFIG = WG.TurboBarCam.CONFIG
    API = WG.TurboBarCam.API

    -- Get and set initial bindings
    updateDataModel()

    --RmlUi.SetDebugContext(widget.rmlContext)
    Log:info("Initialized successfully")
    return true
end

-- Widget shutdown
function widget:Shutdown()
    if WG['info'] and WG['info'].clearCustomHover then
        WG['info'].clearCustomHover()
    end

    if document then
        document:Close()
        document = nil
    end

    if helpDocument then
        helpDocument:Close()
        helpDocument = nil
        if helpContext then
            helpContext = nil
        end
    end

    if widget.rmlContext then
        widget.rmlContext:RemoveDataModel(MODEL_NAME)
    end

    initialized = false
    visible = false
    if WG.TurboBarCam then
        WG.TurboBarCam.UI = nil
    end
    Log:info("Shutdown complete")
end

function widget:RestartWidget()
    widget:Shutdown()
    widget:Initialize()
end

local function hideUI()
    if not visible then
        return
    end
    visible = false
    if document then
        document:Hide()
    end
    if helpDocument then
        helpDocument:Hide()
    end
end

local function showUI()
    if visible then
        return
    end
    visible = true
    if document then
        document:Show()
    end
    if helpDocument then
        helpDocument:Show()
    end
end

function widget:Update()
    if Spring.IsGUIHidden() or isLobbyVisible then
        hideUI()
        return
    end

    if initialized then
        showUI()
        updateDataModel()
    end
end

function widget:RecvLuaMsg(msg)
    if msg:sub(1, 19) == 'LobbyOverlayActive0' then
        isLobbyVisible = false
    elseif msg:sub(1, 19) == 'LobbyOverlayActive1' then
        isLobbyVisible = true
    end
end
