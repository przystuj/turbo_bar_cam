if not WG.TurboBarCam.CONFIG then
    ---@class WidgetConfig
    WG.TurboBarCam.CONFIG = {
        -- Should offset values be saved after changing/disabling mode
        MODE_TRANSITION_SMOOTHING = 0.04, -- For smoothing between camera modes
        ALLOW_TRACKING_WITHOUT_SELECTION = true,

        -- Debug and performance settings
        DEBUG = {
            LOG_LEVEL = "DEBUG", -- INFO, DEBUG, TRACE
            TRACE_BACK = true, -- print stacktraces of errors
        },

        DRIVER = {
            TRANSITION_TIME = 0.2,
            ANGULAR_VELOCITY_TARGET = 0.0001,
            VELOCITY_TARGET = 1,
            DISTANCE_TARGET = 0.001,
        },

        -- Performance settings
        PERFORMANCE = {
            ANCHOR_STEPS_PER_SECOND = 240, -- Steps per second for smooth transitions
        },

        TRANSITION = {
            MODE_TRANSITION_DURATION = 1.0, -- Duration of transition between modes in seconds
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
                -- Transition settings
                DURATION = 5.0, -- Default transition duration (seconds)
                SINGLE_DURATION_MODE = true, -- If true all anchors have the same duration
            },

            UNIT_FOLLOW = {
                ATTACH_TO_WEAPON = false, -- If true, combat mode camera attaches to the active weapon instead of the hull
                MOUSE_SENSITIVITY = 0.004,
                INITIAL_TRANSITION_DURATION = 1.2, -- Duration of the entry transition into unit_follow mode
                TARGET_SWITCH_DURATION = 5, -- Transition between targets
                IGNORE_AIR_TARGETS = true,
                TARGET_ACQUISITION_DELAY = 0.2,
                STABILIZATION = {
                    BASE_FACTOR = 0.03,
                    MAX_FACTOR = 0.01,
                },
                OFFSETS = {
                    -- DEFAULT mode offsets
                    DEFAULT = {
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
                    },

                    ATTACK_STATE_COOLDOWN = 4,
                },
                DEFAULT_OFFSETS = {
                    DEFAULT = {
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
                    },

                    ATTACK_STATE_COOLDOWN = 4,
                },
                SMOOTHING = {
                    -- DEFAULT mode smoothing
                    DEFAULT = {
                        POSITION_FACTOR = 3,
                        ROTATION_FACTOR = 1.5,
                    },

                    -- COMBAT mode smoothing (when combat mode is enabled but not actively firing)
                    COMBAT = {
                        POSITION_FACTOR = 1,
                        ROTATION_FACTOR = 1,
                    },

                    -- WEAPON mode smoothing (when actively firing at a target)
                    WEAPON = {
                        POSITION_FACTOR = 1,
                        ROTATION_FACTOR = 1,
                    }
                },
            },

            -- Orbit camera settings
            ORBIT = {
                INITIAL_TRANSITION_DURATION = 2,
                HEIGHT_FACTOR = 8, -- Height is 8x unit height
                OFFSETS = {
                    DISTANCE = 800, -- Distance from unit
                    SPEED = 0.05, -- Orbit speed in radians per frame
                    HEIGHT = nil, -- It's calculated from unit height
                },
                DEFAULT_OFFSETS = {
                    SPEED = 0.05,
                    DISTANCE = 800,
                    HEIGHT = nil, -- It's calculated from unit height
                },
                SMOOTHING_FACTOR = 3,
            },

            UNIT_TRACKING = {
                INITIAL_TRANSITION_DURATION = 2,
                INITIAL_TRANSITION_FACTOR = 0.01,
                HEIGHT = 0, -- Height offset for look-at point in world units
                SMOOTHING = {
                    ROTATION_FACTOR = 0.05, -- Lower = smoother but more lag (0.0-1.0)
                    POSITION_FACTOR = 0.1, -- Specific for Tracking Camera mode (likely for direction, not position)
                },
                DEFAULT_SMOOTHING = {
                    ROTATION_FACTOR = 0.05,
                    TRACKING_FACTOR = 0.1,
                },
                DECELERATION_PROFILE = { -- When transitioning into unit tracking mode
                    DURATION = 2,
                    INITIAL_BRAKING = 1.0,
                    PATH_ADHERENCE = 1,
                },
            },

            PROJECTILE_CAMERA = {
                DEFAULT_CAMERA_MODE = "follow",
                COMPATIBLE_MODES_FROM = { "unit_follow", "unit_tracking", "orbit" },
                TRACKABLE_UNIT_DEFS = { "armsilo", "corsilo", },

                POSITION_SMOOTHING = 2,
                ROTATION_SMOOTHING = 1,
                IMPACT_VIEW_DURATION = 1.5,

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
                    POSITION = 1.5, -- Position smoothing factor (lower = smoother but more lag)
                    ROTATION = 1.5, -- Rotation smoothing factor
                    STABLE_POSITION = 3, -- Stable mode position smoothing
                    STABLE_ROTATION = 3, -- Stable mode rotation smoothing
                },

                -- Default smoothing values (for reset)
                DEFAULT_SMOOTHING = {
                    POSITION = 1.5,
                    ROTATION = 1.5,
                    STABLE_POSITION = 3,
                    STABLE_ROTATION = 3,
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
    }
end

---@type WidgetConfig
local CONFIG = WG.TurboBarCam.CONFIG

--- Parameters which can be modified by actions. paramName = {minValue, maxValue, [rad if value is in radians]}
---@class ModifiableParams
---@see Utils#adjustParams
CONFIG.MODIFIABLE_PARAMS = {
    UNIT_FOLLOW = {
        PARAMS_ROOT = CONFIG.CAMERA_MODES.UNIT_FOLLOW.OFFSETS,
        PARAM_NAMES = {
            -- Peace mode offsets
            ["DEFAULT.HEIGHT"] = { nil, nil },
            ["DEFAULT.FORWARD"] = { nil, nil },
            ["DEFAULT.SIDE"] = { nil, nil },
            ["DEFAULT.ROTATION"] = { nil, nil, "rad" },

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

            ATTACK_STATE_COOLDOWN = 0,

            -- Other params
            MOUSE_SENSITIVITY = { 0.0001, 0.01 },
        }
    },
    ORBIT = {
        PARAMS_ROOT = CONFIG.CAMERA_MODES.ORBIT.OFFSETS,
        PARAM_NAMES = {
            HEIGHT = { nil, nil },
            DISTANCE = { nil, nil },
            SPEED = { -0.5, 0.5 },
        }
    },
    UNIT_TRACKING = {
        PARAMS_ROOT = CONFIG.CAMERA_MODES.UNIT_TRACKING,
        PARAM_NAMES = {
            HEIGHT = { nil, nil },
        }
    },
    ANCHOR = {
        PARAMS_ROOT = CONFIG.CAMERA_MODES.ANCHOR,
        PARAM_NAMES = {
            DURATION = { 0, nil },
        }
    },
    GROUP_TRACKING = {
        PARAMS_ROOT = CONFIG.CAMERA_MODES.GROUP_TRACKING,
        PARAM_NAMES = {
            -- Camera adjustments
            EXTRA_DISTANCE = { nil, nil }, -- Extra distance beyond calculated value
            EXTRA_HEIGHT = { nil, nil }, -- Extra height beyond calculated value
            ORBIT_OFFSET = { -3.14, 3.14, "rad" }, -- Orbit offset angle in radians

            -- Smoothing factors
            ["SMOOTHING.POSITION"] = { 1, nil }, -- Min/max for position smoothing
            ["SMOOTHING.ROTATION"] = { 1, nil }, -- Min/max for rotation smoothing
            ["SMOOTHING.STABLE_POSITION"] = { 1, nil }, -- Min/max for stable position smoothing
            ["SMOOTHING.STABLE_ROTATION"] = { 1, nil }, -- Min/max for stable rotation smoothing
        }
    },
    PROJECTILE_CAMERA = {
        PARAMS_ROOT = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA,
        PARAM_NAMES = {
            ["STATIC.OFFSET_SIDE"] = { nil, nil },
            ["STATIC.OFFSET_HEIGHT"] = { nil, nil },
            ["STATIC.LOOK_AHEAD"] = { nil, nil },
            ["FOLLOW.DISTANCE"] = { nil, nil },
            ["FOLLOW.HEIGHT"] = { nil, nil },
            ["FOLLOW.LOOK_AHEAD"] = { nil, nil },
        }
    },
}

return WG.TurboBarCam.CONFIG
