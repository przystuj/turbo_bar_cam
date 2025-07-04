if not RmlUi then
    return
end

---@type LogBuilder
local LogBuilder = VFS.Include("LuaUI/TurboBarCommons/logger_prototype.lua")
---@type Log
local Log

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
        version = 2
    }
end

local MODEL_NAME = "turbobarcam_model"
local document
local dm_handle ---@type UIDataModel
local initialized = false
local visible = false

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

local function ResetParams(_, mode)
    local action = string.format("turbobarcam_%s_adjust_params reset", mode)
    Spring.SendCommands(action)
end

local function ToggleDebugInfo(_)
    dm_handle.isDebugFolded = not dm_handle.isDebugFolded
end

local function ToggleAnchorsInfo(_)
    dm_handle.isAnchorsFolded = not dm_handle.isAnchorsFolded
end

local function ToggleSavedAnchorSetsInfo(_)
    dm_handle.isSavedAnchorSetsFolded = not dm_handle.isSavedAnchorSetsFolded
end

local function ToggleOptionsInfo(_)
    dm_handle.isOptionsFolded = not dm_handle.isOptionsFolded
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
    local newAnchorSetName = dm_handle.anchors.newAnchorSetName
    if newAnchorSetName and newAnchorSetName ~= "" then
        Spring.SendCommands("turbobarcam_anchor_save " .. newAnchorSetName)
        dm_handle.anchors.newAnchorSetName = ""
    else
        Log:warn("Cannot save anchor set with an empty name.")
    end
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

---@class UIDataModel
local initDataModel = {
    status = "DISABLED",
    currentMode = "None",
    isEnabled = false,
    isOptionsFolded = true,
    isDebugFolded = true,
    isAnchorsFolded = true,
    isSavedAnchorSetsFolded = true,
    playerCamSelectionActive = true,
    trackingWithoutSelectionActive = false,
    anchors = {
        anchors_list = {},
        activeAnchorId = -1,
        hasAnchors = false,
        visualizationEnabled = false,
        newAnchorSetName = "",
        newAnchorDuration = 10,
        newAnchorDurationDisplay = "10.0s",
    },
    savedAnchorSets = {},
    hasSavedAnchorSets = false,

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
        overview = { HEIGHT = 1 },
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
    AdjustAnchorDuration = AdjustAnchorDuration,
    ResetParams = ResetParams,
    ToggleDebugInfo = ToggleDebugInfo,
    ToggleAnchorsInfo = ToggleAnchorsInfo,
    ToggleSavedAnchorSetsInfo = ToggleSavedAnchorSetsInfo,
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
}

local function getCleanMapName()
    local mapName = Game.mapName

    -- Remove version numbers at the end (patterns like 1.2.3 or V1.2.3)
    local cleanName = mapName:gsub("%s+[vV]?%d+%.?%d*%.?%d*$", "")

    return cleanName
end

-- Update data model with current TurboBarCam state and keybindings
local function updateDataModel()
    if not initialized or not dm_handle or not WG.TurboBarCam then
        return
    end

    STATE = WG.TurboBarCam.STATE
    CONFIG = WG.TurboBarCam.CONFIG
    API = WG.TurboBarCam.API

    dm_handle.debug_log_level = CONFIG.DEBUG.LOG_LEVEL

    -- Update status
    dm_handle.isEnabled = STATE.enabled or false
    dm_handle.status = dm_handle.isEnabled and "Enabled" or "Disabled"

    dm_handle.playerCamSelectionActive = STATE.allowPlayerCamUnitSelection or false
    dm_handle.trackingWithoutSelectionActive = CONFIG.ALLOW_TRACKING_WITHOUT_SELECTION or false

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

    table.sort(anchors_list, function(a, b) return a.id < b.id end)
    dm_handle.anchors.anchors_list = anchors_list
    dm_handle.anchors.hasAnchors = #anchors_list > 0
    dm_handle.anchors.activeAnchorId = STATE.active.anchor.lastUsedAnchor or -1
    dm_handle.anchors.visualizationEnabled = STATE.active.anchor.visualizationEnabled or false

    -- Saved Anchor Sets
    local mapName = getCleanMapName()
    local mapPresets = API.loadSettings("anchors", mapName, {}) or {}
    local sets_list = {}
    for id, _ in pairs(mapPresets) do
        table.insert(sets_list, id)
    end
    table.sort(sets_list)
    dm_handle.savedAnchorSets = sets_list
    dm_handle.hasSavedAnchorSets = #sets_list > 0
end

-- Widget initialization
function widget:Initialize()
    if not WG.TurboBarCam then
        Log:warn("TurboBarCam is not initialized")
        return
    end

    WG.TurboBarCam.UI = {}

    -- Get RmlUi context through widget
    widget.rmlContext = RmlUi.CreateContext("shared")
    Log = LogBuilder.createInstance("TurboBarCamUI", function()
        return "DEBUG"
    end)

    if not widget.rmlContext then
        Log:warn("Failed to create RmlUi context")
        return false
    end

    STATE = WG.TurboBarCam.STATE
    CONFIG = WG.TurboBarCam.CONFIG
    API = WG.TurboBarCam.API

    -- Open data model with all variables
    widget.rmlContext:RemoveDataModel(MODEL_NAME)
    dm_handle = widget.rmlContext:OpenDataModel(MODEL_NAME, initDataModel)

    if not dm_handle then
        Log:warn("Failed to open data model")
        return false
    end

    if CONFIG and CONFIG.CAMERA_MODES and CONFIG.CAMERA_MODES.ANCHOR then
        local duration = CONFIG.CAMERA_MODES.ANCHOR.DURATION or 10
        dm_handle.anchors.newAnchorDuration = duration
        dm_handle.anchors.newAnchorDurationDisplay = string.format('%.1fs', duration)
    end

    -- Get and set initial bindings
    updateDataModel()

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

    --RmlUi.SetDebugContext(widget.rmlContext)
    Log:info("Initialized successfully")
    return true
end

-- Widget shutdown
function widget:Shutdown()
    if document then
        document:Close()
        document = nil
    end

    if widget.rmlContext then
        widget.rmlContext:RemoveDataModel(MODEL_NAME)
    end

    initialized = false
    visible = false
    WG.TurboBarCam.UI = nil
    Log:info("Shutdown complete")
end

function widget:RestartWidget()
    widget:Shutdown()
    widget:Initialize()
end

function widget:GameFrame()
    if initialized and visible then
        updateDataModel()
    end
end

function widget:RecvLuaMsg(msg, playerID)
    if msg:sub(1, 19) == 'LobbyOverlayActive0' then
        document:Show()
    elseif msg:sub(1, 19) == 'LobbyOverlayActive1' then
        document:Hide()
    end
end