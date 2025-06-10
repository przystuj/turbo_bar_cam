---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "SpecGroups")

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
---@param groupId string Group id
---@return boolean success Whether the group was set successfully
function SpecGroups.set(groupId)
    -- Validate input
    if not groupId then
        Log:debug("Invalid group id.")
        return false
    end

    -- Get currently selected units
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits == 0 then
        Log:debug("No units selected to add to group " .. groupId)
        return false
    end

    -- Store the selected units in the group
    STATE.specGroups.groups[groupId] = selectedUnits

    Log:debug("Added " .. #selectedUnits .. " units to spectator group " .. groupId)
    return true
end

--- Selects units from a spectator unit group
---@param groupId string Group id
---@return boolean success Whether the group selection was successful
function SpecGroups.select(groupId)

    -- Validate input
    if not groupId then
        Log:debug("Invalid group id.")
        return false
    end

    -- Check if the group exists
    if not STATE.specGroups.groups[groupId] or #STATE.specGroups.groups[groupId] == 0 then
        Log:debug("Spectator group " .. groupId .. " is empty")
        return false
    end

    -- Filter valid units
    local validUnits = {}
    for _, unitID in ipairs(STATE.specGroups.groups[groupId]) do
        if Spring.ValidUnitID(unitID) then
            table.insert(validUnits, unitID)
        end
    end

    -- Update the group with only valid units
    STATE.specGroups.groups[groupId] = validUnits

    -- If no valid units remain, report it
    if #validUnits == 0 then
        Log:debug("No valid units remain in spectator group " .. groupId)
        return false
    end

    -- Select the units
    Spring.SelectUnitArray(validUnits)

    Log:debug("Selected " .. #validUnits .. " units from spectator group " .. groupId)
    return true
end

--- Clears a spectator unit group
---@param groupId string Group id
---@return boolean success Whether the group was cleared successfully
function SpecGroups.clear(groupId)

    -- Validate input
    if not groupId then
        Log:debug("Invalid group id.")
        return false
    end

    -- Clear the group
    STATE.specGroups.groups[groupId] = {}

    Log:debug("Cleared spectator group " .. groupId)
    return true
end

--- Handles spectator unit group commands
---@param action string Command parameters
---@param groupId string Group id
---@return boolean success Always returns true for widget handler
function SpecGroups.handleCommand(action, groupId)
    if not groupId then
        Log:debug("Invalid group id.")
        return true
    end

    if action == "set" then
        SpecGroups.set(groupId)
    elseif action == "select" then
        SpecGroups.select(groupId)
    elseif action == "clear" then
        SpecGroups.clear(groupId)
    else
        Log:debug("Unknown action. Use 'set', 'select', or 'clear'")
    end

    return true
end

return SpecGroups