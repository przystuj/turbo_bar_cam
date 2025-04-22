-- TurboBarCam UI Parameters Module

-- Load utils
local scriptPath = LUAUI_DIRNAME .. "RmlWidgets/gui_turbobarcam/"
local utils = VFS.Include(scriptPath .. "utils.lua")
local bindings = VFS.Include(scriptPath .. "bindings.lua")

local params = {}

-- Parameter definitions for each mode's adjust params
params.MODE_PARAMS = {
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

-- Get parameters for the current mode
function params.getParameters(CONFIG, mode)
    local parameters = {}
    
    -- If no mode or is "None", return empty array
    if not mode or mode == "None" or not WG.TurboBarCam or not WG.TurboBarCam.CONFIG then
        return parameters
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
        return parameters
    end
    
    -- Get the configuration for this mode
    local config = WG.TurboBarCam.CONFIG.CAMERA_MODES[internalMode]
    if not config then
        return parameters
    end
    
    -- Get parameter definitions
    local paramDefs = WG.TurboBarCam.PARAM_DEFS and WG.TurboBarCam.PARAM_DEFS[string.upper(internalMode)]
    
    -- For each parameter in the config
    for paramName, paramValue in pairs(config) do
        -- Skip tables (nested params will be handled separately)
        if type(paramValue) ~= "table" then
            -- Get param boundaries from definition or use defaults
            local min, max, step = -2000, 3000, 1
            local key = ""
            
            -- Check if we have param definitions
            if paramDefs and paramDefs.PARAM_NAMES and paramDefs.PARAM_NAMES[paramName] then
                local def = paramDefs.PARAM_NAMES[paramName]
                if def[1] ~= nil then min = def[1] end
                if def[2] ~= nil then max = def[2] end
                
                -- Special case for small values
                if min > -1 and max < 1 then
                    step = 0.001
                elseif min > -10 and max < 10 then
                    step = 0.01
                end
                
                -- Handle radians differently
                if def[3] == "rad" then
                    step = 0.01
                end
            end
            
            -- Get associated hotkey if available
            local paramId = internalMode .. "." .. paramName
            if bindings.PARAM_HOTKEYS[paramId] and bindings.PARAM_HOTKEYS[paramId][1] then
                key = bindings.PARAM_HOTKEYS[paramId][1]
            end
            
            -- Add parameter to list
            table.insert(parameters, {
                id = paramId,
                name = utils.getDisplayName(paramName),
                value = paramValue,
                min = min,
                max = max,
                step = step,
                key = key
            })
        end
    end
    
    -- Handle nested parameters (like SMOOTHING)
    for paramName, paramValue in pairs(config) do
        if type(paramValue) == "table" then
            for subParamName, subParamValue in pairs(paramValue) do
                -- Skip tables (we only go one level deep)
                if type(subParamValue) ~= "table" then
                    -- Get param boundaries from definition or use defaults
                    local min, max, step = -2000, 3000, 1
                    local key = ""
                    
                    -- Check if we have param definitions
                    local fullParamName = paramName .. "." .. subParamName
                    if paramDefs and paramDefs.PARAM_NAMES and paramDefs.PARAM_NAMES[fullParamName] then
                        local def = paramDefs.PARAM_NAMES[fullParamName]
                        if def[1] ~= nil then min = def[1] end
                        if def[2] ~= nil then max = def[2] end
                        
                        -- Special case for small values
                        if min > -1 and max < 1 then
                            step = 0.001
                        elseif min > -10 and max < 10 then
                            step = 0.01
                        end
                        
                        -- Handle radians differently
                        if def[3] == "rad" then
                            step = 0.01
                        end
                    end
                    
                    -- Get associated hotkey if available
                    local paramId = internalMode .. "." .. fullParamName
                    if bindings.PARAM_HOTKEYS[paramId] and bindings.PARAM_HOTKEYS[paramId][1] then
                        key = bindings.PARAM_HOTKEYS[paramId][1]
                    end
                    
                    -- Add parameter to list
                    table.insert(parameters, {
                        id = paramId,
                        name = utils.getDisplayName(fullParamName),
                        value = subParamValue,
                        min = min,
                        max = max,
                        step = step,
                        key = key
                    })
                end
            end
        end
    end
    
    return parameters
end

-- Update a specific parameter in the TurboBarCam config
function params.updateParameter(widget, paramId, value)
    if not WG.TurboBarCam or not WG.TurboBarCam.CONFIG then
        Spring.Echo("[TurboBarCam UI] Cannot update parameter - TurboBarCam config not found")
        return
    end
    
    -- Parse the parameter ID to get mode and parameter name
    local mode, paramName = paramId:match("([^%.]+)%.(.+)")
    if not mode or not paramName then
        Spring.Echo("[TurboBarCam UI] Invalid parameter ID: " .. paramId)
        return
    end
    
    -- Get the config for this mode
    local config = WG.TurboBarCam.CONFIG.CAMERA_MODES[mode]
    if not config then
        Spring.Echo("[TurboBarCam UI] Config not found for mode: " .. mode)
        return
    end
    
    -- Convert value to number
    value = tonumber(value)
    if not value then
        Spring.Echo("[TurboBarCam UI] Invalid value for parameter: " .. value)
        return
    end
    
    -- Update the parameter - handle nested parameters
    local parts = {}
    for part in paramName:gmatch("[^%.]+") do
        table.insert(parts, part)
    end
    
    if #parts == 1 then
        -- Direct parameter
        config[paramName] = value
    elseif #parts == 2 then
        -- Nested parameter
        if not config[parts[1]] then 
            config[parts[1]] = {} 
        end
        config[parts[1]][parts[2]] = value
    end
    
    -- Trigger update
    widget:RefreshBindings()
    
    Spring.Echo("[TurboBarCam UI] Updated parameter: " .. paramId .. " = " .. value)
end

-- Reset a specific parameter to its default
function params.resetParameter(widget, paramId)
    if not WG.TurboBarCam or not WG.TurboBarCam.CONFIG then
        Spring.Echo("[TurboBarCam UI] Cannot reset parameter - TurboBarCam config not found")
        return
    end
    
    -- Parse the parameter ID to get mode and parameter name
    local mode, paramName = paramId:match("([^%.]+)%.(.+)")
    if not mode or not paramName then
        Spring.Echo("[TurboBarCam UI] Invalid parameter ID: " .. paramId)
        return
    end
    
    -- Check if we have default values from PARAM_DEFS
    if WG.TurboBarCam.PARAM_DEFS and WG.TurboBarCam.PARAM_DEFS[string.upper(mode)] then
        local paramDefs = WG.TurboBarCam.PARAM_DEFS[string.upper(mode)]
        if paramDefs.PARAMS_ROOT then
            local defaultValue = nil
            
            -- Handle nested parameters
            local parts = {}
            for part in paramName:gmatch("[^%.]+") do
                table.insert(parts, part)
            end
            
            if #parts == 1 then
                -- Try to get default value
                defaultValue = paramDefs.PARAMS_ROOT[paramName]
            elseif #parts == 2 then
                -- Try to get nested default value
                if paramDefs.PARAMS_ROOT[parts[1]] then
                    defaultValue = paramDefs.PARAMS_ROOT[parts[1]][parts[2]]
                end
            end
            
            if defaultValue ~= nil then
                -- Update the parameter with default value
                params.updateParameter(widget, paramId, defaultValue)
                return
            end
        end
    end
    
    -- If we don't have a default value, reset to 0 or other reasonable default
    local reasonable_default = 0
    
    -- For some params we can guess better defaults
    if paramName:find("HEIGHT") then
        reasonable_default = 250
    elseif paramName:find("DISTANCE") then
        reasonable_default = 500
    elseif paramName:find("SPEED") then
        reasonable_default = 0.001
    elseif paramName:find("ROTATION") or paramName:find("OFFSET") then
        reasonable_default = 0
    elseif paramName:find("SMOOTHING") then
        reasonable_default = 0.01
    end
    
    params.updateParameter(widget, paramId, reasonable_default)
end

-- Reset all parameters for the current mode
function params.resetAllParameters(widget, STATE)
    local currentMode = STATE and STATE.tracking and STATE.tracking.mode or "None"
    if currentMode == "None" then
        Spring.Echo("[TurboBarCam UI] No active mode to reset parameters")
        return
    end
    
    -- Get parameters for the current mode
    local parameters = params.getParameters(WG.TurboBarCam.CONFIG, bindings.availableModes[currentMode])
    
    -- Reset each parameter
    for _, param in ipairs(parameters) do
        params.resetParameter(widget, param.id)
    end
    
    Spring.Echo("[TurboBarCam UI] Reset all parameters for mode: " .. currentMode)
end

return params