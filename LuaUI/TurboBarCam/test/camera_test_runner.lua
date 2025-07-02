---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONSTANTS = ModuleManager.CONSTANTS(function(m) CONSTANTS = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "TestRunner")
local CameraDriver = ModuleManager.CameraDriver(function(m) CameraDriver = m end)
local ModeManager = ModuleManager.ModeManager(function(m) ModeManager = m end)
local CameraStateTracker = ModuleManager.CameraStateTracker(function(m) CameraStateTracker = m end)
local Utils = ModuleManager.Utils(function(m) Utils = m end)
local QuaternionUtils = ModuleManager.QuaternionUtils(function(m) QuaternionUtils = m end)
local MathUtils = ModuleManager.MathUtils(function(m) MathUtils = m end)

---@class CameraTestRunner
local CameraTestRunner = {}

---
-- Test Suite Definition
---
local TestSuite = {
    [1] = { name = "Translate +X", startPos = { x = 4000, y = 300, z = 4000 }, startEuler = { rx = 1.57, ry = 0 }, targetConfig = { position = { x = 5000, y = 300, z = 4000 }, duration = 1.5 } },
}

---
-- Helper Functions
---

local function calculateStdDev(t, mean)
    if #t < 2 then
        return 0
    end
    local sumOfSquares = 0
    for _, val in ipairs(t) do
        sumOfSquares = sumOfSquares + (val - mean) ^ 2
    end
    return math.sqrt(sumOfSquares / #t)
end

local function analyzeData(dataLog, dt)
    if #dataLog < 2 then
        return {}
    end

    local analysis = {
        maxVelocity = 0,
        maxAngularVelocity = 0,
        accelerations = {},
        posDeltas = {},
        rotDeltas = {},
        maxPos_ZScore_index = 0,
        maxRot_ZScore_index = 0,
    }

    for i = 2, #dataLog do
        local current = dataLog[i]
        local prev = dataLog[i - 1]

        local velMag = MathUtils.vector.magnitude(current.vel)
        if velMag > analysis.maxVelocity then
            analysis.maxVelocity = velMag
        end

        local angVelMag = MathUtils.vector.magnitude(current.angVel)
        if angVelMag > analysis.maxAngularVelocity then
            analysis.maxAngularVelocity = angVelMag
        end

        local accelVec = MathUtils.vector.subtract(current.vel, prev.vel)
        table.insert(analysis.accelerations, MathUtils.vector.magnitude(accelVec) / dt)

        local posDeltaVec = MathUtils.vector.subtract(current.pos, prev.pos)
        table.insert(analysis.posDeltas, MathUtils.vector.magnitude(posDeltaVec) / dt)

        local rotDeltaQuat = QuaternionUtils.multiply(current.orient, QuaternionUtils.inverse(prev.orient))
        local _, rotAngleRad = QuaternionUtils.toAxisAngle(rotDeltaQuat)
        table.insert(analysis.rotDeltas, math.abs(rotAngleRad / dt))
    end

    -- Jitter Score
    local meanAccel = 0
    for _, v in ipairs(analysis.accelerations) do meanAccel = meanAccel + v end
    if #analysis.accelerations > 0 then meanAccel = meanAccel / #analysis.accelerations end
    local sumOfSquares = 0
    for _, v in ipairs(analysis.accelerations) do sumOfSquares = sumOfSquares + (v - meanAccel) ^ 2 end
    if #analysis.accelerations > 0 then analysis.jitterScore = math.sqrt(sumOfSquares / #analysis.accelerations) else analysis.jitterScore = 0 end


    -- Z-Scores
    local posDeltaMean, rotDeltaMean = 0, 0
    for _, v in ipairs(analysis.posDeltas) do posDeltaMean = posDeltaMean + v end
    if #analysis.posDeltas > 0 then posDeltaMean = posDeltaMean / #analysis.posDeltas end

    for _, v in ipairs(analysis.rotDeltas) do rotDeltaMean = rotDeltaMean + v end
    if #analysis.rotDeltas > 0 then rotDeltaMean = rotDeltaMean / #analysis.rotDeltas end

    local posDeltaStdDev = calculateStdDev(analysis.posDeltas, posDeltaMean)
    local rotDeltaStdDev = calculateStdDev(analysis.rotDeltas, rotDeltaMean)

    analysis.maxPos_ZScore, analysis.maxRot_ZScore = 0, 0
    if posDeltaStdDev > 0.01 then
        for i = 1, #analysis.posDeltas do
            local z = math.abs((analysis.posDeltas[i] - posDeltaMean) / posDeltaStdDev)
            if z > analysis.maxPos_ZScore then
                analysis.maxPos_ZScore = z
                analysis.maxPos_ZScore_index = i
            end
        end
    end

    if rotDeltaStdDev > 0.01 then
        for i = 1, #analysis.rotDeltas do
            local z = math.abs((analysis.rotDeltas[i] - rotDeltaMean) / rotDeltaStdDev)
            if z > analysis.maxRot_ZScore then
                analysis.maxRot_ZScore = z
                analysis.maxRot_ZScore_index = i
            end
        end
    end

    return analysis
end

local function interpretAnalysis(analysis, dataLog)
    local verdicts = {}
    if (analysis.maxRot_ZScore or 0) > 3.0 then
        local failIndex = analysis.maxRot_ZScore_index
        if dataLog[failIndex] then
            local frame = dataLog[failIndex].frame
            table.insert(verdicts, string.format("FAIL: Severe rotational jump detected around f=%s", frame))
        end
    end

    if (analysis.maxPos_ZScore or 0) > 3.0 then
        local failIndex = analysis.maxPos_ZScore_index
        if dataLog[failIndex] then
            local frame = dataLog[failIndex].frame
            table.insert(verdicts, string.format("FAIL: Severe positional jump detected around f=%s", frame))
        end
    end

    if #verdicts == 0 then
        return "PASS: Movement appears smooth."
    else
        return table.concat(verdicts, " ")
    end
end


---
-- Public Functions
---

function CameraTestRunner.generateReport()
    local runnerState = STATE.testRunner
    local report_lines = { "========== CAMERA DRIVER TEST SUITE REPORT ==========" }

    for _, testId in ipairs(runnerState.testQueue) do
        local res = runnerState.results[testId]
        if res then
            local test = TestSuite[testId]
            local analysis = res.analysis
            local verdict = interpretAnalysis(analysis, res.data)

            local report_string = string.format(
                    "[%s] (ID: %d)\n  >> Verdict: %s\n  Jitter: %.2f | Z-Score Pos: %.2f | Z-Score Rot: %.2f | Max Vel: %.1f | Max Ang Vel: %.2f",
                    test.name,
                    testId,
                    verdict,
                    analysis.jitterScore or 0,
                    analysis.maxPos_ZScore or 0,
                    analysis.maxRot_ZScore or 0,
                    analysis.maxVelocity or 0,
                    analysis.maxAngularVelocity or 0
            )
            table.insert(report_lines, report_string)
        end
    end
    table.insert(report_lines, "=================== END OF REPORT ===================")

    local full_report = table.concat(report_lines, "\n")
    Log:info(full_report)

    local file = io.open("LuaUI/TurboBarCam/test/result.txt", "w")
    if file then
        file:write(full_report)
        file:close()
        Log:info("Test report saved to LuaUI/TurboBarCam/test/result.txt")
    else
        Log:warn("Could not open file to save test report.")
    end
end

function CameraTestRunner.start(testId)
    if Utils.isTurboBarCamDisabled() then
        return
    end
    local runnerState = STATE.testRunner
    if runnerState.isRunning then
        Log:warn("Test suite is already running.")
        return
    end
    ModeManager.disableMode()

    runnerState.testQueue = {}
    if testId and TestSuite[tonumber(testId)] then
        Log:info("Initializing single test run for ID: " .. testId)
        table.insert(runnerState.testQueue, tonumber(testId))
    else
        Log:info("Initializing full camera test suite...")
        for id in pairs(TestSuite) do
            table.insert(runnerState.testQueue, id)
        end
        table.sort(runnerState.testQueue)
    end

    if #runnerState.testQueue == 0 then
        Log:warn("No valid tests found for ID: " .. tostring(testId))
        return
    end

    local mapX = Game.mapSizeX
    local mapZ = Game.mapSizeZ
    Spring.SetCameraState({ px = mapX / 2, py = 400, pz = mapZ / 2, rx = 1.57, ry = 0 })

    runnerState.isRunning = true
    runnerState.queueIndex = 1
    runnerState.testPhase = "setup"
    runnerState.phaseTimer = 0.5
    runnerState.results = {}
end

function CameraTestRunner.update(dt)
    local runnerState = STATE.testRunner
    if not runnerState.isRunning then
        return
    end

    local testId = runnerState.testQueue[runnerState.queueIndex]
    if not testId then
        runnerState.isRunning = false
        runnerState.testPhase = "idle"
        CameraTestRunner.generateReport()
        return
    end

    local test = TestSuite[testId]
    runnerState.phaseTimer = runnerState.phaseTimer - dt

    if runnerState.testPhase == "setup" then
        Log:debug("Setting up test: " .. test.name)
        Spring.SetCameraState({ px = test.startPos.x, py = test.startPos.y, pz = test.startPos.z, rx = test.startEuler.rx, ry = test.startEuler.ry })
        runnerState.phaseTimer = 0
        runnerState.testPhase = "run"
        runnerState.phaseTimer =  test.targetConfig.duration + 0.5
        runnerState.results[testId] = { data = {} }
        ModeManager.disableMode()

    elseif runnerState.testPhase == "run" then
        runnerState.testPhase = "running"
        runnerState.testStartTime = Spring.GetTimer()
        local target = test.targetConfig
        if not target.position then
            target.position = test.startPos
        end
        CameraDriver.setTarget(target)

    elseif runnerState.testPhase == "running" then
        table.insert(runnerState.results[testId].data, {
            frame = Spring.GetGameFrame(),
            pos = CameraStateTracker.getPosition(),
            vel = CameraStateTracker.getVelocity(),
            orient = CameraStateTracker.getOrientation(),
            angVel = CameraStateTracker.getAngularVelocity()
        })
        if runnerState.phaseTimer <= 0 then
            runnerState.testPhase = "teardown"
            runnerState.phaseTimer = 0.1
        end

    elseif runnerState.testPhase == "teardown" then
        if runnerState.phaseTimer <= 0 then
            local testResult = runnerState.results[testId]
            testResult.analysis = analyzeData(testResult.data, dt)
            runnerState.queueIndex = runnerState.queueIndex + 1
            runnerState.testPhase = "setup"
            runnerState.phaseTimer = 0.2
        end
    end
end

return CameraTestRunner