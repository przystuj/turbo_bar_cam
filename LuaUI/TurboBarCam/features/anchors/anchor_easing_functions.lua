-- todo EasingFunctions
--accelerate and decelerate work the other way around
--
--these do not work - camera stutters and rubberbands
--    easeInOutBack
--    easeInOutElastic
--    easeOutBounce
--    easeInOutBounce

---@class EasingFunctions
local EasingFunctions = {}

-- Basic easing functions
EasingFunctions.linear = function(t) return t end

-- Quadratic functions
EasingFunctions.accelerate = function(t) return t * t end  -- Quadratic ease-in
EasingFunctions.decelerate = function(t) return 1 - (1 - t) * (1 - t) end  -- Quadratic ease-out
EasingFunctions.smooth = function(t) return t * t * (3 - 2 * t) end  -- Smoothstep

-- Cubic functions
EasingFunctions.easeInCubic = function(t) return t * t * t end
EasingFunctions.easeOutCubic = function(t)
    local t2 = t - 1
    return t2 * t2 * t2 + 1
end
EasingFunctions.easeInOutCubic = function(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local t2 = (t - 1)
        return 1 + 4 * t2 * t2 * t2
    end
end

-- Quadratic functions
EasingFunctions.easeInQuad = function(t) return t * t end
EasingFunctions.easeOutQuad = function(t) return t * (2 - t) end
EasingFunctions.easeInOutQuad = function(t)
    if t < 0.5 then
        return 2 * t * t
    else
        return 1 - (-2 * t + 2) ^ 2 / 2
    end
end

-- Quartic functions
EasingFunctions.easeInOutQuart = function(t)
    if t < 0.5 then
        return 8 * t * t * t * t
    else
        local t2 = (-2 * t + 2)
        return 1 - t2 * t2 * t2 * t2 / 2
    end
end

-- Special easing functions
EasingFunctions.easeInOutBack = function(t)
    local c1 = 1.70158
    local c2 = c1 * 1.525

    if t < 0.5 then
        return (2 * t) ^ 2 * ((c2 + 1) * 2 * t - c2) / 2
    else
        return ((2 * t - 2) ^ 2 * ((c2 + 1) * (t * 2 - 2) + c2) + 2) / 2
    end
end

-- Elastic ease for more dramatic effects
EasingFunctions.easeInOutElastic = function(t)
    local c5 = (2 * math.pi) / 4.5

    if t == 0 then
        return 0
    elseif t == 1 then
        return 1
    elseif t < 0.5 then
        return -(2^(20 * t - 10) * math.sin((20 * t - 11.125) * c5)) / 2
    else
        return (2^(-20 * t + 10) * math.sin((20 * t - 11.125) * c5)) / 2 + 1
    end
end

-- Bounce effect
EasingFunctions.easeOutBounce = function(t)
    local n1 = 7.5625
    local d1 = 2.75

    if t < 1 / d1 then
        return n1 * t * t
    elseif t < 2 / d1 then
        t = t - 1.5 / d1
        return n1 * t * t + 0.75
    elseif t < 2.5 / d1 then
        t = t - 2.25 / d1
        return n1 * t * t + 0.9375
    else
        t = t - 2.625 / d1
        return n1 * t * t + 0.984375
    end
end

EasingFunctions.easeInOutBounce = function(t)
    if t < 0.5 then
        return (1 - EasingFunctions.easeOutBounce(1 - 2 * t)) / 2
    else
        return (1 + EasingFunctions.easeOutBounce(2 * t - 1)) / 2
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

--- Get predefined speed control presets
---@param presetName string Name of the preset
---@return table|nil speedControls Speed control points or nil if preset not found
function EasingFunctions.getPresetSpeedControls(presetName)
    ---@class SpeedProfiles
    local presets = {
        -- Constant speed
        constant = {
            {time = 0.0, speed = 1.0},
            {time = 1.0, speed = 1.0}
        },

        -- Accelerate: start slow, end fast
        accelerate = {
            {time = 0.0, speed = 0.5},  -- Start at half speed
            {time = 0.8, speed = 2.0},  -- End at double speed
            {time = 1.0, speed = 2.0}
        },

        -- Decelerate: start fast, end slow
        decelerate = {
            {time = 0.0, speed = 2.0},  -- Start at double speed
            {time = 0.2, speed = 2.0},
            {time = 1.0, speed = 0.5}   -- End at half speed
        },

        -- Emphasis at middle
        emphasizeMiddle = {
            {time = 0.0, speed = 1.0},   -- Normal start
            {time = 0.4, speed = 0.5},   -- Slow in middle
            {time = 0.6, speed = 0.5},   -- Slow in middle
            {time = 1.0, speed = 1.0}    -- Normal end
        },

        -- Dramatic with several peaks and valleys
        dramatic = {
            {time = 0.0, speed = 1.0},
            {time = 0.2, speed = 2.0},   -- Fast
            {time = 0.3, speed = 0.5},   -- Slow
            {time = 0.5, speed = 1.5},   -- Medium-fast
            {time = 0.7, speed = 0.3},   -- Very slow
            {time = 0.9, speed = 2.0},   -- Fast
            {time = 1.0, speed = 0.7}    -- Medium-slow at end
        },

        -- Smooth acceleration and deceleration
        smooth = {
            {time = 0.0, speed = 0.7},   -- Start slightly slower
            {time = 0.2, speed = 1.0},   -- Accelerate to normal
            {time = 0.5, speed = 1.3},   -- Slightly faster in middle
            {time = 0.8, speed = 1.0},   -- Back to normal
            {time = 1.0, speed = 0.7}    -- End slightly slower
        },

        -- Cinematic slow reveal
        cinematicReveal = {
            {time = 0.0, speed = 0.3},   -- Very slow start
            {time = 0.3, speed = 0.5},   -- Gradual increase
            {time = 0.7, speed = 1.2},   -- Building momentum
            {time = 0.9, speed = 1.5},   -- Fast near end
            {time = 1.0, speed = 1.0}    -- Normal at end
        },

        -- Highlight waypoints with dramatic pauses
        dramatic2 = {
            {time = 0.0, speed = 1.5},   -- Fast start
            {time = 0.2, speed = 0.2},   -- Dramatic slowdown
            {time = 0.4, speed = 1.5},   -- Speed up
            {time = 0.6, speed = 0.2},   -- Another dramatic slowdown
            {time = 0.8, speed = 1.5},   -- Speed up
            {time = 1.0, speed = 0.2}    -- End with slowdown
        },

        -- Pulse effect with rhythmic speed changes
        pulse = {
            {time = 0.0, speed = 1.0},
            {time = 0.1, speed = 1.5},
            {time = 0.2, speed = 0.8},
            {time = 0.3, speed = 1.5},
            {time = 0.4, speed = 0.8},
            {time = 0.5, speed = 1.5},
            {time = 0.6, speed = 0.8},
            {time = 0.7, speed = 1.5},
            {time = 0.8, speed = 0.8},
            {time = 0.9, speed = 1.5},
            {time = 1.0, speed = 1.0}
        }
    }

    return presets[presetName]
end

return {
    EasingFunctions = EasingFunctions
}