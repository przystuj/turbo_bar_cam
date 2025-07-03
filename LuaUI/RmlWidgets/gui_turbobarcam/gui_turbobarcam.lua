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
        date = "April 2025",
        license = "GNU GPL, v2 or later",
        layer = 0,
        enabled = true,
        version = 1
    }
end

local MODEL_NAME = "turbobarcam_model"
local document
local dm_handle
local initialized = false
local visible = false

---@type WidgetState
local STATE
---@type WidgetConfig
local CONFIG

local availableModes = {
    unit_follow = "Unit Follow",
    unit_tracking = "Unit Tracking",
    orbit = "Orbit Camera",
    overview = "Overview",
    group_tracking = "Group Tracking",
    projectile_camera = "Projectile Camera"
}

local initDataModel = {
    status = "DISABLED",
    currentMode = "None",
    isEnabled = false,
    isDriverFolded = true,
    -- Parameter adjustment step values
    adjustments = {
        unit_follow = { DEFAULT = { HEIGHT = 5, FORWARD = 5, SIDE = 5, ROTATION = 0.1 } },
        unit_tracking = { HEIGHT = 20 },
        orbit = { DISTANCE = 20, HEIGHT = 20, SPEED = 0.01 },
        group_tracking = { EXTRA_DISTANCE = 15, EXTRA_HEIGHT = 5, ORBIT_OFFSET = 0.01 },
        overview = { HEIGHT = 1 },
    },
    -- Pre-formatted strings for display
    display_params = {
        unit_follow = { DEFAULT = { HEIGHT = "0", FORWARD = "0", SIDE = "0" } },
        unit_tracking = { HEIGHT = "0" },
        orbit = { DISTANCE = "0", HEIGHT = "0", SPEED = "0.00" },
        group_tracking = { EXTRA_DISTANCE = "0", EXTRA_HEIGHT = "0", ORBIT_OFFSET = "0.00" },
    },
    -- Debug Info
    debug_pos_smooth = "",
    debug_rot_smooth = "",
    debug_velocity = "",
    debug_ang_velocity = "",
    debug_distance = "",
    debug_pos_complete = false,
    debug_rot_complete = false,
    -- Simulation Info
    sim_position = "",
    sim_velocity = "",
    sim_orientation = "",
    sim_ang_velocity = "",
    -- Projectile Camera Info
    isProjectileCameraActive = false,
    proj_cam_submode = "",
    proj_cam_prev_mode = "",
    proj_cam_status = "",
    proj_cam_impact_countdown = "",
    proj_cam_projectiles = {},
}

-- Update data model with current TurboBarCam state and keybindings
local function updateDataModel()
    if not initialized or not dm_handle then
        return
    end

    -- Get the latest state and config
    if WG.TurboBarCam and WG.TurboBarCam.STATE then
        STATE = WG.TurboBarCam.STATE
    end
    if WG.TurboBarCam and WG.TurboBarCam.CONFIG then
        CONFIG = WG.TurboBarCam.CONFIG
    end

    -- Update status
    dm_handle.isEnabled = STATE.enabled or false
    dm_handle.status = dm_handle.isEnabled and "Enabled" or "Disabled"

    -- Update current mode
    local currentMode = STATE.active.mode.name or "None"
    dm_handle.currentMode = currentMode ~= "None" and (availableModes[currentMode] or currentMode) or "None"

    -- Update current parameter values from CONFIG and format for display
    if CONFIG then
        local dp = dm_handle.display_params
        local cfg = CONFIG.CAMERA_MODES
        dp.unit_follow.DEFAULT.HEIGHT = string.format('%.0f', cfg.UNIT_FOLLOW.OFFSETS.DEFAULT.HEIGHT or 0)
        dp.unit_follow.DEFAULT.FORWARD = string.format('%.0f', cfg.UNIT_FOLLOW.OFFSETS.DEFAULT.FORWARD or 0)
        dp.unit_follow.DEFAULT.SIDE = string.format('%.0f', cfg.UNIT_FOLLOW.OFFSETS.DEFAULT.SIDE or 0)
        dp.unit_tracking.HEIGHT = string.format('%.0f', cfg.UNIT_TRACKING.HEIGHT or 0)
        dp.orbit.DISTANCE = string.format('%.0f', cfg.ORBIT.OFFSETS.DISTANCE or 0)
        dp.orbit.HEIGHT = string.format('%.0f', cfg.ORBIT.OFFSETS.HEIGHT or 0)
        dp.orbit.SPEED = string.format('%.2f', cfg.ORBIT.OFFSETS.SPEED or 0)
        dp.group_tracking.EXTRA_DISTANCE = string.format('%.0f', cfg.GROUP_TRACKING.EXTRA_DISTANCE or 0)
        dp.group_tracking.EXTRA_HEIGHT = string.format('%.0f', cfg.GROUP_TRACKING.EXTRA_HEIGHT or 0)
        dp.group_tracking.ORBIT_OFFSET = string.format('%.2f', cfg.GROUP_TRACKING.ORBIT_OFFSET or 0)
    end


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

    dm_handle.debug_pos_complete = jobSTATE.isPositionComplete or false
    dm_handle.debug_rot_complete = jobSTATE.isRotationComplete or false

    -- Update simulation info
    local sim = STATE.core.driver.simulation
    dm_handle.sim_position = string.format("x: %.1f, y: %.1f, z: %.1f", sim.position.x, sim.position.y, sim.position.z)
    dm_handle.sim_velocity = string.format("x: %.1f, y: %.1f, z: %.1f", sim.velocity.x, sim.velocity.y, sim.velocity.z)
    dm_handle.sim_orientation = string.format("rx: %.3f, ry: %.3f", sim.euler.rx, sim.euler.ry)
    dm_handle.sim_ang_velocity = string.format("x: %.3f, y: %.3f, z: %.3f", sim.angularVelocity.x, sim.angularVelocity.y, sim.angularVelocity.z)

    -- Update mode-specific info
    local isProjCam = STATE.active.mode.name == 'projectile_camera'
    dm_handle.isProjectileCameraActive = isProjCam

    if isProjCam then
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
        local unitProjectiles = (unitID and STATE.core.projectileTracking.unitProjectiles[unitID].projectiles) or {}
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


        -- Clear the existing array in-place
        while #dm_handle.proj_cam_projectiles > 0 do
            table.remove(dm_handle.proj_cam_projectiles)
        end

        local selectedProjectiles = {}

        -- Insert new data
        for i = 1, math.min(3, #sortedProjectiles) do
            local p = sortedProjectiles[i]
            table.insert(selectedProjectiles, {
                id = p.id,
                pos = string.format("%.0f, %.0f, %.0f", p.position.x, p.position.y, p.position.z)
            })
        end

        dm_handle.proj_cam_projectiles = selectedProjectiles

        Log:debug(selectedProjectiles)
        Log:debug(dm_handle.proj_cam_projectiles)
    end
end

-- Widget initialization
function widget:Initialize()
    -- Get RmlUi context through widget
    widget.rmlContext = RmlUi.CreateContext("turbobarcam_ui")
    Log = LogBuilder.createInstance("TurboBarCamUI", function()
        return "DEBUG"
    end)

    if not widget.rmlContext then
        Log:warn("Failed to create RmlUi context")
        return false
    end

    STATE = WG.TurboBarCam and WG.TurboBarCam.STATE or {
        enabled = false,
        active = {
            mode = {
                name = nil
            }
        }
    }

    -- Open data model with all variables
    widget.rmlContext:RemoveDataModel(MODEL_NAME)
    dm_handle = widget.rmlContext:OpenDataModel(MODEL_NAME, initDataModel)

    if not dm_handle then
        Log:warn("Failed to open data model")
        return false
    end

    -- Get and set initial bindings
    updateDataModel()

    -- Load the document (passing the widget for events)
    document = widget.rmlContext:LoadDocument("LuaUI/RmlWidgets/gui_turbobarcam/rml/gui_turbobarcam.rml", widget)

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

    Log:info("Initialized successfully")

    return true
end

-- Widget shutdown
function widget:Shutdown()
    if document then
        document:Close()
        document = nil
    end

    if widget.rmlContext and dm_handle then
        widget.rmlContext:RemoveDataModel(MODEL_NAME)
        dm_handle = nil
    end

    initialized = false
    visible = false
    Log:info("Shutdown complete")
end

function widget:CallAction(action)
    Spring.SendCommands(action)
end

function widget:SetUnitFollowLookPoint()
    if CONFIG and CONFIG.COMMANDS then
        local cmdID = CONFIG.COMMANDS.SET_FIXED_LOOK_POINT
        local cmdDescIndex = Spring.GetCmdDescIndex(cmdID)
        if cmdDescIndex then
            Spring.SetActiveCommand(cmdDescIndex, 1, true, false, Spring.GetModKeyState())
        end
    end
end

function widget:AdjustParam(mode, param_path, sign)
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

function widget:ResetParams(mode)
    local action = string.format("turbobarcam_%s_adjust_params reset", mode)
    Spring.SendCommands(action)
end

function widget:ToggleDriverInfo()
    if dm_handle then
        dm_handle.isDriverFolded = not dm_handle.isDriverFolded
    end
end

function widget:RestartWidget()
    widget:Shutdown()
    widget:Initialize()
end

function widget:Update()
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