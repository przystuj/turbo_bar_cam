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
        anchors = {},
        lastUsedAnchor = nil,

        scheduler = { schedules = {} },

        -- Transitions (Managed by TransitionManager)
        transitions = {},

        -- Camera transitions (Old anchor transition state)
        transition = {
            active = false,
            startTime = nil,
            steps = {},
            currentStepIndex = 1,
            currentAnchorIndex = nil
        },

        -- Camera tracking
        mode = {
            name = nil,
            targetType = nil,
            unitID = nil,
            targetPoint = nil,
            lastTargetPoint = nil,
            transitionTarget = nil, -- Used for specific LERP transitions by features

            offsets = { fps = {}, orbit = {}, projectile_camera = {} },

            graceTimer = nil,
            lastUnitID = nil,

            lastCamPos = { x = 0, y = 0, z = 0 },
            lastCamDir = { x = 0, y = 0, z = 0 },
            lastRotation = { rx = 0, ry = 0, rz = 0 },

            -- Legacy generic mode transition states (being phased out as features manage their own transitions)
            -- ModeManager no longer sets these directly for generic transitions.
            -- Kept for compatibility with unrefactored modules that might read them.
            isModeTransitionInProgress = false,
            transitionProgress = nil,
            -- transitionStartTime = nil, -- This was used with getTransitionProgress, which is removed/changed

            -- New states set by ModeManager for feature-led transitions
            initialCameraStateForModeEntry = nil,
            optionalTargetCameraStateForModeEntry = nil,
            -- transitionStartState = nil, -- Replaced by initialCameraStateForModeEntry for clarity

            unit_tracking = {
                -- Purpose: This flag indicates if the UnitTrackingCamera feature has performed
                -- its specific initialization logic (like starting its entry camera transition)
                -- for the current activation of the 'unit_tracking' mode. It's reset by
                -- ModeManager when the mode is disabled or changed, allowing the feature
                -- to re-initialize its entry behavior next time it's activated.
                isModeInitialized = false,
            },

            fps = {
                isModeInitialized = false,
                transitionFactor = nil,
                entrySubmode = nil, -- Used to determine target view for entry transition (PEACE or COMBAT)
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

            projectile_camera = { -- State for the projectile_camera feature when active
                isModeInitialized = false, -- For feature-led entry transition
                armed = false,
                watchedUnitID = nil,
                continuouslyArmedUnitID = nil,
                returnToPreviousMode = false,
                lastArmingTime = 0,
                previousMode = nil,
                previousCameraState = nil,
                impactPosition = nil,
                cameraMode = nil, -- 'follow' or 'static' submodes
                initialCamPos = nil,
                initialImpactVelocity = nil,
                initialImpactRotVelocity = nil,
                isHighArc = false,
                highArcGoingUpward = false,
                highArcDirectionChangeCompleted = false,
                transitionFactor = nil,
                rampUpFactor = 1, -- for gradual approaching set camera distance

                projectile = { -- Data about the projectile itself
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
                isModeInitialized = false, -- Placeholder for consistency if group_tracking is refactored
                unitIDs = {},
                centerOfMass = { x = 0, y = 0, z = 0 },
                targetDistance = nil,
                radius = 0,
                outliers = {},
                lastCenterOfMass = { x = 0, y = 0, z = 0 },
            },

            orbit = {
                isModeInitialized = false, -- For feature-led entry transition
                angle = nil,
                lastPosition = nil,
                lastCamPos = nil,
                lastCamRot = nil,
                isPaused = false,
                loadedAngleForEntry = nil,
            },

            overview = {
                isModeInitialized = false, -- For feature-led entry transition (ModeManager will need to handle this path)
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
            noCamera = false
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
