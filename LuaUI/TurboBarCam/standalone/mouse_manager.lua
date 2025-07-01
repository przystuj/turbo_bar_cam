---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local Log = ModuleManager.Log(function(m) Log = m end, "MouseManager")
local Utils = ModuleManager.Utils(function(m) Utils = m end)

---@class MouseManager
local MouseManager = {}

function MouseManager.registerMode(modeName)
    if not STATE.core.mouse.registeredModes[modeName] then
        STATE.core.mouse.registeredModes[modeName] = true
        Log:trace("Mouse input tracking registered for mode: " .. modeName)
    end
end

local function shouldProcessInput()
    for modeName, _ in pairs(STATE.core.mouse.registeredModes) do
        if not Utils.isModeDisabled(modeName) then
            return true
        end
    end
    return false
end

local function fireCallbacks(eventType, ...)
    if STATE.core.mouse.callbacks[eventType] then
        for modeName, callback in pairs(STATE.core.mouse.callbacks[eventType]) do
            if STATE.core.mouse.registeredModes[modeName] and not Utils.isModeDisabled(modeName) then
                callback(...)
            end
        end
    end
end

local function registerCallback(eventType, modeName, callback)
    if not STATE.core.mouse.callbacks[eventType] then
        STATE.core.mouse.callbacks[eventType] = {}
    end

    STATE.core.mouse.callbacks[eventType][modeName] = callback
    Log:trace("Registered " .. eventType .. " callback for mode: " .. modeName)
end

local function processMouseButton(buttonKey, buttonName, mouseX, mouseY, currentTime)
    local isDownKey = "is" .. buttonKey .. "MouseDown"
    local pressStartKey = buttonKey:lower() .. "MousePressStartTime"
    local initialPressKey = "initialPress" .. buttonKey
    local lastClickKey = "last" .. buttonKey .. "ClickTime"
    local clickCountKey = buttonKey:lower() .. "ClickCount"
    local isDoubleClickKey = "isDoubleClick" .. buttonKey
    local isDraggingKey = "isDragging" .. buttonKey

    local _, _, lmb, mmb, rmb = Spring.GetMouseState()
    local isDown = ({ LMB = lmb, MMB = mmb, RMB = rmb })[buttonKey]
    local lastClickTime = STATE.active.mouse[lastClickKey]

    if isDown and not STATE.active.mouse[isDownKey] then
        -- Button just pressed
        STATE.active.mouse[isDownKey] = true
        STATE.active.mouse[pressStartKey] = currentTime
        STATE.active.mouse[initialPressKey] = { x = mouseX, y = mouseY }

        -- Check for double click
        if lastClickTime and Spring.DiffTimers(currentTime, lastClickTime) < STATE.active.mouse.doubleClickThreshold then
            STATE.active.mouse[clickCountKey] = 2
            STATE.active.mouse[isDoubleClickKey] = true
            fireCallbacks("onDouble" .. buttonKey, mouseX, mouseY)
        else
            STATE.active.mouse[clickCountKey] = 1
            STATE.active.mouse[isDoubleClickKey] = false
        end

        STATE.active.mouse[lastClickKey] = currentTime

    elseif isDown and STATE.active.mouse[isDownKey] then
        -- Button being held down
        local dx = mouseX - STATE.active.mouse[initialPressKey].x
        local dy = mouseY - STATE.active.mouse[initialPressKey].y
        local dragDistance = math.sqrt(dx * dx + dy * dy)
        local dragTime = Spring.DiffTimers(currentTime, STATE.active.mouse[pressStartKey])

        if STATE.active.mouse[isDoubleClickKey] then
            fireCallbacks("onDoubleClickHold" .. buttonKey, mouseX, mouseY, dragTime)
        else
            fireCallbacks("onHold" .. buttonKey, mouseX, mouseY, dragTime)
        end

        -- Check if drag should start or continue
        if not STATE.active.mouse[isDraggingKey] and (dragDistance > STATE.active.mouse.dragThreshold or dragTime > STATE.active.mouse.dragTimeThreshold) then
            STATE.active.mouse[isDraggingKey] = true
            STATE.active.mouse.lastDragX = mouseX
            STATE.active.mouse.lastDragY = mouseY
            fireCallbacks("onDragStart" .. buttonKey, STATE.active.mouse[initialPressKey].x, STATE.active.mouse[initialPressKey].y, mouseX, mouseY, STATE.active.mouse[isDoubleClickKey])
        elseif STATE.active.mouse[isDraggingKey] and STATE.active.mouse.lastDragX and STATE.active.mouse.lastDragY then
            local dragDx = mouseX - STATE.active.mouse.lastDragX
            local dragDy = mouseY - STATE.active.mouse.lastDragY
            if dragDx ~= 0 or dragDy ~= 0 then
                fireCallbacks("onDrag" .. buttonKey, dragDx, dragDy, mouseX, mouseY, STATE.active.mouse[isDoubleClickKey])
                STATE.active.mouse.lastDragX = mouseX
                STATE.active.mouse.lastDragY = mouseY
            end
        end

    elseif not isDown and STATE.active.mouse[isDownKey] then
        -- Button just released
        local wasDoubleClick = STATE.active.mouse[isDoubleClickKey]
        local wasDragging = STATE.active.mouse[isDraggingKey]
        local holdTime = Spring.DiffTimers(currentTime, STATE.active.mouse[pressStartKey])

        if not wasDragging and not wasDoubleClick then
            fireCallbacks("on" .. buttonKey, mouseX, mouseY)
        end

        fireCallbacks("onRelease" .. buttonKey, mouseX, mouseY, wasDoubleClick, wasDragging, holdTime)
        STATE.active.mouse[isDownKey] = false
        STATE.active.mouse[isDraggingKey] = false
        STATE.active.mouse[isDoubleClickKey] = false
        STATE.active.mouse.lastDragX = nil
        STATE.active.mouse.lastDragY = nil
    end
end

function MouseManager.update()
    if not shouldProcessInput() then
        return
    end

    local mouseX, mouseY, lmb, mmb, rmb = Spring.GetMouseState()
    local currentTime = Spring.GetTimer()

    -- Fire mouse move event if position has changed
    if mouseX ~= STATE.active.mouse.lastMouseX or mouseY ~= STATE.active.mouse.lastMouseY then
        fireCallbacks("onMouseMove", mouseX, mouseY,
                mouseX - (STATE.active.mouse.lastMouseX or mouseX),
                mouseY - (STATE.active.mouse.lastMouseY or mouseY))
    end

    STATE.active.mouse.lastMouseX = mouseX
    STATE.active.mouse.lastMouseY = mouseY

    processMouseButton("LMB", "Left", mouseX, mouseY, currentTime)
    processMouseButton("MMB", "Middle", mouseX, mouseY, currentTime)
    processMouseButton("RMB", "Right", mouseX, mouseY, currentTime)
end

-- MMB handlers
MouseManager.onMMB = function(modeName, callback)
    registerCallback("onMMB", modeName, callback)
end

MouseManager.onDoubleMMB = function(modeName, callback)
    registerCallback("onDoubleMMB", modeName, callback)
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

MouseManager.onRMB = function(modeName, callback)
    registerCallback("onRMB", modeName, callback)
end

-- LMB handlers
MouseManager.onLMB = function(modeName, callback)
    registerCallback("onLMB", modeName, callback)
end

MouseManager.onDoubleLMB = function(modeName, callback)
    registerCallback("onDoubleLMB", modeName, callback)
end

MouseManager.onReleaseLMB = function(modeName, callback)
    registerCallback("onReleaseLMB", modeName, callback)
end

MouseManager.onDragLMB = function(modeName, callback)
    registerCallback("onDragLMB", modeName, callback)
end

MouseManager.onDragStartLMB = function(modeName, callback)
    registerCallback("onDragStartLMB", modeName, callback)
end

MouseManager.onMouseMove = function(modeName, callback)
    registerCallback("onMouseMove", modeName, callback)
end

return MouseManager