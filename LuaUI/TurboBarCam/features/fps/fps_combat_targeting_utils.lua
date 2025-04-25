---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarCam/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarCam/common.lua")

local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG
local Util = CommonModules.Util
local Log = CommonModules.Log

---@class FPSTargetingUtils
local FPSTargetingUtils = {}

-- Constants for air target handling
local AIR_HEIGHT_THRESHOLD = 80      -- Minimum height to consider a target as "air"
local ACTIVATION_ANGLE = 0.5         -- Minimum angle to activate air target adjustment
local DEACTIVATION_ANGLE = 0.4       -- Angle to deactivate adjustment (hysteresis)

-- Constants for target grouping (cloud targeting)
local TARGET_HISTORY_SIZE = 20       -- How many recent targets to track
local TARGET_HISTORY_DURATION = 3.0  -- How long targets remain in history (seconds)
local MIN_TARGETS_FOR_CLOUD = 3      -- Minimum targets needed to form a "cloud"
local CLOUD_RADIUS = 300             -- Maximum radius for targets to be considered in the same cloud

-- Initialize targeting state
local function initializeTargetingState()
    if not STATE.tracking.fps.targeting then
        STATE.tracking.fps.targeting = {
            -- Air targeting
            airAdjustmentActive = false,
            lastUpdateTime = Spring.GetTimer(),
            lastRealPos = nil,
            positionHistory = {},
            isCachedTarget = false,
            cachedTargetDuration = 0,
            velocityX = 0,
            velocityY = 0,
            velocityZ = 0,
            speed = 0,
            ySpeed = 0,
            lastVelocityLogTime = Spring.GetTimer(),
            lastLogTime = Spring.GetTimer(),
            isMovingFast = false,
            isMovingUpFast = false,
            frameCounter = 0,
            
            -- Target cloud tracking
            targetHistory = {},       -- Recent target positions
            cloudCenter = nil,        -- Center of the target cloud
            cloudRadius = 0,          -- Radius of the target cloud
            useCloudTargeting = false, -- Whether to use cloud targeting
            cloudStartTime = nil,     -- When cloud targeting began
            lastCloudUpdateTime = Spring.GetTimer(),
            highActivityDetected = false,
            activityLevel = 0         -- Measure of targeting activity (0-1)
        }
    end
    return STATE.tracking.fps.targeting
end

--- Detects if a position is being cached (not updated in real time)
--- @param targetPos table The current target position
--- @param targeting table The targeting state
--- @return boolean isCached Whether the position is cached
local function detectCachedPosition(targetPos, targeting)
    -- Check if the position is exactly the same as the last real position
    if targeting.lastRealPos and 
       targetPos.x == targeting.lastRealPos.x and
       targetPos.y == targeting.lastRealPos.y and
       targetPos.z == targeting.lastRealPos.z then
        targeting.cachedTargetDuration = targeting.cachedTargetDuration + 1
        return true
    else
        -- Not using a cached position, or first frame
        targeting.lastRealPos = {
            x = targetPos.x,
            y = targetPos.y,
            z = targetPos.z
        }
        targeting.cachedTargetDuration = 0
        return false
    end
end

--- Estimates velocity for a target based on position history or simulation
--- @param targetPos table The target position
--- @param unitPos table The unit position
--- @param horizontalDist number Horizontal distance to target
--- @param targeting table The targeting state
--- @param using_cached_target boolean Whether using a cached target
local function updateTargetVelocity(targetPos, unitPos, horizontalDist, targeting, using_cached_target)
    local currentTime = Spring.GetTimer()
    
    -- For high-speed target detection with cached positions, simulate target motion
    if using_cached_target and targeting.cachedTargetDuration > 30 then
        -- Air units typically move at 80-150 units/second
        -- For high-speed fighters, assume around 120 units/second
        local estimated_speed = 120.0
        
        -- Direction from our unit to the target (normalized)
        local dx = targetPos.x - unitPos.x
        local dz = targetPos.z - unitPos.z
        local dirX, dirZ
        
        if horizontalDist > 0.001 then
            dirX = dx / horizontalDist
            dirZ = dz / horizontalDist
        else
            dirX, dirZ = 0, 1  -- Default direction if target is directly above
        end
        
        -- Apply some randomness to make it feel natural
        local randomFactor = (math.random() * 0.4) + 0.8  -- 0.8 to 1.2
        
        -- Set estimated velocity components
        targeting.velocityX = dirX * estimated_speed * randomFactor
        targeting.velocityZ = dirZ * estimated_speed * randomFactor
        
        -- Assume slight vertical movement for fighters
        targeting.velocityY = (math.random() * 20) - 10  -- -10 to +10
        
        -- Calculate total speed
        targeting.speed = math.sqrt(
            targeting.velocityX * targeting.velocityX +
            targeting.velocityY * targeting.velocityY +
            targeting.velocityZ * targeting.velocityZ
        )
        
        -- Set vertical speed component
        targeting.ySpeed = targeting.velocityY
        
        -- For cached targets, we generally won't detect "fast upward movement"
        targeting.isMovingFast = targeting.speed > 150
        targeting.isMovingUpFast = false
        
        -- Log estimated velocity periodically
        if Spring.DiffTimers(currentTime, targeting.lastVelocityLogTime) > 1.0 then
            Log.trace(string.format("Estimated target velocity: %.1f units/s (x=%.1f, y=%.1f, z=%.1f)", 
                targeting.speed, targeting.velocityX, targeting.velocityY, targeting.velocityZ))
            targeting.lastVelocityLogTime = currentTime
        end
    else 
        -- Normal velocity sampling (only useful for actively tracked targets)
        targeting.frameCounter = targeting.frameCounter + 1
        
        -- Only update velocity when we have a real position update
        if not using_cached_target and targeting.frameCounter % 3 == 0 then
            -- Update position history when we have real position data
            table.insert(targeting.positionHistory, {
                pos = {x = targetPos.x, y = targetPos.y, z = targetPos.z},
                time = currentTime
            })
            
            -- Keep only the last 5 position records
            if #targeting.positionHistory > 5 then
                table.remove(targeting.positionHistory, 1)
            end
            
            -- Calculate velocity if we have enough history (at least 2 points)
            if #targeting.positionHistory >= 2 then
                local newest = targeting.positionHistory[#targeting.positionHistory]
                local oldest = targeting.positionHistory[1]
                
                local timeDiff = Spring.DiffTimers(newest.time, oldest.time)
                
                -- Ensure we have a meaningful time difference
                if timeDiff > 0.05 then
                    -- Calculate velocity components
                    targeting.velocityX = (newest.pos.x - oldest.pos.x) / timeDiff
                    targeting.velocityY = (newest.pos.y - oldest.pos.y) / timeDiff
                    targeting.velocityZ = (newest.pos.z - oldest.pos.z) / timeDiff
                    
                    -- Calculate speed magnitudes
                    targeting.speed = math.sqrt(
                        targeting.velocityX * targeting.velocityX +
                        targeting.velocityY * targeting.velocityY +
                        targeting.velocityZ * targeting.velocityZ
                    )
                    targeting.ySpeed = targeting.velocityY
                    
                    -- Flag for fast-moving targets
                    local speedThreshold = 200  -- Units per second
                    local upSpeedThreshold = 150  -- Upward units per second
                    
                    local prevIsMovingFast = targeting.isMovingFast
                    local prevIsMovingUpFast = targeting.isMovingUpFast
                    
                    targeting.isMovingFast = targeting.speed > speedThreshold
                    targeting.isMovingUpFast = targeting.ySpeed > upSpeedThreshold
                    
                    -- Log when movement state changes
                    if targeting.isMovingUpFast and not prevIsMovingUpFast then
                        Log.info(string.format("Fast upward movement detected: %.1f units/s (threshold: %.1f)", 
                            targeting.ySpeed, upSpeedThreshold))
                    elseif not targeting.isMovingUpFast and prevIsMovingUpFast then
                        Log.info("Target no longer moving fast upward")
                    end
                    
                    -- Log velocity periodically
                    if Spring.DiffTimers(currentTime, targeting.lastVelocityLogTime) > 1.0 then
                        Log.trace(string.format("Target velocity: %.1f units/s (x=%.1f, y=%.1f, z=%.1f)", 
                            targeting.speed, targeting.velocityX, targeting.velocityY, targeting.velocityZ))
                        targeting.lastVelocityLogTime = currentTime
                    end
                end
            end
        end
    end
end

--- Updates the target history for cloud targeting
--- @param targetPos table The current target position
--- @param targeting table The targeting state
local function updateTargetHistory(targetPos, targeting)
    local currentTime = Spring.GetTimer()
    
    -- Add current target to history
    table.insert(targeting.targetHistory, {
        pos = {x = targetPos.x, y = targetPos.y, z = targetPos.z},
        time = currentTime
    })
    
    -- Remove old targets
    local i = 1
    while i <= #targeting.targetHistory do
        local timeDiff = Spring.DiffTimers(currentTime, targeting.targetHistory[i].time)
        if timeDiff > TARGET_HISTORY_DURATION then
            table.remove(targeting.targetHistory, i)
        else
            i = i + 1
        end
    end
    
    -- Keep history size reasonable
    while #targeting.targetHistory > TARGET_HISTORY_SIZE do
        table.remove(targeting.targetHistory, 1)
    end
    
    -- Calculate activity level based on target history size
    targeting.activityLevel = math.min(#targeting.targetHistory / MIN_TARGETS_FOR_CLOUD, 1.0)
    
    -- Update high activity flag
    if targeting.activityLevel >= 0.8 and not targeting.highActivityDetected then
        targeting.highActivityDetected = true
        Log.info("High targeting activity detected - enabling cloud targeting")
        targeting.cloudStartTime = currentTime
    elseif targeting.activityLevel < 0.5 and targeting.highActivityDetected then
        targeting.highActivityDetected = false
        Log.info("Targeting activity normalized - disabling cloud targeting")
        targeting.cloudStartTime = nil
    end
    
    -- Periodically log activity level
    if Spring.DiffTimers(currentTime, targeting.lastCloudUpdateTime) > 1.0 then
        if targeting.activityLevel > 0.5 then
            Log.trace(string.format("Targeting activity level: %.2f (%d targets in history)", 
                targeting.activityLevel, #targeting.targetHistory))
        end
        targeting.lastCloudUpdateTime = currentTime
    end
    
    -- Decide whether to use cloud targeting
    targeting.useCloudTargeting = targeting.highActivityDetected and 
        #targeting.targetHistory >= MIN_TARGETS_FOR_CLOUD
end

--- Calculates the center of the target cloud
--- @param targeting table The targeting state
--- @return table cloudCenter The center of the target cloud
local function calculateCloudCenter(targeting)
    if #targeting.targetHistory < MIN_TARGETS_FOR_CLOUD then
        return nil
    end
    
    -- Calculate the centroid of all recent targets
    local sumX, sumY, sumZ = 0, 0, 0
    local count = 0
    
    -- Give more weight to more recent targets
    local currentTime = Spring.GetTimer()
    
    for _, target in ipairs(targeting.targetHistory) do
        local timeDiff = Spring.DiffTimers(currentTime, target.time)
        local weight = 1.0 - (timeDiff / TARGET_HISTORY_DURATION)
        weight = weight * weight  -- Square for stronger recency bias
        
        sumX = sumX + target.pos.x * weight
        sumY = sumY + target.pos.y * weight
        sumZ = sumZ + target.pos.z * weight
        count = count + weight
    end
    
    if count > 0 then
        local center = {
            x = sumX / count,
            y = sumY / count,
            z = sumZ / count
        }
        
        -- Calculate cloud radius
        local maxDistSq = 0
        for _, target in ipairs(targeting.targetHistory) do
            local dx = target.pos.x - center.x
            local dy = target.pos.y - center.y
            local dz = target.pos.z - center.z
            local distSq = dx*dx + dy*dy + dz*dz
            if distSq > maxDistSq then
                maxDistSq = distSq
            end
        end
        
        targeting.cloudRadius = math.sqrt(maxDistSq)
        
        if targeting.useCloudTargeting then
            Log.trace(string.format("Target cloud: center=(%.1f, %.1f, %.1f), radius=%.1f", 
                center.x, center.y, center.z, targeting.cloudRadius))
        end
        
        return center
    end
    
    return nil
end

--- Gets the appropriate target position (actual target or cloud center)
--- @param targetPos table The current target position
--- @param targeting table The targeting state
--- @return table effectiveTarget The position to aim at
local function getEffectiveTargetPosition(targetPos, targeting)
    -- If cloud targeting is active, use the cloud center instead of the current target
    if targeting.useCloudTargeting then
        local cloudCenter = calculateCloudCenter(targeting)
        if cloudCenter then
            -- Apply some smoothing/interpolation between actual target and cloud center
            local blend = 0.7  -- 70% cloud, 30% actual target
            return {
                x = targetPos.x * (1-blend) + cloudCenter.x * blend,
                y = targetPos.y * (1-blend) + cloudCenter.y * blend,
                z = targetPos.z * (1-blend) + cloudCenter.z * blend
            }
        end
    end
    
    -- Default to actual target position
    return targetPos
end

--- Handles air target camera positioning adjustments
--- @param position table Camera position {x, y, z}
--- @param targetPos table Target position {x, y, z}
--- @param unitPos table Base unit position {x, y, z}
--- @return table adjustedPos Adjusted camera position {x, y, z}
function FPSTargetingUtils.handleAirTargetRepositioning(position, targetPos, unitPos)
    if not position or not targetPos then
        return position
    end
    
    -- Initialize or get targeting state
    local targeting = initializeTargetingState()
    
    -- Store original position for reference
    local x, y, z = position.x, position.y, position.z
    
    -- Check if we're using a cached target position
    local using_cached_target = detectCachedPosition(targetPos, targeting)
    targeting.isCachedTarget = using_cached_target
    
    -- Log when the target position state changes
    local currentTime = Spring.GetTimer()
    if Spring.DiffTimers(currentTime, targeting.lastLogTime) > 1.0 then
        if using_cached_target then
            Log.trace(string.format("Using cached target position (duration: %d frames)", 
                targeting.cachedTargetDuration))
        else
            Log.trace("Using real-time target position")
        end
        targeting.lastLogTime = currentTime
    end
    
    -- Update target history for cloud targeting
    updateTargetHistory(targetPos, targeting)
    
    -- Get the effective target position (actual target or cloud center)
    local effectiveTarget = getEffectiveTargetPosition(targetPos, targeting)
    
    -- Check if target is significantly above the unit (air unit)
    local heightDiff = effectiveTarget.y - unitPos.y
    
    -- Early exit if target isn't significantly above unit
    if heightDiff <= AIR_HEIGHT_THRESHOLD then
        targeting.airAdjustmentActive = false
        return position
    end
    
    -- Calculate angle to target in vertical plane
    local dx = effectiveTarget.x - unitPos.x
    local dy = heightDiff
    local dz = effectiveTarget.z - unitPos.z
    local horizontalDist = math.sqrt(dx*dx + dz*dz)
    local verticalAngle = math.atan2(dy, horizontalDist)
    
    -- Update target velocity
    updateTargetVelocity(effectiveTarget, unitPos, horizontalDist, targeting, using_cached_target)
    
    -- Determine if we need to activate air targeting adjustments (with hysteresis)
    local activationAngle = targeting.airAdjustmentActive 
        and DEACTIVATION_ANGLE or ACTIVATION_ANGLE
    
    -- Skip adjustment if target is moving too fast upward and we're not already tracking it
    if targeting.isMovingUpFast and not targeting.airAdjustmentActive then
        Log.trace("Skipping adjustment for fast upward-moving target")
        return position
    end
    
    -- If angle is steep enough, adjust camera position
    if verticalAngle > activationAngle then
        if not targeting.airAdjustmentActive then
            Log.info(string.format("Activating air target adjustment mode (angle: %.2f, threshold: %.2f)", 
                verticalAngle, activationAngle))
        end
        
        targeting.airAdjustmentActive = true
        
        -- Calculate adjustment based on angle
        -- Higher angle = stronger adjustment
        local angleRatio = math.min((verticalAngle - ACTIVATION_ANGLE) / (math.pi/2 - ACTIVATION_ANGLE), 1.0)
        local adjustmentFactor = 0.3 + (angleRatio * 0.4)  -- Range from 0.3 to 0.7
        
        -- Determine if we're very close to the target (directly underneath)
        local isCloseToTarget = horizontalDist < 300
        local isVeryCloseToTarget = horizontalDist < 200
        local isHighTargetMode = verticalAngle > 0.8  -- ~45 degrees
        
        -- Distance-based adjustment - more aggressive repositioning when close
        local distanceAdjustment = 1.0
        if isCloseToTarget then
            distanceAdjustment = 1.4  -- More aggressive when close
            if isVeryCloseToTarget then
                distanceAdjustment = 1.7  -- Even more aggressive when very close
            end
        end
        
        -- For high targets, focus more on moving back to keep unit in view
        local upRatio, backRatio
        
        -- When directly underneath, move much more back and less up
        if isVeryCloseToTarget and verticalAngle > 1.3 then
            -- Almost overhead
            -- Closest and steepest case - much more backward
            upRatio = 0.15  -- Minimal upward movement
            backRatio = 1.5 * distanceAdjustment  -- Maximize backward movement
        elseif isHighTargetMode then
            -- High target mode: prioritize moving back to keep unit in view
            upRatio = math.min(verticalAngle * 0.25, 0.3) * (isCloseToTarget and 0.7 or 1.0)  -- Reduced upward when close
            backRatio = (0.9 + (angleRatio * 0.3)) * distanceAdjustment  -- Range from 0.9 to 1.2 * adjustment
        else
            -- Normal mode: still favor back movement
            upRatio = math.min(verticalAngle * 0.35, 0.4)  -- Reduced upward movement
            backRatio = (0.8 + (angleRatio * 0.3)) * distanceAdjustment  -- Range from 0.8 to 1.1 * adjustment
        end
        
        -- Apply the adjustment factor to both movements
        -- Calculate distance to move camera
        local moveUp = math.min(heightDiff * upRatio * adjustmentFactor, 90)  -- Reduced maximum height
        local moveBack = math.min(horizontalDist * backRatio * adjustmentFactor, 220)  -- Increased maximum back distance
        
        -- For high targets, ensure substantial back movement
        if isHighTargetMode then
            moveBack = math.max(moveBack, 120)  -- Ensure minimum back movement for high targets
            
            -- Special case for very close targets - ensure maximum back distance
            if isVeryCloseToTarget then
                moveBack = math.max(moveBack, 300)  -- More back when very close
                moveUp = math.min(moveUp, 40)  -- Much less up when very close
            elseif isCloseToTarget then
                moveBack = math.max(moveBack, 200)  -- More back when close
                moveUp = math.min(moveUp, 50)  -- Less up when close
            end
        end
        
        -- Apply vertical adjustment
        y = y + moveUp
        
        -- Apply backward movement along the horizontal vector to target
        if horizontalDist > 0.001 then
            local horNormX = dx / horizontalDist
            local horNormZ = dz / horizontalDist
            x = x - horNormX * moveBack
            z = z - horNormZ * moveBack
        end
        
        -- Enhanced logging with more details
        Log.trace(string.format(
            "Air target adjustment: up=%.1f, back=%.1f, angle=%.2f, dist=%.1f, v=%.1f, vy=%.1f%s%s%s%s%s", 
            moveUp, moveBack, verticalAngle, horizontalDist, targeting.speed, targeting.ySpeed,
            isHighTargetMode and ", HIGH" or "",
            isVeryCloseToTarget and ", VERY_CLOSE" or (isCloseToTarget and ", CLOSE" or ""),
            targeting.isMovingUpFast and ", FAST_UP" or "",
            using_cached_target and ", CACHED" or "",
            targeting.useCloudTargeting and ", CLOUD" or ""
        ))
        
        return { x = x, y = y, z = z }
    else
        if targeting.airAdjustmentActive then
            Log.info(string.format("Deactivating air target adjustment (angle: %.2f, threshold: %.2f)", 
                verticalAngle, activationAngle))
        end
        
        -- No longer meets criteria for adjustment
        targeting.airAdjustmentActive = false
        return position
    end
end

return {
    FPSTargetingUtils = FPSTargetingUtils
}