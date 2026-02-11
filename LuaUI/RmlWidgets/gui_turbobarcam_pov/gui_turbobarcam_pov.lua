if not RmlUi then return end

local widget = widget ---@type Widget
local LogBuilder = VFS.Include("LuaUI/TurboBarCommons/logger_prototype.lua") ---@type LogBuilder
local Log ---@type Log

function widget:GetInfo()
    return {
        name = "TurboBarCam POV",
        desc = "POV overlay: Unit Card, Player List, Game Speed.",
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
local unitDefInfo = {}

local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitExperience = Spring.GetUnitExperience
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitWeaponState = Spring.GetUnitWeaponState
local spValidUnitID = Spring.ValidUnitID
local spGetGameFrame = Spring.GetGameFrame
local spGetGameSpeed = Spring.GetGameSpeed

local MODEL_NAME = "turbobarcam_pov_model"
local document
---@type TurboBarCamHudModelData
local dm

---@type WidgetState
local STATE
---@type WidgetConfig
local CONFIG
---@type TurboBarCamAPI
local API

-- Animation Globals
local BAR_SPEED = 10.0
local blinkTimer = 0.0
local ffTimer = 0.0

-- Internal targets for smoothing
local targetHpPct = 0
local targetEmpPct = 0
local targetXpPct = 0
local targetFFProgress = 0

local teamCache = {}
local allyTeamList

--------------------------------------------------------------------------------
-- Data Processing
--------------------------------------------------------------------------------
local icontypes = VFS.Include("gamedata/icontypes.lua")
local rankTextures = nil

local function getUnitIconPath(unitDef)
    local iconPath = "unitpics/" .. unitDef.name .. ".dds"
    if VFS.FileExists(iconPath) then
        return "/" .. iconPath
    end

    local iconType = unitDef.iconType
    if iconType and icontypes[iconType] then
        local bitmap = icontypes[iconType].bitmap
        if bitmap then
            return "/" .. bitmap
        end
    end

    return "/icons/inverted/blank.png"
end

local function GetTeamColorCss(teamID)
    local r, g, b = Spring.GetTeamColor(teamID)
    return string.format("rgb(%d,%d,%d)", r * 255, g * 255, b * 255)
end

local function refreshUnitInfo()
    for unitDefID, unitDef in pairs(UnitDefs) do
        local info = {}

        info.humanName = unitDef.translatedHumanName
        info.description = unitDef.translatedTooltip
        info.icon = getUnitIconPath(unitDef)

        info.baseReload = nil
        info.baseRange = nil
        info.mainWeaponIdx = nil

        if unitDef.weapons and #unitDef.weapons > 0 then
            for i, w in ipairs(unitDef.weapons) do
                local wDef = WeaponDefs[w.weaponDef]
                if wDef and not wDef.isShield and not wDef.damageAreaOfEffect then
                    info.baseReload = wDef.reload
                    info.baseRange = wDef.range
                    info.mainWeaponIdx = i
                    break
                end
            end
            if not info.baseReload and unitDef.weapons[1] then
                local wDef = WeaponDefs[unitDef.weapons[1].weaponDef]
                if wDef then
                    info.baseReload = wDef.reload
                    info.baseRange = wDef.range
                    info.mainWeaponIdx = 1
                end
            end
        end

        unitDefInfo[unitDefID] = info
    end
end

--------------------------------------------------------------------------------
-- RmlUi Data Model Setup
--------------------------------------------------------------------------------
local modelData = {
    visible = false,

    name = "",
    desc = "",
    icon = "/icons/inverted/blank.png",

    currHp = 0,
    maxHp = 1,
    hpPct = 0,

    empPct = 0,
    empColor = "rgba(127, 127, 255, 0.5)",
    empTime = 0,
    showEmpTimer = false,

    kills = 0,
    xpPct = 0,
    hasRank = false,
    rankIcon = "",
    hpBonus = 0,
    reloadBonus = 0,
    rangeBonus = 0,

    ffVisible = false,
    ffSpeed = "1.0",
    ffShowProgress = false,
    ffProgress = 0,
    ffOpacity = 1.0,

    playerListOpacity = 0.0,
    teamAOpacity = 1.0,
    teamBOpacity = 1.0,
    teamA_players = {},
    teamB_players = {},
}

local function InitializeRml()
    Log = LogBuilder.createInstance("TurboBarCam POV", function()
        return "DEBUG"
    end)

    widget.rmlContext = RmlUi.GetContext("shared")

    if not widget.rmlContext then
        Log:debug("TurboBarCamPOV: Failed to get 'shared' RmlUi context")
        return
    end

    widget.rmlContext:RemoveDataModel(MODEL_NAME)

    dm = widget.rmlContext:OpenDataModel(MODEL_NAME, modelData)

    if not dm then
        Log:debug("TurboBarCamPOV: Failed to open data model")
        return
    end

    document = widget.rmlContext:LoadDocument("LuaUI/RmlWidgets/gui_turbobarcam_pov/gui_turbobarcam_pov.rml", widget)

    if document then
        document:ReloadStyleSheet()
        document:Show()
    end
end

local function FindNextSpeedReset(script, currentStepIndex)
    if not script then return nil, nil end

    -- Helper to check if a specific string contains the speed reset command
    local function isSpeedReset(commandStr)
        if type(commandStr) ~= "string" then return false end
        local speedVal = commandStr:lower():match("setspeed%s+(%d+)")
        return speedVal and tonumber(speedVal) == 1
    end

    for i = currentStepIndex, #script do
        local step = script[i]
        if step and step.commands then
            local cmds = step.commands
            if type(cmds) == "table" then
                for _, cmdEntry in ipairs(cmds) do
                    if isSpeedReset(cmdEntry) then
                        return step.frame, i
                    end
                end
            else
                if isSpeedReset(cmds) then
                    return step.frame, i
                end
            end
        end
    end
    return nil, nil
end

local function UpdateModel(dt)
    if not dm then
        return
    end

    if not WG.TurboBarCam then
        Log:error('TurboBarCam is disabled')
    end

    local frame = spGetGameFrame()
    local speed = spGetGameSpeed()

    -- PLAYER LIST LOGIC
    local showPlayers = STATE.core.scriptRunner.showPlayers
    local showTeamA = STATE.core.scriptRunner.showTeamA
    local showTeamB = STATE.core.scriptRunner.showTeamB

    local FADE_SPEED = 1
    local targetOpacity = showPlayers and 1.0 or 0.0

    if dm.playerListOpacity ~= targetOpacity then
        if dm.playerListOpacity < targetOpacity then
            dm.playerListOpacity = math.min(1.0, dm.playerListOpacity + (FADE_SPEED * dt))
        else
            dm.playerListOpacity = math.max(0.0, dm.playerListOpacity - (FADE_SPEED * dt))
        end
    end

    local targetA = (showTeamA and showPlayers and 1.0) or 0.0
    if dm.teamAOpacity ~= targetA then
        if dm.teamAOpacity < targetA then
            dm.teamAOpacity = math.min(1.0, dm.teamAOpacity + (FADE_SPEED * dt))
        else
            dm.teamAOpacity = math.max(0.0, dm.teamAOpacity - (FADE_SPEED * dt))
        end
    end

    local targetB = (showTeamB and showPlayers and 1.0) or 0.0
    if dm.teamBOpacity ~= targetB then
        if dm.teamBOpacity < targetB then
            dm.teamBOpacity = math.min(1.0, dm.teamBOpacity + (FADE_SPEED * dt))
        else
            dm.teamBOpacity = math.max(0.0, dm.teamBOpacity - (FADE_SPEED * dt))
        end
    end

    -- 2. Populate List
    if dm.playerListOpacity > 0.01 then
        allyTeamList = allyTeamList or Spring.GetAllyTeamList()
        local allyA = allyTeamList[1]
        local allyB = allyTeamList[2]

        local function BuildTeamTable(allyTeamID)
            local result = {}
            if not allyTeamID then return result end

            local teamList = Spring.GetTeamList(allyTeamID)
            for _, teamID in ipairs(teamList) do
                if teamID ~= Spring.GetGaiaTeamID() then
                    local playerList = Spring.GetPlayerList(teamID)

                    -- Add Human Players
                    for _, playerID in ipairs(playerList) do
                        local name, active, spec, _, _, _, _, _, rank, _, customtable = Spring.GetPlayerInfo(playerID, true)
                        if active and not spec then
                            local skillVal = "??"
                            local playerSkill, playerSigma = 0, 8.33

                            if type(customtable) == 'table' then
                                local tsMu = customtable.skill
                                local tsSigma = customtable.skilluncertainty

                                local ts = tsMu and tonumber(tsMu:match("%d+%.?%d*"))
                                if (ts ~= nil) then
                                    playerSkill = math.round(ts, 0)
                                end
                                if tsSigma then
                                    playerSigma = tonumber(tsSigma)
                                end
                                if playerSigma <= 6.65 then
                                    skillVal = playerSkill
                                end
                            end

                            local rankPath = "ranks/" .. math.floor(rank + 1 or 1) .. ".png"
                            table.insert(result, {
                                name = name,
                                color = GetTeamColorCss(teamID),
                                skill = skillVal,
                                rankIcon = rankPath
                            })
                        end
                    end

                    -- Add AI
                    local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
                    if isAI then
                        local _, _, _, aiName = Spring.GetAIInfo(teamID)
                        table.insert(result, {
                            name = aiName or "AI",
                            color = GetTeamColorCss(teamID),
                            skill = "AI",
                            rankIcon = "ranks/0.png"
                        })
                    end
                end
            end
            teamCache[allyTeamID] = result
            return result
        end

        dm.teamA_players = teamCache[allyA] or BuildTeamTable(allyA)
        dm.teamB_players = teamCache[allyB] or BuildTeamTable(allyB)
    end


    -- Fast Forward Logic
    local scriptRunning = STATE.core.scriptRunner.enabled

    if scriptRunning and speed > 1.0 then
        dm.ffVisible = true
        dm.ffSpeed = string.format("%.1f", speed)

        ffTimer = ffTimer + dt
        dm.ffOpacity = 0.5 + 0.5 * math.abs(math.sin(ffTimer * 5))

        local currentScriptStep = STATE.core.scriptRunner.currentStep
        local script = STATE.core.scriptRunner.steps

        local endFrame, endStepIdx = FindNextSpeedReset(script, currentScriptStep)

        if endFrame and endFrame > frame then
            dm.ffShowProgress = true

            local startFrame = frame
            if endStepIdx and endStepIdx > 1 then
                local prevStep = script[currentScriptStep - 1]
                if prevStep then
                    startFrame = prevStep.frame
                end
            end

            if startFrame >= endFrame then startFrame = frame end
            if startFrame >= endFrame then
                targetFFProgress = 100
            else
                local duration = endFrame - startFrame
                local elapsed = frame - startFrame
                targetFFProgress = math.min(100, math.max(0, (elapsed / duration) * 100))
            end
        else
            dm.ffShowProgress = false
            targetFFProgress = 0
        end
    else
        dm.ffVisible = false
        targetFFProgress = 0
    end

    if math.abs(dm.ffProgress - targetFFProgress) > 0.5 then
        dm.ffProgress = dm.ffProgress + (targetFFProgress - dm.ffProgress) * 5.0 * dt
    else
        dm.ffProgress = targetFFProgress
    end

    local targetUnitID = STATE.active.mode.unitID
    if not targetUnitID or not spValidUnitID(targetUnitID) then
        dm.visible = false
        return
    end

    dm.visible = true

    local targetUnitDefID = spGetUnitDefID(targetUnitID)
    local unitDef = unitDefInfo[targetUnitDefID]
    local rawDef = UnitDefs[targetUnitDefID]
    if not unitDef then
        return
    end

    dm.name = unitDef.humanName
    dm.desc = unitDef.description
    dm.icon = unitDef.icon

    local hp, maxHp, empDamage = spGetUnitHealth(targetUnitID)
    if hp then
        hp = math.max(0, hp)
        dm.currHp = math.max(0, math.floor(hp))
        dm.maxHp = math.floor(maxHp)

        targetHpPct = (hp / maxHp) * 100

        if empDamage and empDamage > 0 then
            local pPct = (empDamage / maxHp) * 100
            targetEmpPct = math.min(100, pPct)

            -- Decay is 1/40 per frame
            if empDamage > maxHp then
                local timeSeconds = 40 * ((empDamage / maxHp) - 1)
                dm.empTime = math.floor(timeSeconds)
                dm.showEmpTimer = true
            else
                dm.empTime = 0
                dm.showEmpTimer = false
            end

            if empDamage >= maxHp then
                blinkTimer = blinkTimer + dt * 15
                local alpha = 200 + 20 * math.sin(blinkTimer)
                dm.empColor = string.format("rgba(127, 127, 255, %.2f)", alpha)
            else
                dm.empColor = "rgba(127, 127, 255, 150)" -- approx 200/255
            end
        else
            targetEmpPct = 0
            dm.empTime = 0
        end

        if rawDef.health and maxHp > rawDef.health then
            dm.hpBonus = math.floor(((maxHp / rawDef.health) - 1) * 100)
        else
            dm.hpBonus = 0
        end
    end

    local kills = spGetUnitRulesParam(targetUnitID, "kills")
    dm.kills = kills and math.floor(kills) or 0

    local exp = spGetUnitExperience(targetUnitID)
    if exp then
        if WG['rankicons'] then
            if not rankTextures then
                rankTextures = WG['rankicons'].getRankTextures()
            end

            local maximumRankXP = 0.8
            local numRanks = rankTextures and #rankTextures or 1
            local xpPerLevel = maximumRankXP / math.max(1, numRanks - 1)

            local currentRank = WG['rankicons'].getRank(targetUnitDefID, exp)

            if currentRank and rankTextures and rankTextures[currentRank] and exp > 0 then
                dm.hasRank = true
                dm.rankIcon = "/" .. rankTextures[currentRank]
            else
                dm.hasRank = false
            end

            if currentRank and numRanks > 1 then
                if currentRank >= numRanks then
                    targetXpPct = 100
                else
                    local prevRankThreshold = (currentRank - 1) * xpPerLevel
                    local progress = (exp - prevRankThreshold) / xpPerLevel
                    targetXpPct = math.clamp(math.floor(progress * 100), 0, 100)
                end
            else
                targetXpPct = 0
            end
        end

        if unitDef.mainWeaponIdx then
            if unitDef.baseReload then
                local currentReload = spGetUnitWeaponState(targetUnitID, unitDef.mainWeaponIdx, 'reloadTimeXP')
                if currentReload and currentReload < unitDef.baseReload then
                    dm.reloadBonus = math.floor((1 - (currentReload / unitDef.baseReload)) * 100)
                else
                    dm.reloadBonus = 0
                end
            else
                dm.reloadBonus = 0
            end

            if unitDef.baseRange then
                local currentRange = spGetUnitWeaponState(targetUnitID, unitDef.mainWeaponIdx, 'range')
                if currentRange and currentRange > unitDef.baseRange then
                    dm.rangeBonus = math.floor(currentRange)
                else
                    dm.rangeBonus = 0
                end
            else
                dm.rangeBonus = 0
            end
        else
            dm.reloadBonus = 0
            dm.rangeBonus = 0
        end
    else
        targetXpPct = 0
        dm.hasRank = false
        dm.reloadBonus = 0
        dm.rangeBonus = 0
    end

    if math.abs(dm.hpPct - targetHpPct) > 0.1 then
        dm.hpPct = dm.hpPct + (targetHpPct - dm.hpPct) * BAR_SPEED * dt
    else
        dm.hpPct = targetHpPct
    end

    if math.abs(dm.empPct - targetEmpPct) > 0.1 then
        dm.empPct = dm.empPct + (targetEmpPct - dm.empPct) * BAR_SPEED * dt
    else
        dm.empPct = targetEmpPct
    end

    if math.abs(dm.xpPct - targetXpPct) > 0.1 then
        dm.xpPct = dm.xpPct + (targetXpPct - dm.xpPct) * BAR_SPEED * dt
    else
        dm.xpPct = targetXpPct
    end
end

--------------------------------------------------------------------------------
-- Widget Lifecycle
--------------------------------------------------------------------------------

function widget:Initialize()
    refreshUnitInfo()
    InitializeRml()

    STATE = WG.TurboBarCam.STATE
    CONFIG = WG.TurboBarCam.CONFIG
    API = WG.TurboBarCam.API

    UpdateModel(0)
end

function widget:Shutdown()
    if document then
        document:Close()
        document = nil
    end

    if widget.rmlContext then
        widget.rmlContext:RemoveDataModel(MODEL_NAME)
    end
end

function widget:Update(dt)
    if dm then
        UpdateModel(dt)
    end
end
