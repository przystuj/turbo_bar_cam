-- TurboBarCam UI Widget
-- A standalone RmlUi widget for Beyond All Reason

-- Check if RmlUi is available
if not RmlUi then
    return
end

local widget = widget -- Lua widget global

-- Widget metadata
function widget:GetInfo()
    return {
        name = "TurboBarCam UI",
        desc = "UI for controlling the TurboBarCam camera system",
        author = "YourUsername",
        date = "April 2025",
        license = "GNU GPL, v2 or later",
        layer = 2, -- High layer to be on top
        enabled = true
    }
end

-- Global references
local Spring = Spring
local WG = WG
local VFS = VFS

-- Constants and Variables
local SHORTCUT_KEY = "ctrl+shift+t"
local MODEL_NAME = "turbobarcam_model"
local document = nil
local dm_handle = nil
local initialized = false
local visible = false

-- Attempt to get TurboBarCam context
local STATE = WG.TurboBarCam and WG.TurboBarCam.STATE or {
    enabled = false,
    tracking = { mode = "None" },
    anchors = {}
}

-- Available camera modes definition
local availableModes = {
    fps = "FPS Camera",
    unit_tracking = "Unit Tracking",
    orbit = "Orbit Camera",
    overview = "Overview",
    group_tracking = "Group Tracking",
    projectile_camera = "Projectile Camera"
}

-- Key bindings storage
local keyBinds = {}

-- Initial model data
local initialModel = {
    status = "Disabled",
    isEnabled = false,
    currentMode = "None",
    currentModeActions = "No Active Mode",
    availableModes = {},
    modeActions = {},
    savedAnchors = {},
    hasAnchors = false
}

-- Load UI key bindings from Spring
local function loadKeyBindings()
    keyBinds = {}

    -- Retrieve the key binds from Spring
    local rawBinds = Spring.GetKeyBindings()

    -- Process each bind
    for _, bind in ipairs(rawBinds) do
        local actionName = bind[1]
        local keyCombo = bind[2]

        -- Only consider TurboBarCam actions
        if actionName and string.find(actionName, "turbobarcam_") then
            -- Store the key binding
            keyBinds[actionName] = keyBinds[actionName] or {}
            table.insert(keyBinds[actionName], keyCombo)
        end
    end
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

    -- Build model
    local model = {}

    -- Update status
    model.isEnabled = STATE.enabled or false
    model.status = model.isEnabled and "Enabled" or "Disabled"

    -- Update current mode
    local currentMode = (STATE.tracking and STATE.tracking.mode) or "None"
    model.currentMode = currentMode ~= "None"
            and (availableModes[currentMode] or currentMode)
            or "None"

    -- Update mode actions header
    model.currentModeActions = currentMode ~= "None"
            and (availableModes[currentMode] or currentMode)
            or "No Active Mode"

    -- Update available modes
    model.availableModes = {}
    for modeKey, modeName in pairs(availableModes) do
        local isActive = currentMode == modeKey

        -- Find the key binding for toggling this mode
        local toggleAction = "turbobarcam_toggle_" .. modeKey
        if modeKey == "unit_tracking" then
            toggleAction = "turbobarcam_toggle_tracking_camera"
        end

        local keyBind = ""
        if keyBinds[toggleAction] and keyBinds[toggleAction][1] then
            keyBind = keyBinds[toggleAction][1]
        end

        table.insert(model.availableModes, {
            key = modeKey,
            name = modeName,
            isActive = isActive,
            keyBind = keyBind
        })
    end

    -- Update mode actions
    model.modeActions = {}

    -- Only show actions for current mode, if a mode is active
    if currentMode ~= "None" then
        -- Find actions that belong to the current mode
        for actionName, keyBinds in pairs(keyBinds) do
            if actionName:find(currentMode) or
                    (currentMode == "unit_tracking" and actionName:find("tracking_camera")) then

                -- Skip toggle actions as they're shown in the modes list
                if not actionName:find("toggle_") then
                    local keyBind = keyBinds[1] or "Unbound"
                    local actionDisplay = actionName:gsub("turbobarcam_", ""):gsub("_", " ")

                    table.insert(model.modeActions, {
                        name = actionDisplay,
                        keyBind = keyBind
                    })
                end
            end
        end
    end

    -- Update saved anchors
    model.savedAnchors = {}
    model.hasAnchors = false

    -- Loop through potential anchors (0-9)
    if STATE.anchors then
        for i = 0, 9 do
            if STATE.anchors[i] then
                model.hasAnchors = true

                -- Find keybinding for focusing this anchor
                local focusKeyBind = ""
                local focusAction = "turbobarcam_anchor_focus"

                if keyBinds[focusAction] then
                    for _, bind in ipairs(keyBinds[focusAction]) do
                        if bind:find(tostring(i)) then
                            focusKeyBind = bind
                            break
                        end
                    end
                end

                table.insert(model.savedAnchors, {
                    index = i,
                    keyBind = focusKeyBind
                })
            end
        end
    end

    -- Update the data model
    --dm_handle:UpdateValues(model)
end

-- Toggle UI visibility
local function toggleUI()
    if not initialized then
        return
    end

    visible = not visible

    if document then
        if visible then
            updateDataModel()
            document:Show()
        else
            document:Hide()
        end
    end
end

-- Widget initialization
function widget:Initialize()
    -- Get RmlUi context
    widget.rmlContext = RmlUi.GetContext("shared")

    if not widget.rmlContext then
        Spring.Echo("[TurboBarCam UI] Failed to get RmlUi context")
        return
    end

    -- Load key bindings
    loadKeyBindings()

    -- Open data model
    dm_handle = widget.rmlContext:OpenDataModel(MODEL_NAME, initialModel)

    if not dm_handle then
        Spring.Echo("[TurboBarCam UI] Failed to open data model: " .. MODEL_NAME)
        return
    end

    -- Load the document
    document = widget.rmlContext:LoadDocument("LuaUI/RmlWidgets/gui_turbobarcam/gui_turbobarcam.rml", widget)

    if not document then
        Spring.Echo("[TurboBarCam UI] Failed to load UI document")
        widget.rmlContext:RemoveDataModel(MODEL_NAME)
        dm_handle = nil
        return
    end

    -- Initialize document and data
    document:ReloadStyleSheet()
    --document:Hide() -- Start hidden
    visible = true

    --updateDataModel()

    -- Set initialized flag
    initialized = true

    -- Register the shortcut
    Spring.SendCommands("bind " .. SHORTCUT_KEY .. " luaui togglewidget TurboBarCam UI")

    Spring.Echo("[TurboBarCam UI] Initialized - press " .. SHORTCUT_KEY .. " to toggle")
end

-- Widget update (called each frame)
function widget:Update()
    --if initialized and visible then
    --    updateDataModel()
    --end
end

-- RML event handlers (referenced in the template)
function widget:ToggleTurboBarCam()
    if WG.TurboBarCam and WG.TurboBarCam.UI and WG.TurboBarCam.UI.ToggleTurboBarCam then
        WG.TurboBarCam.UI.ToggleTurboBarCam()
        -- Update UI after toggle
        Spring.SetTimer(0.1, updateDataModel)
    else
        Spring.Echo("[TurboBarCam UI] Could not toggle TurboBarCam - UI functions not loaded")
    end
end

function widget:ToggleMode(mode)
    if mode and WG.TurboBarCam and WG.TurboBarCam.UI and WG.TurboBarCam.UI.ToggleMode then
        WG.TurboBarCam.UI.ToggleMode(mode)
        -- Update UI after toggle
        Spring.SetTimer(0.1, updateDataModel)
    else
        Spring.Echo("[TurboBarCam UI] Could not toggle mode - TurboBarCam not enabled or mode invalid")
    end
end

-- Widget enable/disable events
function widget:Enable()
    if document then
        document:Show()
        visible = true
        updateDataModel()
    end
end

function widget:Disable()
    if document then
        document:Hide()
        visible = false
    end
end

-- Handle widget toggle command
function widget:CommandNotify(cmd)
    if cmd == "togglewidget" then
        toggleUI()
        return true
    end
    return false
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

    -- Remove the shortcut
    Spring.SendCommands("unbind " .. SHORTCUT_KEY .. " luaui togglewidget TurboBarCam UI")
end