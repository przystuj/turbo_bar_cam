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
    ---@field TURBO_OVERVIEW {DEFAULT_HEIGHT_FACTOR: number, DEFAULT_SMOOTHING: number, DEFAULT_ZOOM_LEVEL: number, ZOOM_LEVELS: number[]} Turbo overview settings
    ---@field COMMANDS {SET_FIXED_LOOK_POINT: number} Commands settings
    ---@field TRANSITION {DURATION: number, MIN_DURATION: number, STEPS_PER_SECOND: number} Transition settings
    ---@field FPS {DEFAULT_HEIGHT_OFFSET: number, DEFAULT_FORWARD_OFFSET: number, DEFAULT_SIDE_OFFSET: number, DEFAULT_ROTATION_OFFSET: number, ROTATION_OFFSET: number, HEIGHT_OFFSET: number, FORWARD_OFFSET: number, SIDE_OFFSET: number} FPS camera settings
    ---@field SMOOTHING {POSITION_FACTOR: number, ROTATION_FACTOR: number, FPS_FACTOR: number, TRACKING_FACTOR: number, MODE_TRANSITION_FACTOR: number, FREE_CAMERA_FACTOR: number} Smoothing settings
    ---@field ORBIT {DEFAULT_HEIGHT_FACTOR: number, DEFAULT_DISTANCE: number, DEFAULT_SPEED: number, HEIGHT: number|nil, DISTANCE: number, SPEED: number, AUTO_ORBIT_DELAY: number, AUTO_ORBIT_ENABLED: boolean, AUTO_ORBIT_SMOOTHING_FACTOR: number} Orbit camera settings
    ---@field SPEC_GROUPS {ENABLED: boolean, MAX_GROUPS: number} Spectator groups settings
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
    ---@field DEBUG boolean Whether debug mode is enabled
    ---@field anchors table<number, table> Camera anchor states
    ---@field lastUsedAnchor number|nil Last used camera anchor index
    ---@field transition {active: boolean, startTime: any, steps: table[], currentStepIndex: number, currentAnchorIndex: number|nil} Camera transition state
    ---@field tracking {mode: string|nil, unitID: number|nil, targetUnitID: number|nil, inFreeCameraMode: boolean, inTargetSelectionMode: boolean, prevFreeCamState: boolean, prevMode: string|nil, prevFixedPoint: table|nil, graceTimer: any, lastUnitID: number|nil, unitOffsets: table, fixedPoint: table|nil, lastUnitPos: {x: number, y: number, z: number}, lastCamPos: {x: number, y: number, z: number}, lastCamDir: {x: number, y: number, z: number}, lastRotation: {rx: number, ry: number, rz: number}, prevMode: string|nil, modeTransition: boolean, transitionStartState: table|nil, transitionStartTime: any, freeCam: {lastMouseX: number|nil, lastMouseY: number|nil, targetRx: number|nil, targetRy: number|nil, mouseMoveSensitivity: number, lastUnitHeading: number|nil}} Unit tracking state
    ---@field delayed {frame: number|nil, callback: function|nil} Delayed action state
    ---@field orbit {angle: number, lastPosition: table|nil, stationaryTimer: any, autoOrbitActive: boolean, unitOffsets: table, originalTransitionFactor: number|nil} Orbit camera state
    ---@field specGroups {groups: table, isSpectator: boolean} Spectator groups state
    ---@field turboOverview {height: number|nil, zoomLevel: number, zoomLevels: number[], movementSmoothing: number, lastCursorWorldPos: {x: number, y: number, z: number}, fixedCamPos: {x: number, y: number, z: number}, targetPos: {x: number, y: number, z: number}, movingToTarget: boolean, targetRx: number, targetRy: number, lastMouseX: number|nil, lastMouseY: number|nil, mouseMoveSensitivity: number} Turbo overview camera state
    WG.TURBOBARCAM.STATE = {
        -- Widget state
        enabled = false,
        originalCameraState = nil,
        DEBUG = true,

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
            movementSmoothing = 0.05, -- Smoothing factor for movement to target
            initialMovementSmoothing = 0.01, -- Initial (slower) smoothing factor for movement
            zoomTransitionFactor = 0.04, -- How fast zoom transitions occur
            targetHeight = nil, -- Target height for smooth zoom transitions
            inZoomTransition = false, -- Whether currently in a zoom transition
            lastCursorWorldPos = {x = 0, y = 0, z = 0}, -- Last cursor world position
            fixedCamPos = {x = 0, y = 0, z = 0}, -- Fixed camera position
            targetPos = {x = 0, y = 0, z = 0}, -- Target position to move to
            movingToTarget = false, -- Whether currently moving to target
            moveStartTime = nil, -- When movement to target started (for acceleration)
            targetRx = 0, -- Target pitch rotation
            targetRy = 0, -- Target yaw rotation
            lastMouseX = nil, -- Last mouse X position for rotation calculation
            lastMouseY = nil, -- Last mouse Y position for rotation calculation
            mouseMoveSensitivity = 0.003, -- How sensitive rotation is to mouse movement
        },
    }
end

-- Link both CONFIG and STATE to the module
TurboModule.CONFIG = WG.TURBOBARCAM.CONFIG
TurboModule.STATE = WG.TURBOBARCAM.STATE

-- Export the module (both CONFIG and STATE are shared via WG)
return TurboModule