if not WG.TurboBarCam.STATE then
    ---@class WidgetState
    ---@field DEFAULT WidgetState
    WG.TurboBarCam.STATE = {
        -- Target types
        TARGET_TYPES = {
            UNIT = "UNIT",
            POINT = "POINT",
            NONE = "NONE"
        },

        settings = {
            initialized = false,
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

        --- The new unified tracker for camera state.
        camera = {
            position = {x = 0, y = 0, z = 0},
            velocity = {x = 0, y = 0, z = 0},
            orientation = {w = 1, x = 0, y = 0, z = 0},
            angularVelocity = {x = 0, y = 0, z = 0}, -- as a vector
            euler = {rx = 0, ry = 0, rz = 0},
            history = {},
            maxHistorySize = 10,
            angularVelocityEuler = {x = 0, y = 0, z = 0},
        },

        --- State for the OrientationController
        orientationController = {
            lastKnownLookAtPoint = nil,
            lastKnownRotation = nil,
        },

        cameraTarget = {
            position = nil,
            lookAt = nil,
            euler = nil,
            positionSpring = { tightness = nil, damping = nil },
            orientationSpring = { tightness = nil, damping = nil }
        },

        ---@deprecated Will be replaced by STATE.camera
        cameraVelocity = {
            positionHistory = {},
            rotationHistory = {},
            maxHistorySize = 10,
            currentVelocity = { x = 0, y = 0, z = 0 },
            currentRotationalVelocity = { x = 0, y = 0, z = 0 },
            lastUpdateTime = nil,
            isTracking = false,
            initialized = false
        },

        projectileTracking = {
            unitProjectiles = {}
        },

        -- Core widget state
        enabled = false,
        originalCameraState = nil,
        allowPlayerCamUnitSelection = true,

        -- Camera anchors
        anchor = {
            points = {},
            visualizationEnabled = false,
            activeAnchorId = nil,
        },
        lastUsedAnchor = nil,

        scheduler = { schedules = {} },

        -- Transitions (Managed by TransitionManager)
        transitions = {},

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

            ---@deprecated Will be replaced by STATE.cameraState
            lastCamPos = { x = 0, y = 0, z = 0 },
            ---@deprecated Will be replaced by STATE.cameraState
            lastCamDir = { x = 0, y = 0, z = 0 },
            ---@deprecated Will be replaced by STATE.cameraState
            lastRotation = { rx = 0, ry = 0, rz = 0 },

            isModeTransitionInProgress = false,
            transitionProgress = nil,

            initialCameraStateForModeEntry = nil,
            optionalTargetCameraStateForModeEntry = nil,

            unit_tracking = {
                isModeInitialized = false,
            },

            unit_follow = {
                isModeInitialized = false,
                transitionFactor = nil,
                inTargetSelectionMode = false,
                prevFreeCamState = false,
                prevMode = nil,
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
                projectileTrackingEnabled = false,
                lastUnitProjectileID = nil,
                lastProjectilePosition = nil,
                combatModeEnabled = false,
                useLookAtTarget = false,
                lastTargetPos = nil,
                lastTargetUnitID = nil,
                lastTargetUnitName = nil,
                lastTargetType = nil,
                lastRotationRx = nil,
                lastRotationRy = nil,
                initialTargetAcquisitionTime = nil,
                targetRotationHistory = {},
                rotationChangeThreshold = 0.05,
                isTargetSwitchTransition = false,
                targetSwitchStartTime = nil,
                targetSwitchDuration = 0.4,
                previousWeaponDir = { x = 0, y = 0, z = 0 },
                previousCamPosRelative = { x = 0, y = 0, z = 0 },

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
                    targetAimOffset = { x = 0, y = 0, z = 0 },
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
                isModeInitialized = false,
                armed = false,
                watchedUnitID = nil,
                continuouslyArmedUnitID = nil,
                returnToPreviousMode = false,
                lastArmingTime = 0,
                previousMode = nil,
                previousCameraState = nil,
                impactPosition = nil,
                cameraMode = nil,
                initialCamPos = nil,
                initialImpactVelocity = nil,
                initialImpactRotVelocity = nil,
                isHighArc = false,
                highArcGoingUpward = false,
                highArcDirectionChangeCompleted = false,
                transitionFactor = nil,
                rampUpFactor = 1,

                projectile = {
                    selectedProjectileID = nil,
                    currentProjectileID = nil,
                    lastSwitchTime = nil,
                    isWatchingForProjectiles = false,
                    smoothedPositions = nil,
                    trackingStartTime = nil,
                    lastProjectileVel = nil,
                    lastProjectileVelY = nil,
                },
            },

            group_tracking = {
                isModeInitialized = false,
                unitIDs = {},
                centerOfMass = { x = 0, y = 0, z = 0 },
                targetDistance = nil,
                radius = 0,
                outliers = {},
                lastCenterOfMass = { x = 0, y = 0, z = 0 },
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

        specGroups = {
            groups = {},
            isSpectator = false
        },


        mouse = {
            registeredModes = {},
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
            callbacks = {}
        },

        dollyCam = {
            route = { points = {} },
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
        }
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