---@class Mode
local modes = {
    ORBIT = "orbit",
    ANCHOR = "anchor",
    DOLLYCAM = "dollycam",
    GROUP_TRACKING = "group_tracking",
    ORBIT = "orbit",
    PROJECTILE_CAMERA = "projectile_camera",
    SPEC_GROUPS = "spec_groups",
    UNIT_FOLLOW = "unit_follow",
    UNIT_TRACKING = "unit_tracking",
}

---@class TargetType
local targetTypes = {
    UNIT = "UNIT",
    POINT = "POINT",
    EULER = "EULER",
    NONE = "NONE",
}


if not WG.TurboBarCam.CONSTANTS then
    ---@class Constants
    WG.TurboBarCam.CONSTANTS = {
        MODE = modes,
        TARGET_TYPE = targetTypes,
    }
end

return WG.TurboBarCam.CONSTANTS
