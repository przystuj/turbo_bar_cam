function widget:GetInfo()
    return {
        name = "Veterancy Logger",
        desc = "Finds units with highest veterancy",
        author = "SuperKitowiec",
        date = "2026",
        license = "GNU GPL, v2 or later",
        layer = -9999,
        enabled = true
    }
end

if not Spring.IsReplay() then
    return
end

--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------
local MIN_XP_THRESHOLD = 0.04       -- Minimum XP required to be included in final log

local OUTPUT_DIR = "LuaUI/veterancyData/"

-- LOGIC TUNING
local CHECK_INTERVAL = 10
local POS_CHECK_INTERVAL = 150      -- 5s: Interval for logging position (30fps * 5)
local IDLE_TIMEOUT_FRAMES = 300     -- 10s: How long to wait before deciding a unit is IDLE
local MAX_PAUSE_GAP = 900           -- 30s: Max duration to ever consider a "PAUSE" (safety cap)

--------------------------------------------------------------------------------
-- Speedups
--------------------------------------------------------------------------------
local spGetUnitExperience = Spring.GetUnitExperience
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitPosition = Spring.GetUnitPosition
local spGetGameFrame = Spring.GetGameFrame
local spGetAllUnits = Spring.GetAllUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spEcho = Spring.Echo

local unitRecords = {}
local unitDefWeaponInfo = {} -- Cache for main weapon indices

local function CacheUnitWeaponInfo()
    for unitDefID, unitDef in pairs(UnitDefs) do
        local mainIdx = nil

        if unitDef.weapons and #unitDef.weapons > 0 then
            -- Try to find the first non-shield weapon
            for i, w in ipairs(unitDef.weapons) do
                local wDef = WeaponDefs[w.weaponDef]
                if wDef and not wDef.isShield and wDef.canAttackGround then
                    mainIdx = i
                    break
                end
            end
            if not mainIdx then
                spEcho("Didn't find main weapon for", unitDef.name)
                mainIdx = 1
            end
        end

        if mainIdx then
            unitDefWeaponInfo[unitDefID] = mainIdx
        end
    end
end

-- Specific units to exclude
local ignoreListNames = {
    "corvamp", "armhawk", "legfig", "legvenator", "legafigdef", "armfig", "corveng", -- figs
    "armrock", "corsent", "corwolv", "armart", "corstorm"
}

local ignoreSet = {}
for _, name in ipairs(ignoreListNames) do
    ignoreSet[name] = true
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function isValidUnit(uDefId)
    local ud = UnitDefs[uDefId]
    return ud and not ignoreSet[ud.name] and (ud.speed and ud.speed > 0)
end

local function GetUnitNames(defID)
    if not defID then return "Unknown", "Unknown" end
    local ud = UnitDefs[defID]
    if not ud then return "Unknown", "Unknown" end

    local humanName = ud.translatedHumanName or ud.name
    return ud.name, humanName
end

local function SerializeTable(val, name, depth)
    depth = depth or 0
    local str = ""
    local tab = string.rep("    ", depth)

    if type(val) == "table" then
        if name then str = str .. tab .. name .. " = " end
        str = str .. "{\n"
        for k, v in pairs(val) do
            local key
            if type(k) == "number" then
                key = "[" .. k .. "]"
            else
                key = "[\"" .. k .. "\"]"
            end
            str = str .. SerializeTable(v, key, depth + 1) .. ",\n"
        end
        str = str .. tab .. "}"
    elseif type(val) == "number" then
        if name then str = str .. tab .. name .. " = " end
        str = str .. tostring(val)
    elseif type(val) == "string" then
        if name then str = str .. tab .. name .. " = " end
        str = str .. string.format("%q", val)
    elseif type(val) == "boolean" then
        if name then str = str .. tab .. name .. " = " end
        str = str .. (val and "true" or "false")
    end
    return str
end

-- Helper to close a timeline segment
local function PushHistorySegment(record, endFrame)
    local count = #record.statusHistory
    if count > 0 then
        local lastSegment = record.statusHistory[count]

        if lastSegment.endFrame == nil then
            lastSegment.endFrame = endFrame
        end
    end
end

-- SMART CONSOLIDATION: INTRODUCING "PAUSE"
local function ConsolidateSmart(history)
    if #history < 3 then return history end

    -- Iterate through the timeline looking for triplets: ACTIVE -> IDLE -> ACTIVE
    -- We stop 2 short of the end to ensure we have a 'next' and 'next-next'
    for i = 1, #history - 2 do
        local segA = history[i]
        local segGap = history[i+1]
        local segB = history[i+2]

        if segA.status == "ACTIVE" and segGap.status == "IDLE" and segB.status == "ACTIVE" then

            -- Calculate Durations
            local durA = (segA.endFrame or 0) - segA.startFrame
            local durB = (segB.endFrame or 0) - segB.startFrame
            local durGap = (segGap.endFrame or 0) - segGap.startFrame

            local totalActive = durA + durB

            -- THE RULE:
            -- If the surrounding action is longer than the break, it's just a PAUSE.
            -- Example 1: 5s Active, 15s Idle, 5s Active. Total Active (10) < Idle (15). Result: Keep as IDLE.
            -- Example 2: 5s Active, 15s Idle, 30s Active. Total Active (35) > Idle (15). Result: Mark as PAUSE.
            if durGap < MAX_PAUSE_GAP and totalActive > durGap then
                segGap.status = "PAUSE"
            end
        end
    end

    return history
end

local function UpdateUnitActivity(record, frame)
    -- Reset the idle timer
    record.lastActivityFrame = frame

    -- If it was IDLE, switch back to ACTIVE immediately
    if record.currentStatus == "IDLE" or record.currentStatus == "PAUSE" then
        record.currentStatus = "ACTIVE"

        -- Close the previous IDLE/PAUSE block
        local histLen = #record.statusHistory
        if histLen > 0 then
            record.statusHistory[histLen].endFrame = frame
        end

        table.insert(record.statusHistory, {
            status = "ACTIVE",
            startFrame = frame
        })
    end
end

local function InitUnitRecord(uID, defID, frame)
    local curHP = spGetUnitHealth(uID) or 0
    local unitDef = UnitDefs[defID]

    unitRecords[uID] = {
        defID = defID,
        bornFrame = frame,
        diedFrame = nil,
        finalXP = 0,
        tier = tonumber((unitDef.customParams and unitDef.customParams.techlevel) or "1"),

        -- Stats Tracking
        damageTaken = 0,
        positionHistory = {},

        -- Activity Tracking
        lastCheckedXP = 0,
        lastCheckedHP = curHP,
        currentStatus = "IDLE",

        lastStatusChangeFrame = frame,
        lastActivityFrame = frame,

        statusHistory = {
            [1] = {
                startFrame = frame,
                endFrame = nil,
                status = "IDLE",
            }
        }
    }
end

local function getFilePath()
    local dateStr = os.date("%Y-%m-%d_%H-%M-%S")
    local mapName = Game.mapName or "UnknownMap"
    mapName = string.gsub(mapName, "[/\\:]", "_")
    local baseName = (WG.ReplayMetadata.filename or dateStr .. "_" .. mapName) .. "_veterancyData"

    local finalPath = OUTPUT_DIR .. baseName .. ".lua"
    local counter = 1

    while true do
        local f = io.open(finalPath, "r")
        if f then
            f:close()
            finalPath = OUTPUT_DIR .. baseName .. "_" .. counter .. ".lua"
            counter = counter + 1
        else
            break
        end
    end
    return finalPath
end

--------------------------------------------------------------------------------
-- Callins
--------------------------------------------------------------------------------

function widget:Initialize()
    CacheUnitWeaponInfo()

    local allUnits = spGetAllUnits()
    local currentFrame = spGetGameFrame()
    local bornTime = (currentFrame < 100) and 0 or currentFrame

    for _, uID in ipairs(allUnits) do
        local defID = spGetUnitDefID(uID)
        if isValidUnit(defID) then
            InitUnitRecord(uID, defID, bornTime)
            local xp = spGetUnitExperience(uID) or 0
            unitRecords[uID].lastCheckedXP = xp
            unitRecords[uID].finalXP = xp
        end
    end
    spEcho("[Veterancy Logger] Initialized.")
end

function widget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
    if not ignoreSet[UnitDefs[unitDefID].name] then
        InitUnitRecord(unitID, unitDefID, spGetGameFrame())
    end
end

function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage)
    local r = unitRecords[unitID]
    if r then
        r.lastCheckedHP = spGetUnitHealth(unitID)
        r.damageTaken = r.damageTaken + damage
    end
end

function widget:GameFrame(currentFrame)
    if currentFrame % POS_CHECK_INTERVAL == 0 then
        for uID, r in pairs(unitRecords) do
            local x, _, z = spGetUnitPosition(uID)
            if x then
                table.insert(r.positionHistory, {
                    frame = currentFrame,
                    x = x,
                    z = z
                })
            end
        end
    end

    if currentFrame % CHECK_INTERVAL == 3 then
        local spGetUnitWeaponState = Spring.GetUnitWeaponState

        for unitID, r in pairs(unitRecords) do
            local isActive = false

            -- 1. Check Weapon State
            local mainWeaponIdx = unitDefWeaponInfo[r.defID]
            if mainWeaponIdx then
                local reloadFrame = spGetUnitWeaponState(unitID, mainWeaponIdx, 'reloadFrame')
                if reloadFrame and reloadFrame > currentFrame then
                    isActive = true
                end
            end

            -- 2. Update Activity Timer
            if isActive then
                r.lastActivityFrame = currentFrame
            end

            -- 3. Determine Status
            local timeSinceAction = currentFrame - (r.lastActivityFrame or r.bornFrame)
            local newStatus = (timeSinceAction > IDLE_TIMEOUT_FRAMES) and "IDLE" or "ACTIVE"

            -- 4. Handle Status Change
            if newStatus ~= r.currentStatus then
                local transitionFrame = currentFrame

                -- If becoming IDLE, the segment ended when activity actually stopped.
                if newStatus == "IDLE" and r.currentStatus == "ACTIVE" then
                    transitionFrame = r.lastActivityFrame

                    -- Don't backdate before the segment started
                    local lastSeg = r.statusHistory[#r.statusHistory]
                    if lastSeg and transitionFrame < lastSeg.startFrame then
                        transitionFrame = lastSeg.startFrame
                    end
                end

                -- Close previous block
                local histLen = #r.statusHistory
                if histLen > 0 then
                    r.statusHistory[histLen].endFrame = transitionFrame
                end

                -- Start new block
                table.insert(r.statusHistory, {
                    status = newStatus,
                    startFrame = transitionFrame
                })

                r.currentStatus = newStatus
            end

            local currentXP = spGetUnitExperience(unitID)
            if currentXP then
                r.finalXP = currentXP
            end
        end
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
    if unitRecords[unitID] then
        local xp = spGetUnitExperience(unitID) or 0
        local frame = spGetGameFrame()

        unitRecords[unitID].finalXP = xp
        unitRecords[unitID].diedFrame = frame

        -- Close the final timeline segment
        PushHistorySegment(unitRecords[unitID], frame)
    end
end

function widget:Shutdown()
    spEcho("--------------------------------------------------")
    spEcho("[Veterancy Logger] PROCESSING STATS & SAVING FILES")
    spEcho("--------------------------------------------------")

    local currentFrame = spGetGameFrame()

    -- 1. Final update for units still alive
    local allUnits = spGetAllUnits()
    for _, uID in ipairs(allUnits) do
        if unitRecords[uID] then
            local xp = spGetUnitExperience(uID) or 0
            unitRecords[uID].finalXP = xp
            PushHistorySegment(unitRecords[uID], currentFrame)
        end
    end

    -- 2. APPLY UNIFIED FILTER & CONSOLIDATE
    ---@class ReplayUnitMetadata
    ---@field units UnitMetadata[]
    ---@field metadata ReplayMetadata
    local result = {}
    local exportUnits = {}
    local tempSortList = {}
    local tempDmgTakenList = {}

    for uID, data in pairs(unitRecords) do
        local xp = data.finalXP or 0

        local isValid = xp >= MIN_XP_THRESHOLD and isValidUnit(data.defID)

        if isValid then
            local internalName, niceName = GetUnitNames(data.defID)

            -- APPLY SMART CONSOLIDATION
            local cleanHistory = ConsolidateSmart(data.statusHistory)

            ---@class UnitMetadata
            exportUnits[uID] = {
                name = internalName,
                humanName = niceName,
                defID = data.defID,
                tier = data.tier,
                bornFrame = data.bornFrame,
                diedFrame = data.diedFrame,
                finalXP = xp,
                damageTaken = data.damageTaken,
                positionHistory = data.positionHistory,
                statusHistory = cleanHistory
            }

            local metaEntry = {
                unitId = uID,
                name = internalName,
                humanName = niceName
            }

            table.insert(tempSortList, {
                unitId = uID,
                name = internalName,
                humanName = niceName,
                finalXp = xp
            })

            local takenEntry = {damageTaken = data.damageTaken}
            for k, v in pairs(metaEntry) do takenEntry[k] = v end
            table.insert(tempDmgTakenList, takenEntry)
        end
    end

    -- Sort by XP descending for metadata
    table.sort(tempSortList, function(a, b) return a.finalXp > b.finalXp end)
    local topXpList = {}
    for i = 1, math.min(#tempSortList, 5) do
        table.insert(topXpList, tempSortList[i])
    end

    -- Sort by Damage Taken descending
    table.sort(tempDmgTakenList, function(a, b) return a.damageTaken > b.damageTaken end)
    local topDmgTaken = {}
    for i = 1, math.min(#tempDmgTakenList, 10) do
        table.insert(topDmgTaken, tempDmgTakenList[i])
    end

    result.units = exportUnits
    ---@class ReplayMetadata
    result.metadata = {
        endFrame = currentFrame,
        topXp = topXpList,
        topDmgTaken = topDmgTaken
    }

    -- 3. SAVE RAW DATA (Lua Table)
    local filePath = getFilePath()
    spEcho("[Veterancy Logger] Initialized. Saving to: " .. filePath)
    local rawFile = io.open(filePath, "w")
    if rawFile then
        rawFile:write("-- Map: " .. (Game.mapName or "Unknown") .. "\n")
        rawFile:write("return " .. SerializeTable(result))
        rawFile:close()
    else
        spEcho("[Veterancy Logger] ERROR: Could not open file for writing")
    end
end
