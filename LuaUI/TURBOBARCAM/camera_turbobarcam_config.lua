--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

---@class CONFIG
---@field TRANSITION table Transition settings
---@field FPS table FPS camera settings
---@field SMOOTHING table Smoothing settings
---@field ORBIT table Orbit camera settings
---@field SPEC_GROUPS table Spectator groups settings
local CONFIG = {
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

--------------------------------------------------------------------------------
-- STATE MANAGEMENT
--------------------------------------------------------------------------------

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
local STATE = {
    -- Widget state
    enabled = false,
    originalCameraState = nil,

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
}

-- Export to global scope
return {
    CONFIG = CONFIG,
    STATE = STATE
}
