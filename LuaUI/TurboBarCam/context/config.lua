if not WG.TurboBarCam.CONFIG then
    ---@class WidgetConfig
    WG.TurboBarCam.CONFIG = {
        -- Should offset values be saved after changing/disabling mode
        PERSISTENT_UNIT_SETTINGS = "MODE", -- NONE, UNIT, MODE
        MODE_TRANSITION_SMOOTHING = 0.04, -- For smoothing between camera modes
        ALLOW_TRACKING_WITHOUT_SELECTION = true,

        -- Debug and performance settings
        DEBUG = {
            LOG_LEVEL = "DEBUG", -- INFO, DEBUG, TRACE
            TRACE_BACK = true, -- print stacktraces of errors
        },

        -- Performance settings
        PERFORMANCE = {
            ANCHOR_STEPS_PER_SECOND = 240, -- Steps per second for smooth transitions
        },

        TRANSITION = {
            MODE_TRANSITION_DURATION = 2.0, -- Duration of transition between modes in seconds
            DECELERATION = {
                -- The minimum rate at which velocity decays towards the end of the transition.
                -- A higher value means the camera stops more sharply, a lower value means a gentler stop.
                DECAY_RATE_MIN = 0.5,
                -- The minimum LERP factor for smoothing towards the end of the transition.
                -- It controls how strongly the camera follows the predicted decelerating path vs. its current path.
                -- A lower value results in smoother but potentially less direct deceleration.
                POS_CONTROL_FACTOR_MIN = 0.05,
                ROT_CONTROL_FACTOR_MIN = 0.01,
                -- The positional velocity magnitude below which the camera is considered 'stopped'.
                -- Used to determine when to end the deceleration phase.
                MIN_VELOCITY_THRESHOLD = 1.0,
                -- The rotational velocity magnitude below which the camera is considered 'stopped' rotating.
                -- Used to determine when to end the deceleration phase.
                MIN_ROT_VEL_THRESHOLD = 0.01,
                MAX_POSITION_VELOCITY = 500,
                MAX_ROTATION_VELOCITY = 1,
            }
        },

        -- Camera mode settings
        CAMERA_MODES = {
            ANCHOR = {
                -- modes which will trigger focus_while_tracking effect
                COMPATIBLE_MODES = { "fps", "unit_tracking", "orbit", "projectile_camera" },
                -- Transition settings
                DURATION = 2.0, -- Default transition duration (seconds)
            },

            -- FPS camera settings
            FPS = {
                MOUSE_SENSITIVITY = 0.004,
                OFFSETS = {
                    -- PEACE mode offsets (normal FPS view)
                    PEACE = {
                        HEIGHT = nil, -- It's calculated from unit height
                        FORWARD = -300,
                        SIDE = 0,
                        ROTATION = 0 -- Rotation offset (radians)
                    },

                    -- COMBAT mode offsets (when combat mode is enabled but not actively firing)
                    COMBAT = {
                        HEIGHT = 35,
                        FORWARD = -75,
                        SIDE = 0,
                        ROTATION = 0 -- Rotation offset (radians)
                    },

                    -- WEAPON mode offsets (when actively firing at a target)
                    WEAPON = {
                        HEIGHT = 35,
                        FORWARD = -75,
                        SIDE = 0,
                        ROTATION = 0 -- Rotation offset (radians)
                    }
                },
                DEFAULT_OFFSETS = {
                    PEACE = {
                        HEIGHT = nil, -- It's calculated from unit height
                        FORWARD = -300,
                        SIDE = 0,
                        ROTATION = 0
                    },

                    COMBAT = {
                        HEIGHT = 35,
                        FORWARD = -75,
                        SIDE = 0,
                        ROTATION = 0
                    },

                    WEAPON = {
                        HEIGHT = 0,
                        FORWARD = 0,
                        SIDE = 0,
                        ROTATION = 0
                    }
                },
                SMOOTHING = {
                    -- PEACE mode smoothing (normal FPS view)
                    PEACE = {
                        POSITION_FACTOR = 0.02, -- Lower = smoother but more lag (0.0-1.0)
                        ROTATION_FACTOR = 0.02, -- Lower = smoother but more lag (0.0-1.0)
                    },

                    -- COMBAT mode smoothing (when combat mode is enabled but not actively firing)
                    COMBAT = {
                        POSITION_FACTOR = 0.03,
                        ROTATION_FACTOR = 0.03,
                    },

                    -- WEAPON mode smoothing (when actively firing at a target)
                    WEAPON = {
                        POSITION_FACTOR = 0.02,
                        ROTATION_FACTOR = 0.009,
                    }
                },
            },

            -- Orbit camera settings
            ORBIT = {
                HEIGHT_FACTOR = 8, -- Height is 8x unit height
                DISTANCE = 800, -- Distance from unit
                SPEED = 0.05, -- Orbit speed in radians per frame
                HEIGHT = nil, -- It's calculated from unit height
                DEFAULT_SPEED = 0.05,
                DEFAULT_DISTANCE = 800,
                DEFAULT_HEIGHT = nil, -- It's calculated from unit height
                SMOOTHING = {
                    POSITION_FACTOR = 0.06, -- Lower = smoother but more lag (0.0-1.0)
                    ROTATION_FACTOR = 0.06, -- Lower = smoother but more lag (0.0-1.0)
                },
                DEFAULT_SMOOTHING = {
                    POSITION_FACTOR = 0.06, -- Lower = smoother but more lag (0.0-1.0)
                    ROTATION_FACTOR = 0.06, -- Lower = smoother but more lag (0.0-1.0)
                },
            },

            -- Overview camera settings
            OVERVIEW = {
                -- Height and Distance Settings
                HEIGHT_FACTOR = 0.2, -- Default height as a factor of map diagonal

                -- Movement Behavior Settings
                MIN_DISTANCE = 150, -- Minimum distance to target
                MOUSE_MOVE_SENSITIVITY = 0.15, -- Mouse sensitivity for camera rotation

                HEIGHT_CONTROL_GRANULARITY = 6, -- Number of height steps
                DEFAULT_HEIGHT_LEVEL = 2, -- Default level (1 = highest, granularity = lowest)
                DISTANCE_LEVELS = { 1.0, 0.5, 2.0 }, -- Base (1.0), Close (0.5), Far (2.0)
                DEFAULT_DISTANCE_LEVEL = 1,

                -- Smoothing and Transition Settings
                ZOOM_TRANSITION_FACTOR = 0.04, -- How fast height transitions occur

                -- Adjusted for smoother movement - reduced from original value
                TRANSITION_FACTOR = 0.03, -- Base smoothing factor for movement transitions

                SMOOTHING = {
                    FREE_CAMERA_FACTOR = 0.05, -- Smoothing factor for rotation when using middle mouse
                    MOVEMENT = 0.05, -- Default smoothing factor for camera movement
                },
                DEFAULT_SMOOTHING = {
                    FREE_CAMERA_FACTOR = 0.05,
                    MOVEMENT = 0.05,
                },
            },

            UNIT_TRACKING = {
                HEIGHT = 0, -- Height offset for look-at point in world units
                SMOOTHING = {
                    ROTATION_FACTOR = 0.05, -- Lower = smoother but more lag (0.0-1.0)
                    TRACKING_FACTOR = 0.1, -- Specific for Tracking Camera mode (likely for direction, not position)
                },
                DEFAULT_SMOOTHING = {
                    ROTATION_FACTOR = 0.05,
                    TRACKING_FACTOR = 0.1,
                },
                DECELERATION_PROFILE = { -- When transitioning into unit tracking mode
                    DURATION = 2.5,
                    INITIAL_BRAKING = 1.0,
                    PATH_ADHERENCE = 1,
                },
            },

            PROJECTILE_CAMERA = {
                DEFAULT_CAMERA_MODE = "follow",
                COMPATIBLE_MODES_FROM = { "fps", "unit_tracking", "orbit" },
                DEFAULT_MODE_FALLBACK = "unit_tracking",
                IMPACT_TIMEOUT = 1.5, -- Time to stay on impact after deceleration
                DIRECTION_TRANSITION_DURATION = 3,
                DIRECTION_TRANSITION_THRESHOLD = 1.5,
                DIRECTION_TRANSITION_FACTOR = 0.01,

                FOLLOW = {
                    DISTANCE = 800,
                    HEIGHT = 100,
                    LOOK_AHEAD = 680,
                },

                DEFAULT_FOLLOW = {
                    DISTANCE = 300,
                    HEIGHT = 100,
                    LOOK_AHEAD = 200,
                },

                FOLLOW_HIGH = {
                    DISTANCE = 100,
                    HEIGHT = 400,
                    LOOK_AHEAD = -200,
                },

                DEFAULT_FOLLOW_HIGH = {
                    DISTANCE = 100,
                    HEIGHT = 400,
                    LOOK_AHEAD = -200,
                },

                STATIC = {
                    OFFSET_SIDE = 0,
                    OFFSET_HEIGHT = 0,
                    LOOK_AHEAD = 0,
                },

                DEFAULT_STATIC = {
                    OFFSET_SIDE = 0,
                    OFFSET_HEIGHT = 0,
                    LOOK_AHEAD = 0,
                },

                SMOOTHING = { -- General smoothing for projectile tracking (when not in impact deceleration)
                    POSITION_FACTOR = 0.2,
                    ROTATION_FACTOR = 0.2,
                    INTERPOLATION_FACTOR = 0.2,
                },

                DECELERATION_PROFILE = { -- When projectile hits and camera focuses on impact
                    DURATION = 1.5,
                    INITIAL_BRAKING = 8.0,
                    PATH_ADHERENCE = 0.6,
                    MIN_INITIAL_ROT_MAG = 0,
                },

                DEFAULT_DECELERATION_PROFILE = {
                    DURATION = 1.7,
                    INITIAL_BRAKING = 8.0,
                    PATH_ADHERENCE = 0.6,
                    MIN_INITIAL_ROT_VELOCITY = 0,
                },
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
                    EXTRA_DISTANCE = 1200,
                    EXTRA_HEIGHT = 815,
                    ORBIT_OFFSET = 0,
                },

                -- Smoothing settings
                SMOOTHING = {
                    POSITION = 0.05, -- Position smoothing factor (lower = smoother but more lag)
                    ROTATION = 0.005, -- Rotation smoothing factor
                    STABLE_POSITION = 0.005, -- Stable mode position smoothing
                    STABLE_ROTATION = 0.005, -- Stable mode rotation smoothing
                    TRACKING_FACTOR = 0.1, -- Specific for Tracking Camera mode
                },

                -- Default smoothing values (for reset)
                DEFAULT_SMOOTHING = {
                    POSITION = 0.03,
                    ROTATION = 0.03,
                    STABLE_POSITION = 0.03,
                    STABLE_ROTATION = 0.03,
                    TRACKING_FACTOR = 0.1,
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

--- Parameters which can be modified by actions. paramName = {minValue, maxValue, [rad if value is in radians]}
---@class ModifiableParams
---@see Util#adjustParams
WG.TurboBarCam.CONFIG.MODIFIABLE_PARAMS = {
    FPS = {
        PARAMS_ROOT = WG.TurboBarCam.CONFIG.CAMERA_MODES.FPS.OFFSETS,
        PARAM_NAMES = {
            -- Peace mode offsets
            ["PEACE.HEIGHT"] = { 0, nil },
            ["PEACE.FORWARD"] = { nil, nil },
            ["PEACE.SIDE"] = { nil, nil },
            ["PEACE.ROTATION"] = { nil, nil, "rad" },

            -- Combat mode offsets
            ["COMBAT.HEIGHT"] = { nil, nil },
            ["COMBAT.FORWARD"] = { nil, nil },
            ["COMBAT.SIDE"] = { nil, nil },
            ["COMBAT.ROTATION"] = { nil, nil, "rad" },

            -- Weapon mode offsets
            ["WEAPON.HEIGHT"] = { nil, nil },
            ["WEAPON.FORWARD"] = { nil, nil },
            ["WEAPON.SIDE"] = { nil, nil },
            ["WEAPON.ROTATION"] = { nil, nil, "rad" },

            -- Other params
            MOUSE_SENSITIVITY = { 0.0001, 0.01 },
        }
    },
    ORBIT = {
        PARAMS_ROOT = WG.TurboBarCam.CONFIG.CAMERA_MODES.ORBIT,
        PARAM_NAMES = {
            HEIGHT = { 100, nil },
            DISTANCE = { 100, nil },
            SPEED = { -0.5, 0.5 },
        }
    },
    ANCHOR = {
        PARAMS_ROOT = WG.TurboBarCam.CONFIG.CAMERA_MODES.ANCHOR,
        PARAM_NAMES = {
            DURATION = { 0, nil },
        }
    },
    UNIT_TRACKING = {
        PARAMS_ROOT = WG.TurboBarCam.CONFIG.CAMERA_MODES.UNIT_TRACKING,
        PARAM_NAMES = {
            HEIGHT = { -2000, 2000 },
        }
    },
    GROUP_TRACKING = {
        PARAMS_ROOT = WG.TurboBarCam.CONFIG.CAMERA_MODES.GROUP_TRACKING,
        PARAM_NAMES = {
            -- Camera adjustments
            EXTRA_DISTANCE = { nil, nil }, -- Extra distance beyond calculated value
            EXTRA_HEIGHT = { nil, nil }, -- Extra height beyond calculated value
            ORBIT_OFFSET = { -3.14, 3.14, "rad" }, -- Orbit offset angle in radians

            -- Smoothing factors
            ["SMOOTHING.POSITION"] = { 0.006, 0.2 }, -- Min/max for position smoothing
            ["SMOOTHING.ROTATION"] = { 0.001, 0.2 }, -- Min/max for rotation smoothing
            ["SMOOTHING.STABLE_POSITION"] = { 0.006, 0.2 }, -- Min/max for stable position smoothing
            ["SMOOTHING.STABLE_ROTATION"] = { 0.001, 0.2 }, -- Min/max for stable rotation smoothing
        }
    },
    PROJECTILE_CAMERA = {
        PARAMS_ROOT = WG.TurboBarCam.CONFIG.CAMERA_MODES.PROJECTILE_CAMERA,
        PARAM_NAMES = {
            ["STATIC.OFFSET_SIDE"] = { nil, nil },
            ["STATIC.OFFSET_HEIGHT"] = { nil, nil },
            ["STATIC.LOOK_AHEAD"] = { nil, nil },
            ["FOLLOW.DISTANCE"] = { nil, nil },
            ["FOLLOW.HEIGHT"] = { nil, nil },
            ["FOLLOW.LOOK_AHEAD"] = { nil, nil },
            ["DECELERATION_PROFILE.DURATION"] = { 0, 10 },
            ["DECELERATION_PROFILE.INITIAL_BRAKING"] = { 1, 2000 },
            ["DECELERATION_PROFILE.PATH_ADHERENCE"] = { 0.1, 1 },
            ["DIRECTION_TRANSITION_DURATION"] = { 0.1, 5.0 },
            ["DIRECTION_TRANSITION_ROTATION_FACTOR"] = { 0.001, 0.5 },
            ["DIRECTION_TRANSITION_THRESHOLD_RAD"] = { 0.0087, 0.349, "rad"}, -- Approx 0.5 to 20 degrees
        }
    },
}