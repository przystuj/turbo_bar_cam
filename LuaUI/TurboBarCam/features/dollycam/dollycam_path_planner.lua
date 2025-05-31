---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua")
---@type CameraCommons
local CameraCommons = VFS.Include("LuaUI/TurboBarCam/common/camera_commons.lua")
---@type Util
local Util = VFS.Include("LuaUI/TurboBarCam/common/utils.lua")

local STATE = WidgetContext.STATE

---@class DollyCamPathPlanner
local DollyCamPathPlanner = {}

-- Calculate distance between two points in 3D space
---@param p1 table First point {x, y, z}
---@param p2 table Second point {x, y, z}
---@return number distance Distance between the points
local function calculateDistance(p1, p2)
    local dx = p2.x - p1.x
    local dy = p2.y - p1.y
    local dz = p2.z - p1.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Centripetal parameterization function
---@param p1 table First point {x, y, z}
---@param p2 table Second point {x, y, z}
---@param alpha number Alpha value (0.5 for centripetal, 0.0 for uniform, 1.0 for chordal)
---@return number parameterizedTime The parameterized time value
local function parameterizedTime(p1, p2, alpha)
    local distance = calculateDistance(p1, p2)
    -- Avoid division by zero or very small values
    if distance < 0.0001 then
        return 0.0
    end
    -- Apply alpha power for parameterization
    return math.pow(distance, alpha)
end

-- Create the knot vector for Catmull-Rom with centripetal parameterization
---@param points table[] Array of waypoints with position field
---@param alpha number Alpha value (0.5 for centripetal)
---@return table knotVector The generated knot vector
---@return boolean success Whether the knot vector was created
function DollyCamPathPlanner.createKnotVector(points, alpha)
    if not points or #points < 2 then
        Log.warn("Cannot create knot vector: Need at least 2 points")
        return {}, false
    end

    alpha = alpha or 0.5 -- Default to centripetal parameterization

    -- Initialize knot vector times
    local knotVector = {}
    knotVector[1] = 0.0 -- First point is at time 0

    -- Compute times based on cumulative parameterized distances
    local cumulativeTime = 0.0

    for i = 2, #points do
        local p1 = points[i - 1].position
        local p2 = points[i].position

        local segmentTime = parameterizedTime(p1, p2, alpha)
        cumulativeTime = cumulativeTime + segmentTime

        knotVector[i] = cumulativeTime
        -- Store time in the waypoint for later use
        points[i - 1].time = knotVector[i - 1]
    end

    -- Set the last point's time
    points[#points].time = cumulativeTime

    -- Normalize the knot vector to [0, 1] range
    if cumulativeTime > 0 then
        for i = 1, #knotVector do
            knotVector[i] = knotVector[i] / cumulativeTime
        end

        -- Update stored times in waypoints
        for i = 1, #points do
            points[i].time = points[i].time / cumulativeTime
        end
    end

    return knotVector, true
end

-- Helper function to apply operators to points
---@param a table|number First operand (table or number)
---@param b table|number Second operand (table or number)
---@param op string Operation: "add", "subtract", "multiply"
---@return table result Result of the operation
local function pointOperation(a, b, op)
    -- If a is a number and b is a table, swap them for multiply
    if type(a) == "number" and type(b) == "table" and op == "multiply" then
        a, b = b, a
    end

    -- Handle operations based on types
    if type(a) == "table" and type(b) == "table" then
        -- Both are tables (points)
        if op == "add" then
            return {
                x = a.x + b.x,
                y = a.y + b.y,
                z = a.z + b.z
            }
        elseif op == "subtract" then
            return {
                x = a.x - b.x,
                y = a.y - b.y,
                z = a.z - b.z
            }
        else
            Log.warn("Invalid operation for two points: " .. op)
            return { x = 0, y = 0, z = 0 }
        end
    elseif type(a) == "table" and type(b) == "number" then
        -- Table and scalar
        if op == "multiply" then
            return {
                x = a.x * b,
                y = a.y * b,
                z = a.z * b
            }
        else
            Log.warn("Invalid operation for point and scalar: " .. op)
            return { x = 0, y = 0, z = 0 }
        end
    else
        Log.warn("Invalid operands for pointOp: " .. type(a) .. ", " .. type(b))
        return { x = 0, y = 0, z = 0 }
    end
end

-- Evaluate a Catmull-Rom spline segment with centripetal parameterization
---@param p0 table Point 0 {x, y, z}
---@param p1 table Point 1 {x, y, z}
---@param p2 table Point 2 {x, y, z}
---@param p3 table Point 3 {x, y, z}
---@param t0 number Time at p0
---@param t1 number Time at p1
---@param t2 number Time at p2
---@param t3 number Time at p3
---@param t number Interpolation parameter between t1 and t2 (0.0-1.0)
---@return table result Interpolated position {x, y, z}
local function evaluateCatmullRomSegment(p0, p1, p2, p3, t0, t1, t2, t3, t)
    -- Linear interpolation between t1 and t2
    local tPrime = t1 + t * (t2 - t1)

    -- Time differences
    local t10 = t1 - t0
    local t21 = t2 - t1
    local t32 = t3 - t2

    -- Avoid division by zero
    if math.abs(t10) < 0.0001 then
        t10 = 0.0001
    end
    if math.abs(t21) < 0.0001 then
        t21 = 0.0001
    end
    if math.abs(t32) < 0.0001 then
        t32 = 0.0001
    end

    -- Calculate tangents at endpoints for C1 continuity
    local m1 = pointOperation(
            pointOperation(p2, p0, "subtract"),
            1 / (t2 - t0),
            "multiply"
    )

    local m2 = pointOperation(
            pointOperation(p3, p1, "subtract"),
            1 / (t3 - t1),
            "multiply"
    )

    -- Normalized parameter between 0 and 1
    local s = (tPrime - t1) / (t2 - t1)

    -- Hermite basis functions
    local h00 = 2 * s * s * s - 3 * s * s + 1
    local h10 = s * s * s - 2 * s * s + s
    local h01 = -2 * s * s * s + 3 * s * s
    local h11 = s * s * s - s * s

    -- Combine components using pointOperation
    local term1 = pointOperation(p1, h00, "multiply")
    local term2 = pointOperation(m1, h10 * t21, "multiply")
    local term3 = pointOperation(p2, h01, "multiply")
    local term4 = pointOperation(m2, h11 * t21, "multiply")

    local result = pointOperation(
            pointOperation(term1, term2, "add"),
            pointOperation(term3, term4, "add"),
            "add"
    )

    return result
end

-- Generate a smooth path with evenly spaced points using Catmull-Rom splines
---@return boolean success Whether the path was generated
function DollyCamPathPlanner.generateSmoothPath()
    if not STATE.dollyCam.route or not STATE.dollyCam.route.points or #STATE.dollyCam.route.points < 2 then
        Log.warn("Cannot generate path: Need at least 2 waypoints")
        return false
    end

    local pointDensity = 30

    -- Create knot vector with centripetal parameterization
    local knotVector, success = DollyCamPathPlanner.createKnotVector(STATE.dollyCam.route.points, STATE.dollyCam.alpha)
    if not success then
        Log.warn("Failed to create knot vector")
        return false
    end

    STATE.dollyCam.route.knotVector = knotVector

    -- Clear existing path
    STATE.dollyCam.route.path = {}
    STATE.dollyCam.route.segments = {}
    STATE.dollyCam.route.segmentDistances = {}
    STATE.dollyCam.route.totalDistance = 0

    local extendedPoints = {}

    -- Handle first segment with reflection for C1 continuity
    if #STATE.dollyCam.route.points >= 2 then
        local p0 = STATE.dollyCam.route.points[1].position
        local p1 = STATE.dollyCam.route.points[2].position

        -- Create a reflection of p1 across p0
        local reflection = {
            x = 2 * p0.x - p1.x,
            y = 2 * p0.y - p1.y,
            z = 2 * p0.z - p1.z
        }

        -- Add to extended points
        table.insert(extendedPoints, { position = reflection, time = -knotVector[2] })
    end

    -- Add actual points
    for i, point in ipairs(STATE.dollyCam.route.points) do
        table.insert(extendedPoints, point)
    end

    -- Handle last segment with reflection for C1 continuity
    if #STATE.dollyCam.route.points >= 2 then
        local pn = STATE.dollyCam.route.points[#STATE.dollyCam.route.points].position
        local pn_1 = STATE.dollyCam.route.points[#STATE.dollyCam.route.points - 1].position

        -- Create a reflection of pn_1 across pn
        local reflection = {
            x = 2 * pn.x - pn_1.x,
            y = 2 * pn.y - pn_1.y,
            z = 2 * pn.z - pn_1.z
        }

        -- Add to extended points
        local lastTime = STATE.dollyCam.route.points[#STATE.dollyCam.route.points].time
        local extraTime = lastTime + (lastTime - STATE.dollyCam.route.points[#STATE.dollyCam.route.points - 1].time)
        table.insert(extendedPoints, { position = reflection, time = extraTime })
    end

    local globalPath = {}

    -- First, calculate total accumulated path length (for each segment)
    local segmentLengths = {}
    local totalPathLength = 0

    -- Add exact waypoints to the global path - these are our anchor points
    for i = 1, #STATE.dollyCam.route.points do
        local waypoint = STATE.dollyCam.route.points[i]
        table.insert(globalPath, {
            x = waypoint.position.x,
            y = waypoint.position.y,
            z = waypoint.position.z,
            isWaypoint = true,  -- Mark as waypoint for later
            waypointIndex = i
        })
    end

    -- Now fill in interpolated points between waypoints
    local waypointSegments = {}  -- Store segments between waypoints

    for i = 1, #STATE.dollyCam.route.points - 1 do
        local p0 = extendedPoints[i].position
        local p1 = extendedPoints[i+1].position
        local p2 = extendedPoints[i+2].position
        local p3 = extendedPoints[i+3] and extendedPoints[i+3].position or p2

        local t0 = extendedPoints[i].time
        local t1 = extendedPoints[i+1].time
        local t2 = extendedPoints[i+2].time
        local t3 = extendedPoints[i+3] and extendedPoints[i+3].time or (t2 + (t2 - t1))

        local segment = {}

        -- Add first waypoint
        table.insert(segment, {
            x = STATE.dollyCam.route.points[i].position.x,
            y = STATE.dollyCam.route.points[i].position.y,
            z = STATE.dollyCam.route.points[i].position.z
        })

        -- Add interpolated points (skipping first and last)
        for j = 1, pointDensity - 1 do
            local t = j / pointDensity

            local point = evaluateCatmullRomSegment(p0, p1, p2, p3, t0, t1, t2, t3, t)
            table.insert(segment, point)
        end

        -- Add last waypoint
        table.insert(segment, {
            x = STATE.dollyCam.route.points[i+1].position.x,
            y = STATE.dollyCam.route.points[i+1].position.y,
            z = STATE.dollyCam.route.points[i+1].position.z
        })

        -- Calculate segment length
        local segmentLength = 0
        for j = 2, #segment do
            segmentLength = segmentLength + calculateDistance(segment[j-1], segment[j])
        end

        table.insert(segmentLengths, segmentLength)
        table.insert(waypointSegments, segment)
        totalPathLength = totalPathLength + segmentLength
    end

    -- Now create segments array and global path
    STATE.dollyCam.route.segments = waypointSegments
    STATE.dollyCam.route.segmentDistances = segmentLengths
    STATE.dollyCam.route.totalDistance = totalPathLength

    -- Recreate global path from segments
    STATE.dollyCam.route.path = {}
    for i, segment in ipairs(waypointSegments) do
        for j, point in ipairs(segment) do
            -- Skip first point of non-first segments to avoid duplicates
            if not (i > 1 and j == 1) then
                table.insert(STATE.dollyCam.route.path, point)
            end
        end
    end

    Log.debug(string.format("Generated path with %d segments, total distance: %.2f",
            #waypointSegments, totalPathLength))

    return true
end

-- Get position at a specific distance along the path
---@param distance number Distance along the path
---@return table|nil position Position and rotation at the specified distance, or nil if invalid
function DollyCamPathPlanner.getPositionAtDistance(distance)
    if not STATE.dollyCam.route or not STATE.dollyCam.route.segments or #STATE.dollyCam.route.segments == 0 then
        return nil
    end

    -- Clamp distance to valid range
    distance = math.max(0, math.min(STATE.dollyCam.route.totalDistance, distance))

    -- Find the segment containing this distance
    local traversedDistance = 0
    local targetSegment = 1
    local segmentStart = 0

    for i, segmentDist in ipairs(STATE.dollyCam.route.segmentDistances) do
        if traversedDistance + segmentDist >= distance then
            targetSegment = i
            segmentStart = traversedDistance
            break
        end
        traversedDistance = traversedDistance + segmentDist
    end

    -- Calculate segment-relative progress (0.0 to 1.0)
    local segmentDistance = STATE.dollyCam.route.segmentDistances[targetSegment]
    local segmentProgress = (distance - segmentStart) / segmentDistance

    -- Get control points for this segment
    local waypoints = STATE.dollyCam.route.points

    -- Get the four points needed for Catmull-Rom interpolation
    local p0 = targetSegment > 1 and waypoints[targetSegment-1].position or waypoints[1].position
    local p1 = waypoints[targetSegment].position
    local p2 = waypoints[targetSegment+1].position
    local p3 = targetSegment+1 < #waypoints and waypoints[targetSegment+2].position or waypoints[#waypoints].position

    -- Get time parameters
    local t0 = targetSegment > 1 and waypoints[targetSegment-1].time or 0
    local t1 = waypoints[targetSegment].time
    local t2 = waypoints[targetSegment+1].time
    local t3 = targetSegment+1 < #waypoints and waypoints[targetSegment+2].time or 1

    -- Handle case where we're exactly at a waypoint to avoid numerical issues
    if segmentProgress < 0.001 then
        return {
            x = p1.x,
            y = p1.y,
            z = p1.z
        }
    elseif segmentProgress > 0.999 then
        return {
            x = p2.x,
            y = p2.y,
            z = p2.z
        }
    end

    -- Use the Catmull-Rom spline directly for position calculation
    local point = evaluateCatmullRomSegment(p0, p1, p2, p3, t0, t1, t2, t3, segmentProgress)

    return point
end

-- Get path tangent at a specific distance
---@param distance number Distance along the path
---@return table|nil tangent Normalized tangent vector at the specified distance, or nil if invalid
function DollyCamPathPlanner.getPathTangentAtDistance(distance)
    if not STATE.dollyCam.route or not STATE.dollyCam.route.segments or #STATE.dollyCam.route.segments == 0 then
        return nil
    end

    -- Use a small delta to calculate tangent
    local delta = math.min(1, STATE.dollyCam.route.totalDistance * 0.001)

    local pos1 = DollyCamPathPlanner.getPositionAtDistance(distance)
    local pos2 = DollyCamPathPlanner.getPositionAtDistance(distance + delta)

    if not pos1 or not pos2 then
        return nil
    end

    -- Calculate tangent vector
    local tangent = {
        x = pos2.x - pos1.x,
        y = pos2.y - pos1.y,
        z = pos2.z - pos1.z
    }

    -- Normalize the tangent
    local length = math.sqrt(tangent.x ^ 2 + tangent.y ^ 2 + tangent.z ^ 2)
    if length > 0.0001 then
        tangent.x = tangent.x / length
        tangent.y = tangent.y / length
        tangent.z = tangent.z / length
    end

    return tangent
end

-- Calculate the distance of a point to the path
---@param position table Position to check {x, y, z}
---@param samples number|nil Number of samples to check (default: 50)
---@return number distance Closest distance to the path
---@return number closestDistance Distance along the path of the closest point
function DollyCamPathPlanner.getDistanceToPath(position, samples)
    if not STATE.dollyCam.route or not STATE.dollyCam.route.path or #STATE.dollyCam.route.path == 0 then
        return math.huge, 0
    end

    samples = samples or 50

    local minDistance = math.huge
    local closestDistance = 0
    local sampleStep = STATE.dollyCam.route.totalDistance / samples

    for i = 0, samples do
        local distance = i * sampleStep
        local pathPos = DollyCamPathPlanner.getPositionAtDistance(distance)

        if pathPos then
            local dx = pathPos.x - position.x
            local dy = pathPos.y - position.y
            local dz = pathPos.z - position.z

            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

            if dist < minDistance then
                minDistance = dist
                closestDistance = distance
            end
        end
    end

    return minDistance, closestDistance
end

-- Find the closest waypoint to a position
---@param position table Position to check {x, y, z}
---@return number|nil waypointIndex Index of closest waypoint, or nil if no waypoints
---@return number distance Distance to the closest waypoint
function DollyCamPathPlanner.findClosestWaypoint(position)
    if not STATE.dollyCam.route or not STATE.dollyCam.route.points or #STATE.dollyCam.route.points == 0 then
        return nil, math.huge
    end

    local closestIndex
    local closestDist = math.huge

    for i, waypoint in ipairs(STATE.dollyCam.route.points) do
        local dx = waypoint.position.x - position.x
        local dy = waypoint.position.y - position.y
        local dz = waypoint.position.z - position.z

        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

        if dist < closestDist then
            closestDist = dist
            closestIndex = i
        end
    end

    return closestIndex, closestDist
end

-- Clone a route with additional sample points for smoother paths
---@param route DollyCamRoute Original route
---@param pointDensity number|nil Number of points per segment (default: 5)
---@return DollyCamRoute denseRoute New route with more points
function DollyCamPathPlanner.createDenseRoute(route, pointDensity)
    if not route or not route.points or #route.points < 2 then
        return route
    end

    pointDensity = pointDensity or 5

    -- First generate the path for the original route
    DollyCamPathPlanner.generateSmoothPath()

    -- Create a new route
    local denseRoute = {
        name = route.name .. " (Dense)",
        points = {},
        path = {},
        segments = {},
        totalDistance = 0,
        segmentDistances = {},
        knotVector = {}
    }

    -- Add the first point
    table.insert(denseRoute.points, Util.deepCopy(route.points[1]))

    -- For each segment, add intermediate points
    for i = 1, #route.segments do
        local segment = route.segments[i]
        local stepSize = math.max(1, math.floor(#segment / pointDensity))

        -- Add points at regular intervals, skipping the first one
        for j = stepSize, #segment, stepSize do
            local pos = segment[j]

            local waypoint = {
                position = {
                    x = pos.x,
                    y = pos.y,
                    z = pos.z
                },
                tension = route.points[1].tension, -- Use same tension as original
                time = nil -- Will be calculated
            }

            table.insert(denseRoute.points, waypoint)
        end
    end

    -- Generate path for the dense route
    DollyCamPathPlanner.generateSmoothPath(denseRoute)

    return denseRoute
end

return {
    DollyCamPathPlanner = DollyCamPathPlanner
}