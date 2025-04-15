---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local Log = CommonModules.Log

---@class MouseManager
local MouseManager = {}

function MouseManager.registerMode(modeName)
    if not STATE.mouse.registeredModes[modeName] then
        STATE.mouse.registeredModes[modeName] = true
        Log.debug("Mouse input tracking registered for mode: " .. modeName)
    end
end

local function shouldProcessInput()
    for modeName, _ in pairs(STATE.mouse.registeredModes) do
        if not Util.isModeDisabled(modeName) then
            return true
        end
    end
    return false
end

local function fireCallbacks(eventType, ...)
    if STATE.mouse.callbacks[eventType] then
        for modeName, callback in pairs(STATE.mouse.callbacks[eventType]) do
            if STATE.mouse.registeredModes[modeName] and not Util.isModeDisabled(modeName) then
                callback(...)
            end
        end
    end
end

local function registerCallback(eventType, modeName, callback)
    if not STATE.mouse.callbacks[eventType] then
        STATE.mouse.callbacks[eventType] = {}
    end

    STATE.mouse.callbacks[eventType][modeName] = callback
    Log.debug("Registered " .. eventType .. " callback for mode: " .. modeName)
end

local function processMouseButton(buttonKey, buttonName, mouseX, mouseY, currentGameTime)
    local isDownKey = "is" .. buttonKey .. "MouseDown"
    local pressStartKey = buttonKey:lower() .. "MousePressStartTime"
    local initialPressKey = "initialPress" .. buttonKey
    local lastClickKey = "last" .. buttonKey .. "ClickTime"
    local clickCountKey = buttonKey:lower() .. "ClickCount"
    local isDoubleClickKey = "isDoubleClick" .. buttonKey
    local isDraggingKey = "isDragging" .. buttonKey

    local _, _, lmb, mmb, rmb = Spring.GetMouseState()
    local isDown = ({LMB = lmb, MMB = mmb, RMB = rmb})[buttonKey]
    local lastClickTime = STATE.mouse[lastClickKey] or -math.huge

    if isDown and not STATE.mouse[isDownKey] then
        STATE.mouse[isDownKey] = true
        STATE.mouse[pressStartKey] = currentGameTime
        STATE.mouse[initialPressKey] = { x = mouseX, y = mouseY }

        if currentGameTime - lastClickTime < STATE.mouse.doubleClickThreshold then
            STATE.mouse[clickCountKey] = 2
            STATE.mouse[isDoubleClickKey] = true
            fireCallbacks("onDouble" .. buttonKey, mouseX, mouseY)
        else
            STATE.mouse[clickCountKey] = 1
            STATE.mouse[isDoubleClickKey] = false
        end

        STATE.mouse[lastClickKey] = currentGameTime

    elseif isDown and STATE.mouse[isDownKey] then
        local dx = mouseX - STATE.mouse[initialPressKey].x
        local dy = mouseY - STATE.mouse[initialPressKey].y
        local dragDistance = math.sqrt(dx * dx + dy * dy)
        local dragTime = currentGameTime - STATE.mouse[pressStartKey]

        if STATE.mouse[isDoubleClickKey] then
            fireCallbacks("onDoubleClickHold" .. buttonKey, mouseX, mouseY, dragTime)
        else
            fireCallbacks("onHold" .. buttonKey, mouseX, mouseY, dragTime)
        end

        if not STATE.mouse[isDraggingKey] and (dragDistance > STATE.mouse.dragThreshold or dragTime > STATE.mouse.dragTimeThreshold) then
            STATE.mouse[isDraggingKey] = true
            STATE.mouse.lastDragX = mouseX
            STATE.mouse.lastDragY = mouseY
            fireCallbacks("onDragStart" .. buttonKey, STATE.mouse[initialPressKey].x, STATE.mouse[initialPressKey].y, mouseX, mouseY, STATE.mouse[isDoubleClickKey])
        elseif STATE.mouse[isDraggingKey] then
            local dragDx = mouseX - STATE.mouse.lastDragX
            local dragDy = mouseY - STATE.mouse.lastDragY
            if dragDx ~= 0 or dragDy ~= 0 then
                fireCallbacks("onDrag" .. buttonKey, dragDx, dragDy, mouseX, mouseY, STATE.mouse[isDoubleClickKey])
                STATE.mouse.lastDragX = mouseX
                STATE.mouse.lastDragY = mouseY
            end
        end

    elseif not isDown and STATE.mouse[isDownKey] then
        local wasDoubleClick = STATE.mouse[isDoubleClickKey]
        local wasDragging = STATE.mouse[isDraggingKey]
        local holdTime = currentGameTime - STATE.mouse[pressStartKey]

        if not wasDragging and not wasDoubleClick then
            fireCallbacks("on" .. buttonKey, mouseX, mouseY)
        end

        fireCallbacks("onRelease" .. buttonKey, mouseX, mouseY, wasDoubleClick, wasDragging, holdTime)
        STATE.mouse[isDownKey] = false
        STATE.mouse[isDraggingKey] = false
        STATE.mouse[isDoubleClickKey] = false
        STATE.mouse.lastDragX = nil
        STATE.mouse.lastDragY = nil
    end
end

function MouseManager.update()
    if not shouldProcessInput() then
        return
    end

    local mouseX, mouseY, lmb, mmb, rmb = Spring.GetMouseState()
    local currentGameTime = Spring.GetGameSeconds()

    STATE.mouse.lastMouseX = mouseX
    STATE.mouse.lastMouseY = mouseY

    processMouseButton("LMB", "Left", mouseX, mouseY, currentGameTime)
    processMouseButton("MMB", "Middle", mouseX, mouseY, currentGameTime)
    processMouseButton("RMB", "Right", mouseX, mouseY, currentGameTime)
end

-- MMB handlers
MouseManager.onMMB = function(modeName, callback)
    registerCallback("onMMB", modeName, callback)
end

MouseManager.onDragStartMMB = function(modeName, callback)
    registerCallback("onDragStartMMB", modeName, callback)
end

MouseManager.onDragMMB = function(modeName, callback)
    registerCallback("onDragMMB", modeName, callback)
end

MouseManager.onReleaseMMB = function(modeName, callback)
    registerCallback("onReleaseMMB", modeName, callback)
end

-- RMB handlers
MouseManager.onHoldRMB = function(modeName, callback)
    registerCallback("onHoldRMB", modeName, callback)
end

MouseManager.onDragRMB = function(modeName, callback)
    registerCallback("onDragRMB", modeName, callback)
end

MouseManager.onReleaseRMB = function(modeName, callback)
    registerCallback("onReleaseRMB", modeName, callback)
end

-- LMB (optional, add more if needed)
MouseManager.onLMB = function(modeName, callback)
    registerCallback("onLMB", modeName, callback)
end

MouseManager.onReleaseLMB = function(modeName, callback)
    registerCallback("onReleaseLMB", modeName, callback)
end

return {
    MouseManager = MouseManager
}