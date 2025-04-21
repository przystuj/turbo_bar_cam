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

---@class TurboBarCamUI
local TurboBarCamUI = {
    initialized = false,
    visible = false,
    document = nil,
    rmlContext = nil,
    dataModelHandle = nil,

    -- Data model
    model = {
        status = "Disabled",
        isEnabled = false,
        currentMode = "None",
        currentModeActions = "No Active Mode",
        availableModes = {},
        modeActions = {},
        savedAnchors = {},
        hasAnchors = false
    },

    -- Constants
    MAIN_MODEL_NAME = "turbobarcam_model",

    -- Available modes definition
    modesInfo = {
        fps = "FPS Camera",
        unit_tracking = "Unit Tracking",
        orbit = "Orbit Camera",
        overview = "Overview",
        group_tracking = "Group Tracking",
        projectile_camera = "Projectile Camera"
    }
}

-- Initialize the UI module
function TurboBarCamUI.initialize()
    -- Get RmlUi context
    TurboBarCamUI.rmlContext = RmlUi.GetContext("shared")

    if not TurboBarCamUI.rmlContext then
        Log.info("[UI] Failed to get RmlUi context")
        return false
    end

    widget.rmlContext = RmlUi.GetContext("TurboBarCam")

    -- Initialize data model
    TurboBarCamUI.dataModelHandle = TurboBarCamUI.rmlContext:OpenDataModel(TurboBarCamUI.MAIN_MODEL_NAME, TurboBarCamUI.model)

    if not TurboBarCamUI.dataModelHandle then
        Log.info("[UI] Failed to open data model " .. TurboBarCamUI.MAIN_MODEL_NAME)
        return false
    end

    -- Load the document
    TurboBarCamUI.document = TurboBarCamUI.rmlContext:LoadDocument("LuaUI/TurboBarCam/ui/rml/ui_template.rml", widget)

    if not TurboBarCamUI.document then
        Log.info("[UI] Failed to load UI document")
        TurboBarCamUI.rmlContext:RemoveDataModel(TurboBarCamUI.MAIN_MODEL_NAME)
        return false
    end

    -- Prepare and load initial data
    TurboBarCamUI.loadKeyBindings()
    TurboBarCamUI.updateDataModel()

    -- Reload stylesheet and show document
    TurboBarCamUI.document:ReloadStyleSheet()

    -- Initially hide the UI
    TurboBarCamUI.document:Hide()
    TurboBarCamUI.visible = false

    TurboBarCamUI.initialized = true
    return true
end

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
        if string.find(actionName, "turbobarcam_") then
            -- Store the key binding
            TurboBarCamUI.keyBinds[actionName] = TurboBarCamUI.keyBinds[actionName] or {}
            table.insert(TurboBarCamUI.keyBinds[actionName], keyCombo)
        end
    end
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
        TurboBarCamUI.document.visible = TurboBarCamUI.visible

        if TurboBarCamUI.visible then
            -- Update UI when showing
            TurboBarCamUI.update()
        end
    end
end

-- Update the UI with current TurboBarCam state
function TurboBarCamUI.update()
    if not TurboBarCamUI.initialized or not TurboBarCamUI.visible or not TurboBarCamUI.document then
        return
    end

    -- Update status and toggle button
    local statusElement = TurboBarCamUI.document:GetElementById("status-text")
    local toggleButton = TurboBarCamUI.document:GetElementById("toggle-button")

    if STATE.enabled then
        statusElement.inner_rml = "Enabled"
        statusElement.class_name = "status-enabled"
        toggleButton.inner_rml = "Disable TurboBarCam"
    else
        statusElement.inner_rml = "Disabled"
        statusElement.class_name = "status-disabled"
        toggleButton.inner_rml = "Enable TurboBarCam"
    end

    -- Update current mode
    local currentMode = STATE.tracking.mode or "None"
    TurboBarCamUI.document:GetElementById("current-mode").inner_rml = currentMode ~= "None"
            and (TurboBarCamUI.availableModes[currentMode] or currentMode)
            or "None"

    -- Update mode actions header
    TurboBarCamUI.document:GetElementById("current-mode-actions").inner_rml = currentMode ~= "None"
            and (TurboBarCamUI.availableModes[currentMode] or currentMode)
            or "No Active Mode"

    -- Update available modes
    local modesHtml = ""
    for modeKey, modeName in pairs(TurboBarCamUI.availableModes) do
        local isActive = currentMode == modeKey
        local modeClass = isActive and "btn active" or "btn"

        -- Find the key binding for toggling this mode
        local toggleAction = "turbobarcam_toggle_" .. modeKey

        local keyBindText = ""
        if TurboBarCamUI.keyBinds[toggleAction] and TurboBarCamUI.keyBinds[toggleAction][1] then
            keyBindText = " [" .. TurboBarCamUI.keyBinds[toggleAction][1] .. "]"
        end

        modesHtml = modesHtml ..
                '<div class="' .. modeClass .. '" onclick="TurboBarCamUI.ToggleMode(\'' .. modeKey .. '\')">' ..
                modeName .. keyBindText ..
                '</div>'
    end

    TurboBarCamUI.document:GetElementById("available-modes").inner_rml = modesHtml

    -- Update mode actions
    local actionsHtml = ""

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

                    actionsHtml = actionsHtml ..
                            '<div class="action">' ..
                            '<span>' .. actionDisplay .. '</span>' ..
                            '<span class="action-key">' .. keyBind .. '</span>' ..
                            '</div>'
                end
            end
        end
    end

    if actionsHtml == "" then
        actionsHtml = '<div>No actions available for this mode</div>'
    end

    TurboBarCamUI.document:GetElementById("mode-actions").inner_rml = actionsHtml

    -- Update saved anchors
    local anchorsHtml = ""
    local hasAnchors = false

    -- Loop through potential anchors (0-9)
    for i = 0, 9 do
        if STATE.anchors[i] then
            hasAnchors = true

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

            anchorsHtml = anchorsHtml ..
                    '<div class="anchor-item">' ..
                    'Anchor ' .. i ..
                    (focusKeyBind ~= "" and ' <span class="action-key">' .. focusKeyBind .. '</span>' or '') ..
                    '</div>'
        end
    end

    if not hasAnchors then
        anchorsHtml = '<div>No anchors saved</div>'
    end

    TurboBarCamUI.document:GetElementById("saved-anchors").inner_rml = anchorsHtml
end

-- Shutdown function
function TurboBarCamUI.shutdown()
    if TurboBarCamUI.initialized and TurboBarCamUI.document then
        TurboBarCamUI.rml.RemoveDocument(TurboBarCamUI.document)
        TurboBarCamUI.document = nil
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
