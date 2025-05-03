---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CameraManager
local CameraManager = VFS.Include("LuaUI/TurboBarCam/standalone/camera_manager.lua").CameraManager
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")
---@type EasingFunctions
local EasingFunctions = VFS.Include("LuaUI/TurboBarCam/features/anchors/anchor_easing_functions.lua").EasingFunctions

local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local Util = CommonModules.Util
local CameraCommons = CommonModules.CameraCommons
local Log = CommonModules.Log

---@class CameraAnchorUtils
local CameraAnchorUtils = {}

--- Interpolates between two angles along the shortest path
---@param a number Start angle (in radians)
---@param b number End angle (in radians)
---@param t number Interpolation factor (0.0-1.0)
---@return number interpolated angle
function CameraAnchorUtils.lerpAngle(a, b, t)
    -- Normalize both angles to -pi to pi range
    a = CameraAnchorUtils.normalizeAngle(a)
    b = CameraAnchorUtils.normalizeAngle(b)

    -- Find the shortest path
    local diff = b - a

    -- If the difference is greater than pi, we need to go the other way around
    if diff > math.pi then
        diff = diff - 2 * math.pi
    elseif diff < -math.pi then
        diff = diff + 2 * math.pi
    end

    return a + diff * t
end

--- Normalizes an angle to be within -pi to pi range
---@param angle number|nil Angle to normalize (in radians)
---@return number normalized angle
function CameraAnchorUtils.normalizeAngle(angle)
    if angle == nil then
        return 0 -- Default to 0 if angle is nil
    end

    local twoPi = 2 * math.pi
    angle = angle % twoPi
    if angle > math.pi then
        angle = angle - twoPi
    end
    return angle
end

--- Calculate global tangent vectors for all waypoints to ensure C1 continuity
---@param points table Array of waypoints
---@return table tangents Array of tangent vectors (one per point)
function CameraAnchorUtils.calculateGlobalTangentVectors(points)
    local tangents = {}
    local tension = 0.7  -- Higher tension for more continuous curves

    Log.debug("Calculating global tangent vectors for " .. #points .. " points")

    for i = 1, #points do
        if i == 1 then
            -- First point: use direction to next point
            if #points > 1 then
                local p0 = points[i].state
                local p1 = points[i + 1].state

                tangents[i] = {
                    x = (p1.px - p0.px) * tension,
                    y = (p1.py - p0.py) * tension,
                    z = (p1.pz - p0.pz) * tension
                }
            else
                tangents[i] = { x = 0, y = 0, z = 0 }
            end
        elseif i == #points then
            -- Last point: use direction from previous point
            local pn = points[i].state
            local pn1 = points[i - 1].state

            tangents[i] = {
                x = (pn.px - pn1.px) * tension,
                y = (pn.py - pn1.py) * tension,
                z = (pn.pz - pn1.pz) * tension
            }
        else
            -- Interior point: For continuous movement, calculate the tangent that keeps the camera moving through the point
            local prev = points[i - 1].state
            local curr = points[i].state
            local next = points[i + 1].state

            -- Calculate the through-vector from previous to next point
            local throughX = next.px - prev.px
            local throughY = next.py - prev.py
            local throughZ = next.pz - prev.pz

            -- Normalize the through-vector
            local throughMag = math.sqrt(throughX^2 + throughY^2 + throughZ^2)
            if throughMag > 0.001 then
                throughX = throughX / throughMag
                throughY = throughY / throughMag
                throughZ = throughZ / throughMag
            end

            -- Calculate incoming and outgoing segment lengths
            local inDist = math.sqrt((curr.px - prev.px)^2 + (curr.py - prev.py)^2 + (curr.pz - prev.pz)^2)
            local outDist = math.sqrt((next.px - curr.px)^2 + (next.py - curr.py)^2 + (next.pz - curr.pz)^2)

            -- Weight the tangent by the shorter segment to maintain velocity
            local segmentScale = math.min(inDist, outDist)

            -- Use the through-vector scaled by the segment distance to maintain velocity
            tangents[i] = {
                x = throughX * segmentScale * tension,
                y = throughY * segmentScale * tension,
                z = throughZ * segmentScale * tension
            }

            -- Ensure minimum velocity at waypoints
            local tangentMag = math.sqrt(tangents[i].x^2 + tangents[i].y^2 + tangents[i].z^2)
            if tangentMag < 100 then -- Increased minimum threshold
                -- Scale up the tangent to maintain minimum velocity
                local scale = 100 / (tangentMag + 0.001)
                tangents[i].x = tangents[i].x * scale
                tangents[i].y = tangents[i].y * scale
                tangents[i].z = tangents[i].z * scale
            end
        end

        -- Log tangent information
        local mag = math.sqrt(tangents[i].x^2 + tangents[i].y^2 + tangents[i].z^2)
        Log.debug(string.format("Point %d tangent: (%.3f, %.3f, %.3f), magnitude: %.3f",
                i, tangents[i].x, tangents[i].y, tangents[i].z, mag))
    end

    return tangents
end

--- Generates a sequence of camera states for smooth transition
---@param startState table Start camera state
---@param endState table End camera state
---@param numSteps number Number of transition steps
---@param interpolationFunc function|nil Optional custom interpolation function
---@return table[] steps Array of transition step states
function CameraAnchorUtils.generateSteps(startState, endState, numSteps, interpolationFunc)
    local steps = {}

    -- Use default interpolation if none provided
    interpolationFunc = interpolationFunc or EasingFunctions.easeInOutCubic

    -- Camera parameters to interpolate
    local cameraParams = {
        "zoomFromHeight", "fov", "gndOffset", "dist", "flipped",
        "vx", "vy", "vz", "ax", "ay", "az", "height",
        "rotZ"
    }

    -- Camera rotation parameters that need special angle interpolation
    local rotationParams = {
        "rx", "ry", "rz", "rotX", "rotY"
    }

    for i = 1, numSteps do
        local t = (i - 1) / (numSteps - 1)
        local easedT = interpolationFunc(t)

        -- Create a new state by interpolating between start and end
        local statePatch = {}

        -- Core position parameters
        statePatch.px = CameraCommons.lerp(startState.px, endState.px, easedT)
        statePatch.py = CameraCommons.lerp(startState.py, endState.py, easedT)
        statePatch.pz = CameraCommons.lerp(startState.pz, endState.pz, easedT)

        -- Core direction parameters
        statePatch.dx = CameraCommons.lerp(startState.dx, endState.dx, easedT)
        statePatch.dy = CameraCommons.lerp(startState.dy, endState.dy, easedT)
        statePatch.dz = CameraCommons.lerp(startState.dz, endState.dz, easedT)

        -- Camera specific parameters (non-rotational)
        for _, param in ipairs(cameraParams) do
            if startState[param] ~= nil and endState[param] ~= nil then
                statePatch[param] = CameraCommons.lerp(startState[param], endState[param], easedT)
            end
        end

        -- Camera rotation parameters (need special angle interpolation)
        for _, param in ipairs(rotationParams) do
            if startState[param] ~= nil and endState[param] ~= nil then
                statePatch[param] = CameraAnchorUtils.lerpAngle(startState[param], endState[param], easedT)
            end
        end

        steps[i] = statePatch
    end

    -- Ensure the last step exactly matches the end state
    steps[numSteps] = Util.deepCopy(endState)

    return steps
end

--- Creates a position-based transition between camera states
---@param startState table Start camera state
---@param endState table End camera state
---@param duration number Transition duration in seconds
---@param targetPos table|nil Optional target position to focus on
---@param interpolationFunc function|nil Optional custom interpolation function
---@return table[] steps Array of transition step states
function CameraAnchorUtils.createPositionTransition(startState, endState, duration, targetPos, interpolationFunc)
    -- Generate transition steps for smooth transition
    local numSteps = math.max(2, math.floor(duration * CONFIG.PERFORMANCE.ANCHOR_STEPS_PER_SECOND))

    -- If tracking a unit, adjust the end position to maintain focus
    if targetPos then
        -- Create a hybrid end state that maintains unit focus
        local focusState = Util.deepCopy(endState)

        -- Calculate direction from position to target
        local direction = CameraCommons.calculateCameraDirectionToThePoint(focusState, targetPos)

        -- Update end state with focus direction
        focusState.dx = direction.dx
        focusState.dy = direction.dy
        focusState.dz = direction.dz
        focusState.rx = direction.rx
        focusState.ry = direction.ry

        return CameraAnchorUtils.generateSteps(startState, focusState, numSteps, interpolationFunc)
    end

    return CameraAnchorUtils.generateSteps(startState, endState, numSteps, interpolationFunc)
end

--- Starts a transition between camera states
---@param endState table End camera state
---@param duration number Transition duration in seconds
---@param interpolationFunc function|nil Optional interpolation function
function CameraAnchorUtils.startTransitionToAnchor(endState, duration, interpolationFunc)
    -- Generate transition steps for smooth transition
    local startState = CameraManager.getCameraState("CameraAnchorUtils.start")
    local numSteps = math.max(2, math.floor(duration * CONFIG.PERFORMANCE.ANCHOR_STEPS_PER_SECOND))

    STATE.transition.steps = CameraAnchorUtils.generateSteps(startState, endState, numSteps, interpolationFunc)
    STATE.transition.currentStepIndex = 1
    STATE.transition.startTime = Spring.GetTimer()
    STATE.transition.active = true
end

--- Modified createPathTransition with better continuity checks
---@param points table Array of path points
---@return table pathInfo Information about the generated path
function CameraAnchorUtils.createPathTransition(points)
    if #points < 2 then
        Log.debug("Path requires at least 2 points")
        return nil
    end

    -- Debug log the points
    Log.debug("Creating path transition with " .. #points .. " points")

    -- Calculate global tangent vectors using the comprehensive function
    local globalTangents = CameraAnchorUtils.calculateGlobalTangentVectors(points)

    -- Store tangents in points
    for i, point in ipairs(points) do
        point.tangent = globalTangents[i]
    end

    -- Initialize path info
    local pathInfo = {
        steps = {},
        stepTimes = {},
        totalDuration = 0,
        points = points,
        tangents = globalTangents
    }

    -- Generate steps along the entire path
    local currentTime = 0

    for i = 1, #points - 1 do
        local p0 = points[i]
        local p1 = points[i + 1]

        local transitionTime = p0.transitionTime or 0
        if transitionTime > 0 then
            -- Calculate steps for this segment
            local numSteps = math.max(2, math.floor(transitionTime * CONFIG.PERFORMANCE.ANCHOR_STEPS_PER_SECOND))

            for j = 1, numSteps do
                local t = (j - 1) / (numSteps - 1)

                -- Don't ease at end points to maintain velocity
                local easedT = t
                if j > 1 and j < numSteps then
                    easedT = EasingFunctions.linear(t)
                end

                -- Scale tangents by duration
                local v0 = {
                    x = p0.tangent.x * transitionTime,
                    y = p0.tangent.y * transitionTime,
                    z = p0.tangent.z * transitionTime
                }

                local v1 = {
                    x = p1.tangent.x * transitionTime,
                    y = p1.tangent.y * transitionTime,
                    z = p1.tangent.z * transitionTime
                }

                -- Hermite interpolation for position
                local pos = Util.hermiteInterpolate(p0.state, p1.state, v0, v1, easedT)

                -- Hermite interpolation for rotation
                -- Create rotation tangents by extracting rx/ry components
                local rotTangent0 = {
                    rx = p0.state.rx and (p1.state.rx - p0.state.rx) / transitionTime,
                    ry = p0.state.ry and (p1.state.ry - p0.state.ry) / transitionTime
                }

                local rotTangent1 = {
                    rx = p0.state.rx and (p1.state.rx - p0.state.rx) / transitionTime,
                    ry = p0.state.ry and (p1.state.ry - p0.state.ry) / transitionTime
                }

                -- Use specialized rotation interpolation
                local rx, ry = Util.hermiteInterpolateRotation(
                        p0.state.rx or 0, p0.state.ry or 0,
                        p1.state.rx or 0, p1.state.ry or 0,
                        rotTangent0, rotTangent1, easedT
                )

                -- Calculate direction from the interpolated rx/ry
                local cosRx = math.cos(rx)
                local dx = math.sin(ry) * cosRx
                local dy = math.sin(rx)
                local dz = math.cos(ry) * cosRx

                -- Create camera state
                local state = {
                    mode = 0,
                    name = "fps",
                    px = pos.x,
                    py = pos.y,
                    pz = pos.z,
                    rx = rx,
                    ry = ry,
                    rz = 0,
                    dx = dx,
                    dy = dy,
                    dz = dz
                }

                -- Calculate time for this step
                local stepTime = currentTime + (j - 1) * transitionTime / (numSteps - 1)

                table.insert(pathInfo.steps, {
                    time = stepTime,
                    state = state
                })
            end

            -- Update current time
            currentTime = currentTime + transitionTime
        end
    end

    pathInfo.totalDuration = currentTime

    -- Finalize path and debug
    CameraAnchorUtils.finalizePath(pathInfo)
    if CONFIG.DEBUG.LOG_LEVEL == "TRACE" then
        CameraAnchorUtils.debugPathExecution(pathInfo)
        CameraAnchorUtils.debugPathStructure(pathInfo)
    end
    return pathInfo
end

--- Finalize path by sorting steps and adding step times
---@param pathInfo table Path information structure
function CameraAnchorUtils.finalizePath(pathInfo)
    -- Sort steps by time for safety
    table.sort(pathInfo.steps, function(a, b)
        return a.time < b.time
    end)

    -- Add step times
    for i = 1, #pathInfo.steps - 1 do
        table.insert(pathInfo.stepTimes, pathInfo.steps[i + 1].time - pathInfo.steps[i].time)
    end

    -- Add a final step time
    if #pathInfo.steps > 0 then
        table.insert(pathInfo.stepTimes, 0.01) -- Small value for last step
    end

    Log.info(string.format("Created path with %d steps, total duration: %.1f seconds",
            #pathInfo.steps, pathInfo.totalDuration))
end


--- Calculate velocity at each point for debugging
---@param points table Array of points
function CameraAnchorUtils.debugVelocityAtPoints(points)
    local velocities = {}

    for i = 1, #points do
        local tangent = points[i].tangent
        local mag = math.sqrt((tangent.x or 0)^2 + (tangent.y or 0)^2 + (tangent.z or 0)^2)

        velocities[i] = {
            direction = tangent,
            magnitude = mag
        }

        Log.debug(string.format("Point %d velocity: magnitude=%.3f, direction=(%.3f, %.3f, %.3f)",
                i, mag, tangent.x, tangent.y, tangent.z))
    end

    return velocities
end

--- Debug function to check if tangents are causing velocity issues
---@param pathInfo table Path information structure
function CameraAnchorUtils.checkTangentVelocity(pathInfo) -- todo
    Log.info("\n=== TANGENT VELOCITY CHECK ===")

    for i = 1, #pathInfo.points do
        local point = pathInfo.points[i]
        local tangent = point.tangent

        if tangent then
            local mag = math.sqrt(tangent.x^2 + tangent.y^2 + tangent.z^2)
            Log.info(string.format("Point %d tangent magnitude: %.3f", i, mag))

            if mag < 10 then
                Log.warn(string.format("  WARNING: Very low tangent magnitude at point %d", i))
            end
        else
            Log.warn(string.format("  WARNING: Missing tangent at point %d", i))
        end
    end
end

---@param t number Interpolation parameter (0-1)
---@return number easedT Eased value that preserves velocity at boundaries
function CameraAnchorUtils.preserveVelocityEasing(t)
    -- Linear interpolation at boundaries to prevent zero velocity
    if t < 0.1 then
        return t * 10  -- Linear for first 10%
    elseif t > 0.9 then
        return 0.9 + (t - 0.9) * 10  -- Linear for last 10%
    else
        -- Smooth in the middle
        local adjusted = (t - 0.1) / 0.8
        return 0.1 + adjusted * adjusted * (3 - 2 * adjusted) * 0.8
    end
end

--- Check and fix the actual path execution to prevent stopping at waypoints
---@param pathInfo table Path information structure
function CameraAnchorUtils.debugPathExecution(pathInfo)
    Log.info("=== PATH EXECUTION DEBUG ===")

    -- Check velocity at waypoint boundaries
    for i = 1, #pathInfo.steps - 1 do
        local currentStep = pathInfo.steps[i]
        local nextStep = pathInfo.steps[i + 1]

        -- Calculate velocity between steps
        local dt = pathInfo.stepTimes[i] or 0.01
        if dt > 0 then
            local velocity = {
                x = (nextStep.state.px - currentStep.state.px) / dt,
                y = (nextStep.state.py - currentStep.state.py) / dt,
                z = (nextStep.state.pz - currentStep.state.pz) / dt
            }

            local mag = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)

            -- Check if velocity drops to near zero at waypoints
            if mag < 10 then  -- Threshold for "stopped"
                Log.warn(string.format("Low velocity at step %d: %.3f units/sec", i, mag))

                -- Check if this is near a waypoint
                for j, point in ipairs(pathInfo.points) do
                    local dist = math.sqrt(
                            (currentStep.state.px - point.state.px)^2 +
                                    (currentStep.state.py - point.state.py)^2 +
                                    (currentStep.state.pz - point.state.pz)^2
                    )
                    if dist < 50 then
                        Log.warn(string.format("  Near waypoint %d!", j))
                    end
                end
            end
        end
    end
end

--- Debug function to add before executing a queue
---@param pathInfo table Path information structure
function CameraAnchorUtils.debugPathStructure(pathInfo)
    Log.info("=== PATH STRUCTURE DEBUG ===")
    Log.info(string.format("Total steps: %d", #pathInfo.steps))
    Log.info(string.format("Total duration: %.2f", pathInfo.totalDuration))
    Log.info("Step time structure:")

    -- Check if steps are properly connected
    for i = 1, math.min(10, #pathInfo.stepTimes) do
        Log.info(string.format("  Step %d: time=%.4f", i, pathInfo.stepTimes[i] or 0))
    end

    -- Check velocity continuity between segments
    Log.info("\nVelocity continuity check:")
    for i = 1, #pathInfo.points - 1 do
        -- Find steps around point transitions
        local pointTransitionTime = 0
        for j = 1, i do
            if pathInfo.points[j].transitionTime then
                pointTransitionTime = pointTransitionTime + pathInfo.points[j].transitionTime
            end
        end

        -- Find step closest to transition
        local closestStepIndex = 1
        local minTimeDiff = math.huge
        for j = 1, #pathInfo.steps do
            local timeDiff = math.abs(pathInfo.steps[j].time - pointTransitionTime)
            if timeDiff < minTimeDiff then
                minTimeDiff = timeDiff
                closestStepIndex = j
            end
        end

        -- Check velocity at transition
        if closestStepIndex > 1 and closestStepIndex < #pathInfo.steps then
            local prevStep = pathInfo.steps[closestStepIndex - 1]
            local currentStep = pathInfo.steps[closestStepIndex]
            local nextStep = pathInfo.steps[closestStepIndex + 1]

            -- Make sure steps have valid state
            if prevStep and prevStep.state and currentStep and currentStep.state and
                    nextStep and nextStep.state then

                -- Calculate velocities before and after transition
                local dt = pathInfo.stepTimes[closestStepIndex - 1] or 0.01
                local velBefore = 0

                if dt > 0.000001 then  -- Protect against division by tiny numbers
                    local dx = (currentStep.state.px or 0) - (prevStep.state.px or 0)
                    local dy = (currentStep.state.py or 0) - (prevStep.state.py or 0)
                    local dz = (currentStep.state.pz or 0) - (prevStep.state.pz or 0)
                    velBefore = math.sqrt(dx*dx + dy*dy + dz*dz) / dt
                end

                dt = pathInfo.stepTimes[closestStepIndex] or 0.01
                local velAfter = 0

                if dt > 0.000001 then  -- Protect against division by tiny numbers
                    local dx = (nextStep.state.px or 0) - (currentStep.state.px or 0)
                    local dy = (nextStep.state.py or 0) - (currentStep.state.py or 0)
                    local dz = (nextStep.state.pz or 0) - (currentStep.state.pz or 0)
                    velAfter = math.sqrt(dx*dx + dy*dy + dz*dz) / dt
                end

                -- Check for NaN values before logging
                if velBefore ~= velBefore or velAfter ~= velAfter then  -- NaN check
                    Log.warn(string.format("  Point %d transition at step %d: vel before=NaN, vel after=NaN",
                            i + 1, closestStepIndex))
                else
                    Log.info(string.format("  Point %d transition at step %d: vel before=%.3f, vel after=%.3f",
                            i + 1, closestStepIndex, velBefore, velAfter))
                end
            end
        end
    end

    -- Check if speed control is affecting transitions
    if pathInfo.speedControlSettings then
        Log.info("\nSpeed control active: " .. tostring(pathInfo.speedControlSettings))
    end
end



--- Performs Hermite interpolation of camera rotations, handling the special case of angles
---@param rx0 number Start pitch angle
---@param ry0 number Start yaw angle
---@param rx1 number End pitch angle
---@param ry1 number End yaw angle
---@param v0 table Start tangent angles {rx, ry}
---@param v1 table End tangent angles {rx, ry}
---@param t number Interpolation factor (0-1)
---@return number rx Interpolated pitch angle
---@return number ry Interpolated yaw angle
function Util.hermiteInterpolateRotation(rx0, ry0, rx1, ry1, v0, v1, t)
    -- Special handling for segments to prevent rotation glitches
    if t <= 0 then return rx0, ry0 end
    if t >= 1 then return rx1, ry1 end

    -- Handle pitch (rx) with standard Hermite interpolation
    -- Pitch is constrained and doesn't wrap, so standard interpolation works
    local t2 = t * t
    local t3 = t2 * t

    local h00 = 2*t3 - 3*t2 + 1
    local h10 = t3 - 2*t2 + t
    local h01 = -2*t3 + 3*t2
    local h11 = t3 - t2

    local rx = h00 * rx0 + h10 * (v0.rx or 0) + h01 * rx1 + h11 * (v1.rx or 0)

    -- Handle yaw (ry) carefully because it wraps around
    -- Normalize angles to handle wrap-around correctly
    ry0 = CameraAnchorUtils.normalizeAngle(ry0)
    ry1 = CameraAnchorUtils.normalizeAngle(ry1)

    -- Find the shortest path for yaw
    local diff = ry1 - ry0
    if diff > math.pi then
        diff = diff - 2 * math.pi
    elseif diff < -math.pi then
        diff = diff + 2 * math.pi
    end

    -- Apply Hermite with the adjusted difference
    local ry = ry0 + h00 * 0 + h10 * (v0.ry or 0) + h01 * diff + h11 * (v1.ry or 0)

    -- Normalize the final angle
    ry = CameraAnchorUtils.normalizeAngle(ry)

    return rx, ry
end

return {
    CameraAnchorUtils = CameraAnchorUtils
}