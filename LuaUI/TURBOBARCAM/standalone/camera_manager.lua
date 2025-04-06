---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TURBOBARCAM/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TURBOBARCAM/common/log.lua").Log
---@type Util
local Util = VFS.Include("LuaUI/TURBOBARCAM/common/utils.lua").Util

local STATE = WidgetContext.WidgetState.STATE

-- Initialize the call history in WG to persist across module reloads
if not WG.TURBOBARCAM then
    WG.TURBOBARCAM = {}
end

if not WG.TURBOBARCAM.CALL_HISTORY then
    WG.TURBOBARCAM.CALL_HISTORY = {
        GetCameraState = {},
        SetCameraState = {}
    }
end

---@class CameraManager
local CameraManager = {
    cache = {
        -- Camera state caching
        currentState = nil,
        currentFrame = 0,
        dirtyFlag = false
    }
}

---@field historyLimit number Maximum number of calls to track in history
local options = {
    -- Maximum number of calls to track in history
    historyLimit = 50,
}

local function addToHistory(historyType, entry)
    -- Skip UpdateManager calls for cleaner history
    if entry.source == "UpdateManager.processCycle" and historyType == "GetCameraState" then
        return
    end

    table.insert(WG.TURBOBARCAM.CALL_HISTORY[historyType], 1, entry)
    if #WG.TURBOBARCAM.CALL_HISTORY[historyType] > options.historyLimit then
        table.remove(WG.TURBOBARCAM.CALL_HISTORY[historyType])
    end
end

--- Begin a new frame in the camera manager
---@param frameNum number The current frame number
function CameraManager.beginFrame(frameNum)
    if frameNum ~= CameraManager.cache.currentFrame then
        CameraManager.cache.currentFrame = frameNum
    end
end

--- Get the current camera state (cached per frame)
---@param source string Source of the getCameraState call for tracking
---@return table cameraState The current camera state
function CameraManager.getCameraState(source)
    assert(source, "Source parameter is required for getCameraState")

    addToHistory("GetCameraState", {
        frame = CameraManager.cache.currentFrame,
        source = source,
        time = os.clock(),
        mode = STATE.mode or "none"
    })

    -- Check if we need to refresh the cached state
    if CameraManager.cache.dirtyFlag or not CameraManager.cache.currentState then
        CameraManager.cache.currentState = Spring.GetCameraState()
        CameraManager.cache.dirtyFlag = false

        -- Verify that we're in FPS mode
        if CameraManager.cache.currentState.mode ~= 0 then
            Log.debug("Warning: Camera is not in FPS mode, current mode: " .. (CameraManager.cache.currentState.mode or "nil"))
            CameraManager.cache.currentState.mode = 0
            CameraManager.cache.currentState.name = "fps"
        end
    end

    return CameraManager.cache.currentState
end

-- Detect and fix large rotation changes that might cause camera spinning
---@param currentState table Current camera state
---@param newState table New camera state to apply
---@param smoothing number Smoothing factor (0-1)
---@param source string Source of the operation for logging
---@return boolean Whether a fix was applied
local function applyRotationFix(currentState, newState, smoothing, source)
    ---@type table
    local fixRotationPatch = {}
    local fixRequired = false

    -- Check for large rx changes
    if currentState.rx ~= newState.rx and currentState.rx and newState.rx and
            math.abs(currentState.rx - newState.rx) > 1 then
        Log.debug(string.format("[%s] Rotation fix detected: currentState.rx=%.3f newState.rx=%.3f",
                source, currentState.rx or 0, newState.rx or 0))
        fixRequired = true
        fixRotationPatch.rx = newState.rx
    end

    -- Check for large ry changes
    if currentState.ry ~= newState.ry and currentState.ry and newState.ry and
            math.abs(currentState.ry - newState.ry) > 1 then
        Log.debug(string.format("[%s] Rotation fix detected: currentState.ry=%.3f newState.ry=%.3f",
                source, currentState.ry or 0, newState.ry or 0))
        fixRequired = true
        fixRotationPatch.ry = newState.ry
    end

    -- Apply fix only if needed and when smoothing is enabled
    if fixRequired and smoothing > 0 then
        Spring.SetCameraState(fixRotationPatch, 0)
    end

    return fixRequired
end

-- Normalize rotation values for Spring engine
---@param cameraState table The camera state to normalize
---@return table normalized The normalized camera state
local function normalizeRotation(cameraState)
    ---@type table
    local normalized = Util.deepCopy(cameraState)

    -- Ensure rx is properly normalized for Spring (range [0, pi])
    if normalized.rx ~= nil then
        normalized.rx = normalized.rx % (2 * math.pi)
        if normalized.rx > math.pi then
            normalized.rx = 2 * math.pi - normalized.rx
        end
    end

    -- Ensure ry is properly normalized for Spring (range [-pi, pi])
    if normalized.ry ~= nil then
        normalized.ry = normalized.ry % (2 * math.pi)
        if normalized.ry > math.pi then
            normalized.ry = normalized.ry - 2 * math.pi
        end
    end

    -- Ensure rz is properly normalized for Spring (range [-pi, pi])
    if normalized.rz ~= nil then
        normalized.rz = normalized.rz % (2 * math.pi)
        if normalized.rz > math.pi then
            normalized.rz = normalized.rz - 2 * math.pi
        end
    end

    return normalized
end

--- Apply camera state with optional smoothing
---@param cameraState table Camera state to apply
---@param smoothing number Smoothing factor (0 for no smoothing, 1 for full smoothing)
---@param source string Source of the setCameraState call for tracking
function CameraManager.setCameraState(cameraState, smoothing, source)
    assert(source, "Source parameter is required for setCameraState")

    -- Add to history for debugging
    addToHistory("SetCameraState", {
        frame = CameraManager.cache.currentFrame,
        source = source,
        time = os.clock(),
        smoothing = smoothing,
        mode = STATE.mode or "none"
    })

    -- Normal path - direct camera state setting
    local normalizedState = normalizeRotation(cameraState)
    local currentState = Spring.GetCameraState()

    -- Fix potential rotation issues
    applyRotationFix(currentState, normalizedState, smoothing, source)

    -- Apply the camera state
    Spring.SetCameraState(normalizedState, smoothing)

    -- Mark state as dirty since we've changed it
    CameraManager.cache.dirtyFlag = true
end

---@class CallHistoryReturn
---@field frame number Current frame number
---@field GetCameraState table Get calls history
---@field SetCameraState table Set calls history

--- Get call history for debugging
---@return CallHistoryReturn Call history for debugging
function CameraManager.getCallHistory()
    return {
        frame = CameraManager.cache.currentFrame,
        GetCameraState = {
            history = WG.TURBOBARCAM.CALL_HISTORY.GetCameraState
        },
        SetCameraState = {
            history = WG.TURBOBARCAM.CALL_HISTORY.SetCameraState
        }
    }
end

--- Print camera call history in a formatted way
function CameraManager.printCallHistory()
    local history = CameraManager.getCallHistory()
    local getCalls = history.GetCameraState.history
    local setCalls = history.SetCameraState.history

    Log.info("=== Camera Call History (Frame " .. history.frame .. ") ===")
    Log.info("GetCameraState calls: " .. #getCalls)
    -- Print GetCameraState calls
    for i = 1, #getCalls do
        local call = getCalls[i]
        Log.info(string.format("%d. GET  | Mode: %s | Frame: %d. | Source: %s",
                i, call.mode, call.frame, call.source))
    end

    Log.info("SetCameraState calls: " .. #setCalls)

    -- Print SetCameraState calls
    for i = 1, #setCalls do
        local call = setCalls[i]
        local smoothingStr = call.smoothing > 0 and "SMOOTH" or "INSTANT"
        Log.info(string.format("%d. SET  | Mode: %s | Frame: %d. | Source: %s | %s",
                i, call.mode, call.frame, call.source, smoothingStr))
    end

    Log.info("======================================")
end

-- Clean up resources when the manager is no longer needed
function CameraManager.shutdown()
    CameraManager.cache = {
        currentState = nil,
        currentFrame = 0,
        dirtyFlag = false
    }

    WG.TURBOBARCAM.CALL_HISTORY = {}

end

return {
    CameraManager = CameraManager
}