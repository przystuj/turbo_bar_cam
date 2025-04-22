if not RmlUi then
    return
end

-- Load helper files
local scriptPath = LUAUI_DIRNAME .. "RmlWidgets/gui_turbobarcam/"
local bindings = VFS.Include(scriptPath .. "bindings.lua")
local params = VFS.Include(scriptPath .. "parameters.lua")
local utils = VFS.Include(scriptPath .. "utils.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log

local widget = widget

-- Widget metadata
function widget:GetInfo()
    return {
        name = "TurboBarCam UI",
        desc = "UI for controlling the TurboBarCam camera system",
        author = "YourUsername",
        date = "April 2025",
        license = "GNU GPL, v2 or later",
        layer = 1000,
        enabled = true
    }
end

local MODEL_NAME = "turbobarcam_model"
local document
local dm_handle
local initialized = false
local visible = false

local STATE
local CONFIG

-- Set active tab
function widget:SetTab(tabName)
    if initialized and dm_handle then
        dm_handle.activeTab = tabName
    end
end

-- Update a specific parameter in the TurboBarCam config
function widget:UpdateParameter(paramId, value)
    return params.updateParameter(self, paramId, value)
end

-- Reset a specific parameter to its default
function widget:ResetParameter(paramId)
    return params.resetParameter(self, paramId)
end

-- Reset all parameters for the current mode
function widget:ResetAllParameters()
    return params.resetAllParameters(self, STATE)
end

-- Debug function to dump all bindings
function widget:DumpBindings()
    bindings.dumpBindings(STATE)
end

-- Update data model with current TurboBarCam state and keybindings
local function updateDataModel()
    if not initialized or not dm_handle then
        return
    end

    -- Get the latest state and config if available
    if WG.TurboBarCam then
        if WG.TurboBarCam.STATE then
            STATE = WG.TurboBarCam.STATE
        end
        if WG.TurboBarCam.CONFIG then
            CONFIG = WG.TurboBarCam.CONFIG
        end
    end

    -- Update status
    dm_handle.isEnabled = STATE.enabled or false
    dm_handle.status = dm_handle.isEnabled and "Enabled" or "Disabled"

    -- Update current mode
    local currentMode = (STATE.tracking and STATE.tracking.mode) or "None"
    dm_handle.currentMode = currentMode ~= "None"
            and (bindings.availableModes[currentMode] or currentMode)
            or "None"

    -- Get bindings for the current mode
    local binds = bindings.getActiveModeMappings(STATE, dm_handle.currentMode)

    -- Set the bindings array in the data model
    Log.debug(binds)
    dm_handle.bindings = binds

    -- Get parameters for the current mode
    local parameters = params.getParameters(CONFIG, dm_handle.currentMode)

    -- Set the parameters array in the data model
    dm_handle.parameters = parameters
end

-- Widget initialization
function widget:Initialize()
    -- Get RmlUi context through widget
    widget.rmlContext = RmlUi.CreateContext("turbobarcam_ui")

    if not widget.rmlContext then
        Log.debug("[TurboBarCam UI] Failed to create RmlUi context")
        return false
    end

    -- Get initial state and config
    if WG.TurboBarCam then
        STATE = WG.TurboBarCam.STATE or {
            enabled = false,
            tracking = { mode = "None" },
        }
        CONFIG = WG.TurboBarCam.CONFIG
    else
        STATE = {
            enabled = false,
            tracking = { mode = "None" },
        }
    end

    -- Open data model with array support for bindings and parameters
    widget.rmlContext:RemoveDataModel(MODEL_NAME)
    dm_handle = widget.rmlContext:OpenDataModel(MODEL_NAME, {
        status = STATE.enabled and "ENABLED" or "DISABLED",
        currentMode = STATE.tracking and STATE.tracking.mode and bindings.availableModes[STATE.tracking.mode] or "None",
        isEnabled = STATE.enabled,
        activeTab = "keybinds",
        -- Use arrays for dynamic content
        bindings = { { key = "", name = "", param = "" } },
        parameters = {},
        test1 = "test1",
        test2 = { "test2" },
        test3 = { test = "test3" },
    })

    if not dm_handle then
        Log.debug("[TurboBarCam UI] Failed to open data model")
        return false
    end

    -- Load the document (passing the widget for events)
    document = widget.rmlContext:LoadDocument("LuaUI/RmlWidgets/gui_turbobarcam/rml/gui_turbobarcam.rml", widget)

    if not document then
        Log.debug("[TurboBarCam UI] Failed to load document")
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

    Log.debug("[TurboBarCam UI] Initialized successfully")

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
    Log.debug("[TurboBarCam UI] Shutdown complete")
end

function widget:ToggleTurboBarCam()
    if WG.TurboBarCam and WG.TurboBarCam.UI and WG.TurboBarCam.UI.ToggleTurboBarCam then
        WG.TurboBarCam.UI.ToggleTurboBarCam()
    else
        Log.debug("[TurboBarCam UI] Could not toggle TurboBarCam - UI functions not loaded")
    end
end

function widget:RefreshBindings()
    if initialized and visible then
        Log.debug("[TurboBarCam UI] Refreshing UI")
        updateDataModel()
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