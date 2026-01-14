---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local WidgetManager = ModuleManager.WidgetManager(function(m) WidgetManager = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "ScriptRunner")

---@class ScriptRunner
local ScriptRunner = {}

---@class ScriptStep
---@field commands string
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

local function start()
    ---@type ScriptStep[]
    local script = VFS.Include("LuaUI/TurboBarCam/script.lua")
    local currentFrame = Spring.GetGameFrame()
    local currentStep = 1
    local message = ""

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

        message = message .. step.frame .. ": " .. step.commands
        step.frame = tonumber(step.frame)
        if step.frame < currentFrame then
            step.isDone = true
            currentStep = currentStep + 1
            message = message .. " (skipped)"
        end
        message = message .. "\n"
    end

    if currentStep > #script then
        Log:info("Script is already completed")
        return
    end

    STATE.core.scriptRunner.script = script
    STATE.core.scriptRunner.enabled = true
    STATE.core.scriptRunner.stepsCount = #script
    STATE.core.scriptRunner.currentStep = currentStep
    Log:info("Script enabled\n" .. message)
    if currentFrame < 1 then
        Spring.SendCommands("forcestart")
        Spring.SendCommands("skip 1")
    end
    Spring.SendCommands("HideInterface")
end

local function stop()
    STATE.core.scriptRunner.enabled = false
    STATE.core.scriptRunner.script = nil
    STATE.core.scriptRunner.stepsCount = 0
    STATE.core.scriptRunner.currentStep = 0
end

function ScriptRunner.toggle()
    if Utils.isTurboBarCamDisabled() then
        WidgetManager.enable()
    end

    if STATE.core.scriptRunner.enabled then
        stop()
    else
        start()
    end
end

function ScriptRunner.togglePlayersList()
    if Utils.isTurboBarCamDisabled() then
        return false
    end

    STATE.core.scriptRunner.showPlayers = not STATE.core.scriptRunner.showPlayers
    Log:debug("Show player list: ", STATE.core.scriptRunner.showPlayers)
end

function ScriptRunner.update(frame)
    if not STATE.core.scriptRunner.enabled then
        return
    end

    ---@type ScriptStep[]
    local script = STATE.core.scriptRunner.script

    for _, step in ipairs(script) do
        if not step.isDone and step.frame <= frame then
            Spring.SendCommands(step.commands)
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
