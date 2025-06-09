---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end)

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------
---@class Utils
local Utils = {}

function Utils.isTurboBarCamDisabled()
    if not STATE.enabled then
        Log:trace("TurboBarCam must be enabled first. Use /turbobarcam_toggle")
        return true
    end
end

---@param mode 'unit_follow'|'unit_tracking'|'orbit'|'overview'
function Utils.isModeDisabled(mode)
    if mode == "global" and STATE.active.mode.name then
        return true
    end
    if mode ~= "global" and STATE.active.mode.name ~= mode then
        return true
    end
end

--- Splits a string path by a delimiter.
-- @param path The string path to split (e.g., "A.B.C").
-- @param delimiter The character to split by (defaults to ".").
-- @return A table containing the path segments.
function Utils.splitPath(path, delimiter)
    delimiter = delimiter or "."
    local segments = {}
    -- Use gmatch to find all sequences of characters that are not the delimiter
    for segment in string.gmatch(path, "([^" .. delimiter .. "]+)") do
        table.insert(segments, segment)
    end
    return segments
end

return Utils