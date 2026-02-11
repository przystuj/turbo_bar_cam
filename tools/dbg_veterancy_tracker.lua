function widget:GetInfo()
    return {
        name = "Unit Data Logger",
        desc = "Gathers unit data",
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

-- Replaces SerializeTable to write directly to file (Streaming)
-- This avoids creating massive strings in memory
local function WriteValue(f, val, depth)
    local tab = string.rep("    ", depth)

    if type(val) == "table" then
        f:write("{\n")
        for k, v in pairs(val) do
            local keyStr
            if type(k) == "number" then
                keyStr = "[" .. k .. "]"
            else
                keyStr = "[\"" .. k .. "\"]"
            end
            f:write(tab .. "    " .. keyStr .. " = ")
            WriteValue(f, v, depth + 1)
            f:write(",\n")
        end
        f:write(tab .. "}")
    elseif type(val) == "number" then
        f:write(tostring(val))
    elseif type(val) == "string" then
        f:write(string.format("%q", val))
    elseif type(val) == "boolean" then
        f:write(val and "true" or "false")
    end
end

-- Specialized writer to reconstruct the flat position array into the expected table format
local function WritePositionHistory(f, flatData, depth)
    local tab = string.rep("    ", depth)
    f:write("{\n")
    local innerTab = tab .. "    "
    -- Iterate in steps of 3 to reconstruct {frame, x, z}
    for i = 1, #flatData, 3 do
        f:write(string.format("%s{ frame = %d, x = %.1f, z = %.1f },\n",
                innerTab, flatData[i], flatData[i+1], flatData[i+2]))
    end
    f:write(tab .. "}")
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
        -- OPTIMIZATION: Store positions as a flat array [frame, x, z, frame, x, z...]
        -- instead of a list of tables to save massive memory overhead.
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
                -- OPTIMIZATION: Insert scalars into flat array.
                -- Avoids creating a new table object every 5 seconds for every unit.
                table.insert(r.positionHistory, currentFrame)
                table.insert(r.positionHistory, x)
                table.insert(r.positionHistory, z)
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

        -- OPTIMIZATION: Remove insignificant units immediately to free memory
        if xp < MIN_XP_THRESHOLD then
            unitRecords[unitID] = nil
            return
        end

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

    -- 2. METADATA GATHERING (PASS 1)
    local tempSortList = {}
    local tempDmgTakenList = {}

    for uID, data in pairs(unitRecords) do
        local xp = data.finalXP or 0
        local isValid = xp >= MIN_XP_THRESHOLD and isValidUnit(data.defID)

        if isValid then
            local internalName, niceName = GetUnitNames(data.defID)

            table.insert(tempSortList, {
                unitId = uID,
                name = internalName,
                humanName = niceName,
                finalXp = xp
            })

            table.insert(tempDmgTakenList, {
                unitId = uID,
                name = internalName,
                humanName = niceName,
                damageTaken = data.damageTaken
            })
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

    -- 3. STREAM DATA TO FILE (PASS 2)
    local filePath = getFilePath()
    spEcho("[Veterancy Logger] Initialized. Saving to: " .. filePath)
    local rawFile = io.open(filePath, "w")

    if rawFile then
        rawFile:write("-- Map: " .. (Game.mapName or "Unknown") .. "\n")
        rawFile:write("return {\n")

        -- Write metadata
        rawFile:write("    metadata = ")
        WriteValue(rawFile, {
            endFrame = currentFrame,
            topXp = topXpList,
            topDmgTaken = topDmgTaken
        }, 1)
        rawFile:write(",\n")

        -- Write units individually
        rawFile:write("    units = {\n")

        local count = 0
        for uID, data in pairs(unitRecords) do
            local xp = data.finalXP or 0
            local isValid = xp >= MIN_XP_THRESHOLD and isValidUnit(data.defID)

            if isValid then
                local internalName, niceName = GetUnitNames(data.defID)
                local cleanHistory = ConsolidateSmart(data.statusHistory)

                -- Stream the unit entry directly to file to avoid memory spikes
                rawFile:write("    [" .. uID .. "] = {\n")

                -- Write simple fields
                rawFile:write(string.format("        name = %q,\n", internalName))
                rawFile:write(string.format("        humanName = %q,\n", niceName))
                rawFile:write(string.format("        defID = %d,\n", data.defID))
                rawFile:write(string.format("        tier = %d,\n", data.tier or 1))
                rawFile:write(string.format("        bornFrame = %d,\n", data.bornFrame))
                if data.diedFrame then
                    rawFile:write(string.format("        diedFrame = %d,\n", data.diedFrame))
                end
                rawFile:write(string.format("        finalXP = %.4f,\n", xp))
                rawFile:write(string.format("        damageTaken = %.1f,\n", data.damageTaken))

                -- Write Status History (Standard Table)
                rawFile:write("        statusHistory = ")
                WriteValue(rawFile, cleanHistory, 2)
                rawFile:write(",\n")

                -- Write Position History (Reconstruct from flat array on the fly)
                rawFile:write("        positionHistory = ")
                WritePositionHistory(rawFile, data.positionHistory, 2)
                rawFile:write("\n")

                rawFile:write("    },\n")

                -- Explicit GC to prevent accumulation during loop
                count = count + 1
                if count % 100 == 0 then
                    collectgarbage("collect")
                end
            end
        end

        rawFile:write("    }\n")
        rawFile:write("}")
        rawFile:close()
    else
        spEcho("[Veterancy Logger] ERROR: Could not open file for writing")
    end
end
