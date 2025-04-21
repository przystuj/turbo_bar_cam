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

-- Save a local reference to widget.rmlContext for use throughout the module
local rmlContext = nil

-- Initialize the UI module
function TurboBarCamUI.initialize()
    if TurboBarCamUI.initialized then
        return true
    end

    -- Get RmlUi context through widget
    rmlContext = RmlUi.GetContext("shared")

    if not rmlContext then
        Log.info("[UI] Failed to get RmlUi context")
        return false
    end

    -- Open data model first
    local dmHandle = rmlContext:OpenDataModel(TurboBarCamUI.MAIN_MODEL_NAME, initialModel)

    if not dmHandle then
        Log.info("[UI] Failed to open data model " .. TurboBarCamUI.MAIN_MODEL_NAME)
        return false
    end

    -- Load the document (passing the widget for events)
    TurboBarCamUI.document = rmlContext:LoadDocument("LuaUI/TurboBarCam/ui/rml/ui_template.rml", widget)

    if not TurboBarCamUI.document then
        Log.info("[UI] Failed to load UI document")
        rmlContext:RemoveDataModel(TurboBarCamUI.MAIN_MODEL_NAME)
        return false
    end

    -- Setup document
    TurboBarCamUI.document:ReloadStyleSheet()

    TurboBarCamUI.initialized = true
    Log.info("[UI] TurboBarCam UI initialized - press Ctrl+Shift+T to toggle")
    return true
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

-- Shutdown function
function TurboBarCamUI.shutdown()
    if TurboBarCamUI.initialized then
        if TurboBarCamUI.document then
            TurboBarCamUI.document:Close()
            TurboBarCamUI.document = nil
        end

        if rmlContext then
            rmlContext:RemoveDataModel(TurboBarCamUI.MAIN_MODEL_NAME)
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
