-- TurboBarCam UI Utilities Module

local utils = {}

-- Helper function to get pretty action name
function utils.getPrettyActionName(actionName)
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

-- Format a parameter name for display
function utils.getDisplayName(paramName)
    -- Replace underscores with spaces
    local name = paramName:gsub("_", " ")
    
    -- Replace dots with spaces
    name = name:gsub("%.", " ")
    
    -- Capitalize first letter of each word
    name = name:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest
    end)
    
    return name
end

return utils