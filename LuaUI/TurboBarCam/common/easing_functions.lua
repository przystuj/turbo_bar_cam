---@class EasingFunctions
local EasingFunctions = {}

function EasingFunctions.linear(t)
    return t
end

function EasingFunctions.easeIn(t)
    return t * t * t
end

function EasingFunctions.easeOut(t)
    local t2 = t - 1
    return t2 * t2 * t2 + 1
end

function EasingFunctions.easeInOut(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local t2 = (t - 1)
        return 1 + 4 * t2 * t2 * t2
    end
end

-- Aliases
EasingFunctions["none"] = EasingFunctions.linear
EasingFunctions["in"] = EasingFunctions.easeIn
EasingFunctions["out"] = EasingFunctions.easeOut
EasingFunctions["inout"] = EasingFunctions.easeInOut

return EasingFunctions