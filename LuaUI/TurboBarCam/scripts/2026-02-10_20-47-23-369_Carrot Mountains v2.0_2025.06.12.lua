return {
    steps = {
        -- INIT
        { frame = 30, label = "Init", commands = { "skip f30900" } },

        -- CUT #01 Hound (Pre-Pause (Switching to Neighbor))
        {
            frame = 30900,
            label = "Hound (Pre-Pause (Switching to Neighbor))",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 1299 combat",
                "turbobarcam_script_select_unit 1299",
            }
        },

        -- CUT #02 Hound (Pre-Pause (Switching to Neighbor))
        {
            frame = 31803,
            label = "Hound (Pre-Pause (Switching to Neighbor))",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 22957 combat",
                "turbobarcam_script_select_unit 22957",
            }
        },

        -- CUT #03 Hound (Anchor End (Idle))
        {
            frame = 36283,
            label = "Hound (Anchor End (Idle))",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 15800 combat",
                "turbobarcam_script_select_unit 15800",
            }
        },

        -- CUT #04 Hound (Anchor End (Idle))
        {
            frame = 37693,
            label = "Hound (Anchor End (Idle))",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 1299 combat",
                "turbobarcam_script_select_unit 1299",
            }
        },

        -- CUT #05 Hound (Anchor End (Idle))
        {
            frame = 39633,
            label = "Hound (Anchor End (Idle))",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 137 combat",
                "turbobarcam_script_select_unit 137",
            }
        },

        -- CUT #06 Razorback (Anchor End (Idle))
        {
            frame = 41993,
            label = "Razorback (Anchor End (Idle))",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 27023 combat",
                "turbobarcam_script_select_unit 27023",
            }
        },

        -- CUT #07 Mammoth (Anchor End (Idle))
        {
            frame = 44253,
            label = "Mammoth (Anchor End (Idle))",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 15686 combat",
                "turbobarcam_script_select_unit 15686",
            }
        },

        -- CUT #08 Mammoth (Anchor End (Idle))
        {
            frame = 44863,
            label = "Mammoth (Anchor End (Idle))",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 14259 combat",
                "turbobarcam_script_select_unit 14259",
            }
        },

        -- CUT #09 Razorback (Anchor End (Idle))
        {
            frame = 45793,
            label = "Razorback (Anchor End (Idle))",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 28781 combat",
                "turbobarcam_script_select_unit 28781",
            }
        },

        -- CUT #10 Marauder (Anchor End (Idle))
        {
            frame = 46703,
            label = "Marauder (Anchor End (Idle))",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 24564 combat",
                "turbobarcam_script_select_unit 24564",
            }
        },

        -- CUT #11 Marauder (Pre-Pause)
        {
            frame = 47853,
            label = "Marauder (Pre-Pause)",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 11263 combat",
                "turbobarcam_script_select_unit 11263",
            }
        },

        -- CUT #12 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 48923,
            label = "Fast Forward (Skipping Long Pause)",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #13 Marauder (Anchor End (Idle))
        {
            frame = 49773,
            label = "Marauder (Anchor End (Idle))",
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #14 Razorback (Pre-Pause (Switching to Neighbor))
        {
            frame = 49843,
            label = "Razorback (Pre-Pause (Switching to Neighbor))",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 1715 combat",
                "turbobarcam_script_select_unit 1715",
            }
        },

        -- CUT #15 Razorback (Anchor End (Idle))
        {
            frame = 52853,
            label = "Razorback (Anchor End (Idle))",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 19906 combat",
                "turbobarcam_script_select_unit 19906",
            }
        },

        -- END
        { frame = 54742, label = "END", commands = {} },
    }
}
