if not RmlUi then
    return
end

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

local STATE

local availableModes = {
    fps = "FPS Camera",
    unit_tracking = "Unit Tracking",
    orbit = "Orbit Camera",
    overview = "Overview",
    group_tracking = "Group Tracking",
    projectile = "Projectile Camera"
}

-- Action prefixes for different camera modes
local MODE_ACTION_PREFIXES = {
    fps = "turbobarcam_fps_",
    unit_tracking = "turbobarcam_unit_tracking_",
    orbit = "turbobarcam_orbit_",
    overview = "turbobarcam_overview_",
    group_tracking = "turbobarcam_group_tracking_",
    projectile = "turbobarcam_projectile_"
}

-- Actions we want to display for each mode (priority order)
local MODE_IMPORTANT_ACTIONS = {
    fps = {
        "toggle_fps_camera",
        "fps_adjust_params",
        "fps_set_fixed_look_point",
        "fps_clear_fixed_look_point",
        "fps_next_weapon",
        "fps_clear_weapon_selection"
    },
    unit_tracking = {
        "toggle_unit_tracking",
        "unit_tracking_adjust_params"
    },
    orbit = {
        "toggle_orbit",
        "orbit_adjust_params"
    },
    overview = {
        "overview_toggle",
        "overview_change_height"
    },
    group_tracking = {
        "toggle_group_tracking_camera",
        "group_tracking_adjust_params"
    },
    projectile = {
        "projectile_camera_follow",
        "projectile_camera_track",
        "projectile_adjust_params"
    }
}

-- Parameter definitions for each mode's adjust params
local MODE_PARAMS = {
    fps = {
        HEIGHT = { direction = "vertical", units = "distance" },
        FORWARD = { direction = "forward", units = "distance" },
        SIDE = { direction = "horizontal", units = "distance" },
        ROTATION = { direction = "rotation", units = "rad" },
        WEAPON_HEIGHT = { direction = "vertical", units = "distance", target = "weapon" },
        WEAPON_FORWARD = { direction = "forward", units = "distance", target = "weapon" },
        WEAPON_SIDE = { direction = "horizontal", units = "distance", target = "weapon" },
        WEAPON_ROTATION = { direction = "rotation", units = "rad", target = "weapon" }
    },
    orbit = {
        HEIGHT = { direction = "vertical", units = "distance" },
        DISTANCE = { direction = "distance", units = "distance" },
        SPEED = { direction = "speed", units = "rotation" }
    },
    unit_tracking = {
        HEIGHT = { direction = "vertical", units = "distance" }
    },
    group_tracking = {
        EXTRA_DISTANCE = { direction = "distance", units = "distance" },
        EXTRA_HEIGHT = { direction = "vertical", units = "distance" },
        ORBIT_OFFSET = { direction = "rotation", units = "rad" },
        ["SMOOTHING.POSITION"] = { direction = "smoothing", target = "position" },
        ["SMOOTHING.ROTATION"] = { direction = "smoothing", target = "rotation" },
        ["SMOOTHING.STABLE_POSITION"] = { direction = "smoothing", target = "stable position" },
        ["SMOOTHING.STABLE_ROTATION"] = { direction = "smoothing", target = "stable rotation" }
    },
    projectile = {
        DISTANCE = { direction = "distance", units = "distance" },
        HEIGHT = { direction = "vertical", units = "distance" },
        LOOK_AHEAD = { direction = "forward", units = "distance", target = "look point" }
    }
}

-- Direct lookup table from uikeys.txt
local KEY_LOOKUP = {
    -- Common controls
    ["turbobarcam_toggle"] = "numpad.",
    ["turbobarcam_toggle_ui"] = "Ctrl+]",
    ["turbobarcam_toggle_zoom"] = "Home",

    -- FPS mode
    ["turbobarcam_toggle_fps_camera"] = "numpad1",
    ["turbobarcam_fps_adjust_params"] = { "numpad8", "numpad5", "numpad6", "numpad4", "numpad7", "numpad9", "Ctrl+numpad8", "Ctrl+numpad5" },
    ["turbobarcam_fps_clear_fixed_look_point"] = "numpad*",
    ["turbobarcam_fps_set_fixed_look_point"] = "numpad/",
    ["turbobarcam_fps_clear_weapon_selection"] = "End",
    ["turbobarcam_fps_next_weapon"] = "PageDown",

    -- Unit Tracking
    ["turbobarcam_toggle_unit_tracking"] = "numpad3",
    ["turbobarcam_unit_tracking_adjust_params"] = { "numpad8", "numpad5", "Ctrl+numpad3" },

    -- Orbit
    ["turbobarcam_toggle_orbit"] = "numpad2",
    ["turbobarcam_orbit_adjust_params"] = { "numpad5", "numpad8", "numpad6", "numpad4", "numpad9", "numpad7" },

    -- Overview
    ["turbobarcam_overview_toggle"] = "PageUp",
    ["turbobarcam_overview_change_height"] = { "numpad8", "numpad5" },

    -- Group tracking
    ["turbobarcam_toggle_group_tracking_camera"] = "numpad0",
    ["turbobarcam_group_tracking_adjust_params"] = { "numpad5", "numpad8", "numpad6", "numpad4", "numpad7", "numpad9", "Ctrl+numpad0" },

    -- Projectile
    ["turbobarcam_projectile_camera_follow"] = "Delete",
    ["turbobarcam_projectile_camera_track"] = "Insert",
    ["turbobarcam_projectile_adjust_params"] = { "numpad8", "numpad5", "numpad9", "numpad7", "numpad6", "numpad4" }
}

-- Lookup table for parameter adjustments from uikeys.txt
local PARAM_ADJUSTMENTS = {
    -- FPS
    ["numpad8|turbobarcam_fps_adjust_params"] = "add;FORWARD,15;HEIGHT,-3",
    ["numpad5|turbobarcam_fps_adjust_params"] = "add;FORWARD,-15;HEIGHT,3",
    ["Ctrl+numpad8|turbobarcam_fps_adjust_params"] = "add;HEIGHT,5",
    ["Ctrl+numpad5|turbobarcam_fps_adjust_params"] = "add;HEIGHT,-5",
    ["numpad6|turbobarcam_fps_adjust_params"] = "add;SIDE,5",
    ["numpad4|turbobarcam_fps_adjust_params"] = "add;SIDE,-5",
    ["numpad7|turbobarcam_fps_adjust_params"] = "add;ROTATION,-0.1",
    ["numpad9|turbobarcam_fps_adjust_params"] = "add;ROTATION,0.1",

    -- Unit tracking
    ["numpad8|turbobarcam_unit_tracking_adjust_params"] = "add;HEIGHT,20",
    ["numpad5|turbobarcam_unit_tracking_adjust_params"] = "add;HEIGHT,-20",
    ["Ctrl+numpad3|turbobarcam_unit_tracking_adjust_params"] = "reset",

    -- Orbit
    ["numpad5|turbobarcam_orbit_adjust_params"] = "add;HEIGHT,5;DISTANCE,10",
    ["numpad8|turbobarcam_orbit_adjust_params"] = "add;HEIGHT,-5;DISTANCE,-10",
    ["numpad6|turbobarcam_orbit_adjust_params"] = "add;HEIGHT,5",
    ["numpad4|turbobarcam_orbit_adjust_params"] = "add;HEIGHT,-5",
    ["numpad9|turbobarcam_orbit_adjust_params"] = "add;SPEED,0.0001",
    ["numpad7|turbobarcam_orbit_adjust_params"] = "add;SPEED,-0.0001",

    -- Overview
    ["numpad8|turbobarcam_overview_change_height"] = "1",
    ["numpad5|turbobarcam_overview_change_height"] = "-1",

    -- Group tracking
    ["numpad5|turbobarcam_group_tracking_adjust_params"] = "add;EXTRA_DISTANCE,15;EXTRA_HEIGHT,5",
    ["numpad8|turbobarcam_group_tracking_adjust_params"] = "add;EXTRA_DISTANCE,-15;EXTRA_HEIGHT,-5",
    ["numpad6|turbobarcam_group_tracking_adjust_params"] = "add;ORBIT_OFFSET,0.1",
    ["numpad4|turbobarcam_group_tracking_adjust_params"] = "add;ORBIT_OFFSET,-0.1",
    ["numpad7|turbobarcam_group_tracking_adjust_params"] = "add;SMOOTHING.POSITION,-0.002;SMOOTHING.ROTATION,-0.001;SMOOTHING.STABLE_POSITION,-0.002;SMOOTHING.STABLE_ROTATION,-0.001",
    ["numpad9|turbobarcam_group_tracking_adjust_params"] = "add;SMOOTHING.POSITION,0.002;SMOOTHING.ROTATION,0.001;SMOOTHING.STABLE_POSITION,0.002;SMOOTHING.STABLE_ROTATION,0.001",
    ["Ctrl+numpad0|turbobarcam_group_tracking_adjust_params"] = "reset",

    -- Projectile
    ["numpad8|turbobarcam_projectile_adjust_params"] = "add;DISTANCE,-5",
    ["numpad5|turbobarcam_projectile_adjust_params"] = "add;DISTANCE,5",
    ["numpad9|turbobarcam_projectile_adjust_params"] = "add;LOOK_AHEAD,5",
    ["numpad7|turbobarcam_projectile_adjust_params"] = "add;LOOK_AHEAD,-5",
    ["numpad6|turbobarcam_projectile_adjust_params"] = "add;HEIGHT,5",
    ["numpad4|turbobarcam_projectile_adjust_params"] = "add;HEIGHT,-5"
}

-- Helper function to parse param adjustments
local function parseParamAdjustment(adjustString)
    if not adjustString then
        return nil
    end

    -- Check for reset
    if adjustString == "reset" then
        return "Reset all parameters"
    end

    -- Parse the add command
    local parts = {}
    local commands = {}

    -- First split by semicolons to get each command
    for cmd in adjustString:gmatch("[^;]+") do
        table.insert(parts, cmd)
    end

    -- First part should be "add"
    if parts[1] ~= "add" then
        return nil
    end

    -- Parse each parameter adjustment
    for i = 2, #parts do
        local paramName, value = parts[i]:match("([^,]+),([^,]+)")
        if paramName and value then
            local direction = ""
            local numVal = tonumber(value)

            if numVal > 0 then
                direction = "Increase"
            elseif numVal < 0 then
                direction = "Decrease"
            end

            -- Get the mode from the current context
            local currentMode = STATE and STATE.tracking and STATE.tracking.mode or "None"

            -- Get parameter metadata
            local modeParams = MODE_PARAMS[currentMode]
            local paramInfo = modeParams and modeParams[paramName]

            if paramInfo then
                local paramText = ""

                -- Build description based on parameter direction and target
                if paramInfo.target then
                    paramText = direction .. " " .. paramInfo.target .. " " .. paramInfo.direction
                else
                    paramText = direction .. " " .. paramInfo.direction
                end

                -- For rotations with rad units, make it more readable
                if paramInfo.units == "rad" then
                    if numVal > 0 then
                        paramText = "Rotate right"
                    else
                        paramText = "Rotate left"
                    end
                end

                table.insert(commands, paramText)
            else
                -- Fallback if parameter info not found
                table.insert(commands, direction .. " " .. paramName)
            end
        end
    end

    -- Return a comma-separated list of adjustments
    return table.concat(commands, ", ")
end

-- Get key bindings for actions from Spring and fallback to our lookup
local function GetKeyBindForAction(action)
    -- Try Spring's action hotkeys first
    local keys = Spring.GetActionHotKeys(action)
    if keys and #keys > 0 then
        return keys[1]
    end

    -- Fall back to our lookup table
    local key = KEY_LOOKUP[action]
    if key then
        -- If it's a table, return the first one
        if type(key) == "table" then
            return key[1]
        end
        return key
    end

    return "Not bound"
end

-- Helper function to get pretty action name
local function getPrettyActionName(actionName)
    -- Strip prefix and replace underscores with spaces
    local baseAction = actionName:gsub("turbobarcam_", "")

    -- Make parameters look better
    baseAction = baseAction:gsub("adjust_params", "adjust")

    -- Replace underscores with spaces and capitalize first letter of each word
    baseAction = baseAction:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest
    end)

    return baseAction
end

-- Debug function to dump all bindings
function widget:DumpBindings()
    Spring.Echo("[TurboBarCam UI] Dumping all TurboBarCam bindings")

    -- Check our internal lookup table
    Spring.Echo("1. Internal lookup table actions:")
    for action, _ in pairs(KEY_LOOKUP) do
        Spring.Echo("  " .. action)
    end

    -- First try using GetActionHotKeys with our lookup
    Spring.Echo("2. Using Spring.GetActionHotKeys with our lookup:")
    for action, _ in pairs(KEY_LOOKUP) do
        local keys = Spring.GetActionHotKeys(action)
        local keyStr = "none"
        if keys and #keys > 0 then
            keyStr = table.concat(keys, ", ")
        end
        Spring.Echo("  " .. action .. " -> " .. keyStr)
    end

    -- Also check GetKeyBindings
    Spring.Echo("3. Using Spring.GetKeyBindings:")
    local keyBinds = Spring.GetKeyBindings()
    if keyBinds then
        local turboBinds = {}
        for _, binding in ipairs(keyBinds) do
            if binding.action and binding.action:find("turbobarcam_") == 1 then
                table.insert(turboBinds, binding)
                Spring.Echo("  " .. binding.command .. " -> " .. binding.action)
            end
        end
        Spring.Echo("  Found " .. #turboBinds .. " TurboBarCam bindings")
    else
        Spring.Echo("  GetKeyBindings returned nil")
    end

    -- Dump some parameter adjustments
    Spring.Echo("4. Checking parameter adjustments:")
    for key, adjustment in pairs(PARAM_ADJUSTMENTS) do
        local actionKey, actionName = key:match("([^|]+)|(.+)")
        if actionKey and actionName then
            local parsedAdj = parseParamAdjustment(adjustment)
            Spring.Echo("  " .. actionKey .. " -> " .. (parsedAdj or "Unknown"))
        end
    end

end


-- Get active mode keybinds with smart fallbacks
local function getActiveModeMappings(mode)
    local mappings = {}

    -- Add toggle TurboBarCam first
    mappings[#mappings + 1] = {
        name = "Toggle TurboBarCam",
        key = GetKeyBindForAction("turbobarcam_toggle"),
        param = ""
    }

    mappings[#mappings + 1] = {
        name = "Toggle UI",
        key = GetKeyBindForAction("turbobarcam_toggle_ui"),
        param = ""
    }

    -- Add zoom toggle only if TurboBarCam is enabled
    if STATE and STATE.enabled then
        mappings[#mappings + 1] = {
            name = "Toggle Zoom",
            key = GetKeyBindForAction("turbobarcam_toggle_zoom"),
            param = ""
        }

    end


    -- If no mode or is "None", just return common controls
    if not mode or mode == "None" then
        return mappings
    end

    -- Find internal mode name
    local internalMode = nil
    for modeKey, modeName in pairs(availableModes) do
        if modeName == mode then
            internalMode = modeKey
            break
        end
    end

    if not internalMode then
        return mappings
    end

    -- Get important actions for this mode
    local modeActions = MODE_IMPORTANT_ACTIONS[internalMode]
    if modeActions then
        for _, actionSuffix in ipairs(modeActions) do
            local fullAction = "turbobarcam_" .. actionSuffix
            local keyBind = GetKeyBindForAction(fullAction)

            -- Handle adjust params differently - we want to display them with details
            if actionSuffix:find("adjust_params") then
                -- Check each key possibility for this action
                local keys = (type(KEY_LOOKUP[fullAction]) == "table") and KEY_LOOKUP[fullAction] or { keyBind }

                -- Add an entry for each key that adjusts params
                for _, key in ipairs(keys) do
                    local adjustKey = key .. "|" .. fullAction
                    local adjustParams = PARAM_ADJUSTMENTS[adjustKey]

                    if adjustParams then
                        -- Parse the adjustment to get a readable description
                        local paramDesc = parseParamAdjustment(adjustParams)

                        -- Only add if we have a valid keybind and description
                        if key ~= "Not bound" and paramDesc then
                            mappings[#mappings + 1] = {
                                name = getPrettyActionName(fullAction),
                                key = key,
                                param = paramDesc
                            }

                            -- Limit to max of 10 bindings total
                            if #mappings >= 10 then
                                break
                            end
                        end
                    end
                end
            else
                -- Regular action without parameters
                if keyBind ~= "Not bound" then
                    mappings[#mappings + 1] = {
                        name = getPrettyActionName(fullAction),
                        key = keyBind,
                        param = ""
                    }

                    -- Limit to max of 10 bindings total
                    if #mappings >= 10 then
                        break
                    end
                end
            end
        end
    end

    return mappings
end

-- Update data model with current TurboBarCam state and keybindings
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

    -- Get bindings for the current mode
    local bindings = getActiveModeMappings(dm_handle.currentMode)

    -- Update the bindings in the data model
    for i = 1, 10 do
        dm_handle["binding" .. i .. "name"] = ""
        dm_handle["binding" .. i .. "key"] = ""
        dm_handle["binding" .. i .. "param"] = ""
    end

    -- Set the bindings we found
    for i = 1, math.min(10, #bindings) do
        dm_handle["binding" .. i .. "name"] = bindings[i].name
        dm_handle["binding" .. i .. "key"] = bindings[i].key
        dm_handle["binding" .. i .. "param"] = bindings[i].param or ""
    end

    -- Debug print
    Spring.Echo("[TurboBarCam UI] Updated data model. Mode: " .. dm_handle.currentMode .. ", Bindings: " .. #bindings)
end

-- Widget initialization
function widget:Initialize()
    -- Get RmlUi context through widget
    widget.rmlContext = RmlUi.CreateContext("turbobarcam_ui")

    if not widget.rmlContext then
        Spring.Echo("[TurboBarCam UI] Failed to create RmlUi context")
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
        -- Binding placeholders
        binding1name = "",
        binding1key = "",
        binding1param = "",
        binding2name = "",
        binding2key = "",
        binding2param = "",
        binding3name = "",
        binding3key = "",
        binding3param = "",
        binding4name = "",
        binding4key = "",
        binding4param = "",
        binding5name = "",
        binding5key = "",
        binding5param = "",
        binding6name = "",
        binding6key = "",
        binding6param = "",
        binding7name = "",
        binding7key = "",
        binding7param = "",
        binding8name = "",
        binding8key = "",
        binding8param = "",
        binding9name = "",
        binding9key = "",
        binding9param = "",
        binding10name = "",
        binding10key = "",
        binding10param = ""
    })

    if not dm_handle then
        Spring.Echo("[TurboBarCam UI] Failed to open data model")
        return false
    end

    -- Load the document (passing the widget for events)
    document = widget.rmlContext:LoadDocument("LuaUI/RmlWidgets/gui_turbobarcam/rml/gui_turbobarcam.rml", widget)

    if not document then
        Spring.Echo("[TurboBarCam UI] Failed to load document")
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

    Spring.Echo("[TurboBarCam UI] Initialized successfully")

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
    Spring.Echo("[TurboBarCam UI] Shutdown complete")
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