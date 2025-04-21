if not RmlUi then
    return
end

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

local availableModes = {
    fps = "FPS Camera",
    unit_tracking = "Unit Tracking",
    orbit = "Orbit Camera",
    overview = "Overview",
    group_tracking = "Group Tracking",
    projectile_camera = "Projectile Camera"
}

-- Action prefixes for different camera modes
local MODE_ACTION_PREFIXES = {
    fps = "turbobarcam_fps_",
    unit_tracking = "turbobarcam_unit_tracking_",
    orbit = "turbobarcam_orbit_",
    overview = "turbobarcam_overview_",
    group_tracking = "turbobarcam_group_tracking_",
    projectile_camera = "turbobarcam_projectile_"
}

-- Helper function to get pretty action name
local function getPrettyActionName(actionName)
    -- Strip prefix and replace underscores with spaces
    local baseAction = actionName:gsub("turbobarcam_", "")

    -- Strip the mode prefix if it exists
    for mode, prefix in pairs(MODE_ACTION_PREFIXES) do
        baseAction = baseAction:gsub("^" .. mode:gsub("_", "_") .. "_", "")
    end

    -- Replace underscores with spaces and capitalize first letter of each word
    baseAction = baseAction:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest
    end)

    return baseAction
end

-- Function to get key bindings for actions
local function getActionBindings()
    local bindings = {}

    -- Get all keybinds from Spring
    local allBindings = Spring.GetKeyBindings()

    for _, binding in ipairs(allBindings) do
        local action = binding.action
        if action:find("turbobarcam_") == 1 then
            -- Format the key binding
            local key = binding.command:match("%s(.+)$") or binding.command

            -- Format the action name
            bindings[action] = {
                action = action,
                key = key,
                prettyName = getPrettyActionName(action)
            }
        end
    end

    return bindings
end

-- Function to get bindings for the current mode
local function getModeBindings(currentMode)
    if not currentMode or currentMode == "None" then
        return {}
    end

    -- Convert display mode name back to internal mode name
    local internalMode = nil
    for mode, displayName in pairs(availableModes) do
        if displayName == currentMode then
            internalMode = mode
            break
        end
    end

    if not internalMode then
        return {}
    end

    local prefix = MODE_ACTION_PREFIXES[internalMode]
    if not prefix then
        return {}
    end

    local allBindings = getActionBindings()
    local modeBindings = {}

    -- Add general TurboBarCam controls
    table.insert(modeBindings, {
        actionName = "Toggle TurboBarCam",
        keyBind = allBindings["turbobarcam_toggle"] and allBindings["turbobarcam_toggle"].key or "Not bound"
    })

    table.insert(modeBindings, {
        actionName = "Toggle UI",
        keyBind = allBindings["turbobarcam_toggle_ui"] and allBindings["turbobarcam_toggle_ui"].key or "Not bound"
    })

    -- Get mode-specific bindings
    for action, bindInfo in pairs(allBindings) do
        if action:find(prefix) == 1 then
            table.insert(modeBindings, {
                actionName = bindInfo.prettyName,
                keyBind = bindInfo.key
            })
        end
    end

    -- Add the toggle action for this mode
    local toggleAction = "turbobarcam_toggle_" .. internalMode
    if allBindings[toggleAction] then
        table.insert(modeBindings, {
            actionName = "Toggle " .. currentMode,
            keyBind = allBindings[toggleAction].key
        })
    end

    return modeBindings
end

-- Update data model with current TurboBarCam state
local function updateDataModel()
    if not initialized or not dm_handle then
        return
    end

    -- Get the latest state if available
    if WG.TurboBarCam and WG.TurboBarCam.STATE then
        STATE = WG.TurboBarCam.STATE
    end

    -- Update status
    dm_handle.isEnabled = STATE.enabled or false
    dm_handle.status = dm_handle.isEnabled and "Enabled" or "Disabled"

    -- Update current mode
    local currentMode = (STATE.tracking and STATE.tracking.mode) or "None"
    dm_handle.currentMode = currentMode ~= "None"
            and (availableModes[currentMode] or currentMode)
            or "None"

    -- Update keybindings for current mode
    dm_handle.modeBindings = getModeBindings(dm_handle.currentMode)
end

-- Widget initialization
function widget:Initialize()

    -- Get RmlUi context through widget
    widget.rmlContext = RmlUi.CreateContext("turbobarcam_ui")

    if not widget.rmlContext then
        return false
    end

    STATE = WG.TurboBarCam and WG.TurboBarCam.STATE or {
        enabled = false,
        tracking = { mode = "None" },
    }

    -- Open data model first
    widget.rmlContext:RemoveDataModel(MODEL_NAME)
    dm_handle = widget.rmlContext:OpenDataModel(MODEL_NAME, {
        status = STATE.enabled and "ENABLED" or "DISABLED",
        currentMode = STATE.tracking.mode or "None",
        isEnabled = STATE.enabled,
        modeBindings = {}
    })

    if not dm_handle then
        return false
    end

    -- Get and set initial bindings
    updateDataModel()

    -- Load the document (passing the widget for events)
    document = widget.rmlContext:LoadDocument("LuaUI/RmlWidgets/gui_turbobarcam/rml/gui_turbobarcam.rml", widget)

    if not document then
        widget.rmlContext:RemoveDataModel(MODEL_NAME)
        return false
    end

    -- Setup document
    document:ReloadStyleSheet()
    document:Show()
    visible = true
    initialized = true

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
end

function widget:ToggleTurboBarCam()
    if WG.TurboBarCam and WG.TurboBarCam.UI and WG.TurboBarCam.UI.ToggleTurboBarCam then
        WG.TurboBarCam.UI.ToggleTurboBarCam()
    else
        Spring.Echo("[TurboBarCam UI] Could not toggle TurboBarCam - UI functions not loaded")
    end
end

function widget:RefreshBindings()
    if initialized and visible then
        Spring.Echo("[TurboBarCam UI] Refreshing keybindings")
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