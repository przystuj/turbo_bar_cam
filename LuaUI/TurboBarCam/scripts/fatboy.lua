-- this is an example script which I used for this replay https://bar-rts.com/replays/bb936469494e23ac3618b99110f57e4d

return {
    {
        frame = "5",
        --commands = "skip f12700"
        commands = "skip f13135"
    },

    {
        frame = "5000",
        commands = {
            "turbobarcam_anchor_load fatboy",
            "specteam 1",
            "togglelos",
            "turbobarcam_track_projectiles 9803", -- tacnuke
            "turbobarcam_track_projectiles 2099", -- tzar
            "turbobarcam_script_toggle_music",
            "option notifications_spoken 0",
        }
    },


    -- commander boom
    --{
    --    frame = "12710",
    --    commands = "turbobarcam_anchor_focus 3 snap"
    --},
    --{
    --    frame = "+5",
    --    commands = {
    --        "turbobarcam_smoothing position 25",
    --        "turbobarcam_smoothing rotation 3",
    --        "turbobarcam_anchor_focus 4"
    --    }
    --},
    --{
    --    frame = "12944",
    --    commands = {
    --        "turbobarcam_smoothing position 35",
    --        "turbobarcam_anchor_focus 12"
    --    }
    --},
    --{
    --    frame = "13135",
    --    commands = {
    --        "turbobarcam_stop_tracking",
    --        "turbobarcam_smoothing reset",
    --        --"skip f14340"
    --    }
    --},


    -- random fights
    {
        frame = "13145",
        commands = "turbobarcam_anchor_focus 13 snap"
    },
    {
        frame = "+5",
        commands = "turbobarcam_anchor_focus 14"
    },
    {
        frame = "13242",
        commands = "turbobarcam_script_show_players_list"
    },
    {
        frame = "13449",
        commands = "turbobarcam_stop_tracking"
    },

    {
        frame = "+10",
        commands = "turbobarcam_anchor_focus 15 snap"
    },
    {
        frame = "+5",
        commands = "turbobarcam_anchor_focus 16"
    },
    {
        frame = "13613",
        commands = "turbobarcam_script_show_players_list"
    },
    {
        frame = "+300",
        commands = { "turbobarcam_stop_tracking" }
    },



    -- fatboy fly

    {
        frame = "13940",
        commands = { "turbobarcam_anchor_focus 18 snap" }
    },
    {
        frame = "+5",
        commands = { "turbobarcam_anchor_focus 17" }
    },
    {
        frame = "14281",
        commands = { "turbobarcam_anchor_focus 19" }
    },




    --{
    --    frame = "14350",
    --    commands = { "turbobarcam_anchor_focus 8 snap" }
    --},
    --{
    --    frame = "+3",
    --    commands = {
    --        "turbobarcam_smoothing position 20",
    --        "turbobarcam_smoothing rotation 4",
    --        "turbobarcam_anchor_focus 11"
    --    }
    --},
    --{
    --    frame = "14639",
    --    commands = {
    --        "turbobarcam_stop_tracking",
    --        "turbobarcam_smoothing reset",
    --    }
    --},


    -- fatboy start
    {
        frame = "14640",
        commands = {
            "turbobarcam_anchor_focus 5 snap",
            "turbobarcam_smoothing position 5",
        }
    },
    {
        frame = "14645",
        commands = "turbobarcam_anchor_focus 6"
    },
    {
        frame = "14795",
        commands = {
            "turbobarcam_smoothing reset",
            "turbobarcam_toggle_unit_follow_camera 20559 combat",
            "turbobarcam_script_select_unit 20559",
        }
    },


    {
        frame = "20131",
        commands = {
            "turbobarcam_script_play_track music/original/warlow/Ryan Krause - Retribution.ogg"
        }
    },




    -- abduction attempt
    {
        frame = "21729",
        commands = {
            "turbobarcam_unit_follow_set_fixed_look_target UNIT 573",
            "turbobarcam_unit_follow_adjust_params temp;WEAPON.FORWARD,20;WEAPON.SIDE,190",
        }
    },
    {
        frame = "21877",
        commands = { "turbobarcam_unit_follow_clear_fixed_look_point", "turbobarcam_reload_settings" }
    },


    {
        frame = "29388",
        commands = "setspeed 7"
    },
    {
        frame = "31496",
        commands = "setspeed 1"
    },


    -- commander pick up
    {
        frame = "32699",
        commands = "turbobarcam_smoothing position 10"
    },
    {
        frame = "32700",
        commands = "turbobarcam_unit_follow_adjust_params temp;WEAPON.FORWARD,-245"
    },
    {
        frame = "32810",
        commands = "turbobarcam_reload_settings"
    },
    {
        frame = "32830",
        commands = "turbobarcam_smoothing reset"
    },


    -- 34955 - tzar
    -- look at projectile
    {
        frame = "34893",
        commands = "turbobarcam_unit_follow_set_fixed_look_target PROJECTILE 10826"
    },
    {
        frame = "34965",
        commands = { "turbobarcam_smoothing rotation 0.5", "turbobarcam_unit_follow_set_fixed_look_target UNIT 2099" }
    },
    {
        frame = "+30",
        commands = { "turbobarcam_smoothing rotation 3" }
    },
    {
        frame = "35020",
        commands = "turbobarcam_unit_follow_clear_fixed_look_point"
    },
    {
        frame = "+60",
        commands = { "turbobarcam_smoothing reset" }
    },


    -- commander kill
    {
        frame = "36530",
        commands = { "turbobarcam_smoothing position 0.5", "turbobarcam_projectile_camera_follow" }
    },
    {
        frame = "36545",
        commands = { "turbobarcam_smoothing position 10" }
    },
    {
        frame = "36657",
        commands = { "turbobarcam_smoothing reset" }
    },
    {
        frame = "36660",
        commands = { "turbobarcam_projectile_camera_follow" }
    },



    {
        frame = "37267",
        commands = {
            "turbobarcam_script_play_track music/original/warhigh/Ryan Krause - Xavier.ogg"
        }
    },


    -- 40261 - tac nuke
    {
        frame = "40232",
        commands = "turbobarcam_unit_follow_set_fixed_look_target PROJECTILE 709"
    },
    {
        frame = "40268",
        commands = "turbobarcam_unit_follow_clear_fixed_look_point"
    },


    -- 41318 bombowce

    {
        frame = "41320",
        commands = "turbobarcam_unit_follow_set_fixed_look_target UNIT 13922"
    },
    {
        frame = "41730",
        commands = { "turbobarcam_smoothing rotation 10", "turbobarcam_unit_follow_clear_fixed_look_point" }
    },
    {
        frame = "+10",
        commands = { "turbobarcam_smoothing reset" }
    },


    -- afus
    {
        frame = "42364",
        commands = { "turbobarcam_unit_follow_set_fixed_look_target UNIT 325", "turbobarcam_unit_follow_adjust_params temp;WEAPON.FORWARD,-50;WEAPON.SIDE,-165" }
    },
    {
        frame = "42491",
        commands = { "turbobarcam_unit_follow_clear_fixed_look_point", "turbobarcam_reload_settings" }
    },


    -- dgun
    {
        frame = "42580",
        commands = { "turbobarcam_unit_follow_set_fixed_look_target UNIT 5748", "turbobarcam_unit_follow_adjust_params temp;WEAPON.FORWARD,-50;WEAPON.SIDE,-165" }
    },
    {
        frame = "42827",
        commands = {
            "turbobarcam_smoothing rotation 0.5",
            "turbobarcam_smoothing position 0.5",
            "turbobarcam_unit_follow_set_fixed_look_target UNIT 27791"
        }
    },
    {
        frame = "42840",
        commands = {
            "turbobarcam_smoothing reset",
            "turbobarcam_smoothing position 15",
            "turbobarcam_orbit_toggle",
        }
    },



    -- outro
    {
        frame = "42846",
        commands = { "turbobarcam_smoothing position 60" , "turbobarcam_smoothing rotation 10"}
    },
    {
        frame = "42848",
        commands = "turbobarcam_anchor_focus 1"
    },

    {
        frame = "43024",
        commands = { "turbobarcam_smoothing position 90", "turbobarcam_anchor_focus 2" }
    },

    {
        frame = "43060",
        commands = "turbobarcam_script_show_players_list"
    },
    {
        frame = "43300",
        commands = "turbobarcam_script_show_players_list B"
    },
    {
        frame = "43420",
        commands = "turbobarcam_script_show_players_list"
    },


    {
        frame = "60000",
        commands = "dummy"
    },
}
