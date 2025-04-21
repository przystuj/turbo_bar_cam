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
        layer = 2, -- High layer to be on top
        enabled = true
    }
end

local MODEL_NAME = "turbobarcam_model"
local document
local dm_handle
local initialized = false
local visible = false
local rmlContext

-- Widget initialization
function widget:Initialize()

    -- Get RmlUi context through widget
    rmlContext = RmlUi.GetContext("shared")

    if not rmlContext then
        return false
    end

    -- Open data model first
    local dmHandle = rmlContext:OpenDataModel(MODEL_NAME, {})

    if not dmHandle then
        return false
    end

    -- Load the document (passing the widget for events)
    document = rmlContext:LoadDocument("LuaUI/RmlWidgets/gui_turbobarcam/gui_turbobarcam.rml", widget)

    if not document then
        rmlContext:RemoveDataModel(MODEL_NAME)
        return false
    end

    -- Setup document
    document:ReloadStyleSheet()

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