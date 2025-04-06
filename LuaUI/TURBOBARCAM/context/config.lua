--------------------------------------------------------------------------------
-- CONFIGURATION MANAGEMENT
--------------------------------------------------------------------------------

-- Initialize the global widget table for TURBOBARCAM if it doesn't exist
WG.TURBOBARCAM = WG.TURBOBARCAM or {}

-- Create a module to export
---@class WidgetConfigModule
---@field CONFIG WidgetConfig
local WidgetConfig = {}

local MODES = {
    FPS = "fps",
    FIXED_POINT = "fps.fixed_point",
    UNIT_TRACKING = "unit_tracking",
    ORBIT = "orbit",
    OVERVIEW = "overview",
    GROUP_TRACKING = "group_tracking",
}

-- Only initialize CONFIG if it doesn't exist in WG already
if not WG.TURBOBARCAM.CONFIG then
    ---@class WidgetConfig
    WG.TURBOBARCAM.CONFIG = {

        -- Camera mode settings
        CAMERA_MODES = {
            ANCHOR = {
                -- modes which will trigger focus_while_tracking effect
                COMPATIBLE_MODES = { "fps", "unit_tracking", "orbit", "fixed_point" },
                -- Transition settings
                DURATION = 2.0, -- Default transition duration (seconds)
                STEPS_PER_SECOND = 60 -- Steps per second for smooth transitions
            },

            -- FPS camera settings
            FPS = {
                OFFSETS = {
                    HEIGHT = 60, -- Default height, will be updated based on unit height
                    FORWARD = -300,
                    SIDE = 0,
                    ROTATION = 0 -- Rotation offset (radians)
                },
                DEFAULT_OFFSETS = {
                    HEIGHT = 60,
                    FORWARD = -300,
                    SIDE = 0,
                    ROTATION = 0
                },
                MOUSE_SENSITIVITY = 0.004,
            },

            -- Orbit camera settings
            ORBIT = {
                HEIGHT_FACTOR = 8, -- Height is 8x unit height
                DISTANCE = 800, -- Distance from unit
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
                -- Height and Distance Settings
                HEIGHT_FACTOR = 0.33, -- Default height as a factor of map diagonal. Affects how high the camera sits above the map. Higher values = higher camera position.
                DEADZONE = 0, -- Deadzone for mouse steering (0-1 range). Higher values require more mouse movement to begin steering.

                -- Movement Behavior Settings
                MIN_DISTANCE = 150, -- Minimum distance to target. When reached, camera stops moving. Lower values allow closer inspection.
                FORWARD_VELOCITY = 5, -- Base forward movement speed in map units per frame. Higher values = faster camera movement toward target.
                MOUSE_MOVE_SENSITIVITY = 0.01, -- Mouse sensitivity for camera rotation. Higher values make camera rotate faster with mouse movement.
                BUFFER_ZONE = 0.10, -- Area in the middle of the screen (0-1 range) where mouse does not cause camera rotation. Larger values create a larger "dead zone".
                INVERT_SIDE_MOVEMENT = true, -- When true, camera moves opposite to the mouse side movement direction.

                -- Rotation Settings
                MAX_ROTATION_SPEED = 0.015, -- Maximum rotation speed (radians per frame). Higher values = faster max rotation.
                EDGE_ROTATION_MULTIPLIER = 1.0, -- Multiplier for rotation speed when cursor is at screen edge. Higher values speed up edge rotation.
                MAX_ANGULAR_VELOCITY = 0.008, -- Maximum steering angular velocity (radians per frame). Controls how fast the camera can turn while moving.
                ANGULAR_DAMPING = 0.70, -- Rate at which steering angular velocity decreases (0-1). Lower values create sharper stops.

                -- Zoom Settings
                DEFAULT_ZOOM_LEVEL = 1, -- Default zoom level index (1-based).
                ZOOM_LEVELS = { 1, 2, 4 }, -- Available zoom levels (multipliers). More levels = more granular zoom options.

                -- Smoothing and Transition Settings
                MOVEMENT_SMOOTHING = 0.05, -- Default smoothing factor for camera movement (0-1). Lower values = smoother but slower movement.
                INITIAL_SMOOTHING = 0.01, -- Initial smoothing factor for movement acceleration. Lower values give slower initial movement.
                ZOOM_TRANSITION_FACTOR = 0.04, -- How fast zoom transitions occur (0-1). Higher values = quicker zoom changes.
                TRANSITION_FACTOR = 0.05, -- Smoothing factor for movement transitions (0-1). Higher values = quicker transitions.
                MODE_TRANSITION_TIME = 0.5, -- Duration of mode transition in seconds. Lower values = faster mode switching.
            },

            UNIT_TRACKING = {
                HEIGHT = 0, -- Height offset for look-at point in world units
            },

            -- Group tracking camera settings
            GROUP_TRACKING = {
                -- Distance settings
                DEFAULT_DISTANCE = 600, -- Default camera distance from center of mass
                MIN_DISTANCE = 400, -- Minimum camera distance
                MAX_DISTANCE = 900, -- Maximum camera distance

                -- Height settings
                DEFAULT_HEIGHT_FACTOR = 1.3, -- Default height as a factor of distance

                -- Camera adjustments
                EXTRA_DISTANCE = 0, -- Additional distance from group (adds to calculated distance)
                EXTRA_HEIGHT = 0, -- Additional height (adds to calculated height)
                ORBIT_OFFSET = 0, -- Orbit angle offset in radians (0 = behind, π/2 = right side, π = front, 3π/2 = left side)

                -- Default adjustments (for reset)
                DEFAULT_ADJUSTMENTS = {
                    EXTRA_DISTANCE = 0,
                    EXTRA_HEIGHT = 0,
                    ORBIT_OFFSET = 0,
                },

                -- Smoothing settings
                SMOOTHING = {
                    POSITION = 0.03, -- Position smoothing factor (lower = smoother but more lag)
                    ROTATION = 0.01, -- Rotation smoothing factor
                    STABLE_POSITION = 0.01, -- Stable mode position smoothing
                    STABLE_ROTATION = 0.005, -- Stable mode rotation smoothing
                },

                -- Default smoothing values (for reset)
                DEFAULT_SMOOTHING = {
                    POSITION = 0.03,
                    ROTATION = 0.01,
                    STABLE_POSITION = 0.01,
                    STABLE_ROTATION = 0.005,
                },

                -- Aircraft handling
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
            },
        },

        -- Smoothing factors
        SMOOTHING = {
            POSITION_FACTOR = 0.01, -- Lower = smoother but more lag (0.0-1.0)
            ROTATION_FACTOR = 0.01, -- Lower = smoother but more lag (0.0-1.0)
            TRACKING_FACTOR = 0.1, -- Specific for Tracking Camera mode
            MODE_TRANSITION_FACTOR = 0.04, -- For smoothing between camera modes
            FREE_CAMERA_FACTOR = 0.05  -- Smoothing factor for free camera mouse movement
        },

        -- Command IDs
        COMMANDS = {
            SET_FIXED_LOOK_POINT = 455626,
        },

        -- Spectator settings
        SPEC_GROUPS = {
            ENABLED = true, -- Enable spectator unit groups
            MAX_GROUPS = 9  -- Maximum number of groups (1-9)
        }
    }
end

-- Link CONFIG to the module
---@type WidgetConfig
WidgetConfig.CONFIG = WG.TURBOBARCAM.CONFIG

--- Parameters which can be modified by actions. paramName = {minValue, maxValue, [rad if value is in radians]}
---@class ModifiableParams
---@see UtilsModule#adjustParams
WidgetConfig.CONFIG.MODIFIABLE_PARAMS = {
    FPS = {
        PARAMS_ROOT = WidgetConfig.CONFIG.CAMERA_MODES.FPS.OFFSETS,
        PARAM_NAMES = {
            HEIGHT = { 0, nil },
            FORWARD = { nil, nil },
            SIDE = { nil, nil },
            ROTATION = { nil, nil, "rad" },
            MOUSE_SENSITIVITY = { 0.0001, 0.01 }
        }
    },
    ORBIT = {
        PARAMS_ROOT = WidgetConfig.CONFIG.CAMERA_MODES.ORBIT,
        PARAM_NAMES = {
            HEIGHT = { 100, nil },
            DISTANCE = { 100, nil },
            SPEED = { -0.005, 0.005 },
        }
    },
    ANCHOR = {
        PARAMS_ROOT = WidgetConfig.CONFIG.CAMERA_MODES.ANCHOR,
        PARAM_NAMES = {
            DURATION = { 0, nil },
        }
    },
    TURBO_OVERVIEW = {
        PARAMS_ROOT = WidgetConfig.CONFIG.CAMERA_MODES.TURBO_OVERVIEW,
        PARAM_NAMES = {
            DEFAULT_SMOOTHING = { 0.001, 0.5 },
            FORWARD_VELOCITY = { 1, 20 },
            MAX_ROTATION_SPEED = { 0.001, 0.05 },
            BUFFER_ZONE = { 0, 0.5 },
        }
    },
    UNIT_TRACKING = {
        PARAMS_ROOT = WidgetConfig.CONFIG.CAMERA_MODES.UNIT_TRACKING,
        PARAM_NAMES = {
            HEIGHT = { -2000, 2000 },
        }
    },
    GROUP_TRACKING = {
        PARAMS_ROOT = WidgetConfig.CONFIG.CAMERA_MODES.GROUP_TRACKING,
        PARAM_NAMES = {
            -- Camera adjustments
            EXTRA_DISTANCE = { -1000, 3000 }, -- Extra distance beyond calculated value
            EXTRA_HEIGHT = { -1000, 3000 }, -- Extra height beyond calculated value
            ORBIT_OFFSET = { -3.14, 3.14, "rad" }, -- Orbit offset angle in radians

            -- Smoothing factors
            ["SMOOTHING.POSITION"] = { 0.001, 0.2 }, -- Min/max for position smoothing
            ["SMOOTHING.ROTATION"] = { 0.001, 0.2 }, -- Min/max for rotation smoothing
            ["SMOOTHING.STABLE_POSITION"] = { 0.001, 0.2 }, -- Min/max for stable position smoothing
            ["SMOOTHING.STABLE_ROTATION"] = { 0.001, 0.2 }, -- Min/max for stable rotation smoothing
        }
    }
}

-- Export the module (both CONFIG and STATE are shared via WG)
return WidgetConfig