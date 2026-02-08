return {
    steps = {
        {
            frame = 30,
            commands = {
                "turbobarcam_anchor_focus 1 snap",
            }
        },
        {
            frame = 60,
            commands = {
                "skip f8110",
                "option notifications_spoken 0",
                "turbobarcam_anchor_focus 2",
            }
        },
        {
            frame = 400,
            commands = {
                "turbobarcam_script_play_track music/original/warlow/Ryan Krause - Ground Zero.ogg"
            }
        },

        {
            frame = 1000,
            commands = {
                "turbobarcam_script_show_players_list",
            }
        },

        {
            frame = 7000,
            commands = {
                "turbobarcam_script_show_players_list",
            }
        },

        -- CUT #01 Thug (Pre-Pause)
        {
            frame = 8000,
            commands = {
                "turbobarcam_smoothing reset",
                "togglelos",
                "turbobarcam_toggle_unit_follow_camera 14925 combat",
                --"turbobarcam_script_select_unit 14925",
            }
        },

        -- CUT #04 Thug (Anchor End (Idle))
        {
            frame = 9038,
            commands = {
                "turbobarcam_smoothing position 10",
                "turbobarcam_smoothing rotation 10",
                "turbobarcam_toggle_unit_follow_camera 9524 combat",
--                "turbobarcam_script_select_unit 9524",
            }
        },
        {
            frame = "+40",
            commands = {
                "turbobarcam_smoothing reset",
            }
        },

        -- CUT #05 Lasher (Swap to Better Unit)
        {
            frame = 10630,
            commands = {
                "turbobarcam_smoothing position 10",
                "turbobarcam_smoothing rotation 10",
                "turbobarcam_toggle_unit_follow_camera 30619 combat",
--                "turbobarcam_script_select_unit 30619",
            }
        },
        {
            frame = "+40",
            commands = {
                "turbobarcam_smoothing reset",
            }
        },

        -- CUT #06 Tzar (Anchor End (Idle))
        {
            frame = 12080,
            commands = {
                "turbobarcam_smoothing position 6",
                "turbobarcam_smoothing rotation 6",
                "turbobarcam_toggle_unit_follow_camera 9437 combat",
--                "turbobarcam_script_select_unit 9437",
            }
        },

        {
            frame = "+20",
            commands = {
                "turbobarcam_smoothing reset",
            }
        },

        -- CUT #07 Whistler (Swap to Better Unit)
        {
            frame = 14200,
            commands = {
                "turbobarcam_smoothing position 10",
                "turbobarcam_smoothing rotation 10",
                "turbobarcam_toggle_unit_follow_camera 18144 combat",
--                "turbobarcam_script_select_unit 18144",
            }
        },
        {
            frame = "+40",
            commands = {
                "turbobarcam_smoothing reset",
            }
        },
        {
            frame = 15300,
            commands = {
                "turbobarcam_smoothing rotation 3",
                "turbobarcam_smoothing position 5",
            }
        },

        -- CUT #08 Quaker (Pre-Pause)
        {
            frame = 15720,
            commands = {
                "turbobarcam_unit_follow_toggle_combat_mode",
            }
        },
        {
            frame = 15732,
            commands = {
                "turbobarcam_smoothing reset",
            }
        },
        {
            frame = 15794,
            commands = {
                "turbobarcam_smoothing position 5",
                "turbobarcam_smoothing rotation 5",
                "turbobarcam_toggle_unit_follow_camera 17965 combat",
--                "turbobarcam_script_select_unit 17965",
            }
        },
        {
            frame = "+40",
            commands = {
                "turbobarcam_smoothing reset",
            }
        },
        {
            frame = 22300,
            commands = {
                "turbobarcam_smoothing position 180",
                "turbobarcam_smoothing rotation 10",
                "option notifications_spoken 1",
                "turbobarcam_anchor_focus 3"
            }
        },
        {
            frame = "+60",
            commands = {
                "turbobarcam_script_show_players_list",
            }
        },
        {
            frame = "+180",
            commands = {
                "turbobarcam_script_show_players_list",
            }
        },

        {
            frame = 999999,
            commands = {
                "setspeed 1",
            }
        },
    }
}
