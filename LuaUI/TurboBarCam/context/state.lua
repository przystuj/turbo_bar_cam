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

        -- Camera tracking
        tracking = {
            mode = nil,
            targetType = nil,
            unitID = nil,
            targetPoint = nil,
            lastTargetPoint = nil,

            offsets = { fps = {}, orbit = {}, projectile_camera = {} },

            graceTimer = nil,
            lastUnitID = nil,

            lastCamPos = { x = 0, y = 0, z = 0 },
            lastCamDir = { x = 0, y = 0, z = 0 },
            lastRotation = { rx = 0, ry = 0, rz = 0 },

            isModeTransitionInProgress = false,
            transitionStartState = nil,
            transitionStartTime = nil,

            fps = {
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
                    lastCloudUpdateTime = nil,
                    highActivityDetected = false,
                    activityLevel = 0,
                    lastTargetSwitchTime = nil,
                    targetSwitchCount = 0,
                    lastStatusLogTime = nil,
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

            projectile = {
                selectedProjectileID = nil,
                currentProjectileID = nil,
                lastSwitchTime = nil,
                isWatchingForProjectiles = false,
                smoothedPositions = nil, -- Will be { camPos = {x,y,z}, targetPos = {x,y,z} }
            },

            projectileWatching = {
                armed = false,
                watchedUnitID = nil,
                continuouslyArmedUnitID = nil,
                lastArmingTime = 0,
                previousMode = nil,
                previousCameraState = nil,
                impactTimer = nil, -- Timer for how long to stay on impact *after* deceleration
                impactPosition = nil, -- {pos = {x,y,z}, vel = {x,y,z}}
                cameraMode = nil,
                initialCamPos = nil,

                isImpactDecelerating = false, -- True if currently in the impact deceleration phase
                impactDecelerationStartTime = nil, -- Timer for the start of impact deceleration
                initialImpactVelocity = nil         -- Camera velocity captured at the start of impact deceleration {x,y,z}
            },

            group = {
                unitIDs = {},
                centerOfMass = { x = 0, y = 0, z = 0 },
                targetDistance = nil,
                radius = 0,
                outliers = {},
                lastCenterOfMass = { x = 0, y = 0, z = 0 },
            },

            orbit = {
                angle = nil,
                lastPosition = nil,
                lastCamPos = nil,
                lastCamRot = nil,
                isPaused = false,
            },
        },

        specGroups = {
            groups = {},
            isSpectator = false
        },

        overview = {
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
            noCamera = false
        }
    }
end
