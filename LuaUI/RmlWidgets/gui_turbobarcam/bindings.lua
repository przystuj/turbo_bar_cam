-- TurboBarCam UI Bindings Module

-- Load utils
local scriptPath = LUAUI_DIRNAME .. "RmlWidgets/gui_turbobarcam/"
local utils = VFS.Include(scriptPath .. "utils.lua")

local bindings = {}

-- Available camera modes with display names
bindings.availableModes = {
    fps = "FPS Camera",
    unit_tracking = "Unit Tracking",
    orbit = "Orbit Camera",
    overview = "Overview",
    group_tracking = "Group Tracking",
    projectile = "Projectile Camera"
}

-- Action prefixes for different camera modes
bindings.MODE_ACTION_PREFIXES = {
    fps = "turbobarcam_fps_",
    unit_tracking = "turbobarcam_unit_tracking_",
    orbit = "turbobarcam_orbit_",
    overview = "turbobarcam_overview_",
    group_tracking = "turbobarcam_group_tracking_",
    projectile = "turbobarcam_projectile_"
}

-- Actions we want to display for each mode (priority order)
bindings.MODE_IMPORTANT_ACTIONS = {
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

-- Direct lookup table from uikeys.txt
bindings.KEY_LOOKUP = {
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
bindings.PARAM_ADJUSTMENTS = {
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

-- Lookup table for parameter-specific hotkeys
bindings.PARAM_HOTKEYS = {
    -- FPS
    ["fps.HEIGHT"] = { "Ctrl+numpad8", "Ctrl+numpad5" },
    ["fps.FORWARD"] = { "numpad8", "numpad5" },
    ["fps.SIDE"] = { "numpad6", "numpad4" },
    ["fps.ROTATION"] = { "numpad9", "numpad7" },

    -- Orbit
    ["orbit.HEIGHT"] = { "numpad6", "numpad4", "numpad5", "numpad8" },
    ["orbit.DISTANCE"] = { "numpad5", "numpad8" },
    ["orbit.SPEED"] = { "numpad9", "numpad7" },

    -- Unit tracking
    ["unit_tracking.HEIGHT"] = { "numpad8", "numpad5" },

    -- Group tracking
    ["group_tracking.EXTRA_DISTANCE"] = { "numpad5", "numpad8" },
    ["group_tracking.EXTRA_HEIGHT"] = { "numpad5", "numpad8" },
    ["group_tracking.ORBIT_OFFSET"] = { "numpad6", "numpad4" },
    ["group_tracking.SMOOTHING.POSITION"] = { "numpad9", "numpad7" },
    ["group_tracking.SMOOTHING.ROTATION"] = { "numpad9", "numpad7" },
    ["group_tracking.SMOOTHING.STABLE_POSITION"] = { "numpad9", "numpad7" },
    ["group_tracking.SMOOTHING.STABLE_ROTATION"] = { "numpad9", "numpad7" },

    -- Projectile
    ["projectile.DISTANCE"] = { "numpad8", "numpad5" },
    ["projectile.HEIGHT"] = { "numpad6", "numpad4" },
    ["projectile.LOOK_AHEAD"] = { "numpad9", "numpad7" }
}

-- Helper function to parse param adjustments
function bindings.parseParamAdjustment(adjustString, currentMode)
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

    -- Load parameter definitions
    local params = VFS.Include(scriptPath .. "parameters.lua")

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

            -- Get parameter metadata
            local modeParams = params.MODE_PARAMS[currentMode]
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
function bindings.getKeyBindForAction(action)
    -- Try Spring's action hotkeys first
    local keys = Spring.GetActionHotKeys(action)
    if keys and #keys > 0 then
        return keys[1]
    end

    -- Fall back to our lookup table
    local key = bindings.KEY_LOOKUP[action]
    if key then
        -- If it's a table, return the first one
        if type(key) == "table" then
            return key[1]
        end
        return key
    end

    return "Not bound"
end

-- Get active mode keybinds with smart fallbacks
function bindings.getActiveModeMappings(STATE, mode)
    local mappings = {}

    -- Add toggle TurboBarCam first
    mappings[#mappings + 1] = {
        name = "Toggle TurboBarCam",
        key = bindings.getKeyBindForAction("turbobarcam_toggle"),
        param = ""
    }

    mappings[#mappings + 1] = {
        name = "Toggle UI",
        key = bindings.getKeyBindForAction("turbobarcam_toggle_ui"),
        param = ""
    }

    -- Add zoom toggle only if TurboBarCam is enabled
    if STATE and STATE.enabled then
        mappings[#mappings + 1] = {
            name = "Toggle Zoom",
            key = bindings.getKeyBindForAction("turbobarcam_toggle_zoom"),
            param = ""
        }
    end

    -- If no mode or is "None", just return common controls
    if not mode or mode == "None" then
        return mappings
    end

    -- Find internal mode name
    local internalMode = nil
    for modeKey, modeName in pairs(bindings.availableModes) do
        if modeName == mode then
            internalMode = modeKey
            break
        end
    end

    if not internalMode then
        return mappings
    end

    -- Get important actions for this mode
    local modeActions = bindings.MODE_IMPORTANT_ACTIONS[internalMode]
    if modeActions then
        for _, actionSuffix in ipairs(modeActions) do
            local fullAction = "turbobarcam_" .. actionSuffix
            local keyBind = bindings.getKeyBindForAction(fullAction)

            -- Handle adjust params differently - we want to display them with details
            if actionSuffix:find("adjust_params") then
                -- Check each key possibility for this action
                local keys = (type(bindings.KEY_LOOKUP[fullAction]) == "table") and bindings.KEY_LOOKUP[fullAction] or { keyBind }

                -- Add an entry for each key that adjusts params
                for _, key in ipairs(keys) do
                    local adjustKey = key .. "|" .. fullAction
                    local adjustParams = bindings.PARAM_ADJUSTMENTS[adjustKey]

                    if adjustParams then
                        -- Parse the adjustment to get a readable description
                        local paramDesc = bindings.parseParamAdjustment(adjustParams, internalMode)

                        -- Only add if we have a valid keybind and description
                        if key ~= "Not bound" and paramDesc then
                            mappings[#mappings + 1] = {
                                name = utils.getPrettyActionName(fullAction),
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
                        name = utils.getPrettyActionName(fullAction),
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

return bindings