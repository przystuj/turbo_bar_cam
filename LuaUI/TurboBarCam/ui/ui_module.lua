---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Log = CommonModules.Log
local Util = CommonModules.Util

-- Check if RmlUi is available
if not RmlUi then
    Log.info("RmlUi not available, UI module will not initialize")
    return {
        TurboBarCamUI = {
            initialize = function()
                return false
            end,
            update = function()
            end,
            toggle = function()
            end,
            shutdown = function()
            end
        }
    }
end

local widget = widget

---@class TurboBarCamUI
local TurboBarCamUI = {
    initialized = false,
    visible = false,
    document = nil,

    -- Constants
    MAIN_MODEL_NAME = "turbobarcam_ui_model", -- Changed to avoid conflict

    -- Available modes definition
    availableModes = {
        fps = "FPS Camera",
        unit_tracking = "Unit Tracking",
        orbit = "Orbit Camera",
        overview = "Overview",
        group_tracking = "Group Tracking",
        projectile_camera = "Projectile Camera"
    },

    -- Key bindings storage
    keyBinds = {}
}

-- Initialize model data
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
function TurboBarCamUI.loadKeyBindings()
    TurboBarCamUI.keyBinds = {}

    -- Retrieve the key binds from Spring
    local rawBinds = Spring.GetKeyBindings()

    -- Process each bind
    for _, bind in ipairs(rawBinds) do
        local actionName = bind[1]
        local keyCombo = bind[2]

        -- Only consider TurboBarCam actions
        if actionName and string.find(actionName, "turbobarcam_") then
            -- Store the key binding
            TurboBarCamUI.keyBinds[actionName] = TurboBarCamUI.keyBinds[actionName] or {}
            table.insert(TurboBarCamUI.keyBinds[actionName], keyCombo)
        end
    end
end

-- Initialize the UI module
function TurboBarCamUI.initialize()
    if TurboBarCamUI.initialized then
        return true
    end

    -- Get RmlUi context through widget
    widget.rmlContext = RmlUi.GetContext("shared")

    if not widget.rmlContext then
        Log.info("[UI] Failed to get RmlUi context")
        return false
    end

    -- Prepare and load initial data
    TurboBarCamUI.loadKeyBindings()

    -- Open data model first
    local dmHandle = widget.rmlContext:OpenDataModel(TurboBarCamUI.MAIN_MODEL_NAME, initialModel)

    if not dmHandle then
        Log.info("[UI] Failed to open data model " .. TurboBarCamUI.MAIN_MODEL_NAME)
        return false
    end

    -- Load the document (passing the widget for events)
    TurboBarCamUI.document = widget.rmlContext:LoadDocument("LuaUI/TurboBarCam/ui/rml/ui_template.rml", widget)

    if not TurboBarCamUI.document then
        Log.info("[UI] Failed to load UI document")
        widget.rmlContext:RemoveDataModel(TurboBarCamUI.MAIN_MODEL_NAME)
        return false
    end

    -- Update the document with current state
    TurboBarCamUI.updateDataModel(dmHandle)

    -- Setup document
    TurboBarCamUI.document:ReloadStyleSheet()
    TurboBarCamUI.document:Hide() -- Start hidden
    TurboBarCamUI.visible = false

    TurboBarCamUI.initialized = true
    return true
end

-- Update data model with current TurboBarCam state
function TurboBarCamUI.updateDataModel(dm_handle)
    if not TurboBarCamUI.initialized then
        return
    end

    -- Get the handle if not provided
    local handle = dm_handle or widget.rmlContext:GetDataModel(TurboBarCamUI.MAIN_MODEL_NAME)
    if not handle then return end

    -- Build model
    local model = {}

    -- Update status
    model.isEnabled = STATE.enabled
    model.status = STATE.enabled and "Enabled" or "Disabled"

    -- Update current mode
    local currentMode = STATE.tracking.mode or "None"
    model.currentMode = currentMode ~= "None"
            and (TurboBarCamUI.availableModes[currentMode] or currentMode)
            or "None"

    -- Update mode actions header
    model.currentModeActions = currentMode ~= "None"
            and (TurboBarCamUI.availableModes[currentMode] or currentMode)
            or "No Active Mode"

    -- Update available modes
    model.availableModes = {}
    for modeKey, modeName in pairs(TurboBarCamUI.availableModes) do
        local isActive = currentMode == modeKey

        -- Find the key binding for toggling this mode
        local toggleAction = "turbobarcam_toggle_" .. modeKey
        if modeKey == "unit_tracking" then
            toggleAction = "turbobarcam_toggle_tracking_camera"
        end

        local keyBind = ""
        if TurboBarCamUI.keyBinds[toggleAction] and TurboBarCamUI.keyBinds[toggleAction][1] then
            keyBind = TurboBarCamUI.keyBinds[toggleAction][1]
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
        for actionName, keyBinds in pairs(TurboBarCamUI.keyBinds) do
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
    for i = 0, 9 do
        if STATE.anchors[i] then
            model.hasAnchors = true

            -- Find keybinding for focusing this anchor
            local focusKeyBind = ""
            local focusAction = "turbobarcam_anchor_focus"

            if TurboBarCamUI.keyBinds[focusAction] then
                for _, bind in ipairs(TurboBarCamUI.keyBinds[focusAction]) do
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

    -- Update the data model
    handle:UpdateValues(model)
end

-- Toggle UI visibility
function TurboBarCamUI.toggle()
    if not TurboBarCamUI.initialized then
        if not TurboBarCamUI.initialize() then
            return
        end
    end

    TurboBarCamUI.visible = not TurboBarCamUI.visible

    if TurboBarCamUI.document then
        if TurboBarCamUI.visible then
            TurboBarCamUI.update()
            TurboBarCamUI.document:Show()
        else
            TurboBarCamUI.document:Hide()
        end
    end
end

-- Update function to be called from the update manager
function TurboBarCamUI.update()
    if TurboBarCamUI.initialized and TurboBarCamUI.visible then
        -- Update data model
        TurboBarCamUI.updateDataModel()
    end
end

-- RML event handlers (referenced in the template)
function widget:ToggleTurboBarCam()
    if CoreModules and CoreModules.WidgetControl then
        CoreModules.WidgetControl.toggle()
        TurboBarCamUI.update() -- Update UI immediately after toggle
    else
        Log.info("[UI] Could not toggle TurboBarCam - WidgetControl not loaded")
    end
end

function widget:ToggleMode(mode)
    if mode and STATE.enabled then
        local actionName = "turbobarcam_toggle_" .. mode

        -- Special case for unit_tracking
        if mode == "unit_tracking" then
            actionName = "turbobarcam_toggle_tracking_camera"
        end

        -- Execute the action through Spring
        Spring.SendCommands(actionName)

        -- Update the UI after a short delay to allow state to update
        Spring.SetTimer(0.1, function() TurboBarCamUI.update() end)
    else
        Log.info("[UI] Could not toggle mode - TurboBarCam not enabled or mode invalid")
    end
end

-- Shutdown function
function TurboBarCamUI.shutdown()
    if TurboBarCamUI.initialized then
        if TurboBarCamUI.document then
            TurboBarCamUI.document:Close()
            TurboBarCamUI.document = nil
        end

        if widget.rmlContext then
            widget.rmlContext:RemoveDataModel(TurboBarCamUI.MAIN_MODEL_NAME)
        end
    end

    TurboBarCamUI.initialized = false
end

-- Export UI module
return {
    TurboBarCamUI = TurboBarCamUI,
    initialize = TurboBarCamUI.initialize,
    update = TurboBarCamUI.update,
    toggle = TurboBarCamUI.toggle,
    shutdown = TurboBarCamUI.shutdown
}
