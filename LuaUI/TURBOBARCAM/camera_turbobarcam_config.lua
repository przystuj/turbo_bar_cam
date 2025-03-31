--------------------------------------------------------------------------------
-- CONFIGURATION & STATE MANAGEMENT
--------------------------------------------------------------------------------

-- Initialize the global widget table for TURBOBARCAM if it doesn't exist
WG.TURBOBARCAM = WG.TURBOBARCAM or {}

-- Create a module to export
local TurboModule = {}

-- Only initialize CONFIG if it doesn't exist in WG already
if not WG.TURBOBARCAM.CONFIG then
    ---@class CONFIG
    ---@field COMMANDS table Commands settings
    ---@field TRANSITION table Transition settings
    ---@field FPS table FPS camera settings
    ---@field SMOOTHING table Smoothing settings
    ---@field ORBIT table Orbit camera settings
    ---@field SPEC_GROUPS table Spectator groups settings
    WG.TURBOBARCAM.CONFIG = {

        TURBO_OVERVIEW = {
            DEFAULT_HEIGHT_FACTOR = 0.1, -- Default height as a factor of map diagonal
            DEFAULT_SMOOTHING = 0.05, -- Default smoothing factor
            DEFAULT_ZOOM_LEVEL = 1, -- Default zoom level index
            ZOOM_LEVELS = {1, 2, 4}, -- Available zoom levels (multipliers)
        },

        COMMANDS = {
            SET_FIXED_LOOK_POINT = 455625,
        },

        -- Transition settings
        TRANSITION = {
            DURATION = 2.0,
            MIN_DURATION = 0.0,
            STEPS_PER_SECOND = 60
        },

        -- FPS camera settings
        FPS = {
            DEFAULT_HEIGHT_OFFSET = 60, -- This will be updated dynamically based on unit height
            DEFAULT_FORWARD_OFFSET = -100,
            DEFAULT_SIDE_OFFSET = 0,
            DEFAULT_ROTATION_OFFSET = 0, -- Default rotation offset (0 to pi, can be negative)
            ROTATION_OFFSET = 0, -- Current rotation offset
            HEIGHT_OFFSET = 60, -- This will be updated dynamically based on unit height
            FORWARD_OFFSET = -100,
            SIDE_OFFSET = 0
        },

        SMOOTHING = {
            POSITION_FACTOR = 0.05, -- Lower = smoother but more lag (0.0-1.0)
            ROTATION_FACTOR = 0.008, -- Lower = smoother but more lag (0.0-1.0)
            FPS_FACTOR = 0.15, -- Specific for FPS mode
            TRACKING_FACTOR = 0.05, -- Specific for Tracking Camera mode
            MODE_TRANSITION_FACTOR = 0.04, -- For smoothing between camera modes
            FREE_CAMERA_FACTOR = 0.05  -- Smoothing factor for free camera mouse movement
        },

        ORBIT = {
            DEFAULT_HEIGHT_FACTOR = 4, -- Default height is 4x unit height
            DEFAULT_DISTANCE = 300, -- Default distance from unit
            DEFAULT_SPEED = 0.0005, -- Radians per frame
            HEIGHT = nil, -- Will be set dynamically based on unit height
            DISTANCE = 300, -- Distance from unit
            SPEED = 0.01, -- Orbit speed in radians per frame
            AUTO_ORBIT_DELAY = 10, -- Seconds of no movement to trigger auto orbit
            AUTO_ORBIT_ENABLED = true, -- Whether auto-orbit is enabled
            AUTO_ORBIT_SMOOTHING_FACTOR = 5
        },

        SPEC_GROUPS = {
            ENABLED = true, -- Enable spectator unit groups
            MAX_GROUPS = 9  -- Maximum number of groups (1-9)
        }
    }
end

-- Only initialize STATE if it doesn't exist in WG already
if not WG.TURBOBARCAM.STATE then
    ---@class STATE
    ---@field enabled boolean Whether the widget is enabled
    ---@field originalCameraState table|nil Original camera state before enabling
    ---@field anchors table<number, table> Camera anchor states
    ---@field lastUsedAnchor number|nil Last used camera anchor index
    ---@field transition table Camera transition state
    ---@field tracking table Unit tracking state
    ---@field delayed table Delayed action state
    ---@field orbit table Orbit camera state
    ---@field specGroups table Spectator groups state
    WG.TURBOBARCAM.STATE = {
        -- Widget state
        enabled = false,
        originalCameraState = nil,
        DEBUG = false,

        -- Anchors
        anchors = {},
        lastUsedAnchor = nil,

        -- Transition
        transition = {
            active = false,
            startTime = nil,
            steps = {},
            currentStepIndex = 1,
            currentAnchorIndex = nil
        },

        -- Tracking
        tracking = {
            mode = nil, -- 'fps' or 'tracking_camera' or 'fixed_point' or 'orbit'
            unitID = nil,
            targetUnitID = nil, -- Store the ID of the unit we're looking at
            inFreeCameraMode = false,
            inTargetSelectionMode = false, -- Tracks if we're currently selecting a target
            prevFreeCamState = false, -- Stores the free camera state before target selection
            prevMode = nil, -- Stores the previous mode (fps/fixed_point) during selection
            prevFixedPoint = nil, -- Stores the previous fixed point during selection
            graceTimer = nil, -- Timer for grace period
            lastUnitID = nil, -- Store the last tracked unit
            unitOffsets = {}, -- Store individual unit camera offsets

            -- For fixed point tracking
            fixedPoint = nil, -- {x, y, z}

            -- Smoothing data
            lastUnitPos = { x = 0, y = 0, z = 0 },
            lastCamPos = { x = 0, y = 0, z = 0 },
            lastCamDir = { x = 0, y = 0, z = 0 },
            lastRotation = { rx = 0, ry = 0, rz = 0 },

            -- Mode transition tracking
            prevMode = nil, -- Previous camera mode
            modeTransition = false, -- Is transitioning between modes
            transitionStartState = nil, -- Start camera state for transition
            transitionStartTime = nil, -- When transition started

            freeCam = {
                lastMouseX = nil,
                lastMouseY = nil,
                targetRx = nil, -- Target rotation X (pitch)
                targetRy = nil, -- Target rotation Y (yaw)
                mouseMoveSensitivity = 0.003, -- How sensitive the camera is to mouse movement
                lastUnitHeading = nil
            }
        },

        -- Delayed actions
        delayed = {
            frame = nil, -- Game frame when the callback should execute
            callback = nil  -- Function to call when frame is reached
        },

        orbit = {
            angle = 0, -- Current orbit angle in radians
            lastPosition = nil, -- Last unit position to detect movement
            stationaryTimer = nil, -- Timer to track how long unit has been stationary
            autoOrbitActive = false, -- Whether auto-orbit is currently active
            unitOffsets = {}, -- Store individual unit orbit settings
            originalTransitionFactor = nil, -- Store original transition factor
        },

        specGroups = {
            groups = {}, -- Will store unit IDs for each group (1-9)
            isSpectator = false -- Tracks if we're currently spectating
        },

        turboOverview = {
            height = nil, -- Will be set dynamically based on map size
            zoomLevel = 1, -- Current zoom level index
            zoomLevels = {1, 2, 4}, -- Available zoom levels (multipliers)
            smoothing = 0.01, -- Smoothing factor for cursor following
            lastCursorWorldPos = {x = 0, y = 0, z = 0}, -- Last cursor world position
        },
    }
end

-- Link both CONFIG and STATE to the module
TurboModule.CONFIG = WG.TURBOBARCAM.CONFIG
TurboModule.STATE = WG.TURBOBARCAM.STATE

-- Export the module (both CONFIG and STATE are shared via WG)
return TurboModule