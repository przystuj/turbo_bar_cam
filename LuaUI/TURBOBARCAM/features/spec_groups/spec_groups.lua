-- Spectator Groups module for TURBOBARCAM
-- Load modules
---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TURBOBARCAM/common.lua")

local CONFIG = WidgetContext.WidgetConfig.CONFIG
local STATE = WidgetContext.WidgetState.STATE
local Util = CommonModules.Util

---@class SpecGroups
local SpecGroups = {}

--- Checks if the player is currently spectating
---@return boolean isSpectator Whether the player is spectating
function SpecGroups.checkSpectatorStatus()
    -- Check if we're a spectator
    local _, _, spec = Spring.GetPlayerInfo(Spring.GetMyPlayerID())
    STATE.specGroups.isSpectator = spec
    return spec
end

--- Sets a spectator unit group
---@param groupNum number Group number (1-9)
---@return boolean success Whether the group was set successfully
function SpecGroups.set(groupNum)
    -- Convert to number
    groupNum = tonumber(groupNum)

    -- Validate input
    if not groupNum or groupNum < 1 or groupNum > CONFIG.SPEC_GROUPS.MAX_GROUPS then
        Util.debugEcho("Invalid group number. Use 1-" .. CONFIG.SPEC_GROUPS.MAX_GROUPS)
        return false
    end

    -- Check if we're in spectator mode
    if not SpecGroups.checkSpectatorStatus() then
        Util.debugEcho("Spectator unit groups only available when spectating")
        return false
    end

    -- Get currently selected units
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits == 0 then
        Util.debugEcho("No units selected to add to group " .. groupNum)
        return false
    end

    -- Store the selected units in the group
    STATE.specGroups.groups[groupNum] = selectedUnits

    Util.debugEcho("Added " .. #selectedUnits .. " units to spectator group " .. groupNum)
    return true
end

--- Selects units from a spectator unit group
---@param groupNum number Group number (1-9)
---@return boolean success Whether the group selection was successful
function SpecGroups.select(groupNum)
    -- Convert to number
    groupNum = tonumber(groupNum)

    -- Validate input
    if not groupNum or groupNum < 1 or groupNum > CONFIG.SPEC_GROUPS.MAX_GROUPS then
        Util.debugEcho("Invalid group number. Use 1-" .. CONFIG.SPEC_GROUPS.MAX_GROUPS)
        return false
    end

    -- Check if we're in spectator mode
    if not SpecGroups.checkSpectatorStatus() then
        Util.debugEcho("Spectator unit groups only available when spectating")
        return false
    end

    -- Check if the group exists
    if not STATE.specGroups.groups[groupNum] or #STATE.specGroups.groups[groupNum] == 0 then
        Util.debugEcho("Spectator group " .. groupNum .. " is empty")
        return false
    end

    -- Filter valid units
    local validUnits = {}
    for _, unitID in ipairs(STATE.specGroups.groups[groupNum]) do
        if Spring.ValidUnitID(unitID) then
            table.insert(validUnits, unitID)
        end
    end

    -- Update the group with only valid units
    STATE.specGroups.groups[groupNum] = validUnits

    -- If no valid units remain, report it
    if #validUnits == 0 then
        Util.debugEcho("No valid units remain in spectator group " .. groupNum)
        return false
    end

    -- Select the units
    Spring.SelectUnitArray(validUnits)

    Util.debugEcho("Selected " .. #validUnits .. " units from spectator group " .. groupNum)
    return true
end

--- Clears a spectator unit group
---@param groupNum number Group number (1-9)
---@return boolean success Whether the group was cleared successfully
function SpecGroups.clear(groupNum)
    -- Convert to number
    groupNum = tonumber(groupNum)

    -- Validate input
    if not groupNum or groupNum < 1 or groupNum > CONFIG.SPEC_GROUPS.MAX_GROUPS then
        Util.debugEcho("Invalid group number. Use 1-" .. CONFIG.SPEC_GROUPS.MAX_GROUPS)
        return false
    end

    -- Clear the group
    STATE.specGroups.groups[groupNum] = {}

    Util.debugEcho("Cleared spectator group " .. groupNum)
    return true
end

--- Handles spectator unit group commands
---@param params string Command parameters
---@return boolean success Always returns true for widget handler
function SpecGroups.handleCommand(params)
    local action, groupNum = params:match("(%a+)%s+(%d+)")
    if not action or not groupNum then
        Util.debugEcho("Usage: /spec_unit_group [set|select|clear] [1-" .. CONFIG.SPEC_GROUPS.MAX_GROUPS .. "]")
        return true
    end

    groupNum = tonumber(groupNum)

    if not groupNum or groupNum < 1 or groupNum > CONFIG.SPEC_GROUPS.MAX_GROUPS then
        Util.debugEcho("Invalid group number. Use 1-" .. CONFIG.SPEC_GROUPS.MAX_GROUPS)
        return true
    end

    if action == "set" then
        SpecGroups.set(groupNum)
    elseif action == "select" then
        SpecGroups.select(groupNum)
    elseif action == "clear" then
        SpecGroups.clear(groupNum)
    else
        Util.debugEcho("Unknown action. Use 'set', 'select', or 'clear'")
    end

    return true
end

return {
    SpecGroups = SpecGroups
}