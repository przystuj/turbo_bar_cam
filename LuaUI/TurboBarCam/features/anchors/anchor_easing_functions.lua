---@class EasingFunctions
local EasingFunctions = {}

EasingFunctions["none"] = function(t) return t end

EasingFunctions["in"] = function(t) return t * t * t end

EasingFunctions["out"] = function(t)
    local t2 = t - 1
    return t2 * t2 * t2 + 1
end

EasingFunctions["inout"] = function(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local t2 = (t - 1)
        return 1 + 4 * t2 * t2 * t2
    end
end

return {
    EasingFunctions = EasingFunctions
}