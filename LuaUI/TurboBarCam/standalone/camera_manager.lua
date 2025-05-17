---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log
---@type Util
local Util = VFS.Include("LuaUI/TurboBarCam/common/utils.lua").Util

local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG

-- Initialize the call history in WG to persist across module reloads
if not WG.TurboBarCam then
    WG.TurboBarCam = {}
end

if not WG.TurboBarCam.CALL_HISTORY then
    WG.TurboBarCam.CALL_HISTORY = {
        GetCameraState = {},
        SetCameraState = {}
    }
end

---@class CameraManager
local CameraManager = {
    cache = {
        -- Camera state caching
        currentState = nil,
        dirtyFlag = false,
        lastRefreshTime = 0,
        refreshInterval = 0.1 -- Refresh cache every 100ms
    }
}

---@field historyLimit number Maximum number of calls to track in history
local options = {
    -- Maximum number of calls to track in history
    historyLimit = 50,
}

function CameraManager.toggleZoom()
    if Util.isTurboBarCamDisabled() then
        return
    end

    local cycle = {
        [45] = 24,
        [24] = 12,
        [12] = 45
    }
    local camState = CameraManager.getCameraState("WidgetControl.toggleZoom")
    local fov = cycle[camState.fov] or 45
    CameraManager.setCameraState({fov = fov}, 1, "WidgetControl.toggleZoom")
end

function CameraManager.setFov(fov)
    if Util.isTurboBarCamDisabled() then
        return
    end

    local camState = CameraManager.getCameraState("WidgetControl.setFov")
    if camState.fov == fov then
        return
    end
    CameraManager.setCameraState({fov = fov}, 1, "WidgetControl.setFov")
end

local function addToHistory(historyType, entry)
    if WidgetContext.CONFIG.DEBUG.LOG_LEVEL ~= "TRACE" then
        return
    end

    -- Skip UpdateManager calls for cleaner history
    if entry.source == "UpdateManager.processCycle" and historyType == "GetCameraState" then
        return
    end

    local history = WG.TurboBarCam.CALL_HISTORY[historyType]

    -- Check if this is a repeated call (same source and mode)
    if #history > 0 then
        local lastEntry = history[1]
        if lastEntry.source == entry.source and lastEntry.mode == entry.mode and
                (historyType ~= "SetCameraState" or lastEntry.smoothing == entry.smoothing) then
            -- This is a repeat call, just increment the count
            lastEntry.count = (lastEntry.count or 1) + 1
            return
        end
    end

    -- New unique entry
    entry.count = 1
    table.insert(history, 1, entry)

    -- Keep the history within size limit
    if #history > options.historyLimit then
        table.remove(history)
    end
end

--- Get the current camera state (with time-based cache)
---@param source string Source of the getCameraState call for tracking
---@return table cameraState The current camera state
function CameraManager.getCameraState(source)
    if CONFIG.PERFORMANCE.CAMERA_CACHE == false then
        return Spring.GetCameraState()
    end
    assert(source, "Source parameter is required for getCameraState")

    addToHistory("GetCameraState", {
        source = source,
        time = os.clock(),
        mode = STATE.tracking.mode or "none"
    })

    local currentTime = os.clock()
    local timeSinceLastRefresh = currentTime - (CameraManager.cache.lastRefreshTime or 0)

    -- Check if we need to refresh the cached state
    if CameraManager.cache.dirtyFlag or
            not CameraManager.cache.currentState or
            timeSinceLastRefresh > CameraManager.cache.refreshInterval then

        CameraManager.cache.currentState = Spring.GetCameraState()
        CameraManager.cache.dirtyFlag = false
        CameraManager.cache.lastRefreshTime = currentTime

        -- Verify that we're in FPS mode
        if CameraManager.cache.currentState.mode ~= 0 then
            Log.trace("Warning: Camera is not in FPS mode, current mode: " .. (CameraManager.cache.currentState.mode or "nil"))
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
        Log.trace(string.format("[%s] Rotation fix detected: currentState.rx=%.3f newState.rx=%.3f",
                source, currentState.rx or 0, newState.rx or 0))
        fixRequired = true
        fixRotationPatch.rx = newState.rx
    end

    -- Check for large ry changes
    if currentState.ry ~= newState.ry and currentState.ry and newState.ry and
            math.abs(currentState.ry - newState.ry) > 1 then
        Log.trace(string.format("[%s] Rotation fix detected: currentState.ry=%.3f newState.ry=%.3f",
                source, currentState.ry or 0, newState.ry or 0))
        fixRequired = true
        fixRotationPatch.ry = newState.ry
    end

    -- Apply fix only if needed and when smoothing is enabled
    if fixRequired and smoothing > 0 then
        CameraManager.setCameraState(fixRotationPatch, 0, "CameraManager.applyRotationFix")
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
    if CONFIG.PERFORMANCE.CAMERA_CACHE == false then
        Spring.SetCameraState(cameraState, smoothing)
    end
    assert(source, "Source parameter is required for setCameraState")

    -- Add to history for debugging
    addToHistory("SetCameraState", {
        source = source,
        time = os.clock(),
        smoothing = smoothing,
        mode = STATE.tracking.mode or "none"
    })

    -- todo check if these are required
    --local normalizedState = normalizeRotation(cameraState)
    --applyRotationFix(currentState, normalizedState, smoothing, source)

    -- Apply the camera state
    Spring.SetCameraState(cameraState, smoothing)

    -- Mark state as dirty since we've changed it
    CameraManager.cache.dirtyFlag = true
end

---@class CallHistoryReturn
---@field GetCameraState table Get calls history
---@field SetCameraState table Set calls history

--- Get call history for debugging
---@return CallHistoryReturn Call history for debugging
function CameraManager.getCallHistory()
    return {
        GetCameraState = {
            history = WG.TurboBarCam.CALL_HISTORY.GetCameraState
        },
        SetCameraState = {
            history = WG.TurboBarCam.CALL_HISTORY.SetCameraState
        }
    }
end

--- Print camera call history in a formatted way
function CameraManager.printCallHistory()
    if WidgetContext.CONFIG.DEBUG.LOG_LEVEL ~= "TRACE" then
        Log.info("Call history is gathered only when LOG_LEVEL=TRACE")
        return
    end

    local history = CameraManager.getCallHistory()
    local getCalls = history.GetCameraState.history
    local setCalls = history.SetCameraState.history

    Log.info("=== Camera Call History ===")
    Log.info("GetCameraState calls:")
    -- Print GetCameraState calls
    for i = 1, #getCalls do
        local call = getCalls[i]
        local countStr = call.count > 1 and " [" .. call.count .. "x]" or ""
        Log.info(string.format("%d. GET  | Mode: %s | Source: %s%s",
                i, call.mode, call.source, countStr))
    end

    Log.info("SetCameraState calls:")
    -- Print SetCameraState calls
    for i = 1, #setCalls do
        local call = setCalls[i]
        local smoothingStr = call.smoothing > 0 and "SMOOTH" or "INSTANT"
        local countStr = call.count > 1 and " [" .. call.count .. "x]" or ""
        Log.info(string.format("%d. SET  | Mode: %s | Source: %s | %s%s",
                i, call.mode, call.source, smoothingStr, countStr))
    end

    Log.info("======================================")
end

--- Compare two camera states and print their differences
---@param oldState table First camera state
---@param newState table Second camera state
---@param source string Source of the newState for tracking
function CameraManager.printCameraStateDiff(oldState, newState, source)
    local threshold = 0.001

    local hasChanges = false
    local cameraStateKeys = {
        -- Position
        "px", "py", "pz",
        -- Rotation
        "rx", "ry", "rz",
        -- Direction vectors
        "dx", "dy", "dz",
        -- Up vectors
        "ux", "uy", "uz",
        -- Camera mode and name
        "mode", "name",
        -- Rotation and zoom related
        "flipped", "fov", "height", "zscale", "zoom",
        -- Other camera properties
        "dist", "gndOffset", "relDist", "tiltSpeed", "time",
    }

    -- Print header
    Log.debug("===== Camera State Diff [" .. source .. "] =====")

    -- Function to format values for display
    local function formatValue(value)
        if type(value) == "number" then
            return string.format("%.6f", value)
        elseif value == nil then
            return "nil"
        else
            return tostring(value)
        end
    end

    -- Check each camera state property
    for _, key in ipairs(cameraStateKeys) do
        local val1 = oldState[key]
        local val2 = newState[key]

        -- Skip if newState value is nil (indicating no change) or both are nil
        if not (val2 == nil or (val1 == nil and val2 == nil)) then
            -- Check if values are different
            local isDifferent = false
            if type(val1) == "number" and type(val2) == "number" then
                -- For numbers, use threshold comparison
                isDifferent = math.abs(val1 - val2) > threshold
            else
                -- For other types, direct comparison
                isDifferent = val1 ~= val2
            end

            -- Print difference if found
            if isDifferent then
                hasChanges = true
                Log.debug(string.format("  %s: %s -> %s",
                        key,
                        formatValue(val1),
                        formatValue(val2)))
            end
        end
    end

    -- Check for any keys in one state but not in the known list
    local extraKeys = {}
    for key, _ in pairs(oldState) do
        if not Util.tableContains(cameraStateKeys, key) and newState[key] ~= nil and oldState[key] ~= newState[key] then
            table.insert(extraKeys, key)
        end
    end

    for key, _ in pairs(newState) do
        if not Util.tableContains(cameraStateKeys, key) and
                not Util.tableContains(extraKeys, key) and
                newState[key] ~= nil and
                oldState[key] ~= newState[key] then
            table.insert(extraKeys, key)
        end
    end

    -- Print extra keys if any
    if #extraKeys > 0 then
        hasChanges = true
        Log.debug("  Extra properties with differences:")
        for _, key in ipairs(extraKeys) do
            Log.debug(string.format("  %s: %s -> %s",
                    key,
                    formatValue(oldState[key]),
                    formatValue(newState[key])))
        end
    end

    -- If no changes were found
    if not hasChanges then
        Log.debug("  No significant differences found (threshold: " .. threshold .. ")")
    end

    Log.debug("=============================================")

    return hasChanges
end

-- Clean up resources when the manager is no longer needed
function CameraManager.shutdown()
    CameraManager.cache = {
        currentState = nil,
        dirtyFlag = false
    }

    WG.TurboBarCam.CALL_HISTORY = {
        GetCameraState = {},
        SetCameraState = {}
    }
end

return {
    CameraManager = CameraManager
}