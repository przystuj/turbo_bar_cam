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

--- Calculates distance between two camera state positions
---@param state1 table First camera state
---@param state2 table Second camera state
---@return number distance Distance between positions
function CameraAnchorUtils.getPositionDistance(state1, state2)
    local pos1 = { x = state1.px, y = state1.py, z = state1.pz }
    local pos2 = { x = state2.px, y = state2.py, z = state2.pz }
    return CameraCommons.vectorMagnitude(CameraCommons.vectorSubtract(pos2, pos1))
end

--- Scales a tangent vector appropriately for camera transitions
---@param tangent table Tangent vector with x,y,z components
---@param transitionTime number Duration of transition in seconds
---@param distance number Distance between points
---@return table scaledTangent Properly scaled tangent vector
function CameraAnchorUtils.scaleTangentForTransition(tangent, transitionTime, distance)
    -- Get base tangent magnitude
    local magnitude = CameraCommons.vectorMagnitude(tangent)

    if magnitude < 0.001 then
        return { x = 0, y = 0, z = 0 }
    end

    -- Calculate velocity factors
    -- Minimum velocity to maintain at waypoints (prevents stopping)
    local minVelocity = 20

    -- Base desired velocity (distance/time with a minimum)
    local baseVelocity = math.max(minVelocity, distance / math.max(0.1, transitionTime))

    -- Scale tangent to maintain consistent velocity through waypoints
    -- Use a velocity-based approach instead of direct time scaling
    local targetMagnitude = baseVelocity * 0.5  -- Half the segment velocity for smooth transition

    -- Ensure minimum magnitude to prevent stopping at waypoints
    targetMagnitude = math.max(targetMagnitude, minVelocity)

    -- Scale the tangent
    local scaleFactor = targetMagnitude / magnitude
    return {
        x = tangent.x * scaleFactor,
        y = tangent.y * scaleFactor,
        z = tangent.z * scaleFactor
    }
end

--- Calculates global tangent vectors for a continuous path
---@param points table Array of path points with position data
---@return table tangents Array of tangent vectors
function CameraAnchorUtils.calculateContinuousPathTangents(points)
    local tangents = {}

    -- Handle simple cases
    if #points <= 1 then
        return {{x = 0, y = 0, z = 0}}
    elseif #points == 2 then
        -- Simple case: just use direction vector
        local direction = CameraCommons.vectorSubtract(
                {x = points[2].state.px, y = points[2].state.py, z = points[2].state.pz},
                {x = points[1].state.px, y = points[1].state.py, z = points[1].state.pz}
        )
        local dist = CameraCommons.vectorMagnitude(direction)
        local scaled = CameraCommons.vectorMultiply(direction, 0.5)
        return {scaled, scaled}
    end

    -- For each point, calculate a tangent based on its neighbors
    for i = 1, #points do
        local tangent = {x = 0, y = 0, z = 0}

        if i == 1 then
            -- First point: use forward difference
            tangent = CameraCommons.vectorSubtract(
                    {x = points[2].state.px, y = points[2].state.py, z = points[2].state.pz},
                    {x = points[1].state.px, y = points[1].state.py, z = points[1].state.pz}
            )
        elseif i == #points then
            -- Last point: use backward difference
            tangent = CameraCommons.vectorSubtract(
                    {x = points[#points].state.px, y = points[#points].state.py, z = points[#points].state.pz},
                    {x = points[#points-1].state.px, y = points[#points-1].state.py, z = points[#points-1].state.pz}
            )
        else
            -- Interior points: use Catmull-Rom approach (average of segments)
            local prev = {x = points[i-1].state.px, y = points[i-1].state.py, z = points[i-1].state.pz}
            local curr = {x = points[i].state.px, y = points[i].state.py, z = points[i].state.pz}
            local next = {x = points[i+1].state.px, y = points[i+1].state.py, z = points[i+1].state.pz}

            -- Calculate catmull-rom tangent (weighted average of adjacent segments)
            tangent = CameraCommons.vectorSubtract(next, prev)
            -- Scale by 0.5 for Catmull-Rom parameterization
            tangent = CameraCommons.vectorMultiply(tangent, 0.5)
        end

        -- Scale the tangent magnitude to a reasonable value
        -- For Catmull-Rom splines, it should be around half the segment length
        local magThreshold = 0.0001  -- Avoid division by zero
        local tangentMag = CameraCommons.vectorMagnitude(tangent)

        if tangentMag > magThreshold then
            -- Scale tangent to prevent stopping at waypoints
            local scaledMag = 0

            if i == 1 then
                -- First point: use distance to next point
                local dist = CameraAnchorUtils.getPositionDistance(points[i].state, points[i+1].state)
                scaledMag = dist * 0.5
            elseif i == #points then
                -- Last point: use distance from previous point
                local dist = CameraAnchorUtils.getPositionDistance(points[i-1].state, points[i].state)
                scaledMag = dist * 0.5
            else
                -- Interior points: use average of adjacent segments
                local prevDist = CameraAnchorUtils.getPositionDistance(points[i-1].state, points[i].state)
                local nextDist = CameraAnchorUtils.getPositionDistance(points[i].state, points[i+1].state)
                scaledMag = (prevDist + nextDist) * 0.5
            end

            -- Ensure minimum tangent length (prevents stopping at waypoints)
            scaledMag = math.max(scaledMag, 30)

            -- Scale tangent to desired magnitude
            tangent = CameraCommons.vectorMultiply(tangent, scaledMag / tangentMag)
        end

        tangents[i] = tangent
    end

    return tangents
end

--- Generate steps for a path segment between two points
---@param pathInfo table Path information structure to add steps to
---@param p0 table Starting waypoint
---@param p1 table Ending waypoint
---@param startTime number Starting time for this segment
---@return number endTime Ending time after generating steps
function CameraAnchorUtils.generateSegmentSteps(pathInfo, p0, p1, startTime)
    local transitionTime = p0.transitionTime or 0
    local currentTime = startTime

    if transitionTime <= 0 then
        return currentTime
    end

    -- Calculate segment distance
    local distance = CameraAnchorUtils.getPositionDistance(p0.state, p1.state)

    -- Calculate steps based on configuration
    local numSteps = math.max(2, math.floor(transitionTime * CONFIG.PERFORMANCE.ANCHOR_STEPS_PER_SECOND))

    -- Scale tangents properly for this segment
    local v0 = CameraAnchorUtils.scaleTangentForTransition(p0.tangent, transitionTime, distance)
    local v1 = CameraAnchorUtils.scaleTangentForTransition(p1.tangent, transitionTime, distance)

    -- Generate steps for this segment
    for j = 1, numSteps do
        local t = (j - 1) / (numSteps - 1)

        -- Use existing hermite interpolation
        local pos = Util.hermiteInterpolate(p0.state, p1.state, v0, v1, t)

        -- Create camera state
        local rx, ry = Util.hermiteInterpolateRotation(
                p0.state.rx or 0, p0.state.ry or 0,
                p1.state.rx or 0, p1.state.ry or 0,
                { rx = (p1.state.rx - p0.state.rx) / transitionTime,
                  ry = (p1.state.ry - p0.state.ry) / transitionTime },
                { rx = (p1.state.rx - p0.state.rx) / transitionTime,
                  ry = (p1.state.ry - p0.state.ry) / transitionTime },
                t
        )

        -- Calculate camera direction from rotation
        local cosRx = math.cos(rx)
        local dx = math.sin(ry) * cosRx
        local dy = math.sin(rx)
        local dz = math.cos(ry) * cosRx

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

        local stepTime = currentTime + (j - 1) * transitionTime / (numSteps - 1)

        table.insert(pathInfo.steps, {
            time = stepTime,
            state = state
        })
    end

    return currentTime + transitionTime
end

--- Creates a path transition with continuous motion through waypoints
---@param points table Array of path points
---@return table pathInfo Information about the generated path
function CameraAnchorUtils.createPathTransition(points)
    if #points < 2 then
        Log.debug("Path requires at least 2 points")
        return nil
    end

    Log.debug("Creating continuous path with " .. #points .. " points")

    -- Calculate global tangent vectors using Catmull-Rom spline approach
    local globalTangents = CameraAnchorUtils.calculateContinuousPathTangents(points)

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

    -- Generate path steps
    local currentTime = 0

    for i = 1, #points - 1 do
        local transitionTime = points[i].transitionTime or 1.0
        local numSteps = math.max(2, math.floor(transitionTime * CONFIG.PERFORMANCE.ANCHOR_STEPS_PER_SECOND))

        -- Get position tangents
        local v0 = points[i].tangent
        local v1 = points[i+1].tangent

        -- Calculate rotation tangents separately - this is the key fix
        -- Use the difference in angles divided by transition time
        local rotTangent0 = {
            rx = (points[i+1].state.rx - points[i].state.rx) / transitionTime * 0.5,
            ry = 0  -- Calculate below with normalization for yaw
        }

        -- Handle yaw (ry) carefully because it wraps around
        local ry0 = CameraCommons.normalizeAngle(points[i].state.ry or 0)
        local ry1 = CameraCommons.normalizeAngle(points[i+1].state.ry or 0)

        -- Find shortest path for yaw
        local diff = ry1 - ry0
        if diff > math.pi then diff = diff - 2 * math.pi
        elseif diff < -math.pi then diff = diff + 2 * math.pi end

        rotTangent0.ry = diff / transitionTime * 0.5

        -- Second point uses same tangent for continuous movement
        local rotTangent1 = rotTangent0

        for j = 1, numSteps do
            local t = (j - 1) / (numSteps - 1)

            -- Use Hermite interpolation for position
            local pos = Util.hermiteInterpolate(points[i].state, points[i+1].state, v0, v1, t)

            -- Use proper rotation interpolation with rotation-specific tangents
            local rx, ry = Util.hermiteInterpolateRotation(
                    points[i].state.rx or 0, points[i].state.ry or 0,
                    points[i+1].state.rx or 0, points[i+1].state.ry or 0,
                    rotTangent0, rotTangent1,
                    t
            )

            -- Calculate camera direction from rotation
            local cosRx = math.cos(rx)
            local dx = math.sin(ry) * cosRx
            local dy = math.sin(rx)
            local dz = math.cos(ry) * cosRx

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

            local stepTime = currentTime + (j - 1) * transitionTime / (numSteps - 1)

            table.insert(pathInfo.steps, {
                time = stepTime,
                state = state
            })
        end

        currentTime = currentTime + transitionTime
    end

    pathInfo.totalDuration = currentTime

    -- Finalize the path
    CameraAnchorUtils.finalizePath(pathInfo)

    return pathInfo
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
    interpolationFunc = interpolationFunc or EasingFunctions.easeInOut

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

--- Debug function to check if tangents are causing velocity issues
---@param pathInfo table Path information structure
function CameraAnchorUtils.checkTangentVelocity(pathInfo)
    Log.info("\n=== TANGENT VELOCITY CHECK ===")

    for i = 1, #pathInfo.points do
        local point = pathInfo.points[i]
        local tangent = point.tangent

        if tangent then
            local mag = math.sqrt(tangent.x ^ 2 + tangent.y ^ 2 + tangent.z ^ 2)
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

            local mag = math.sqrt(velocity.x ^ 2 + velocity.y ^ 2 + velocity.z ^ 2)

            -- Check if velocity drops to near zero at waypoints
            if mag < 10 then
                -- Threshold for "stopped"
                Log.warn(string.format("Low velocity at step %d: %.3f units/sec", i, mag))

                -- Check if this is near a waypoint
                for j, point in ipairs(pathInfo.points) do
                    local dist = math.sqrt(
                            (currentStep.state.px - point.state.px) ^ 2 +
                                    (currentStep.state.py - point.state.py) ^ 2 +
                                    (currentStep.state.pz - point.state.pz) ^ 2
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

                if dt > 0.000001 then
                    -- Protect against division by tiny numbers
                    local dx = (currentStep.state.px or 0) - (prevStep.state.px or 0)
                    local dy = (currentStep.state.py or 0) - (prevStep.state.py or 0)
                    local dz = (currentStep.state.pz or 0) - (prevStep.state.pz or 0)
                    velBefore = math.sqrt(dx * dx + dy * dy + dz * dz) / dt
                end

                dt = pathInfo.stepTimes[closestStepIndex] or 0.01
                local velAfter = 0

                if dt > 0.000001 then
                    -- Protect against division by tiny numbers
                    local dx = (nextStep.state.px or 0) - (currentStep.state.px or 0)
                    local dy = (nextStep.state.py or 0) - (currentStep.state.py or 0)
                    local dz = (nextStep.state.pz or 0) - (currentStep.state.pz or 0)
                    velAfter = math.sqrt(dx * dx + dy * dy + dz * dz) / dt
                end

                -- Check for NaN values before logging
                if velBefore ~= velBefore or velAfter ~= velAfter then
                    -- NaN check
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

return {
    CameraAnchorUtils = CameraAnchorUtils
}