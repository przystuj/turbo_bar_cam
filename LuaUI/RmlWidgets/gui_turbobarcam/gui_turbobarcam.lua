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
        layer = 2,
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
    fps = "FPS Camera",
    unit_tracking = "Unit Tracking",
    orbit = "Orbit Camera",
    overview = "Overview",
    group_tracking = "Group Tracking",
    projectile = "Projectile Camera"
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
    local currentMode = (STATE.tracking and STATE.tracking.mode) or "None"
    dm_handle.currentMode = currentMode ~= "None"
            and (availableModes[currentMode] or currentMode)
            or "None"

    -- Update debug info
    if STATE.core and STATE.core.driver then
        local driver = STATE.core.driver
        local target = driver.target
        local sim = driver.simulation
        local trans = driver.transition

        dm_handle.debug_target_pos = Log:serializeTable(target.position)
        dm_handle.debug_target_lookat = target.lookAt and (target.lookAt.type .. ":" .. tostring(target.lookAt.data)) or "nil"
        dm_handle.debug_target_euler = Log:serializeTable(target.euler)
        dm_handle.debug_target_smooth_pos = target.smoothTimePos and string.format("%.2f", target.smoothTimePos) or "nil"
        dm_handle.debug_target_smooth_rot = target.smoothTimeRot and string.format("%.2f", target.smoothTimeRot) or "nil"

        dm_handle.debug_sim_pos = Log:serializeTable(sim.position)
        dm_handle.debug_sim_vel = Log:serializeTable(sim.velocity)
        dm_handle.debug_sim_orient = Log:serializeTable(sim.orientation)
        dm_handle.debug_sim_ang_vel = Log:serializeTable(sim.angularVelocity)

        dm_handle.debug_sim_ang_vel = Log:serializeTable(sim.angularVelocity)

        local transition_status
        if trans.smoothTimeTransitionStart then
            local elapsed = Spring.DiffTimers(Spring.GetTimer(), trans.smoothTimeTransitionStart)
            transition_status = string.format("In progress (%.2fs)", elapsed)
        else
            transition_status = "Idle"
        end
        dm_handle.debug_transition_status = transition_status
        dm_handle.debug_transition_angular_velocity_magnitude = trans.angularVelocityMagnitude
        dm_handle.debug_transition_velocity_magnitude = trans.velocityMagnitude
        dm_handle.debug_transition_distance = trans.distance
        dm_handle.debug_transition_angular_velocity_magnitude_target = CONFIG.DRIVER.ANGULAR_VELOCITY_TARGET
        dm_handle.debug_transition_velocity_magnitude_target = CONFIG.DRIVER.VELOCITY_TARGET
        dm_handle.debug_transition_distance_target = CONFIG.DRIVER.DISTANCE_TARGET
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
        currentMode = STATE.tracking and STATE.tracking.mode or "None",
        isEnabled = STATE.enabled,
        -- Debug Info
        debug_target_pos = "",
        debug_target_lookat = "",
        debug_target_euler = "",
        debug_target_smooth_pos = "",
        debug_target_smooth_rot = "",
        debug_sim_pos = "",
        debug_sim_vel = "",
        debug_sim_orient = "",
        debug_sim_ang_vel = "",
        debug_transition_status = "",
        debug_transition_angular_velocity_magnitude = "",
        debug_transition_velocity_magnitude = "",
        debug_transition_distance = "",
        debug_transition_angular_velocity_magnitude_target = "",
        debug_transition_velocity_magnitude_target = "",
        debug_transition_distance_target = "",
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
    if WG.TurboBarCam and WG.TurboBarCam.UI and WG.TurboBarCam.UI.ToggleTurboBarCam then
        WG.TurboBarCam.UI.ToggleTurboBarCam()
    else
        Log:warn(" Could not toggle TurboBarCam - UI functions not loaded")
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