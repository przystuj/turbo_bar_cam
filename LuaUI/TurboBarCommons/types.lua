---@class DriverTargetConfig
---@field position Vector
---@field targetType TargetType
---@field targetPoint Vector?
---@field targetUnitId number?
---@field targetEuler Euler?
---@field positionSmoothing number
---@field rotationSmoothing number
---@field isSnap boolean If true camera will instantly snap to the target, skipping the simulation
---@field euler table DEPRECATED
---@field smoothTimePos number DEPRECATED
---@field smoothTimeRot number DEPRECATED

---@class Vector
---@field x number
---@field y number
---@field z number

---@class Euler
---@field rx number
---@field ry number
---@field rz number

---@class Error
---@field message string
---@field traceback string


---@class UnitFollowCombatModeTarget
---@field lastUpdateTime
---@field lastRealPos
---@field positionHistory
---@field isCachedTarget
---@field cachedTargetDuration
---@field velocityX
---@field velocityY
---@field velocityZ
---@field speed
---@field ySpeed
---@field isMovingFast
---@field isMovingUpFast
---@field frameCounter
---@field airAdjustmentActive
---@field lastAdjustmentStateTime
---@field lastLogTime
