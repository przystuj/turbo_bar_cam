---@type Util
local Util = VFS.Include("LuaUI/TURBOBARCAM/common/utils.lua").Util

---@class HistoryEntry
---@field frame number The frame number when this call was made
---@field source string The source of the call
---@field time number The timestamp when the call was made
---@field forced boolean|nil Whether this was a forced refresh (for get calls)
---@field smoothing number|nil The smoothing factor used (for set calls)

---@class CallHistory
---@field get HistoryEntry[] History of get calls
---@field set HistoryEntry[] History of set calls

---@class CameraCache
---@field currentState table|nil The cached camera state
---@field currentFrame number The current frame number
---@field dirtyFlag boolean Whether the cache needs refreshing
---@field callHistory CallHistory History of camera calls

---@class CameraManager
local CameraManager = {}

-- Simple internal state storage
---@type CameraCache
local cache = {
    -- Camera state caching
    currentState = nil,
    currentFrame = 0,
    dirtyFlag = false,

    -- Call history for debugging
    callHistory = {
        GetCameraState = {},
        SetCameraState = {}
    }
}

---@class CameraOptions
---@field historyLimit number Maximum number of calls to track in history

-- Configuration - read from global CONFIG
---@type CameraOptions
local options = {
    -- Maximum number of calls to track in history
    historyLimit = 100,
}

-- Add an entry to history, respecting the limit
---@param historyType "GetCameraState"|"SetCameraState" "GetCameraState" or "SetCameraState"
---@param entry HistoryEntry The history entry to add
local function addToHistory(historyType, entry)
    local history = cache.callHistory[historyType]
    table.insert(history, 1, entry)
    if #history > options.historyLimit then
        table.remove(history)
    end
end

--- Begin a new frame in the camera manager
---@param frameNum number The current frame number
function CameraManager.beginFrame(frameNum)
    if frameNum ~= cache.currentFrame then
        cache.currentFrame = frameNum
    end
end

--- Get the current camera state (cached per frame)
---@param source string Source of the getCameraState call for tracking
---@return table cameraState The current camera state
function CameraManager.getCameraState(source)
    assert(source, "Source parameter is required for getCameraState")

    addToHistory("GetCameraState", {
        frame = cache.currentFrame,
        source = source,
        time = os.clock()
    })

    -- Check if we need to refresh the cached state
    if cache.dirtyFlag or not cache.currentState then
        cache.currentState = Spring.GetCameraState()
        cache.dirtyFlag = false

        -- Verify that we're in FPS mode
        if cache.currentState.mode ~= 0 then
            Util.debugEcho("Warning: Camera is not in FPS mode, current mode: " .. (cache.currentState.mode or "nil"))
            cache.currentState.mode = 0
            cache.currentState.name = "fps"
        end
    end

    return cache.currentState
end

--- Mark the state as dirty (needs refreshing)
function CameraManager.markDirty()
    cache.dirtyFlag = true
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
        Util.debugEcho(string.format("[%s] Rotation fix detected: currentState.rx=%.3f newState.rx=%.3f",
                source, currentState.rx or 0, newState.rx or 0))
        fixRequired = true
        fixRotationPatch.rx = newState.rx
    end

    -- Check for large ry changes
    if currentState.ry ~= newState.ry and currentState.ry and newState.ry and
            math.abs(currentState.ry - newState.ry) > 1 then
        Util.debugEcho(string.format("[%s] Rotation fix detected: currentState.ry=%.3f newState.ry=%.3f",
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
        frame = cache.currentFrame,
        source = source,
        time = os.clock(),
        smoothing = smoothing
    })

    -- Normal path - direct camera state setting
    local normalizedState = normalizeRotation(cameraState)
    local currentState = Spring.GetCameraState()

    -- Fix potential rotation issues
    applyRotationFix(currentState, normalizedState, smoothing, source)

    -- Apply the camera state
    Spring.SetCameraState(normalizedState, smoothing)

    -- Mark state as dirty since we've changed it
    cache.dirtyFlag = true

    -- If no smoothing is applied, we can update our cached state directly
    if smoothing == 0 then
        cache.currentState = Util.deepCopy(cameraState)
    end
end

--- Create a partial state update (only specified fields)
---@param fields table List of field names to include in the partial state
---@param source string Source of the call for tracking
---@return table partialState The partial camera state
function CameraManager.createPartialState(fields, source)
    assert(source, "Source parameter is required for createPartialState")

    local partialState = {}
    local currentState = CameraManager.getCameraState(source)

    -- Copy only the fields we want to update
    for _, field in ipairs(fields) do
        partialState[field] = currentState[field]
    end

    return partialState
end

---@class CallHistoryReturn
---@field frame number Current frame number
---@field getCalls table Get calls history
---@field setCalls table Set calls history

--- Get call history for debugging
---@return CallHistoryReturn Call history for debugging
function CameraManager.getCallHistory()
    return {
        frame = cache.currentFrame,
        getCalls = {
            history = cache.callHistory.get
        },
        setCalls = {
            history = cache.callHistory.set
        }
    }
end

--- Print camera call history in a formatted way
---@param maxEntries number|nil Maximum number of entries to print (optional)
function CameraManager.printCallHistory(maxEntries)
    local history = CameraManager.getCallHistory()
    local getCalls = history.getCalls.history
    local setCalls = history.setCalls.history

    -- Default to 20 entries if not specified
    maxEntries = maxEntries or 20

    Util.echo("=== Camera Call History (Frame " .. history.frame .. ") ===")
    Util.echo("GetCameraState calls: " .. #getCalls)

    -- Print GetCameraState calls
    for i = 1, math.min(#getCalls, maxEntries) do
        local call = getCalls[i]
        local forceFlag = call.forced and " (FORCED)" or ""
        Util.echo(string.format("%d. GET  | Frame: %d | Source: %s%s",
                i, call.frame, call.source, forceFlag))
    end

    Util.echo("\nSetCameraState calls: " .. #setCalls)

    -- Print SetCameraState calls
    for i = 1, math.min(#setCalls, maxEntries) do
        local call = setCalls[i]
        local smoothingStr = call.smoothing > 0 and "SMOOTH" or "INSTANT"
        Util.echo(string.format("%d. SET  | Frame: %d | Source: %s | %s",
                i, call.frame, call.source, smoothingStr))
    end

    Util.echo("======================================")
end

-- Clean up resources when the manager is no longer needed
function CameraManager.shutdown()
    -- Clear all internal state
    cache = {
        currentState = nil,
        currentFrame = 0,
        dirtyFlag = false,
        callHistory = {
            get = {},
            set = {}
        }
    }
end

return {
    CameraManager = CameraManager
}