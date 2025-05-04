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

EasingFunctions.smoothVelocity = function(t)
    -- Ease-in at the start (slower)
    if t < 0.3 then
        return t * t * (3 - 2 * t) -- Smoothstep for first 30%
        -- Ease-out at the end (slower)
    elseif t > 0.7 then
        local u = 1 - t
        local v = 1 - 0.7
        return 1 - (u * u * (3 - 2 * u) / v) * 0.3
        -- Linear in the middle (faster)
    else
        return 0.3 + (t - 0.3) * (0.4 / 0.4) -- Linear for middle 40%
    end
end

EasingFunctions.cameraCurve = function(t)
    -- Ensure t is within bounds
    t = math.max(0, math.min(1, t))

    -- Use a sigmoid-like function for smooth acceleration/deceleration
    -- This creates an S-curve with continuous derivatives at boundaries
    if t < 0.5 then
        return 0.5 * (2*t)^2
    else
        local t2 = 2 * (t - 0.5)
        return 0.5 + 0.5 * (1 - (1-t2)^2)
    end
end

return {
    EasingFunctions = EasingFunctions
}