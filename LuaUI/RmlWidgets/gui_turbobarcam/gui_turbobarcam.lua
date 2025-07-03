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

    -- Update raw camera info
    local rawCam = STATE.core.camera
    dm_handle.raw_position = string.format("x: %.1f, y: %.1f, z: %.1f", rawCam.position.x, rawCam.position.y, rawCam.position.z)
    dm_handle.raw_velocity = string.format("x: %.1f, y: %.1f, z: %.1f", rawCam.velocity.x, rawCam.velocity.y, rawCam.velocity.z)
    dm_handle.raw_orientation = string.format("rx: %.3f, ry: %.3f", rawCam.euler.rx, rawCam.euler.ry)
    dm_handle.raw_ang_velocity = string.format("x: %.3f, y: %.3f, z: %.3f", rawCam.angularVelocity.x, rawCam.angularVelocity.y, rawCam.angularVelocity.z)

    -- Update mode-specific info
    local isProjCam = STATE.active.mode.name == 'projectile_camera'
    dm_handle.isProjectileCameraActive = isProjCam
    dm_handle.show_mode_placeholder = (dm_handle.activeTab == 'mode' and not isProjCam)

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
        local unitProjectiles = (unitID and STATE.core.projectileTracking.unitProjectiles[unitID]) or {}
        local sortedProjectiles = {}
        for _, p in ipairs(unitProjectiles) do table.insert(sortedProjectiles, p) end

        table.sort(sortedProjectiles, function(a, b)
            if type(a) ~= 'table' or type(b) ~= 'table' or not a.creationTime or not b.creationTime then
                return false
            end
            return a.creationTime > b.creationTime
        end)

        dm_handle.proj_cam_projectiles = {}
        for i = 1, math.min(3, #sortedProjectiles) do
            local p = sortedProjectiles[i]
            if p and p.position then
                local pos_str = string.format("%.0f, %.0f, %.0f", p.position.x, p.position.y, p.position.z)
                table.insert(dm_handle.proj_cam_projectiles, string.format("- ID: %s, Pos: (%s)", p.id, pos_str))
            end
        end
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
        tracking = { mode = "None" },
    }

    -- Open data model with all variables
    widget.rmlContext:RemoveDataModel(MODEL_NAME)
    dm_handle = widget.rmlContext:OpenDataModel(MODEL_NAME, {
        status = STATE.enabled and "ENABLED" or "DISABLED",
        currentMode = STATE.active.mode.name or "None",
        isEnabled = STATE.enabled,
        activeTab = "driver",
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
        -- Raw camera Info
        raw_position = "",
        raw_velocity = "",
        raw_orientation = "",
        raw_ang_velocity = "",
        -- Projectile Camera Info
        isProjectileCameraActive = false,
        proj_cam_submode = "",
        proj_cam_prev_mode = "",
        proj_cam_status = "",
        proj_cam_impact_countdown = "",
        proj_cam_projectiles = {},
        show_mode_placeholder = false,
    })

    if not dm_handle then
        Log:warn("Failed to open data model")
        return false
    end

    -- Load the document (passing the widget for events)
    document = widget.rmlContext:LoadDocument("LuaUI/RmlWidgets/gui_turbobarcam/rml/gui_turbobarcam.rml", widget)

    if not document then
        Log:warn("Failed to load document")
        widget.rmlContext:RemoveDataModel(MODEL_NAME)
        return false
    end

    -- Get and set initial bindings
    updateDataModel()

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

function widget:ToggleTurboBarCam()
    if WG.TurboBarCam and WG.TurboBarCam.API and WG.TurboBarCam.API.ToggleTurboBarCam then
        WG.TurboBarCam.API.ToggleTurboBarCam()
    else
        Log:warn(" Could not toggle TurboBarCam - UI functions not loaded")
    end
end

function widget:SetTab(tabName)
    if dm_handle then
        dm_handle.activeTab = tabName
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