return {
    steps = {
        { frame = 30, commands = { "skip f7050" } },

        -- CUT #01 Thug (Pre-Pause)
        {
            frame = 7050,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 14925 combat",
                "turbobarcam_script_select_unit 14925",
            }
        },

        -- CUT #02 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 7503,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #03 Thug (Pre-Pause (Switching to Neighbor))
        {
            frame = 8133,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #04 Thug (Anchor End (Idle))
        {
            frame = 9373,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 9524 combat",
                "turbobarcam_script_select_unit 9524",
            }
        },

        -- CUT #05 Lasher (Swap to Better Unit)
        {
            frame = 10593,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 10349 combat",
                "turbobarcam_script_select_unit 10349",
            }
        },

        -- CUT #06 Tzar (Anchor End (Idle))
        {
            frame = 12000,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 9437 combat",
                "turbobarcam_script_select_unit 9437",
            }
        },

        -- CUT #07 Whistler (Swap to Better Unit)
        {
            frame = 14123,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 30619 combat",
                "turbobarcam_script_select_unit 30619",
            }
        },

        -- CUT #08 Quaker (Pre-Pause)
        {
            frame = 14610,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17965 combat",
                "turbobarcam_script_select_unit 17965",
            }
        },

        -- CUT #09 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 15403,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #10 Quaker (Anchor End (Idle))
        {
            frame = 16033,
            commands = {
                "setspeed 1",
            }
        },
    }
}
