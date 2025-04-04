-- Initialize the global widget table for TURBOBARCAM if it doesn't exist
WG.TURBOBARCAM = WG.TURBOBARCAM or {}

-- Create a module to export

---@class WidgetStateModule
---@field STATE WidgetState
local WidgetState = {}

-- Only initialize STATE if it doesn't exist in WG already
if not WG.TURBOBARCAM.STATE then
    ---@class WidgetState
    WG.TURBOBARCAM.STATE = {
        -- Core widget state
        enabled = false,
        originalCameraState = nil,
        logLevel = "INFO", -- INFO, DEBUG, TRACE

        -- Camera anchors
        anchors = {},
        lastUsedAnchor = nil,

        -- Camera transitions
        transition = {
            active = false,
            startTime = nil,
            steps = {},
            currentStepIndex = 1,
            currentAnchorIndex = nil
        },

        -- Camera tracking
        tracking = {
            -- Current mode
            mode = nil, -- 'fps', 'tracking_camera', 'fixed_point', 'orbit', 'turbo_overview'
            unitID = nil, -- Current tracked unit
            targetUnitID = nil, -- Unit being looked at (for fixed point)

            -- Core tracking state
            fixedPoint = nil, -- Fixed point to look at {x, y, z}
            inFreeCameraMode = false, -- Whether free camera is active
            unitOffsets = {}, -- Store individual unit camera offsets

            -- Selection state
            inTargetSelectionMode = false, -- Whether selecting a target
            prevFreeCamState = false, -- Free camera state before selection
            prevMode = nil, -- Previous mode during selection
            prevFixedPoint = nil, -- Previous fixed point during selection

            -- Grace period
            graceTimer = nil, -- Timer for grace period
            lastUnitID = nil, -- Last tracked unit

            -- Position tracking for smooth movement
            lastUnitPos = { x = 0, y = 0, z = 0 },
            lastCamPos = { x = 0, y = 0, z = 0 },
            lastCamDir = { x = 0, y = 0, z = 0 },
            lastRotation = { rx = 0, ry = 0, rz = 0 },

            -- Mode transition
            modeTransition = false, -- Is transitioning between modes
            transitionStartState = nil, -- Start camera state for transition
            transitionStartTime = nil, -- When transition started

            -- Free camera state
            freeCam = {
                lastMouseX = nil,
                lastMouseY = nil,
                targetRx = nil, -- Target rotation X (pitch)
                targetRy = nil, -- Target rotation Y (yaw)
                mouseMoveSensitivity = 0.003, -- How sensitive the camera is to mouse movement
                lastUnitHeading = nil -- Last unit heading for rotation tracking
            },

            -- Group tracking
            group = {
                unitIDs = {}, -- Array of tracked unit IDs
                centerOfMass = {x = 0, y = 0, z = 0}, -- Calculated center of mass position
                targetDistance = nil, -- Current camera target distance (will be adjusted based on group spread)
                currentDistance = nil, -- Current actual camera distance
                radius = 0, -- Group radius (max distance from center to any unit)
                outliers = {}, -- Units considered outliers (too far from group)
                totalWeight = 0, -- Total weight of all tracked units
                lastCenterOfMass = {x = 0, y = 0, z = 0}, -- Previous frame's center of mass
                centerChanged = false, -- Whether center of mass has significantly changed
                lastOutlierCheck = 0, -- Last time outliers were recalculated
                currentFOV = nil, -- Current FOV consideration
                velocity = {x = 0, y = 0, z = 0}, -- Velocity of center of mass (for determining movement direction)
            }
        },

        -- Orbit camera state
        orbit = {
            angle = 0, -- Current orbit angle in radians
            lastPosition = nil, -- Last unit position to detect movement
            lastCamPos = nil, -- Last camera position to detect movement
            lastCamRot = nil, -- Last camera rotation to detect movement
            stationaryTimer = nil, -- Timer to track how long unit has been stationary
            autoOrbitActive = false, -- Whether auto-orbit is currently active
            unitOffsets = {}, -- Store individual unit orbit settings
            originalTransitionFactor = nil, -- Store original transition factor
        },

        -- Spectator groups
        specGroups = {
            groups = {}, -- Will store unit IDs for each group (1-9)
            isSpectator = false -- Tracks if we're currently spectating
        },

        -- Turbo overview camera state initialized with defaults
        -- These will be properly initialized in TurboOverviewCamera.toggle()
        turboOverview = {
            height = nil, -- Will be set dynamically based on map size
            zoomLevel = 1, -- Current zoom level index
            zoomLevels = {1, 2, 4}, -- Available zoom levels (multipliers)
            movementSmoothing = 0.05, -- Smoothing factor for movement to target
            initialMovementSmoothing = 0.01, -- Initial (slower) smoothing factor
            zoomTransitionFactor = 0.04, -- How fast zoom transitions occur
            targetHeight = nil, -- Target height for smooth zoom transitions
            inZoomTransition = false, -- Whether currently in a zoom transition
            fixedCamPos = {x = 0, y = 0, z = 0}, -- Fixed camera position
            targetPos = {x = 0, y = 0, z = 0}, -- Target position to move to
            movingToTarget = false, -- Whether currently moving to target
            moveStartTime = nil, -- When movement to target started
            targetRx = 0, -- Target pitch rotation
            targetRy = 0, -- Target yaw rotation
            lastMouseX = nil, -- Last mouse X position for rotation calculation
            lastMouseY = nil, -- Last mouse Y position for rotation calculation
            mouseMoveSensitivity = 0.003, -- How sensitive rotation is to mouse movement

            -- Target movement variables
            isMovingToTarget = false, -- Whether movement mode is active
            targetPoint = nil, -- Target point to move toward {x, y, z}
            distanceToTarget = 500, -- Distance from target point
            movementAngle = 0, -- Current movement angle in radians (for steering)
            angularVelocity = 0, -- Current angular velocity (for steering)
            maxAngularVelocity = 0.05, -- Maximum angular velocity
            angularDamping = 0.70, -- How fast angular velocity decreases
            forwardVelocity = 5, -- Constant forward velocity toward target
            minDistanceToTarget = 150, -- Minimum target distance (stop moving when reached)
            movementTransitionFactor = 0.05, -- Smooth transition factor for movement
            inMovementTransition = false, -- Whether in transition to movement mode
            targetMovementAngle = 0, -- Target angle for smooth transitions
        },

        -- Delayed actions
        delayed = {
            frame = nil, -- Game frame when the callback should execute
            callback = nil  -- Function to call when frame is reached
        }
    }
end

-- Link STATE to the module
WidgetState.STATE = WG.TURBOBARCAM.STATE

-- Export the module
return WidgetState