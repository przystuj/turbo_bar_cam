function widget:GetInfo()
    return {
        name = "Unit Data Logger",
        desc = "Gathers unit data",
        author = "SuperKitowiec",
        date = "2026",
        license = "GNU GPL, v2 or later",
        layer = -9000,
        enabled = true
    }
end

--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------
local MIN_XP_THRESHOLD = 0.02       -- Minimum XP required to be included in final log

local OUTPUT_DIR = "LuaUI/unitData/"

-- LOGIC TUNING
local ACTIVITY_CHECK_INTERVAL = 10
local POS_CHECK_INTERVAL = 150      -- 5s: Interval for logging position (30fps * 5)
local TARGET_CHECK_INTERVAL = 90    -- 3s: Interval for logging targets (30fps * 3)
local IDLE_TIMEOUT_FRAMES = 300     -- 10s: How long to wait before deciding a unit is IDLE
local MAX_PAUSE_GAP = 900           -- 30s: Max duration to ever consider a "PAUSE" (safety cap)

--------------------------------------------------------------------------------
-- Speedups
--------------------------------------------------------------------------------
local spGetUnitExperience = Spring.GetUnitExperience
local spGetUnitPosition = Spring.GetUnitPosition
local spGetGameFrame = Spring.GetGameFrame
local spGetAllUnits = Spring.GetAllUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitWeaponTarget = Spring.GetUnitWeaponTarget
local spEcho = Spring.Echo
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
local spGetUnitHeading = Spring.GetUnitHeading
local spGetUnitWeaponState = Spring.GetUnitWeaponState

local GAME_FPS = Game.gameSpeed

local unitRecords = {}
local finishedUnits = {}
local projectileHistory = {}

local unitDefWeaponIndices = {} -- Cache for valid weapon indices list
local fastMode = false


-- Specific units to exclude
local ignoreListNames = {
    "corvamp", "armhawk", "legfig", "legvenator", "legafigdef", "armfig", "corveng", -- figs
    "armrock", "corsent", "corwolv", "armart", "corstorm"
}
local ignoreSet = {}
for _, name in ipairs(ignoreListNames) do
    ignoreSet[name] = true
end

local function isValidUnit(uDefId)
    local ud = UnitDefs[uDefId]
    return ud and not ignoreSet[ud.name] and (ud.speed and ud.speed > 0)
end


local function CacheUnitWeaponInfo()
    for unitDefID, unitDef in pairs(UnitDefs) do
        local validIndices = {}

        if isValidUnit(unitDefID) and unitDef.weapons then
            for i, w in ipairs(unitDef.weapons) do
                local wDef = WeaponDefs[w.weaponDef]
                if wDef and not wDef.isShield and wDef.canAttackGround then
                    table.insert(validIndices, i)
                end
            end
        end

        if #validIndices > 0 then
            unitDefWeaponIndices[unitDefID] = validIndices
        end
    end
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------


local function GetUnitNames(defID)
    if not defID then return "Unknown", "Unknown" end
    local ud = UnitDefs[defID]
    if not ud then return "Unknown", "Unknown" end

    local humanName = ud.translatedHumanName or ud.name
    return ud.name, humanName
end

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

local function WritePositionHistory(f, flatData, depth)
    local tab = string.rep("    ", depth)
    f:write("{\n")
    local innerTab = tab .. "    "
    -- Iterate in steps of 4 to reconstruct {frame, x, z, heading}
    for i = 1, #flatData, 4 do
        local hVal = flatData[i+3]
        local hStr = hVal and string.format(", heading = %.3f", hVal) or ""
        f:write(string.format("%s{ frame = %d, x = %.1f, z = %.1f%s },\n",
                innerTab, flatData[i], flatData[i+1], flatData[i+2], hStr))
    end
    f:write(tab .. "}")
end

local function WriteTargetHistory(f, flatData, depth)
    local tab = string.rep("    ", depth)
    f:write("{\n")
    local innerTab = tab .. "    "
    -- Stride is 8: frame, targetID, name, humanName, tier, x, y, z
    for i = 1, #flatData, 8 do
        local frame = flatData[i]
        local tID = flatData[i+1]
        local name = flatData[i+2]
        local hName = flatData[i+3]
        local tier = flatData[i+4]
        local x = flatData[i+5]
        local y = flatData[i+6]
        local z = flatData[i+7]

        if tID == "ground" then
            f:write(string.format("%s{ frame = %d, targetId = \"ground\", x = %.1f, y = %.1f, z = %.1f },\n",
                    innerTab, frame, x, y, z))
        else
            f:write(string.format("%s{ frame = %d, targetId = %d, name = %q, humanName = %q, tier = %s, x = %.1f, y = %.1f, z = %.1f },\n",
                    innerTab, frame, tID, name, hName, tier, x, y, z))
        end
    end
    f:write(tab .. "}")
end

-- Specialized writer for Projectiles
local function WriteProjectileHistory(f, flatData, depth)
    local tab = string.rep("    ", depth)
    f:write("{\n")
    local innerTab = tab .. "    "
    -- Stride is 7: frame, id, ownerID, x, y, z, ownerHumanName
    for i = 1, #flatData, 7 do
        f:write(string.format("%s{ frame = %d, id = %d, ownerID = %d, x = %.1f, y = %.1f, z = %.1f, ownerHumanName = %q },\n",
                innerTab, flatData[i], flatData[i+1], flatData[i+2], flatData[i+3], flatData[i+4], flatData[i+5], flatData[i+6]))
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

local function ConsolidateSmart(history)
    if #history < 3 then return history end

    for i = 1, #history - 2 do
        local segA = history[i]
        local segGap = history[i + 1]
        local segB = history[i + 2]

        if segA.status == "ACTIVE" and segGap.status == "IDLE" and segB.status == "ACTIVE" then
            local durA = (segA.endFrame or 0) - segA.startFrame
            local durB = (segB.endFrame or 0) - segB.startFrame
            local durGap = (segGap.endFrame or 0) - segGap.startFrame

            local totalActive = durA + durB

            if durGap < MAX_PAUSE_GAP and totalActive > durGap then
                segGap.status = "PAUSE"
            end
        end
    end

    return history
end

local function CalcTotalActiveFrames(history, currentFrame)
    local total = 0
    for _, seg in ipairs(history) do
        if seg.status == "ACTIVE" then
            local ef = seg.endFrame or currentFrame or seg.startFrame
            if ef and ef > seg.startFrame then
                total = total + (ef - seg.startFrame)
            end
        end
    end
    return total
end

local function InitUnitRecord(uID, defID, frame)
    local unitDef = UnitDefs[defID]

    unitRecords[uID] = {
        unitId = uID,
        defID = defID,
        bornFrame = frame,
        diedFrame = nil,
        finalXP = 0,
        tier = tonumber((unitDef.customParams and unitDef.customParams.techlevel) or "1"),
        playerId = spGetUnitTeam(uID),
        teamId = spGetUnitAllyTeam(uID),

        damageTaken = 0,
        -- Stride 4: [frame, x, z, heading...]
        positionHistory = {},

        -- Stride 8: [frame, id, name, humanName, tier, x, y, z...]
        targetHistory = {},

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
    local baseName = WG.ReplayMetadata.filename or dateStr .. "_" .. mapName

    if fastMode then
        baseName = baseName .. "_lite"
    end

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
    fastMode = not Spring.IsReplay()
    CacheUnitWeaponInfo()
    local allUnits = spGetAllUnits()
    local currentFrame = spGetGameFrame()
    local bornTime = (currentFrame < 100) and 0 or currentFrame

    for _, uID in ipairs(allUnits) do
        local defID = spGetUnitDefID(uID)
        if isValidUnit(defID) then
            InitUnitRecord(uID, defID, bornTime)
            local xp = spGetUnitExperience(uID) or 0
            unitRecords[uID].finalXP = xp
        end
    end
    spEcho("[Unit Data Logger] Initialized.")

    if not fastMode and Spring.GetConfigInt("Headless", 0) ~= 0 then
        spEcho("[Unit Data Logger] Headless mode enabled")
        Spring.SendCommands("forcestart", "setmaxspeed 99999", "setminspeed 99999", "hideinterface", "turbobarcam_toggle", "skip 9999999")
    end
end

function widget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
    if not ignoreSet[UnitDefs[unitDefID].name] then
        if unitRecords[unitID] then
            table.insert(finishedUnits, unitRecords[unitID])
            unitRecords[unitID] = nil
        end
        InitUnitRecord(unitID, unitDefID, spGetGameFrame())
    end
end

function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage)
    local r = unitRecords[unitID]
    if r then
        r.damageTaken = r.damageTaken + damage
    end
end

function widget:GameFrame(currentFrame)
    -- PROJECTILE CHECK (Global)
    if currentFrame % TARGET_CHECK_INTERVAL == 0 then
        if WG.TurboBarCam and WG.TurboBarCam.API and WG.TurboBarCam.API.getAllTrackedProjectiles then
            local projectiles = WG.TurboBarCam.API.getAllTrackedProjectiles()
            if projectiles then
                for _, proj in pairs(projectiles) do
                    -- Resolve human name safely
                    local ownerName = "Unknown"
                    if proj.ownerID then
                        local oDefID = spGetUnitDefID(proj.ownerID)
                        if oDefID then
                            local ud = UnitDefs[oDefID]
                            if ud then
                                ownerName = ud.translatedHumanName or ud.name
                            end
                        end
                    end

                    table.insert(projectileHistory, currentFrame)
                    table.insert(projectileHistory, proj.id or -1)
                    table.insert(projectileHistory, proj.ownerID or -1)
                    table.insert(projectileHistory, proj.position.x or 0)
                    table.insert(projectileHistory, proj.position.y or 0)
                    table.insert(projectileHistory, proj.position.z or 0)
                    table.insert(projectileHistory, ownerName)
                end
            end
        end
    end

    for uID, r in pairs(unitRecords) do
        if not fastMode then
            -- Position Check
            if currentFrame % POS_CHECK_INTERVAL == 0 then
                local x, _, z = spGetUnitPosition(uID)
                if x then
                    local heading = spGetUnitHeading(uID)
                    local rad = heading * (math.pi / 32768)

                    table.insert(r.positionHistory, currentFrame)
                    table.insert(r.positionHistory, x)
                    table.insert(r.positionHistory, z)
                    table.insert(r.positionHistory, rad)
                end
            end

            -- Target Check
            if currentFrame % TARGET_CHECK_INTERVAL == 0 then
                local weaponIndices = unitDefWeaponIndices[r.defID]
                if weaponIndices then
                    local bestTargetData = nil
                    local bestTier = -1

                    for _, wIdx in ipairs(weaponIndices) do
                        local tType, _, target = spGetUnitWeaponTarget(uID, wIdx)

                        -- Unit Target
                        if tType == 1 and target then
                            local tDefID = spGetUnitDefID(target)
                            if tDefID then
                                local tUd = UnitDefs[tDefID]
                                local tTier = tonumber((tUd.customParams and tUd.customParams.techlevel) or "1")

                                if tTier >= bestTier then
                                    local tx, ty, tz = spGetUnitPosition(target)
                                    if tx then
                                        bestTier = tTier
                                        bestTargetData = {
                                            id = target,
                                            name = tUd.name,
                                            hName = tUd.translatedHumanName or tUd.name,
                                            tier = tTier,
                                            x = tx, y = ty, z = tz,
                                            isGround = false
                                        }
                                    end
                                end
                            end
                            -- Ground Target
                        elseif tType == 2 and target then
                            if 0 >= bestTier then
                                bestTier = 0
                                bestTargetData = {
                                    id = "ground",
                                    name = "ground",
                                    hName = "Ground",
                                    tier = 0,
                                    x = target[1], y = target[2], z = target[3],
                                    isGround = true
                                }
                            end
                        end
                    end

                    if bestTargetData then
                        table.insert(r.targetHistory, currentFrame)
                        table.insert(r.targetHistory, bestTargetData.id)
                        table.insert(r.targetHistory, bestTargetData.name)
                        table.insert(r.targetHistory, bestTargetData.hName)
                        table.insert(r.targetHistory, bestTargetData.tier)
                        table.insert(r.targetHistory, bestTargetData.x)
                        table.insert(r.targetHistory, bestTargetData.y)
                        table.insert(r.targetHistory, bestTargetData.z)
                    end
                end
            end

            -- Activity Check
            if currentFrame % ACTIVITY_CHECK_INTERVAL == 0 then
                local isActive = false
                local weaponIndices = unitDefWeaponIndices[r.defID]

                if weaponIndices then
                    for _, wIdx in ipairs(weaponIndices) do
                        local reloadFrame = spGetUnitWeaponState(uID, wIdx, 'reloadFrame')
                        if reloadFrame and reloadFrame > currentFrame then
                            isActive = true
                            break
                        end
                    end
                end

                if isActive then
                    r.lastActivityFrame = currentFrame
                end

                local timeSinceAction = currentFrame - (r.lastActivityFrame or r.bornFrame)
                local newStatus = (timeSinceAction > IDLE_TIMEOUT_FRAMES) and "IDLE" or "ACTIVE"

                if newStatus ~= r.currentStatus then
                    local transitionFrame = currentFrame

                    if newStatus == "IDLE" and r.currentStatus == "ACTIVE" then
                        transitionFrame = r.lastActivityFrame
                        local lastSeg = r.statusHistory[#r.statusHistory]
                        if lastSeg and transitionFrame < lastSeg.startFrame then
                            transitionFrame = lastSeg.startFrame
                        end
                    end

                    local histLen = #r.statusHistory
                    if histLen > 0 then
                        r.statusHistory[histLen].endFrame = transitionFrame
                    end

                    table.insert(r.statusHistory, {
                        status = newStatus,
                        startFrame = transitionFrame
                    })

                    r.currentStatus = newStatus
                end
            end
        end

        if currentFrame % ACTIVITY_CHECK_INTERVAL == 0 then
            local currentXP = spGetUnitExperience(uID)
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

        local keep = xp >= MIN_XP_THRESHOLD
        local t = unitRecords[unitID].tier or 1
        if not keep and t == 3 then
            local activeFrames = CalcTotalActiveFrames(unitRecords[unitID].statusHistory, frame)
            if activeFrames >= 30 * GAME_FPS then
                keep = true
            end
        end

        PushHistorySegment(unitRecords[unitID], frame)

        if keep then
            table.insert(finishedUnits, unitRecords[unitID])
        end
        unitRecords[unitID] = nil
    end
end

function widget:Shutdown()
    spEcho("--------------------------------------------------")
    spEcho("[Unit Data Logger] PROCESSING STATS & SAVING FILES")
    spEcho("--------------------------------------------------")

    local currentFrame = spGetGameFrame()

    local allUnits = spGetAllUnits()
    for _, uID in ipairs(allUnits) do
        if unitRecords[uID] then
            local xp = spGetUnitExperience(uID) or 0
            unitRecords[uID].finalXP = xp
            PushHistorySegment(unitRecords[uID], currentFrame)
        end
    end

    for _, data in pairs(unitRecords) do
        table.insert(finishedUnits, data)
    end

    local filePath = getFilePath()
    local absolutePath = VFS.GetFileAbsolutePath(filePath) or filePath
    spEcho("[Unit Data Logger] Saving to: " .. filePath)
    spEcho("[Unit Data Logger] Absolute path: " .. absolutePath)
    local rawFile = io.open(filePath, "w")

    local replayName = WG.ReplayMetadata.filename or "Unknown"

    if rawFile then
        rawFile:write("-- Map: " .. (Game.mapName or "Unknown") .. "\n")
        rawFile:write("return {\n")

        rawFile:write("    metadata = ")
        WriteValue(rawFile, { endFrame = currentFrame, replayName = replayName, mapWidth = Game.mapSizeX or 0, mapHeight = Game.mapSizeZ or 0 }, 1)
        rawFile:write(",\n")

        -- Write Projectile History
        rawFile:write("    projectileHistory = ")
        WriteProjectileHistory(rawFile, projectileHistory, 1)
        rawFile:write(",\n")

        rawFile:write("    units = {\n")

        local count = 0
        for _, data in ipairs(finishedUnits) do
            local xp = data.finalXP or 0
            local cleanHistory = ConsolidateSmart(data.statusHistory)

            local isValidBase = xp >= MIN_XP_THRESHOLD
            local isT3Active = false
            if (data.tier or 1) == 3 then
                local totalActive = 0
                for _, seg in ipairs(cleanHistory) do
                    if seg.status == "ACTIVE" then
                        local ef = seg.endFrame or seg.startFrame
                        if ef > seg.startFrame then
                            totalActive = totalActive + (ef - seg.startFrame)
                        end
                    end
                end
                if totalActive >= 30 * GAME_FPS then
                    isT3Active = true
                end
            end

            local isValid = (isValidBase or isT3Active) and isValidUnit(data.defID)

            if isValid then
                local internalName, niceName = GetUnitNames(data.defID)

                local uniqueKey = tostring(data.unitId) .. "_" .. tostring(data.bornFrame)

                rawFile:write("    [\"" .. uniqueKey .. "\"] = {\n")

                rawFile:write(string.format("        unitId = %d,\n", data.unitId))
                rawFile:write(string.format("        name = %q,\n", internalName))
                rawFile:write(string.format("        humanName = %q,\n", niceName))
                rawFile:write(string.format("        defID = %d,\n", data.defID))
                rawFile:write(string.format("        tier = %d,\n", data.tier or 1))
                rawFile:write(string.format("        playerId = %d,\n", data.playerId or -1))
                rawFile:write(string.format("        teamId = %d,\n", data.teamId or -1))
                rawFile:write(string.format("        bornFrame = %d,\n", data.bornFrame))
                if data.diedFrame then
                    rawFile:write(string.format("        diedFrame = %d,\n", data.diedFrame))
                end
                rawFile:write(string.format("        finalXP = %.4f,\n", xp))
                rawFile:write(string.format("        damageTaken = %.1f,\n", data.damageTaken))

                rawFile:write("        statusHistory = ")
                WriteValue(rawFile, cleanHistory, 2)
                rawFile:write(",\n")

                rawFile:write("        positionHistory = ")
                WritePositionHistory(rawFile, data.positionHistory, 2)
                rawFile:write(",\n")

                rawFile:write("        targetHistory = ")
                WriteTargetHistory(rawFile, data.targetHistory, 2)
                rawFile:write("\n")

                rawFile:write("    },\n")

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
        spEcho("[Unit Data Logger] ERROR: Could not open file for writing")
    end
end
