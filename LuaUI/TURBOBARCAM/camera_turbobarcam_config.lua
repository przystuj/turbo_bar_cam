--------------------------------------------------------------------------------
-- CONFIGURATION & STATE MANAGEMENT (REFACTORED)
--------------------------------------------------------------------------------

-- Initialize the global widget table for TURBOBARCAM if it doesn't exist
WG.TURBOBARCAM = WG.TURBOBARCAM or {}

-- Create a module to export
local TurboModule = {}

-- Only initialize CONFIG if it doesn't exist in WG already
if not WG.TURBOBARCAM.CONFIG then
    ---@class CONFIG
    WG.TURBOBARCAM.CONFIG = {
        -- Camera mode settings
        CAMERA_MODES = {
            -- FPS camera settings
            FPS = {
                OFFSETS = {
                    HEIGHT = 60, -- Default height, will be updated based on unit height
                    FORWARD = -100,
                    SIDE = 0,
                    ROTATION = 0 -- Rotation offset (radians)
                },
                DEFAULT_OFFSETS = {
                    HEIGHT = 60,
                    FORWARD = -100,
                    SIDE = 0,
                    ROTATION = 0
                }
            },

            -- Orbit camera settings
            ORBIT = {
                HEIGHT_FACTOR = 4, -- Height is 4x unit height
                DISTANCE = 300, -- Distance from unit
                SPEED = 0.01, -- Orbit speed in radians per frame
                DEFAULT_SPEED = 0.0005,
                AUTO_ORBIT = {
                    ENABLED = true,
                    DELAY = 10, -- Seconds of no movement to trigger auto orbit
                    SMOOTHING_FACTOR = 5 -- Higher means smoother transition
                }
            },

            -- Turbo overview camera settings
            TURBO_OVERVIEW = {
                HEIGHT_FACTOR = 0.1, -- Default height as a factor of map diagonal
                DEFAULT_SMOOTHING = 0.05, -- Default smoothing factor
                DEFAULT_ZOOM_LEVEL = 1, -- Default zoom level index
                ZOOM_LEVELS = {1, 2, 4}, -- Available zoom levels (multipliers)
            },
        },

        -- Transition settings
        TRANSITION = {
            DURATION = 2.0, -- Default transition duration (seconds)
            MIN_DURATION = 0.0, -- Minimum transition duration
            STEPS_PER_SECOND = 60 -- Steps per second for smooth transitions
        },

        -- Smoothing factors
        SMOOTHING = {
            POSITION_FACTOR = 0.05, -- Lower = smoother but more lag (0.0-1.0)
            ROTATION_FACTOR = 0.008, -- Lower = smoother but more lag (0.0-1.0)
            FPS_FACTOR = 0.15, -- Specific for FPS mode
            TRACKING_FACTOR = 0.05, -- Specific for Tracking Camera mode
            MODE_TRANSITION_FACTOR = 0.04, -- For smoothing between camera modes
            FREE_CAMERA_FACTOR = 0.05  -- Smoothing factor for free camera mouse movement
        },

        -- Command IDs
        COMMANDS = {
            SET_FIXED_LOOK_POINT = 455625,
        },

        -- Spectator settings
        SPEC_GROUPS = {
            ENABLED = true, -- Enable spectator unit groups
            MAX_GROUPS = 9  -- Maximum number of groups (1-9)
        }
    }
end

-- Only initialize STATE if it doesn't exist in WG already
if not WG.TURBOBARCAM.STATE then
    ---@class STATE
    WG.TURBOBARCAM.STATE = {
        -- Core widget state
        enabled = false,
        originalCameraState = nil,
        DEBUG = true,

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
            }
        },

        -- Orbit camera state
        orbit = {
            angle = 0, -- Current orbit angle in radians
            lastPosition = nil, -- Last unit position to detect movement
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

        -- Turbo overview camera state
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
        },

        -- Delayed actions
        delayed = {
            frame = nil, -- Game frame when the callback should execute
            callback = nil  -- Function to call when frame is reached
        }
    }
end

-- Link both CONFIG and STATE to the module
TurboModule.CONFIG = WG.TURBOBARCAM.CONFIG
TurboModule.STATE = WG.TURBOBARCAM.STATE

-- Export the module (both CONFIG and STATE are shared via WG)
return TurboModule