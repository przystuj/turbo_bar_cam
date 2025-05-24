if not WG.TurboBarCam.STATE then
    ---@class WidgetState
    WG.TurboBarCam.STATE = {
        -- Target types
        TARGET_TYPES = {
            UNIT = "UNIT",
            POINT = "POINT",
            NONE = "NONE"
        },

        -- Core widget state
        enabled = false,
        originalCameraState = nil,
        -- toggle required for spectating with player cam. By default TurboBarCam prevents Plater Camera from changing selected units.
        allowPlayerCamUnitSelection = true,

        -- Camera anchors
        anchors = {},
        lastUsedAnchor = nil,

        scheduler = { schedules = {} },

        -- Camera transitions
        transition = {
            active = false,
            startTime = nil,
            steps = {},
            currentStepIndex = 1,
            currentAnchorIndex = nil
        },

        projectileWatching = {
            armed = false, -- True if waiting for a projectile to appear
            watchedUnitID = nil,
            continuouslyArmedUnitID = nil,
            lastArmingTime = 0,
            previousMode = nil, -- Stores the mode active before arming
            previousCameraState = nil, -- Stores camera state before arming
            impactTimer = nil,
            impactPosition = nil,
            cameraMode = "follow", -- This is the "sub-mode" ("follow" or "static") for projectile_camera
            initialCamPos = nil -- For static sub-mode, captured at arming time
        },

        -- Camera tracking
        tracking = {
            -- Current mode
            mode = nil, -- 'fps', 'unit_tracking', 'orbit', 'overview'
            targetType = nil, -- 'UNIT', 'POINT', or 'NONE'
            unitID = nil, -- Current tracked unit
            targetPoint = nil, -- {x, y, z} coordinates for point tracking
            lastTargetPoint = nil, -- Last known position of the target (for fallback)

            offsets = { fps = {}, orbit = {}, projectile_camera = {} }, -- Store mode settings

            -- Grace period
            graceTimer = nil, -- Timer for grace period
            lastUnitID = nil, -- Last tracked unit

            -- Position tracking for smooth movement
            lastCamPos = { x = 0, y = 0, z = 0 },
            lastCamDir = { x = 0, y = 0, z = 0 },
            lastRotation = { rx = 0, ry = 0, rz = 0 },

            -- Mode transition
            isModeTransitionInProgress = false, -- Is transitioning between modes
            transitionStartState = nil, -- Start camera state for transition
            transitionStartTime = nil, -- When transition started

            fps = {
                inTargetSelectionMode = false, -- Whether selecting a target
                prevFreeCamState = false, -- Free camera state before selection
                prevMode = nil, -- Previous mode during selection
                prevFixedPoint = nil, -- Previous fixed point during selection
                isFreeCameraActive = false, -- Whether free camera is active
                targetUnitID = nil, -- Unit being looked at (for fixed point)
                fixedPoint = nil, -- Fixed point to look at {x, y, z}
                isFixedPointActive = false, -- Whether fixed point tracking is active
                isAttacking = false, -- Whether unit's weapons are targeting something
                weaponPos = nil, -- Tracked weapon position - set only when isAttacking
                weaponDir = nil, -- Tracked weapon aim direction - set only when isAttacking
                activeWeaponNum = nil, -- Currently active weapon number
                forcedWeaponNumber = nil, -- Forced weapon number
                projectileTrackingEnabled = false, -- Whether camera should follow a projectile
                lastUnitProjectileID = nil,
                lastProjectilePosition = nil,
                combatModeEnabled = false,
                useLookAtTarget = false,
                lastTargetPos = nil, -- Last valid target position - for smooth transition when targets change
                lastTargetUnitID = nil, -- Last targeted unit ID
                lastTargetUnitName = nil, -- Last targeted unit name
                lastTargetType = nil, -- Last target type (1 = unit, 2 = ground)
                lastRotationRx = nil, -- Last camera rotation X (pitch)
                lastRotationRy = nil, -- Last camera rotation Y (yaw)
                initialTargetAcquisitionTime = nil, -- When the current target was first acquired
                targetRotationHistory = {}, -- History of rotation changes for the current target
                rotationChangeThreshold = 0.05, -- Threshold for logging rotation changes (in radians)
                -- Target Switch Transition State
                isTargetSwitchTransition = false,
                targetSwitchStartTime = nil,
                targetSwitchDuration = 0.4, -- Duration of the switch transition in seconds (adjust as needed)
                previousWeaponDir = { x = 0, y = 0, z = 0 }, -- Weapon/Unit direction *before* the switch
                previousCamPosRelative = { x = 0, y = 0, z = 0 }, -- Camera position relative to unit center *before* switch offsets were calculated
                -- (Optional: Add previousTargetDirection if needed for rotation smoothing logic)

                -- Free camera state
                freeCam = {
                    lastMouseX = nil,
                    lastMouseY = nil,
                    targetRx = nil, -- Target rotation X (pitch)
                    targetRy = nil, -- Target rotation Y (yaw)
                    lastUnitHeading = nil -- Last unit heading for rotation tracking
                },

                targetSmoothing = {
                    targetHistory = {}, -- Recent target positions with timestamps
                    cloudCenter = nil, -- Calculated center of the target cloud
                    cloudRadius = 0, -- Radius of the target cloud
                    useCloudTargeting = false, -- Whether to use cloud targeting
                    cloudStartTime = nil, -- When cloud targeting began
                    lastCloudUpdateTime = nil,
                    highActivityDetected = false,
                    activityLevel = 0, -- Measure of targeting activity (0-1)
                    lastTargetSwitchTime = nil,
                    targetSwitchCount = 0, -- Number of target switches in short period
                    lastStatusLogTime = nil,
                    currentTargetKey = nil, -- Current target identifier
                    targetAimOffset = { x = 0, y = 0, z = 0 }, -- Aim offset for leading targets
                    targetPrediction = {       -- Target movement prediction
                        enabled = false,
                        velocityX = 0,
                        velocityY = 0,
                        velocityZ = 0,
                        lastUpdateTime = nil
                    },
                    rotationConstraint = {     -- Constraint for rotation changes
                        enabled = true,
                        maxRotationRate = 0.07, -- Maximum rotation rate (radians per update)
                        lastYaw = nil, -- Last yaw angle
                        lastPitch = nil, -- Last pitch angle
                        damping = 0.8           -- Damping factor (higher = more constraint)
                    }
                },
            },

            projectile = {
                currentProjectileID = nil, -- Currently tracked projectile ID
                lastSwitchTime = nil, -- When we last switched projectiles
                isWatchingForProjectiles = false,
            },

            -- Group tracking
            group = {
                unitIDs = {}, -- Array of tracked unit IDs
                centerOfMass = { x = 0, y = 0, z = 0 }, -- Calculated center of mass position
                targetDistance = nil, -- Current camera target distance (will be adjusted based on group spread)
                radius = 0, -- Group radius (max distance from center to any unit)
                outliers = {}, -- Units considered outliers (too far from group)
                lastCenterOfMass = { x = 0, y = 0, z = 0 }, -- Previous frame's center of mass
            },

            -- Orbit camera state
            orbit = {
                angle = nil, -- Current orbit angle in radians
                lastPosition = nil, -- Last unit position to detect movement
                lastCamPos = nil, -- Last camera position to detect movement
                lastCamRot = nil, -- Last camera rotation to detect movement
                isPaused = false,
            },
        },

        -- Spectator groups
        specGroups = {
            groups = {}, -- Will store unit IDs for each group (1-9)
            isSpectator = false -- Tracks if we're currently spectating
        },

        overview = {
            height = nil, -- Current base height, calculated from map size

            -- Current state values
            heightLevel = nil, -- Current height level index
            fixedCamPos = nil, -- Fixed camera position (changes when moving to target)
            targetRx = nil, -- Target pitch rotation
            targetRy = nil, -- Target yaw rotation

            -- Movement to target state
            movingToTarget = false, -- Whether the movement button is pressed
            targetPoint = nil, -- Target point to move toward {x, y, z}
            distanceToTarget = nil, -- Current distance from target point
            movementAngle = nil, -- Current movement angle in radians (for steering)
            angularVelocity = nil, -- Current angular velocity (for steering)

            -- Transition states
            inMovementTransition = false, -- Whether in transition to movement mode
            targetHeight = nil, -- Target height for smooth zoom transitions

            -- Mouse tracking
            lastMouseX = nil, -- Last mouse X position
            lastMouseY = nil, -- Last mouse Y position
            screenCenterX = nil, -- Screen center X coordinate

            -- Mouse tracking for rotation and movement
            isMiddleMouseDown = false, -- Whether middle mouse button is currently pressed
            lastMiddleClickTime = 0, -- Time of last middle mouse click for double-click detection
            middleClickCount = 0, -- For tracking single vs double clicks
            doubleClickThreshold = 0.3, -- Time threshold for double-clicks in seconds

            -- Mouse drag tracking
            lastDragX = nil, -- Last X position during drag
            lastDragY = nil, -- Last Y position during drag

            -- Left mouse button tracking
            isLeftMouseDown = false,
            lastLeftClickTime = 0,
            leftClickCount = 0,

            maxRotationSpeed = nil, -- Maximum rotation speed from config
            edgeRotationMultiplier = nil, -- Edge rotation speed multiplier
            maxAngularVelocity = nil, -- Maximum angular velocity for steering
            angularDamping = nil, -- How fast angular velocity decreases
            forwardVelocity = nil, -- Current forward velocity toward target
            minDistanceToTarget = nil, -- Minimum distance to stop at
            movementTransitionFactor = nil, -- Transition smoothing factor

            isRotationModeActive = false, -- Whether rotation mode is active
            rotationTargetPoint = nil, -- The target point to rotate around
            rotationAngle = nil, -- Current rotation angle in radians
            rotationDistance = nil, -- Distance from camera to rotation center
            rotationCenter = nil, -- Rotation center position {x, y, z}

            -- Transition tracking fields
            currentTransitionFactor = nil, -- Stores custom transition factor based on movement distance
            lastTransitionDistance = nil, -- Last distance to target during transition
            stuckFrameCount = 0, -- Count of frames with no significant movement
            userLookedAround = false, -- Tracks whether user has manually looked around during transition

            pendingRotationMode = false, -- Whether rotation mode is pending activation after transition
            pendingRotationCenter = nil, -- Pending rotation center position {x, y, z}
            pendingRotationDistance = nil, -- Pending distance from camera to rotation center
            pendingRotationAngle = nil, -- Pending rotation angle in radians
            enableRotationAfterToggle = nil, -- Flag to enable rotation mode after overview is enabled
        },

        mouse = {
            -- Registered modes
            registeredModes = {},

            -- General state
            isLeftMouseDown = false,
            isMiddleMouseDown = false,
            isRightMouseDown = false,

            -- Last mouse positions for drag detection and calculation
            lastMouseX = 0,
            lastMouseY = 0,

            -- Previous drag positions (for calculating deltas)
            lastDragX = nil,
            lastDragY = nil,

            -- Configuration
            doubleClickThreshold = 0.3, -- seconds
            dragThreshold = 30, -- pixels
            dragTimeThreshold = 0.15, -- seconds

            -- Callback storage
            callbacks = {}
        },

        dollyCam = {
            route = { points = {} },
            isNavigating = false, -- Whether navigation is active
            currentDistance = 0, -- Current position along path
            targetSpeed = 0, -- Target speed (-1.0 to 1.0)
            currentSpeed = 0, -- Current interpolated speed
            direction = 1, -- 1 = forward
            maxSpeed = 200,
            acceleration = 50,
            alpha = 0.5,
            visualizationEnabled = true,
            noCamera = false
        }
    }
end