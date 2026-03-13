return {
    metadata = {
        replayName = "2026-02-26_20-54-32-568_All That Glitters v2.2.3_2025.06.19",
        version = 2,
    },
    steps = {

        -- STEP #01 Init
        {
            frame = 0,
            label = "Init",
            commands = {
                "skip f58685",
            }
        },

        -- STEP #02 Juggernaut
        {
            frame = 58685,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 3051 combat",
                "turbobarcam_script_select_unit_team 3051",
            }
        },

        -- STEP #03 END
        {
            frame = 73773,
            label = "END",
            commands = {
            }
        },
    }
}
