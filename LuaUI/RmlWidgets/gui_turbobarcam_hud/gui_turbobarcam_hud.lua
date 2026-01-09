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

local MODEL_NAME = "turbobarcam_hud_model"
local document
local dm -- Data Model Handle

---@type WidgetState
local STATE

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

        -- Pre-calculate base reload time for bonus calculation
        info.baseReload = nil
        info.mainWeaponIdx = nil

        if unitDef.weapons and #unitDef.weapons > 0 then
            -- Try to find the first non-shield, real weapon
            for i, w in ipairs(unitDef.weapons) do
                local wDef = WeaponDefs[w.weaponDef]
                if wDef and not wDef.isShield and not wDef.damageAreaOfEffect then
                    info.baseReload = wDef.reload
                    info.mainWeaponIdx = i
                    break
                end
            end
            -- Fallback
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
    isVisible = false,
    name = "",
    desc = "",
    icon = "/icons/inverted/blank.png",

    -- Health
    currHp = 0,
    maxHp = 1,
    hpPct = 0,

    -- Stats
    kills = 0,
    xpPct = 0,
    hasRank = false,
    rankIcon = "",
    hpBonus = 0,
    reloadBonus = 0
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

local function UpdateModel()
    if not dm then
        return
    end

    local targetUnitID = STATE.active.mode.unitID
    if not targetUnitID or not spValidUnitID(targetUnitID) then
        if dm.isVisible then
            dm.isVisible = false
        end
        return
    end

    local targetUnitDefID = spGetUnitDefID(targetUnitID)
    local unitDef = unitDefInfo[targetUnitDefID]
    local rawDef = UnitDefs[targetUnitDefID]
    if not unitDef then
        return
    end

    dm.isVisible = true
    dm.name = unitDef.humanName
    dm.desc = unitDef.description
    dm.icon = unitDef.icon

    -- Health
    local hp, maxHp = spGetUnitHealth(targetUnitID)
    if hp then
        dm.currHp = math.floor(hp)
        dm.maxHp = math.floor(maxHp)
        dm.hpPct = math.floor((hp / maxHp) * 100)

        -- Health Bonus Calculation
        if rawDef.health and maxHp > rawDef.health then
            dm.hpBonus = math.floor(((maxHp / rawDef.health) - 1) * 100)
        else
            dm.hpBonus = 0
        end
    end

    -- Kills
    local kills = spGetUnitRulesParam(targetUnitID, "kills")
    dm.kills = kills and math.floor(kills) or 0

    -- Rank & XP
    local exp = spGetUnitExperience(targetUnitID)
    if exp then
        if WG['rankicons'] then
            if not rankTextures then
                rankTextures = WG['rankicons'].getRankTextures()
            end

            -- Logic sourced from gui_rank_icons_gl4.lua
            local maximumRankXP = 0.8
            local numRanks = rankTextures and #rankTextures or 1
            local xpPerLevel = maximumRankXP / math.max(1, numRanks - 1)

            local currentRank = WG['rankicons'].getRank(targetUnitDefID, exp)

            -- 1. Update Rank Icon
            if currentRank and rankTextures and rankTextures[currentRank] and exp > 0 then
                dm.hasRank = true
                dm.rankIcon = "/" .. rankTextures[currentRank]
            else
                dm.hasRank = false
            end

            -- 2. Update XP Bar (Relative Progress)
            if currentRank and numRanks > 1 then
                if currentRank >= numRanks then
                    -- Max rank reached
                    dm.xpPct = 100
                else
                    -- Calculate progress within the current rank level bucket
                    -- Rank 1 covers 0 XP to 1*xpPerLevel
                    -- Rank 2 covers 1*xpPerLevel to 2*xpPerLevel
                    local prevRankThreshold = (currentRank - 1) * xpPerLevel
                    local progress = (exp - prevRankThreshold) / xpPerLevel
                    dm.xpPct = math.clamp(math.floor(progress * 100), 0, 100)
                end
            else
                dm.xpPct = 0
            end
        end

        -- Reload Bonus (DPS)
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
