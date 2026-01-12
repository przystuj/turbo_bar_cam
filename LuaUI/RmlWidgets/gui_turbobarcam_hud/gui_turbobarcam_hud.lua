if not RmlUi then return end

local widget = widget ---@type Widget
local LogBuilder = VFS.Include("LuaUI/TurboBarCommons/logger_prototype.lua") ---@type LogBuilder
local Log ---@type Log

function widget:GetInfo()
    return {
        name = "TurboBarCam HUD",
        desc = "HUD overlay for TurboBarCam displaying selected unit info.",
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

local MODEL_NAME = "turbobarcam_hud_model"
local document
local dm -- Data Model Handle

---@type WidgetState
local STATE
---@type WidgetConfig
local CONFIG
---@type TurboBarCamAPI
local API

local lastConsoleLine = ""

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

local function refreshUnitInfo()
    for unitDefID, unitDef in pairs(UnitDefs) do
        local info = {}

        info.humanName = unitDef.translatedHumanName
        info.description = unitDef.translatedTooltip
        info.icon = getUnitIconPath(unitDef)

        info.baseReload = nil
        info.mainWeaponIdx = nil

        if unitDef.weapons and #unitDef.weapons > 0 then
            for i, w in ipairs(unitDef.weapons) do
                local wDef = WeaponDefs[w.weaponDef]
                if wDef and not wDef.isShield and not wDef.damageAreaOfEffect then
                    info.baseReload = wDef.reload
                    info.mainWeaponIdx = i
                    break
                end
            end
            if not info.baseReload and unitDef.weapons[1] then
                local wDef = WeaponDefs[unitDef.weapons[1].weaponDef]
                if wDef then
                    info.baseReload = wDef.reload
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
    unitVisible = false,
    name = "",
    desc = "",
    icon = "/icons/inverted/blank.png",

    currHp = 0,
    maxHp = 1,
    hpPct = 0,

    kills = 0,
    xpPct = 0,
    hasRank = false,
    rankIcon = "",
    hpBonus = 0,
    reloadBonus = 0,

    gameTime = "00:00",
    targetSpeed = "1.0",
    lastConsoleMsg = "",
    statusInfo = "",
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

local trackUnits = {
    29679,
    1241,
    20872,
    17492,
}
local delimiter = " | "
local function UpdateStatusInfo()
    local status = delimiter
    if STATE.active.mode.unitID then
        status = status .. STATE.active.mode.name .. ":" .. STATE.active.mode.unitID .. delimiter
    end
    if CONFIG.CAMERA_MODES.UNIT_FOLLOW.IGNORE_AIR_TARGETS then
        status = status .. "noAir" .. delimiter
    end
    if #API.getAllTrackedProjectiles() > 0 then
        status = status .. "nuke" .. delimiter
    end
    if STATE.active.mode.unit_follow.freezeAttackState then
        status = status .. "hold" .. delimiter
    end
    for idx,unitId in ipairs(STATE.active.unitsToTrack) do
        if Spring.ValidUnitID(unitId) then
            status = status .. "F" .. tostring(idx) .. delimiter
        end
    end
    return status
end

local function UpdateModel()
    if not dm then
        return
    end

    local frame = spGetGameFrame()
    local totalSeconds = math.floor(frame / 30)
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    dm.gameTime = string.format("%02d:%02d", minutes, seconds)

    local speed = spGetGameSpeed()
    dm.targetSpeed = string.format("%.1f", speed)
    dm.lastConsoleMsg = lastConsoleLine
    dm.statusInfo = UpdateStatusInfo()

    local targetUnitID = STATE.active.mode.unitID
    if not targetUnitID or not spValidUnitID(targetUnitID) then
        if dm.unitVisible then
            dm.unitVisible = false
        end
        return
    end

    local targetUnitDefID = spGetUnitDefID(targetUnitID)
    local unitDef = unitDefInfo[targetUnitDefID]
    local rawDef = UnitDefs[targetUnitDefID]
    if not unitDef then
        return
    end

    dm.unitVisible = true
    dm.name = unitDef.humanName
    dm.desc = unitDef.description
    dm.icon = unitDef.icon

    local hp, maxHp = spGetUnitHealth(targetUnitID)
    if hp then
        hp = math.max(0, hp)
        dm.currHp = math.max(0, math.floor(hp))
        dm.maxHp = math.floor(maxHp)
        dm.hpPct = math.floor((hp / maxHp) * 100)

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
                    dm.xpPct = 100
                else
                    local prevRankThreshold = (currentRank - 1) * xpPerLevel
                    local progress = (exp - prevRankThreshold) / xpPerLevel
                    dm.xpPct = math.clamp(math.floor(progress * 100), 0, 100)
                end
            else
                dm.xpPct = 0
            end
        end

        if unitDef.mainWeaponIdx and unitDef.baseReload then
            local currentReload = spGetUnitWeaponState(targetUnitID, unitDef.mainWeaponIdx, 'reloadTimeXP')
            if currentReload and currentReload < unitDef.baseReload then
                dm.reloadBonus = math.floor((1 - (currentReload / unitDef.baseReload)) * 100)
            else
                dm.reloadBonus = 0
            end
        else
            dm.reloadBonus = 0
        end
    else
        dm.xpPct = 0
        dm.hasRank = false
        dm.reloadBonus = 0
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
        UpdateModel()
    end
end
