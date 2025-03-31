function widget:GetInfo()
    return {
        name = "Tactical Ultra-Responsive Rotation & Brilliant Optics for BAR Camera",
        desc = "Advanced camera control suite with smooth transitions, unit tracking, FPS mode, orbital view, spectator controls, and fixed point tracking. Features include camera anchors, dynamic offsets, free camera mode, auto-orbit, and spectator unit groups.",
        author = "SuperKitowiec",
        date = "Mar 2025",
        license = "GNU GPL, v2 or later",
        layer = 0,
        enabled = true,
        version = 0.5,
        handler = true,
    }
end

-- Include supporting files
local CONFIG_PATH = "LuaUI/Widgets/TURBOBARCAM/camera_turbobarcam_config.lua"
local MODES_PATH = "LuaUI/Widgets/TURBOBARCAM/camera_turbobarcam_modes.lua"
local UTILS_PATH = "LuaUI/Widgets/TURBOBARCAM/camera_turbobarcam_utils.lua"

-- Load modules
---@type {CONFIG: CONFIG, STATE: STATE}
local TurboConfig = VFS.Include(CONFIG_PATH)
---@type {WidgetControl: WidgetControl, CameraTransition: CameraTransition, FPSCamera: FPSCamera, TrackingCamera: TrackingCamera, OrbitingCamera: OrbitingCamera, CameraAnchor: CameraAnchor, SpecGroups: SpecGroups}
local TurboModes = VFS.Include(MODES_PATH)
---@type {Util: Util}
local TurboUtils = VFS.Include(UTILS_PATH)

-- Initialize shorthand references
local CONFIG = TurboConfig.CONFIG
local STATE = TurboConfig.STATE
local Util = TurboUtils.Util
local WidgetControl = TurboModes.WidgetControl
local CameraTransition = TurboModes.CameraTransition
local FPSCamera = TurboModes.FPSCamera
local TrackingCamera = TurboModes.TrackingCamera
local OrbitingCamera = TurboModes.OrbitingCamera
local CameraAnchor = TurboModes.CameraAnchor
local SpecGroups = TurboModes.SpecGroups

-- Command definition for setting fixed look point
local CMD_SET_FIXED_LOOK_POINT = 455625
local CMD_SET_FIXED_LOOK_POINT_DEFINITION = {
    id = CMD_SET_FIXED_LOOK_POINT,
    type = CMDTYPE.ICON_UNIT_OR_MAP,
    name = 'Set Fixed Look Point',
    tooltip = 'Click on a location to focus camera on while following unit',
    cursor = 'settarget',
    action = 'set_fixed_look_point',
}

--------------------------------------------------------------------------------
-- SPRING ENGINE CALLINS
--------------------------------------------------------------------------------

---@param selectedUnits number[] Array of selected unit IDs
function widget:SelectionChanged(selectedUnits)
    if not STATE.enabled then
        return
    end

    -- If no units are selected and tracking is active, start grace period
    if #selectedUnits == 0 then
        if STATE.tracking.mode then
            -- Store the current tracked unit ID
            STATE.tracking.lastUnitID = STATE.tracking.unitID

            -- Start grace period timer (1 second)
            STATE.tracking.graceTimer = Spring.GetTimer()
        end
        return
    end

    -- If units are selected, cancel any active grace period
    if STATE.tracking.graceTimer then
        STATE.tracking.graceTimer = nil
    end

    -- Get the first selected unit
    local unitID = selectedUnits[1]

    -- Update tracking if it's enabled
    if STATE.tracking.mode and STATE.tracking.unitID ~= unitID then
        -- Save current offsets for the previous unit if in FPS mode
        if (STATE.tracking.mode == 'fps' or STATE.tracking.mode == 'fixed_point') and STATE.tracking.unitID then
            STATE.tracking.unitOffsets[STATE.tracking.unitID] = {
                height = CONFIG.FPS.HEIGHT_OFFSET,
                forward = CONFIG.FPS.FORWARD_OFFSET,
                side = CONFIG.FPS.SIDE_OFFSET,
                rotation = CONFIG.FPS.ROTATION_OFFSET
            }
        end

        -- Switch tracking to the new unit
        STATE.tracking.unitID = unitID

        -- For FPS mode, load appropriate offsets
        if STATE.tracking.mode == 'fps' or STATE.tracking.mode == 'fixed_point' then
            if STATE.tracking.unitOffsets[unitID] then
                -- Use saved offsets
                CONFIG.FPS.HEIGHT_OFFSET = STATE.tracking.unitOffsets[unitID].height
                CONFIG.FPS.FORWARD_OFFSET = STATE.tracking.unitOffsets[unitID].forward
                CONFIG.FPS.SIDE_OFFSET = STATE.tracking.unitOffsets[unitID].side
                CONFIG.FPS.ROTATION_OFFSET = STATE.tracking.unitOffsets[unitID].rotation or CONFIG.FPS.DEFAULT_ROTATION_OFFSET
                Spring.Echo("Camera switched to unit " .. unitID .. " with saved offsets")
            else
                -- Get new default height for this unit
                local unitHeight = Util.getUnitHeight(unitID)
                CONFIG.FPS.DEFAULT_HEIGHT_OFFSET = unitHeight
                CONFIG.FPS.HEIGHT_OFFSET = unitHeight
                CONFIG.FPS.FORWARD_OFFSET = CONFIG.FPS.DEFAULT_FORWARD_OFFSET
                CONFIG.FPS.SIDE_OFFSET = CONFIG.FPS.DEFAULT_SIDE_OFFSET
                CONFIG.FPS.ROTATION_OFFSET = CONFIG.FPS.DEFAULT_ROTATION_OFFSET

                -- Initialize storage for this unit
                STATE.tracking.unitOffsets[unitID] = {
                    height = CONFIG.FPS.HEIGHT_OFFSET,
                    forward = CONFIG.FPS.FORWARD_OFFSET,
                    side = CONFIG.FPS.SIDE_OFFSET,
                    rotation = CONFIG.FPS.ROTATION_OFFSET
                }

                Spring.Echo("Camera switched to unit " .. unitID .. " with new offsets")
            end
        else
            Spring.Echo("Tracking switched to unit " .. unitID)
        end
    end
end

function widget:Update()
    if not STATE.enabled then
        return
    end

    -- Check grace period timer if it exists
    if STATE.tracking.graceTimer and STATE.tracking.mode then
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.graceTimer)

        -- If grace period expired (1 second), disable tracking
        if elapsed > 1.0 then
            Util.disableTracking()
            Spring.Echo("Camera tracking disabled - no units selected (after grace period)")
        end
    end

    -- If we're in a mode transition but not tracking any unit,
    -- then we're transitioning back to normal camera from a tracking mode
    if STATE.tracking.modeTransition and not STATE.tracking.mode then
        -- We're transitioning to free camera
        -- Just let the transition time out
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.transitionStartTime)
        if elapsed > 1.0 then
            STATE.tracking.modeTransition = false
        end
    end

    -- During special transition + tracking, handle both components
    if STATE.transition.active then
        -- Update transition position
        local now = Spring.GetTimer()

        -- Calculate current progress
        local elapsed = Spring.DiffTimers(now, STATE.transition.startTime)
        local targetProgress = math.min(elapsed / CONFIG.TRANSITION.DURATION, 1.0)

        -- Determine which position step to use
        local totalSteps = #STATE.transition.steps
        local targetStep = math.max(1, math.min(totalSteps, math.ceil(targetProgress * totalSteps)))

        -- Only update position if we need to move to a new step
        if targetStep > STATE.transition.currentStepIndex then
            STATE.transition.currentStepIndex = targetStep

            -- Get the position state for this step
            local posState = STATE.transition.steps[STATE.transition.currentStepIndex]

            -- Check if we've reached the end
            if STATE.transition.currentStepIndex >= totalSteps then
                STATE.transition.active = false
                STATE.transition.currentAnchorIndex = nil
            end

            -- Only update position, not direction (tracking will handle that)
            if STATE.tracking.mode == 'tracking_camera' and STATE.tracking.unitID then
                -- Get unit position for look direction
                local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)
                local targetPos = { x = unitX, y = unitY, z = unitZ }

                -- Get current (transitioning) camera position
                local camPos = { x = posState.px, y = posState.py, z = posState.pz }

                -- Calculate look direction to the unit
                local lookDir = Util.calculateLookAtPoint(camPos, targetPos)

                -- Create complete camera state with position and look direction
                local combinedState = {
                    mode = 0,
                    name = "fps",
                    px = camPos.x,
                    py = camPos.y,
                    pz = camPos.z,
                    dx = lookDir.dx,
                    dy = lookDir.dy,
                    dz = lookDir.dz,
                    rx = lookDir.rx,
                    ry = lookDir.ry,
                    rz = 0
                }

                -- Apply combined state
                Spring.SetCameraState(combinedState, 0)

                -- Update last values for smooth tracking
                STATE.tracking.lastCamDir = { x = lookDir.dx, y = lookDir.dy, z = lookDir.dz }
                STATE.tracking.lastRotation = { rx = lookDir.rx, ry = lookDir.ry, rz = 0 }
            else
                -- If not tracking, just apply position
                Spring.SetCameraState(posState, 0)
            end
        end
    else
        -- Normal transition behavior when not in special mode
        CameraTransition.update()

        -- Normal tracking behavior when not in special transition
        if STATE.tracking.mode == 'fps' or STATE.tracking.mode == 'fixed_point' then
            -- Check for auto-orbit
            OrbitingCamera.checkUnitMovement()

            if STATE.orbit.autoOrbitActive then
                -- Handle auto-orbit camera update
                OrbitingCamera.updateAutoOrbit()
            else
                -- Normal FPS update
                FPSCamera.update()
            end
        elseif STATE.tracking.mode == 'tracking_camera' then
            TrackingCamera.update()
        elseif STATE.tracking.mode == 'orbit' then
            OrbitingCamera.update()
        end
    end

    -- Check for delayed position storage callback
    if STATE.delayed.frame and Spring.GetGameFrame() >= STATE.delayed.frame then
        if STATE.delayed.callback then
            STATE.delayed.callback()
        end
        STATE.delayed.frame = nil
        STATE.delayed.callback = nil
    end
end

function widget:Initialize()
    -- Widget starts in disabled state, user must enable it manually
    STATE.enabled = false

    -- Register widget control command
    widgetHandler.actionHandler:AddAction(self, "toggle_camera_suite", function()
        return WidgetControl.toggle()
    end, nil, 'p')

    -- Register camera anchor commands
    widgetHandler.actionHandler:AddAction(self, "set_smooth_camera_anchor", function(_, index)
        return CameraAnchor.set(index)
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "focus_smooth_camera_anchor", function(_, index)
        return CameraAnchor.focus(index)
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "decrease_smooth_camera_duration", function()
        CameraAnchor.adjustDuration(-1)
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "increase_smooth_camera_duration", function()
        CameraAnchor.adjustDuration(1)
    end, nil, 'p')

    -- Register FPS camera commands
    widgetHandler.actionHandler:AddAction(self, "toggle_fps_camera", function()
        return FPSCamera.toggle()
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "fps_height_offset_up", function()
        FPSCamera.adjustOffset("height", 10)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "fps_height_offset_down", function()
        FPSCamera.adjustOffset("height", -10)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "fps_forward_offset_up", function()
        FPSCamera.adjustOffset("forward", 10)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "fps_forward_offset_down", function()
        FPSCamera.adjustOffset("forward", -10)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "fps_side_offset_right", function()
        FPSCamera.adjustOffset("side", 10)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "fps_side_offset_left", function()
        FPSCamera.adjustOffset("side", -10)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "fps_rotation_right", function()
        FPSCamera.adjustRotationOffset(0.1)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "fps_rotation_left", function()
        FPSCamera.adjustRotationOffset(-0.1)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "fps_toggle_free_cam", function()
        FPSCamera.toggleFreeCam()
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "fps_reset_defaults", function()
        FPSCamera.resetOffsets()
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "clear_fixed_look_point", function()
        FPSCamera.clearFixedLookPoint()
    end, nil, 'p')

    -- Register Tracking Camera command
    widgetHandler.actionHandler:AddAction(self, "toggle_tracking_camera", function()
        return TrackingCamera.toggle()
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "focus_anchor_and_track", function(_, index)
        return CameraAnchor.focusAndTrack(index)
    end, nil, 'p')

    -- Register Orbiting Camera commands
    widgetHandler.actionHandler:AddAction(self, "toggle_orbiting_camera", function()
        OrbitingCamera.toggle()
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "orbit_speed_up", function()
        OrbitingCamera.adjustSpeed(0.0001)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "orbit_speed_down", function()
        OrbitingCamera.adjustSpeed(-0.0001)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "orbit_reset_defaults", function()
        OrbitingCamera.resetSettings()
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "spec_unit_group", function(_, params)
        return SpecGroups.handleCommand(params)
    end, nil, 'p')

    Spring.I18N.load({
        en = {
            ["ui.orderMenu.set_fixed_look_point"] = "Look point",
            ["ui.orderMenu.set_fixed_look_point_tooltip"] = "Click on a location to focus camera on while following unit.",
        }
    })

    Spring.Echo("TURBOBARCAM loaded but disabled. Use /toggle_camera_suite to enable.")
end

function widget:Shutdown()
    -- Make sure we clean up
    widgetHandler:DeregisterGlobal("spec_unit_group")
    if STATE.enabled then
        WidgetControl.disable()
    end
end

---@param cmdID number Command ID
---@param cmdParams table Command parameters
---@param _ table Command options (unused)
---@return boolean handled Whether the command was handled
function widget:CommandNotify(cmdID, cmdParams, _)
    if cmdID == CMD_SET_FIXED_LOOK_POINT then
        return FPSCamera.setFixedLookPoint(cmdParams)
    end
    return false
end

function widget:CommandsChanged()
    if not STATE.enabled then
        return
    end

    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits > 0 then
        local customCommands = widgetHandler.customCommands
        customCommands[#customCommands + 1] = CMD_SET_FIXED_LOOK_POINT_DEFINITION
    end
end

function widget:GameStart()
    SpecGroups.checkSpectatorStatus()
end

---@param playerID number Player ID
function widget:PlayerChanged(playerID)
    if playerID == Spring.GetMyPlayerID() then
        SpecGroups.checkSpectatorStatus()
    end
end