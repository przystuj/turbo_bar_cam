if not WG.TurboBarCam.CONSTANTS then
    ---@class Constants
    WG.TurboBarCam.CONSTANTS = {
        MODE = {
            ORBIT = "orbit",
            ANCHOR = "anchor",
            DOLLYCAM = "dollycam",
            GROUP_TRACKING = "group_tracking",
            ORBIT = "orbit",
            OVERVIEW = "overview",
            PROJECTILE_CAMERA = "projectile_camera",
            SPEC_GROUPS = "spec_groups",
            UNIT_FOLLOW = "unit_follow",
            UNIT_TRACKING = "unit_tracking",
        },


        TARGET_TYPE = {
            UNIT = "UNIT",
            POINT = "POINT",
            NONE = "NONE"
        },
    }
end

return WG.TurboBarCam.CONSTANTS