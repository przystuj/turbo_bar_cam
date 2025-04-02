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
                }
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

-- Link CONFIG to the module
TurboModule.CONFIG = WG.TURBOBARCAM.CONFIG

-- Import STATE from separate file
local StateModule = VFS.Include("LuaUI/TURBOBARCAM/config/state.lua")
TurboModule.STATE = StateModule.STATE

-- Export the module (both CONFIG and STATE are shared via WG)
return TurboModule