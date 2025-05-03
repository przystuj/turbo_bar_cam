---@class EasingFunctions
local EasingFunctions = {}

-- Basic easing functions
EasingFunctions.linear = function(t) return t end

-- Cubic easing functions (smoother than quadratic)
EasingFunctions.easeIn = function(t) return t * t * t end
EasingFunctions.easeOut = function(t)
    local t2 = t - 1
    return t2 * t2 * t2 + 1
end
EasingFunctions.easeInOut = function(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local t2 = (t - 1)
        return 1 + 4 * t2 * t2 * t2
    end
end

-- Camera-specific functions
EasingFunctions.preserveVelocityAtBoundaries = function(t)
    -- Linear interpolation at boundaries to prevent zero velocity
    if t < 0.1 then
        return t * 10  -- Linear for first 10%
    elseif t > 0.9 then
        return 0.9 + (t - 0.9) * 10  -- Linear for last 10%
    else
        -- Smooth in the middle
        local adjusted = (t - 0.1) / 0.8
        return 0.1 + adjusted * adjusted * (3 - 2 * adjusted) * 0.8
    end
end

return {
    EasingFunctions = EasingFunctions
}