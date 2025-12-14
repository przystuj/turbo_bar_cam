if not WG.TurboBarCam.STATE then
    ---@class WidgetState
    ---@field DEFAULT WidgetState
    WG.TurboBarCam.STATE = {
        -- Core widget state
        enabled = false,
        originalCameraState = nil,
        allowPlayerCamUnitSelection = true,
        error = nil, ---@type Error

        settings = {
            initialized = false,
            ---@type PersistentStorage[]
            storages = {},
            loadModeSettingsFn = {
                unit_follow = nil,
                orbit = nil,
                projectile_camera = nil,
            },
            saveModeSettingsFn = {
                unit_follow = nil,
                orbit = nil,
                projectile_camera = nil,
            },
        },

        anchor = {
            initialized = false,
            ---@type AnchorPoint[]
            points = {},
        },

        specGroups = {
            groups = {},
            isSpectator = false
        },

        dollyCam = {
            route = { points = {} },
        },

        testRunner = {
            isRunning = false,
            queueIndex = 0,
            testQueue = {},
            testPhase = "idle",
            phaseTimer = 0,
            results = {},
            startPosition = nil,
        },

        -- all of these are reset when toggling widget off
        core = {
            -- State for the low-level CameraDriver that executes movement.
            -- Managed exclusively by CameraDriver.
            driver = {
                ---@type DriverTargetConfig
                target = {},
                simulation = {
                    position = { x = 0, y = 0, z = 0 },
                    orientation = { w = 1, x = 0, y = 0, z = 0 },
                    euler = { rx = 0, ry = 0 },
                    velocity = { x = 0, y = 0, z = 0 },
                    angularVelocity = { x = 0, y = 0, z = 0 },
                },
                smoothingTransition = {
                    startingPositionSmoothing = 3,
                    startingRotationSmoothing = 3,
                    currentPositionSmoothing = 3,
                    currentRotationSmoothing = 3,
                    smoothingTransitionStart = nil,
                },
                job = {
                    angularVelocityMagnitude = nil,
                    velocityMagnitude = nil,
                    distance = nil,
                    isPositionComplete = false,
                    isRotationComplete = false,
                    isRotationOnly = nil,
                    isActive = false,
                },
            },

            -- The ground-truth state of the camera as reported by the tracker.
            -- Managed exclusively by CameraStateTracker.
            camera = {
                position = { x = 0, y = 0, z = 0 },
                velocity = { x = 0, y = 0, z = 0 },
                orientation = { w = 1, x = 0, y = 0, z = 0 },
                angularVelocity = { x = 0, y = 0, z = 0 },
                euler = { rx = 0, ry = 0, rz = 0 },
                history = {},
                maxHistorySize = 10,
                angularVelocityEuler = { x = 0, y = 0, z = 0 },
            },

            mouse = {
                registeredModes = {},
                callbacks = {}
            },

            projectileTracking = {
                unitProjectiles = {}
            },

            anchor = {
                lastUsedAnchor = nil,
            },
        },

        -- all of these are reset when changing camera mode
        active = {
            -- Camera anchors
            anchor = {
                visualizationEnabled = false,
                activeAnchorId = nil,
            },

            scheduler = { schedules = {} },

            dollyCam = {
                isNavigating = false,
                currentDistance = 0,
                targetSpeed = 0,
                currentSpeed = 0,
                direction = 1,
                maxSpeed = 200,
                acceleration = 50,
                alpha = 0.5,
                visualizationEnabled = true,
                noCamera = false,
                selectedWaypoints = {},
                hoveredWaypointIndex = nil,
                hoveredPathPointIndex = nil,
                lastMouseScreenPos = { x = 0, y = 0 },
                lastMouseWorldPos = { x = 0, y = 0, z = 0 },
            },

            mouse = {
                isLeftMouseDown = false,
                isMiddleMouseDown = false,
                isRightMouseDown = false,
                lastMouseX = 0,
                lastMouseY = 0,
                lastDragX = nil,
                lastDragY = nil,
                doubleClickThreshold = 0.3,
                dragThreshold = 30,
                dragTimeThreshold = 0.15,
            },

            -- Camera tracking
            mode = {
                name = nil,
                targetType = nil,
                unitID = nil,
                targetPoint = nil,
                lastTargetPoint = nil,
                transitionTarget = nil,

                graceTimer = nil,
                lastUnitID = nil,

                ---@deprecated Will be replaced by STATE.core.cameraState
                lastCamPos = { x = 0, y = 0, z = 0 },
                ---@deprecated Will be replaced by STATE.core.cameraState
                lastCamDir = { x = 0, y = 0, z = 0 },
                ---@deprecated Will be replaced by STATE.core.cameraState
                lastRotation = { rx = 0, ry = 0, rz = 0 },

                isModeTransitionInProgress = false,
                transitionProgress = nil,

                initialCameraStateForModeEntry = nil,
                optionalTargetCameraStateForModeEntry = nil,

                unit_follow = {
                    inTargetSelectionMode = false,
                    prevFreeCamState = false,
                    prevFixedPoint = nil,
                    isFreeCameraActive = false,
                    targetUnitID = nil,
                    fixedPoint = nil,
                    isFixedPointActive = false,
                    isAttacking = false,
                    weaponPos = nil,
                    weaponDir = nil,
                    activeWeaponNum = nil,
                    forcedWeaponNumber = nil,
                    combatModeEnabled = false,
                    lastTargetPos = nil,
                    lastTargetUnitID = nil,
                    isTargetSwitchTransition = false,
                    targetSwitchStartTime = nil,
                    targetSwitchDuration = 0.4,

                    freeCam = {
                        lastMouseX = nil,
                        lastMouseY = nil,
                        targetRx = nil,
                        targetRy = nil,
                        lastUnitHeading = nil
                    },

                    targetSmoothing = {
                        targetHistory = {},
                        cloudCenter = nil,
                        cloudRadius = 0,
                        useCloudTargeting = false,
                        cloudStartTime = nil,
                        highActivityDetected = false,
                        activityLevel = 0,
                        lastTargetSwitchTime = nil,
                        targetSwitchCount = 0,
                        currentTargetKey = nil,
                        targetPrediction = {
                            enabled = false,
                            velocityX = 0,
                            velocityY = 0,
                            velocityZ = 0,
                            lastUpdateTime = nil
                        },
                        rotationConstraint = {
                            enabled = true,
                            maxRotationRate = 0.07,
                            lastYaw = nil,
                            lastPitch = nil,
                            damping = 0.8
                        }
                    },
                },

                projectile_camera = {
                    -- State for "arming" workflow
                    isArmed = false,
                    watchedUnitID = nil,
                    continuouslyArmedUnitID = nil,
                    lastArmingTime = nil,

                    -- State for global "cycling" workflow
                    trackedProjectiles = {},
                    currentProjectileIndex = 0,

                    -- Common state for both workflows
                    currentProjectileID = nil,
                    returnToPreviousMode = true,
                    previousMode = nil,
                    previousCameraState = nil,
                    previousModeState = nil,
                    impactPosition = nil,
                    cameraMode = "follow",
                    initialCamPos = nil,
                    isHighArc = false,
                    impactTime = nil,
                },

                group_tracking = {
                    isModeInitialized = false,
                    unitIDs = {},
                    centerOfMass = { x = 0, y = 0, z = 0 },
                    targetDistance = nil,
                    radius = 0,
                    outliers = {},
                    lastCenterOfMass = { x = 0, y = 0, z = 0 },
                    lastCameraDir = nil,
                },

                orbit = {
                    isModeInitialized = false,
                    angle = nil,
                    lastPosition = nil,
                    lastCamPos = nil,
                    lastCamRot = nil,
                    isPaused = false,
                    loadedAngleForEntry = nil,
                },

                overview = {
                    isModeInitialized = false,
                    height = nil,
                    heightLevel = nil,
                    fixedCamPos = nil,
                    targetRx = nil,
                    targetRy = nil,
                    movingToTarget = false,
                    targetPoint = nil,
                    distanceToTarget = nil,
                    movementAngle = nil,
                    angularVelocity = nil,
                    inMovementTransition = false,
                    targetHeight = nil,
                    lastMouseX = nil,
                    lastMouseY = nil,
                    screenCenterX = nil,
                    isMiddleMouseDown = false,
                    lastMiddleClickTime = 0,
                    middleClickCount = 0,
                    doubleClickThreshold = 0.3,
                    lastDragX = nil,
                    lastDragY = nil,
                    isLeftMouseDown = false,
                    lastLeftClickTime = 0,
                    leftClickCount = 0,
                    maxRotationSpeed = nil,
                    edgeRotationMultiplier = nil,
                    maxAngularVelocity = nil,
                    angularDamping = nil,
                    forwardVelocity = nil,
                    minDistanceToTarget = nil,
                    movementTransitionFactor = nil,
                    isRotationModeActive = false,
                    rotationTargetPoint = nil,
                    rotationAngle = nil,
                    rotationDistance = nil,
                    rotationCenter = nil,
                    currentTransitionFactor = nil,
                    lastTransitionDistance = nil,
                    stuckFrameCount = 0,
                    userLookedAround = false,
                    pendingRotationMode = false,
                    pendingRotationCenter = nil,
                    pendingRotationDistance = nil,
                    pendingRotationAngle = nil,
                    enableRotationAfterToggle = nil,
                },
            },
        },
    }
end

local function deepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = deepCopy(orig_value)
        end
    else
        copy = orig
    end
    return copy
end

WG.TurboBarCam.STATE.DEFAULT = WG.TurboBarCam.STATE.DEFAULT or deepCopy(WG.TurboBarCam.STATE)

return WG.TurboBarCam.STATE
