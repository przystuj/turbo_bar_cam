---@type ModuleManager
local ModuleManager = WG.TurboBarCam.ModuleManager
local STATE = ModuleManager.STATE(function(m) STATE = m end)
local CONFIG = ModuleManager.CONFIG(function(m) CONFIG = m end)
local Log = ModuleManager.Log(function(m) Log = m end)
local Util = ModuleManager.Util(function(m) Util = m end)
local CameraCommons = ModuleManager.CameraCommons(function(m) CameraCommons = m end)
local ProjectileCameraPersistence = ModuleManager.ProjectileCameraPersistence(function(m) ProjectileCameraPersistence = m end)

---@class ProjectileCameraUtils
local ProjectileCameraUtils = {}

--------------------------------------------------------------------------------
-- Camera Calculation and Smoothing Helpers
--------------------------------------------------------------------------------

function ProjectileCameraUtils.calculateCameraPositionForProjectile(pPos, pVel, subMode)
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA

    if subMode == "static" then
        local camState = Spring.GetCameraState()
        return { x = camState.px, y = camState.py, z = camState.pz }
    end

    local rampUpFactor = STATE.mode.projectile_camera.rampUpFactor
    local modeCfg = cfg.FOLLOW
    local distance = modeCfg.DISTANCE * rampUpFactor
    local height = modeCfg.HEIGHT * rampUpFactor

    local projectileDir = CameraCommons.normalizeVector(pVel)
    if CameraCommons.vectorMagnitudeSq(projectileDir) < 0.001 then
        projectileDir = { x = 0, y = -0.5, z = -0.5 } -- Default fallback
        projectileDir = CameraCommons.normalizeVector(projectileDir)
    end

    local camX, camY, camZ

    if STATE.mode.projectile_camera.isHighArc then
        local awayDirXZ
        if STATE.mode.lastCamDir and (STATE.mode.lastCamDir.x ~= 0 or STATE.mode.lastCamDir.z ~= 0) then
            -- Use inverted XZ component of camera's forward vector.
            awayDirXZ = CameraCommons.normalizeVector({ x = -STATE.mode.lastCamDir.x, y = 0, z = -STATE.mode.lastCamDir.z })
        else
            awayDirXZ = { x = 0, y = 0, z = 1 } -- Fallback: Pull camera towards +Z.
        end
        -- Apply distance along 'awayDirXZ' and height along World Y
        camX = pPos.x + awayDirXZ.x * distance
        camZ = pPos.z + awayDirXZ.z * distance
        camY = pPos.y + height
    else
        local worldUp = { x = 0, y = 1, z = 0 }
        local right = CameraCommons.crossProduct(projectileDir, worldUp)
        if CameraCommons.vectorMagnitudeSq(right) < 0.001 then
            local worldFwdTemp = { x = 0, y = 0, z = 1 }
            if math.abs(projectileDir.y) > 0.99 then
                worldFwdTemp = { x = 1, y = 0, z = 0 }
            end
            right = CameraCommons.crossProduct(projectileDir, worldFwdTemp)
            if CameraCommons.vectorMagnitudeSq(right) < 0.001 then
                right = { x = 1, y = 0, z = 0 }
            end
        end
        right = CameraCommons.normalizeVector(right)
        local localUp = CameraCommons.normalizeVector(CameraCommons.crossProduct(right, projectileDir))

        -- Apply Y-constraint to localUp
        if localUp.y < 0 then
            localUp.y = 0
            if CameraCommons.vectorMagnitudeSq(localUp) < 0.001 then
                localUp = { x = 0, y = 1, z = 0 } -- Fallback to world up
            else
                localUp = CameraCommons.normalizeVector(localUp)
            end
        end
        local upVectorForHeight = localUp

        -- Apply distance along projectile direction
        camX = pPos.x - projectileDir.x * distance
        camY = pPos.y - projectileDir.y * distance
        camZ = pPos.z - projectileDir.z * distance
        -- Apply height along (constrained) local up
        camX = camX + upVectorForHeight.x * height
        camY = camY + upVectorForHeight.y * height
        camZ = camZ + upVectorForHeight.z * height
    end

    local result = { x = camX, y = camY, z = camZ }
    return result
end

function ProjectileCameraUtils.calculateIdealTargetPosition(projectilePos, projectileVel)
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA
    local subMode = STATE.mode.projectile_camera.cameraMode
    local modeCfg = cfg[string.upper(subMode)] or cfg.FOLLOW

    local fwd = CameraCommons.normalizeVector(projectileVel)
    if CameraCommons.vectorMagnitudeSq(fwd) < 0.001 then
        fwd = { x = 0, y = 0, z = 1 }
    end

    local pPos = projectilePos
    local lookAhead = modeCfg.LOOK_AHEAD or 0

    local baseTarget = {
        x = pPos.x + fwd.x * lookAhead,
        y = pPos.y + fwd.y * lookAhead,
        z = pPos.z + fwd.z * lookAhead
    }

    if subMode == "static" then
        local offsetHeight = modeCfg.OFFSET_HEIGHT or 0
        local offsetSide = modeCfg.OFFSET_SIDE or 0

        if offsetHeight == 0 and offsetSide == 0 then
            return baseTarget
        end

        local worldUp = { x = 0, y = 1, z = 0 }
        local right = CameraCommons.crossProduct(fwd, worldUp)
        if CameraCommons.vectorMagnitudeSq(right) < 0.001 then
            local worldFwdTemp = { x = 0, y = 0, z = 1 }
            if math.abs(fwd.z) > 0.99 then
                worldFwdTemp = { x = 1, y = 0, z = 0 }
            end
            right = CameraCommons.crossProduct(fwd, worldFwdTemp)
            if CameraCommons.vectorMagnitudeSq(right) < 0.001 then
                right = { x = 1, y = 0, z = 0 }
            end
        end
        right = CameraCommons.normalizeVector(right)
        local localUp = CameraCommons.normalizeVector(CameraCommons.crossProduct(right, fwd))

        return {
            x = baseTarget.x + localUp.x * offsetHeight + right.x * offsetSide,
            y = baseTarget.y + localUp.y * offsetHeight + right.y * offsetSide,
            z = baseTarget.z + localUp.z * offsetHeight + right.z * offsetSide
        }
    end
    return baseTarget
end

function ProjectileCameraUtils.resetSmoothedPositions()
    if STATE.mode.projectile_camera.projectile and STATE.mode.projectile_camera.projectile.smoothedPositions then
        STATE.mode.projectile_camera.projectile.smoothedPositions.camPos = nil
        STATE.mode.projectile_camera.projectile.smoothedPositions.targetPos = nil
    end
end

function ProjectileCameraUtils.resetToDefaults()
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA
    cfg.FOLLOW.DISTANCE = cfg.DEFAULT_FOLLOW.DISTANCE
    cfg.FOLLOW.HEIGHT = cfg.DEFAULT_FOLLOW.HEIGHT
    cfg.FOLLOW.LOOK_AHEAD = cfg.DEFAULT_FOLLOW.LOOK_AHEAD
    cfg.STATIC.LOOK_AHEAD = cfg.DEFAULT_STATIC.LOOK_AHEAD
    cfg.STATIC.OFFSET_HEIGHT = cfg.DEFAULT_STATIC.OFFSET_HEIGHT
    cfg.STATIC.OFFSET_SIDE = cfg.DEFAULT_STATIC.OFFSET_SIDE
    cfg.DECELERATION_PROFILE = Util.deepCopy(cfg.DEFAULT_DECELERATION_PROFILE)
    Log:trace("ProjectileCamera: Restored settings to defaults.")
end

function ProjectileCameraUtils.saveSettings(unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log:trace("ProjectileCamera: Cannot save settings, invalid unitID.")
        return
    end
    local unitDef = UnitDefs[Spring.GetUnitDefID(unitID)]
    if not unitDef then
        Log:warn("ProjectileCamera: Cannot save settings, failed to get unitDef.")
        return
    end
    local unitName = unitDef.name
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA
    local settingsToSave = {
        FOLLOW = { DISTANCE = cfg.FOLLOW.DISTANCE, HEIGHT = cfg.FOLLOW.HEIGHT, LOOK_AHEAD = cfg.FOLLOW.LOOK_AHEAD, },
        STATIC = { LOOK_AHEAD = cfg.STATIC.LOOK_AHEAD, OFFSET_HEIGHT = cfg.STATIC.OFFSET_HEIGHT, OFFSET_SIDE = cfg.STATIC.OFFSET_SIDE, },
        DECELERATION_PROFILE = Util.deepCopy(cfg.DECELERATION_PROFILE),
    }
    ProjectileCameraPersistence.saveSettings(unitName, settingsToSave)
end

function ProjectileCameraUtils.loadSettings(unitID)
    if not unitID or not Spring.ValidUnitID(unitID) then
        Log:trace("ProjectileCamera: Cannot load settings, invalid unitID.")
        ProjectileCameraUtils.resetToDefaults()
        return
    end
    local unitDef = UnitDefs[Spring.GetUnitDefID(unitID)]
    if not unitDef then
        Log:warn("ProjectileCamera: Cannot load settings, failed to get unitDef.")
        ProjectileCameraUtils.resetToDefaults()
        return
    end
    local unitName = unitDef.name
    local cfg = CONFIG.CAMERA_MODES.PROJECTILE_CAMERA
    local loadedSettings = ProjectileCameraPersistence.loadSettings(unitName)
    if loadedSettings then
        Log:trace("ProjectileCamera: Loading saved settings for " .. unitName)
        cfg.FOLLOW.DISTANCE = loadedSettings.FOLLOW and loadedSettings.FOLLOW.DISTANCE or cfg.DEFAULT_FOLLOW.DISTANCE
        cfg.FOLLOW.HEIGHT = loadedSettings.FOLLOW and loadedSettings.FOLLOW.HEIGHT or cfg.DEFAULT_FOLLOW.HEIGHT
        cfg.FOLLOW.LOOK_AHEAD = loadedSettings.FOLLOW and loadedSettings.FOLLOW.LOOK_AHEAD or cfg.DEFAULT_FOLLOW.LOOK_AHEAD
        cfg.STATIC.LOOK_AHEAD = loadedSettings.STATIC and loadedSettings.STATIC.LOOK_AHEAD or cfg.DEFAULT_STATIC.LOOK_AHEAD
        cfg.STATIC.OFFSET_HEIGHT = loadedSettings.STATIC and loadedSettings.STATIC.OFFSET_HEIGHT or cfg.DEFAULT_STATIC.OFFSET_HEIGHT
        cfg.STATIC.OFFSET_SIDE = loadedSettings.STATIC and loadedSettings.STATIC.OFFSET_SIDE or cfg.DEFAULT_STATIC.OFFSET_SIDE
        cfg.DECELERATION_PROFILE = loadedSettings.DECELERATION_PROFILE and Util.deepCopy(loadedSettings.DECELERATION_PROFILE) or Util.deepCopy(cfg.DEFAULT_DECELERATION_PROFILE)
    else
        Log:trace("ProjectileCamera: No saved settings found for " .. unitName .. ". Using defaults.")
        ProjectileCameraUtils.resetToDefaults()
    end
end

function ProjectileCameraUtils.adjustParams(params)
    if Util.isTurboBarCamDisabled() or STATE.mode.name ~= 'projectile_camera' then
        return
    end
    local function getProjectileParamPrefixes()
        return { FOLLOW = "FOLLOW.", STATIC = "STATIC." }
    end
    local function resetAndSave()
        ProjectileCameraUtils.resetToDefaults()
        if STATE.mode.unitID then
            ProjectileCameraUtils.saveSettings(STATE.mode.unitID)
        end
        Log:info("Projectile Camera settings reset to defaults" .. (STATE.mode.unitID and " and saved for current unit type." or "."))
    end
    local currentSubmode = STATE.mode.projectile_camera.cameraMode
    local currentSubmodeUpper = string.upper(currentSubmode)
    Log:trace("Adjusting Projectile Camera params for submode: " .. currentSubmodeUpper)
    Util.adjustParams(params, "PROJECTILE_CAMERA", resetAndSave, currentSubmodeUpper, getProjectileParamPrefixes)
    if STATE.mode.unitID then
        ProjectileCameraUtils.saveSettings(STATE.mode.unitID)
    end
end

function ProjectileCameraUtils.isUnitCentricMode(mode)
    return mode == 'unit_follow' or mode == 'unit_tracking' or mode == 'orbit' or mode == 'projectile_camera'
end

return ProjectileCameraUtils