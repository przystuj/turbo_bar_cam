---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local WidgetManager = ModuleManager.WidgetManager(function(m) WidgetManager = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "ScriptRunner")

---@class ScriptRunner
local ScriptRunner = {}

---@class ScriptStep
---@field commands string|string[]
---@field timestamp string
---@field frame number
---@field isDone boolean


local gameFps = Game.gameSpeed

local function safeNum(str)
    return tonumber(str) or 0
end

local function timestampToSeconds(timestamp)
    local parts = string.split(timestamp, ':')
    if #parts == 1 then
        total = safeNum(parts[1]) -- seconds only
    elseif #parts == 2 then
        total = safeNum(parts[1]) * 60 + safeNum(parts[2]) -- also minutes
    elseif #parts == 3 then
        total = safeNum(parts[1]) * 3600 + safeNum(parts[2]) * 60 + safeNum(parts[3]) -- also hours
    else
        Log:error("Invalid timestamp: " .. timestamp)
        return
    end
    return total
end

local function start(isFinal)
    ---@type ScriptStep[]
    local script = VFS.Include("LuaUI/TurboBarCam/script.lua")

    if not script then
        Log:error("LuaUI/TurboBarCam/script.lua not found")
    end

    local currentFrame = Spring.GetGameFrame()
    local currentStep = 1
    local lastStepFrame = 0

    for _, step in ipairs(script) do
        if step.timestamp and step.timestamp:match("[^%d:]") then
            Log:error("Invalid timestamp format. Only numbers and colons allowed (e.g., 10:30): " .. step.timestamp)
            return
        end

        if not step.timestamp and not step.frame then
            Log:error("Either frame or timestamp has to be set")
            return
        end

        if step.timestamp then
            step.frame = timestampToSeconds(step.timestamp) * gameFps
        end

        if step.frame:sub(1, 1) == "+" then
            step.frame = tonumber(step.frame:sub(2) + lastStepFrame)
        else
            step.frame = tonumber(step.frame)
        end

        if step.frame < lastStepFrame then
            Log:error("Inconsistent timeline detected", step)
        end
        lastStepFrame = step.frame

        if step.frame < currentFrame and type(step.commands) == "string" and not step.commands:match("^skip ") then
            step.isDone = true
            currentStep = currentStep + 1
        end
    end

    if currentStep > #script then
        Log:info("Script is already completed")
        return
    end

    STATE.core.scriptRunner.script = script
    STATE.core.scriptRunner.enabled = true
    STATE.core.scriptRunner.stepsCount = #script
    STATE.core.scriptRunner.currentStep = currentStep
    Log:info("Script enabled")
    if currentFrame < 1 then
        Spring.SendCommands("forcestart")
        Spring.SendCommands("skip 1")
    end
    if isFinal == "true" then
        STATE.core.scriptRunner.isFinal = true
        Spring.SendCommands("HideInterface")
        Spring.SendCommands("togglewidget Hide Cursor")
    end
end

local function stop()
    STATE.core.scriptRunner.enabled = false
    STATE.core.scriptRunner.script = nil
    STATE.core.scriptRunner.stepsCount = 0
    STATE.core.scriptRunner.currentStep = 0
end

function ScriptRunner.toggle(isFinal)
    if Utils.isTurboBarCamDisabled() then
        WidgetManager.enable()
    end

    if STATE.core.scriptRunner.enabled then
        stop()
    else
        start(isFinal)
    end
end

function ScriptRunner.togglePlayersList(team)
    if Utils.isTurboBarCamDisabled() then
        return false
    end

    if team == "A" then
        STATE.core.scriptRunner.showTeamA = not STATE.core.scriptRunner.showTeamA
    elseif team == "B" then
        STATE.core.scriptRunner.showTeamB = not STATE.core.scriptRunner.showTeamB
    else
        STATE.core.scriptRunner.showPlayers = not STATE.core.scriptRunner.showPlayers
        STATE.core.scriptRunner.showTeamA = STATE.core.scriptRunner.showPlayers
        STATE.core.scriptRunner.showTeamB = STATE.core.scriptRunner.showPlayers
    end

    Log:debug("Show player list: ", STATE.core.scriptRunner.showPlayers, STATE.core.scriptRunner.showTeamA, STATE.core.scriptRunner.showTeamB)
end

--- skip to the next step
---@param delay number How many frames before next step it should stop
function ScriptRunner.fastForward(delay)
    if Utils.isTurboBarCamDisabled() then
        return false
    end

    delay = tonumber(delay) or 60

    local nextStepFrame = STATE.core.scriptRunner.script[STATE.core.scriptRunner.currentStep].frame

    Spring.SendCommands("skip f" .. nextStepFrame - delay)
end

function ScriptRunner.selectUnit(unitId)
    if Utils.isTurboBarCamDisabled() then
        return false
    end

    Spring.SelectUnit(unitId)
    Log:debug("Selected unit", unitId)
end

function ScriptRunner.playTrack(trackPath)
    if Utils.isTurboBarCamDisabled() then
        return false
    end

    WG['music'].playTrack(trackPath)
end

function ScriptRunner.toggleMusic()
    if Utils.isTurboBarCamDisabled() then
        return false
    end
    Spring.PauseSoundStream()
end

function ScriptRunner.update(frame)
    if not STATE.core.scriptRunner.enabled then
        return
    end

    ---@type ScriptStep[]
    local script = STATE.core.scriptRunner.script

    for _, step in ipairs(script) do
        if not step.isDone and step.frame <= frame then
            if type(step.commands) == "string" then
                Spring.SendCommands(step.commands)
            else
                for _, command in ipairs(step.commands) do
                    Spring.SendCommands(command)
                end
            end
            step.isDone = true
            STATE.core.scriptRunner.currentStep = STATE.core.scriptRunner.currentStep + 1
        end
    end

    if STATE.core.scriptRunner.currentStep > STATE.core.scriptRunner.stepsCount then
        Log:info("Script finished")
        stop()
    end
end

return ScriptRunner
