return {
    steps = {
        { frame = 30, commands = { "skip f40050" } },

        -- CUT #01 Banisher (Pre-Pause)
        {
            frame = 40050,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 5702 combat",
                "turbobarcam_script_select_unit 5702",
            }
        },

        -- CUT #02 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 41783,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #03 Banisher (Pre-Pause)
        {
            frame = 42363,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #04 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 42563,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #05 Banisher (Anchor End (Idle))
        {
            frame = 43333,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #06 Banisher (Anchor End (Idle))
        {
            frame = 52173,
            commands = {
            }
        },

        -- CUT #07 Banisher (Pre-Pause)
        {
            frame = 56573,
            commands = {
            }
        },

        -- CUT #08 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 57103,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #09 Banisher (Pre-Pause)
        {
            frame = 57753,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #10 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 57933,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #11 Banisher (Pre-Pause)
        {
            frame = 58283,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #12 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 59763,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #13 Banisher (Pre-Pause)
        {
            frame = 60083,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #14 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 61633,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #15 Banisher (Anchor End (Idle))
        {
            frame = 61983,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #16 Catapult (Pre-Pause (Switching to Neighbor))
        {
            frame = 66053,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 3652 combat",
                "turbobarcam_script_select_unit 3652",
            }
        },

        -- CUT #17 Catapult (Pre-Pause)
        {
            frame = 66603,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 16673 combat",
                "turbobarcam_script_select_unit 16673",
            }
        },

        -- CUT #18 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 73923,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #19 Catapult (Anchor End (Idle))
        {
            frame = 74743,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #20 Vanguard (Anchor End (Idle))
        {
            frame = 75623,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 27318 combat",
                "turbobarcam_script_select_unit 27318",
            }
        },

        -- CUT #21 Shiva (Anchor End (Idle))
        {
            frame = 79103,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 26242 combat",
                "turbobarcam_script_select_unit 26242",
            }
        },

        -- CUT #22 Shiva (Anchor End (Idle))
        {
            frame = 79753,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 8359 combat",
                "turbobarcam_script_select_unit 8359",
            }
        },

        -- CUT #23 Grunt (Anchor End (Idle))
        {
            frame = 81993,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 20507 combat",
                "turbobarcam_script_select_unit 20507",
            }
        },

        -- CUT #24 Juggernaut (Anchor End (Idle))
        {
            frame = 86213,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 14289 combat",
                "turbobarcam_script_select_unit 14289",
            }
        },

        -- CUT #25 Juggernaut (Pre-Pause)
        {
            frame = 87893,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 10344 combat",
                "turbobarcam_script_select_unit 10344",
            }
        },

        -- CUT #26 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 88943,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #27 Juggernaut (Anchor End (Idle))
        {
            frame = 89653,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #28 Wasp (Anchor End (Idle))
        {
            frame = 90623,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 268 combat",
                "turbobarcam_script_select_unit 268",
            }
        },

        -- CUT #29 Vanguard (Anchor End (Idle))
        {
            frame = 94953,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 27318 combat",
                "turbobarcam_script_select_unit 27318",
            }
        },

        -- CUT #30 Grunt (Anchor End (Idle))
        {
            frame = 96273,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17000 combat",
                "turbobarcam_script_select_unit 17000",
            }
        },

        -- CUT #31 Shiva (Anchor End (Idle))
        {
            frame = 97113,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 8359 combat",
                "turbobarcam_script_select_unit 8359",
            }
        },

        -- CUT #32 Shiva (Anchor End (Idle))
        {
            frame = 98763,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 26242 combat",
                "turbobarcam_script_select_unit 26242",
            }
        },

        -- CUT #33 Behemoth (Pre-Pause)
        {
            frame = 99393,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 24420 combat",
                "turbobarcam_script_select_unit 24420",
            }
        },

        -- CUT #34 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 104273,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #35 Behemoth (Anchor End (Idle))
        {
            frame = 104723,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #36 Juggernaut (Anchor End (Idle))
        {
            frame = 105773,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 29837 combat",
                "turbobarcam_script_select_unit 29837",
            }
        },

        -- CUT #37 Behemoth (Pre-Pause)
        {
            frame = 107043,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 2973 combat",
                "turbobarcam_script_select_unit 2973",
            }
        },

        -- CUT #38 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 107543,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #39 Behemoth (Anchor End (Idle))
        {
            frame = 108273,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #40 Mammoth (Pre-Pause (Switching to Neighbor))
        {
            frame = 108373,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 8128 combat",
                "turbobarcam_script_select_unit 8128",
            }
        },

        -- CUT #41 Juggernaut (Pre-Pause (Switching to Neighbor))
        {
            frame = 110063,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17676 combat",
                "turbobarcam_script_select_unit 17676",
            }
        },

        -- CUT #42 Mammoth (Anchor End (Idle))
        {
            frame = 110293,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 10335 combat",
                "turbobarcam_script_select_unit 10335",
            }
        },

        -- CUT #43 Behemoth (Pre-Pause (Switching to Neighbor))
        {
            frame = 112533,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 25442 combat",
                "turbobarcam_script_select_unit 25442",
            }
        },

        -- CUT #44 Behemoth (Anchor End (Idle))
        {
            frame = 113453,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 13365 combat",
                "turbobarcam_script_select_unit 13365",
            }
        },

        -- CUT #45 Behemoth (Anchor End (Idle))
        {
            frame = 114383,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 24420 combat",
                "turbobarcam_script_select_unit 24420",
            }
        },

        -- CUT #46 Behemoth (Pre-Pause)
        {
            frame = 115643,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 4401 combat",
                "turbobarcam_script_select_unit 4401",
            }
        },

        -- CUT #47 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 116633,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #48 Behemoth (Pre-Pause (Switching to Neighbor))
        {
            frame = 117353,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #49 Behemoth (Anchor End (Idle))
        {
            frame = 117573,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 8891 combat",
                "turbobarcam_script_select_unit 8891",
            }
        },

        -- CUT #50 Behemoth (Anchor End (Idle))
        {
            frame = 118393,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 13365 combat",
                "turbobarcam_script_select_unit 13365",
            }
        },

        -- CUT #51 Behemoth (Anchor End (Idle))
        {
            frame = 122833,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 12082 combat",
                "turbobarcam_script_select_unit 12082",
            }
        },

        -- CUT #52 Vanguard (Anchor End (Idle))
        {
            frame = 127623,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 1249 combat",
                "turbobarcam_script_select_unit 1249",
            }
        },

        -- CUT #53 Behemoth (Pre-Pause)
        {
            frame = 128453,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 13317 combat",
                "turbobarcam_script_select_unit 13317",
            }
        },

        -- CUT #54 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 129403,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #55 Behemoth (Pre-Pause)
        {
            frame = 129943,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #56 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 130743,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #57 Behemoth (Pre-Pause)
        {
            frame = 131463,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #58 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 131813,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #59 Behemoth (Anchor End (Idle))
        {
            frame = 132173,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #60 Behemoth (Anchor End (Idle))
        {
            frame = 132863,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 8891 combat",
                "turbobarcam_script_select_unit 8891",
            }
        },

        -- CUT #61 Behemoth (Pre-Pause (Switching to Neighbor))
        {
            frame = 133403,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 12082 combat",
                "turbobarcam_script_select_unit 12082",
            }
        },

        -- CUT #62 Behemoth (Pre-Pause)
        {
            frame = 134153,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17784 combat",
                "turbobarcam_script_select_unit 17784",
            }
        },

        -- CUT #63 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 134383,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #64 Behemoth (Anchor End (Idle))
        {
            frame = 135063,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #65 Behemoth (Anchor End (Idle))
        {
            frame = 135813,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 12082 combat",
                "turbobarcam_script_select_unit 12082",
            }
        },

        -- CUT #66 Mammoth (Pre-Pause)
        {
            frame = 138693,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 13964 combat",
                "turbobarcam_script_select_unit 13964",
            }
        },

        -- CUT #67 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 140133,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #68 Mammoth (Pre-Pause)
        {
            frame = 140493,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #69 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 140533,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #70 Mammoth (Anchor End (Idle))
        {
            frame = 141033,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #71 Behemoth (Anchor End (Idle))
        {
            frame = 142223,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 4401 combat",
                "turbobarcam_script_select_unit 4401",
            }
        },

        -- CUT #72 Behemoth (Anchor End (Idle))
        {
            frame = 146733,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 27321 combat",
                "turbobarcam_script_select_unit 27321",
            }
        },

        -- CUT #73 Behemoth (Anchor End (Idle))
        {
            frame = 147633,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 12841 combat",
                "turbobarcam_script_select_unit 12841",
            }
        },

        -- CUT #74 Behemoth (Anchor End (Idle))
        {
            frame = 148723,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 25731 combat",
                "turbobarcam_script_select_unit 25731",
            }
        },

        -- CUT #75 Behemoth (Pre-Pause)
        {
            frame = 151513,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 23243 combat",
                "turbobarcam_script_select_unit 23243",
            }
        },

        -- CUT #76 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 152963,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #77 Behemoth (Anchor End (Idle))
        {
            frame = 153653,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #78 Behemoth (Anchor End (Idle))
        {
            frame = 153763,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 13365 combat",
                "turbobarcam_script_select_unit 13365",
            }
        },

        -- CUT #79 Behemoth (Pre-Pause)
        {
            frame = 155403,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17164 combat",
                "turbobarcam_script_select_unit 17164",
            }
        },

        -- CUT #80 Fast Forward (Skipping Long Pause) [FF]
        {
            frame = 156093,
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #81 Behemoth (Anchor End (Idle))
        {
            frame = 156873,
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #82 Behemoth (Anchor End (Idle))
        {
            frame = 158093,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 23243 combat",
                "turbobarcam_script_select_unit 23243",
            }
        },

        -- CUT #83 Behemoth (Anchor End (Idle))
        {
            frame = 159003,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 10444 combat",
                "turbobarcam_script_select_unit 10444",
            }
        },
    }
}
