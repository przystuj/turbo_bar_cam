--------------------------------------------------------------------------------
-- CONFIGURATION & STATE MANAGEMENT
--------------------------------------------------------------------------------

-- Initialize the global widget table for TURBOBARCAM if it doesn't exist
WG.TURBOBARCAM = WG.TURBOBARCAM or {}

-- Create a module to export
---@class WidgetConfigModule
---@field CONFIG WidgetConfig
local WidgetConfig = {}

-- Only initialize CONFIG if it doesn't exist in WG already
if not WG.TURBOBARCAM.CONFIG then
    ---@class WidgetConfig
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
                HEIGHT_FACTOR = 0.33, -- Default height as a factor of map diagonal
                DEFAULT_SMOOTHING = 0.05, -- Default smoothing factor
                INITIAL_SMOOTHING = 0.01, -- Initial (slower) smoothing factor for acceleration
                DEFAULT_ZOOM_LEVEL = 1, -- Default zoom level index
                ZOOM_LEVELS = {1, 2, 4}, -- Available zoom levels (multipliers)
                ZOOM_TRANSITION_FACTOR = 0.04, -- How fast zoom transitions occur
                MOUSE_MOVE_SENSITIVITY = 0.01, -- Mouse sensitivity for free camera mode
                MODE_TRANSITION_TIME = 0.5, -- Duration of mode transition in seconds
                BUFFER_ZONE = 0.10, -- Area in the middle of the screen when mouse does not cause camera rotation

                -- Target movement settings
                TARGET_MOVEMENT = {
                    MIN_DISTANCE = 150, -- Minimum distance to target (stop moving when reached)
                    FORWARD_VELOCITY = 5, -- Constant forward movement speed
                    MAX_ANGULAR_VELOCITY = 0.008, -- Maximum steering angular velocity
                    ANGULAR_DAMPING = 0.70, -- How fast steering angular velocity decreases
                    DEADZONE = 0, -- Deadzone for mouse steering (0-1)
                    TRANSITION_FACTOR = 0.05, -- Smoothing factor for movement transitions
                    INVERT_SIDE_MOVEMENT = false, -- When true, camera will move opposite side of the mouse
                }
            },

            GROUP_TRACKING = {
                DEFAULT_DISTANCE = 600, -- Default camera distance from center of mass (will be adjusted based on group spread)
                MIN_DISTANCE = 400, -- Minimum distance (camera won't get closer than this)
                MAX_DISTANCE = 900, -- Maximum distance (camera won't get further than this)
                FOV_FACTOR = 1.4, -- Field of view consideration factor for determining if all units are visible
                DEFAULT_HEIGHT_FACTOR = 1.5, -- Default height above the center of mass. Camera height will be DEFAULT_DISTANCE * HEIGHT_FACTOR
                BACKWARD_FACTOR = 2, -- Backward positioning factor. 1.0 = normal distance, higher = more backward
                OUTLIER_CUTOFF_FACTOR = 1.3, -- Distance cutoff factor relative to group radius (units farther than this will be ignored)
                DISTANCE_PADDING = 50, -- Distance padding (additional distance beyond minimum required)
                DISTANCE_SMOOTHING = 0.02, -- Smoothing factors
                POSITION_SMOOTHING = 0.03,
                ROTATION_SMOOTHING = 0.008,
                OUTLIER_TRANSITION_SPEED = 0, -- Transition speed when adding/removing outliers

                CENTER_CHANGE_THRESHOLD_SQ = 100, -- Threshold for determining if center of mass has changed (squared units)
                CLUSTER_CHECK_INTERVAL = 1.0, -- Time between clustering checks (seconds) - less frequent checks
                MIN_CLUSTER_SIZE = 2, -- Minimum number of units before we do clustering - smaller groups
                EPSILON_FACTOR = 3.0, -- Scale factor for adaptive DBSCAN epsilon - MUCH larger, more inclusive clusters
                MIN_EPSILON = 400, -- Minimum epsilon value (distance threshold) - higher minimum distance
                MAX_EPSILON = 1100, -- Maximum epsilon value (distance threshold) - higher maximum distance
                MIN_POINTS_FACTOR = 0.05, -- Minimum points as a fraction of total unit count - fewer units required
                MAX_MIN_POINTS = 2, -- Maximum value for minPoints parameter - fewer points needed for core

                -- Core smoothing parameters - dramatically increased
                POSITION_SMOOTHING = 0.01,           -- Ultra-low for super smooth camera movement
                ROTATION_SMOOTHING = 0.005,          -- Ultra-low for super smooth rotation
                VELOCITY_SMOOTHING_FACTOR = 0.008,    -- Lower for more smoothing
                DISTANCE_SMOOTHING = 0.007,           -- Smoother distance changes

                -- Stability settings
                STATIONARY_BIAS_FACTOR = 0.95,       -- Very high bias for stability
                MIN_VELOCITY_THRESHOLD = 5.0,        -- Much higher threshold to reduce vibration
                VELOCITY_SIGNIFICANCE_THRESHOLD = 10.0, -- Only major movements trigger direction changes
                DIRECTION_CHANGE_THRESHOLD = 0.3,    -- Much lower threshold (big angle change needed)
                MIN_DIRECTION_CHANGE_INTERVAL = 2.0, -- Minimum seconds between direction changes

                -- Anti-vibration measures
                JITTER_PROTECTION_RADIUS = 10.0,      -- Ignore small position changes within this radius
                USE_POSITION_AVERAGING = true,       -- Use position averaging
                POSITION_AVERAGING_SAMPLES = 10,     -- Number of samples for position averaging
                POSITION_SAMPLE_INTERVAL = 0.1,      -- Seconds between position samples

                -- Camera tracking behavior
                TRACKING_UPDATE_INTERVAL = 0.0001, -- Ensures smooth tracking (update every frame)
                DEBUG_TRACKING = false, -- Enable tracking debug info

                -- Special aircraft handling
                AIRCRAFT_DETECTION_ENABLED = true,  -- Enable aircraft detection
                ALWAYS_INCLUDE_AIRCRAFT = true,     -- Always include aircraft in clusters
                AIRCRAFT_EPSILON_FACTOR = 10.0,     -- 10x looser clustering for aircraft
                AIRCRAFT_MIN_EPSILON = 800,         -- Much higher minimum for aircraft
                AIRCRAFT_MAX_EPSILON = 3200,        -- Much higher maximum for aircraft
                AIRCRAFT_EXTRA_DISTANCE = 700,      -- Extra camera distance for aircraft

                -- Contiguous unit detection
                USE_CONTIGUOUS_UNIT_DETECTION = true, -- Enable detection of touching units

                -- Aircraft unit types to detect - add all your air unit defNames
                AIRCRAFT_UNIT_TYPES = {
                    ["armfig"] = true,
                    ["corvamp"] = true,
                    ["armthund"] = true,
                    ["corshad"] = true,
                    ["armbrawl"] = true,
                    ["corsent"] = true,
                    ["armsehak"] = true,
                    ["armawac"] = true,
                    ["armatlas"] = true,
                    ["armdrop"] = true,
                    ["armca"] = true,
                    ["armcsa"] = true,
                    ["armaca"] = true,
                    ["coraca"] = true,
                    ["corca"] = true,
                    ["corcsa"] = true,
                    -- Add all your other air units here
                }
            }
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

-- Link CONFIG to the module
WidgetConfig.CONFIG = WG.TURBOBARCAM.CONFIG

-- Export the module (both CONFIG and STATE are shared via WG)
return WidgetConfig