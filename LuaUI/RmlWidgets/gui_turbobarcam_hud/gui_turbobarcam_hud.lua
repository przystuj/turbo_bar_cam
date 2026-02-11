if not RmlUi then return end

local widget = widget ---@type Widget
local LogBuilder = VFS.Include("LuaUI/TurboBarCommons/logger_prototype.lua") ---@type LogBuilder
local Log ---@type Log

function widget:GetInfo()
    return {
        name = "TurboBarCam HUD",
        desc = "HUD overlay for TurboBarCam displaying replay info.",
        author = "SuperKitowiec",
        date = "January 2026",
        license = "GNU GPL, v2 or later",
        layer = 0,
        enabled = true
    }
end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------
local spGetGameFrame = Spring.GetGameFrame
local spGetGameSpeed = Spring.GetGameSpeed

local MODEL_NAME = "turbobarcam_hud_model"
local document
---@type TurboBarCamHudModelData
local dm

---@type WidgetState
local STATE
---@type WidgetConfig
local CONFIG
---@type TurboBarCamAPI
local API

local lastConsoleLine = ""
local veterancyData = nil ---@type ReplayUnitMetadata
local lastLoadedFile = nil

--------------------------------------------------------------------------------
-- Data Processing
--------------------------------------------------------------------------------

local function GetCommandList(cmds)
    if type(cmds) == "table" then
        return cmds
    elseif type(cmds) == "string" then
        -- Return as a single item list, or split by semicolon if your raw strings use them
        return { cmds }
    end
    return { tostring(cmds) }
end

local function loadVeterancyData()
    if not WG.ReplayMetadata or not WG.ReplayMetadata.filename then return end

    local filename = WG.ReplayMetadata.filename
    if filename == lastLoadedFile then return end

    local path = "LuaUI/veterancyData/" .. filename .. "_veterancyData.lua"
    if VFS.FileExists(path) then
        veterancyData = VFS.Include(path)
        lastLoadedFile = filename
    else
        veterancyData = nil
    end
end

--------------------------------------------------------------------------------
-- RmlUi Data Model Setup
--------------------------------------------------------------------------------
local modelData = {
    gameFrame = "000000",
    gameTime = "00:00",
    targetSpeed = "1.0",
    lastConsoleMsg = "",
    statusInfo = "",

    trackedProjectiles = {},
    projectilesVisible = false,

    statusVisible = true,
    currentMouseTarget = "",

    scriptStepsVisible = false,
    scriptSteps = {},

    vetVisible = false,
    currentVetStatus = "",
    futureVetStates = {},

    currentUnit = "",
}

local function InitializeRml()
    Log = LogBuilder.createInstance("TurboBarCam HUD", function()
        return "DEBUG"
    end)

    widget.rmlContext = RmlUi.GetContext("shared")

    if not widget.rmlContext then
        Log:debug("TurboBarCamHUD: Failed to get 'shared' RmlUi context")
        return
    end

    widget.rmlContext:RemoveDataModel(MODEL_NAME)

    dm = widget.rmlContext:OpenDataModel(MODEL_NAME, modelData)

    if not dm then
        Log:debug("TurboBarCamHUD: Failed to open data model")
        return
    end

    document = widget.rmlContext:LoadDocument("LuaUI/RmlWidgets/gui_turbobarcam_hud/gui_turbobarcam_hud.rml", widget)

    if document then
        document:ReloadStyleSheet()
        document:Show()
    end
end

local delimiter = " | "
local function UpdateStatusInfo()
    local status = delimiter
    if STATE.active.mode.unitID then
        status = status .. STATE.active.mode.name .. ":" .. STATE.active.mode.unitID .. delimiter
    end
    if CONFIG.CAMERA_MODES.UNIT_FOLLOW.IGNORE_AIR_TARGETS then
        status = status .. "NOAIR" .. delimiter
    end
    if STATE.active.mode.unit_follow.combatModeEnabled then
        if STATE.active.mode.unit_follow.lastTargetUnitID then
            status = status .. "CMBT: " .. tostring(STATE.active.mode.unit_follow.lastTargetUnitID) .. delimiter
        else
            status = status .. "CMBT" .. delimiter
        end
    end
    if #API.getAllTrackedProjectiles() > 0 then
        status = status .. "NUKE" .. delimiter
    end
    if STATE.active.mode.unit_follow.freezeAttackState then
        status = status .. "HOLD" .. delimiter
    end
    if STATE.core.driver.job.startTime then
        local jobDuration = Spring.DiffTimers(Spring.GetTimer(), STATE.core.driver.job.startTime)
        status = status .. "JOB: " .. string.format("%.2f (%d)", jobDuration, jobDuration * 30) .. delimiter
    end
    for idx, unitId in ipairs(STATE.core.scriptRunner.unitsToTrack) do
        if Spring.ValidUnitID(unitId) then
            status = status .. "F" .. tostring(idx) .. delimiter
        end
    end
    ---@type ScriptStep[]
    local script = STATE.core.scriptRunner.steps
    if STATE.core.scriptRunner.enabled then
        local nextStepFrame = script[STATE.core.scriptRunner.currentStep].frame
        status = status .. "s" .. STATE.core.scriptRunner.currentStep .. "@" .. nextStepFrame
    end
    return status
end

local function UpdateModel(dt)
    if not dm then
        return
    end

    if not WG.TurboBarCam then
        Log:error('TurboBarCam is disabled')
    end

    local frame = spGetGameFrame()
    local totalSeconds = math.floor(frame / 30)
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    dm.gameTime = string.format("%02d:%02d", minutes, seconds)
    dm.gameFrame = string.format("%06d", frame)

    local speed, speedFactor = spGetGameSpeed()
    dm.targetSpeed = string.format("%.1f <%.1f>", speed, speedFactor)
    dm.lastConsoleMsg = lastConsoleLine
    if STATE.core.scriptRunner.enabled and STATE.core.scriptRunner.isFinal then
        dm.statusVisible = false
    else
        dm.statusInfo = UpdateStatusInfo()
        dm.statusVisible = true
    end

    local mx, my = Spring.GetMouseState()
    local mouseTargetType, mouseTarget = Spring.TraceScreenRay(mx, my)

    if mouseTargetType and type(mouseTarget) ~= "table" then
        dm.currentMouseTarget = string.format("%s: %s", mouseTargetType:sub(1, 1), mouseTarget)
    else
        dm.currentMouseTarget = ""
    end

    ---@type Projectile[]
    local projectiles = API.getAllTrackedProjectiles()
    table.sort(projectiles, function(a, b)
        return a.id > b.id
    end)

    local projectileData = {}
    for _, projectile in pairs(projectiles) do
        table.insert(projectileData, {
            id = projectile.id,
            ownerId = projectile.ownerID,
            time = Spring.DiffTimers(Spring.GetTimer(), projectile.creationTime),
        })
    end

    dm.projectilesVisible = dm.statusVisible and #projectileData > 0
    dm.trackedProjectiles = projectileData

    -- SCRIPT STEPS LOGIC
    local scriptData = {}
    local runner = STATE.core.scriptRunner

    if runner and runner.enabled and runner.steps then
        local currentIdx = runner.currentStep
        local script = runner.steps

        -- 1. Current Step
        if script[currentIdx] then
            table.insert(scriptData, {
                label = script[currentIdx].label or "Current",
                frame = tostring(frame - script[currentIdx].frame) .. " (" .. script[currentIdx].frame .. ")",
                -- Use the new list helper here
                commandsList = GetCommandList(script[currentIdx].commands)
            })
        end

        -- 2. Next Step
        if script[currentIdx + 1] then
            table.insert(scriptData, {
                label = script[currentIdx].label or "Next",
                frame = script[currentIdx + 1].frame,
                -- Use the new list helper here
                commandsList = GetCommandList(script[currentIdx + 1].commands)
            })
        end
    end

    dm.scriptSteps = scriptData
    dm.scriptStepsVisible = dm.statusVisible and (#scriptData > 0)

    -- VETERANCY DATA
    loadVeterancyData()
    dm.vetVisible = false
    local selectedUnits = Spring.GetSelectedUnits()
    if not STATE.core.scriptRunner.isFinal and veterancyData and #selectedUnits > 0 then
        local data = veterancyData.units[selectedUnits[1]]
        dm.currentUnit = selectedUnits[1]
        if data then
            local currentFrame = spGetGameFrame()
            local currentStatus = "UNKNOWN"
            local futureStates = {}

            for i, history in ipairs(data.statusHistory) do
                if currentFrame >= history.startFrame and history.endFrame and currentFrame <= history.endFrame then
                    currentStatus = history.status
                    dm.vetVisible = true

                    -- Look ahead for all future states
                    for j = i + 1, #data.statusHistory do
                        local nextState = data.statusHistory[j]
                        local seconds = math.max(0, math.floor((nextState.startFrame - currentFrame) / 30))
                        table.insert(futureStates, {
                            status = nextState.status,
                            countdown = tostring(seconds) .. "s"
                        })
                    end
                    break
                end
            end

            dm.currentVetStatus = currentStatus
            dm.futureVetStates = futureStates
        end
    end
end

--------------------------------------------------------------------------------
-- Widget Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    InitializeRml()

    STATE = WG.TurboBarCam.STATE
    CONFIG = WG.TurboBarCam.CONFIG
    API = WG.TurboBarCam.API

    UpdateModel(0)
end

function widget:AddConsoleLine(lines)
    for line in lines:gmatch("[^\r\n]+") do
        lastConsoleLine = line
    end
end

function widget:Shutdown()
    if document then
        document:Close()
        document = nil
    end

    if widget.rmlContext then
        widget.rmlContext:RemoveDataModel(MODEL_NAME)
    end

    WG.TurboBarCamHUD = nil
end

function widget:Update(dt)
    if dm then
        UpdateModel(dt)
    end
end
