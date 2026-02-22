return {
    metadata = {
        replayName = "2025-11-08_21-35-27-907_Flats and Forests v2_2025.04.08",
        version = 4,
    },
    steps = {

        -- STEP #01 Init
        {
            frame = 0,
            label = "Init",
            commands = {
                "skip f25313",
                "togglelos",
            }
        },

        -- STEP #02 Tiger
        {
            frame = 25313,
            label = "Tiger",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 21711 combat",
                "turbobarcam_script_select_unit_team 21711",
            }
        },
        {
            frame = 29741,
            label = "Tiger - FF",
            commands = {
                commands = "setspeed 7"
            }
        },
        {
            frame = 303356,
            label = "Tiger - FF End",
            commands = {
                commands = "setspeed 1"
            }
        },

        -- STEP #03 Tiger
        {
            frame = 30930,
            label = "Tiger",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 13882 combat",
                "turbobarcam_script_select_unit_team 13882",
            }
        },

        -- STEP #04 Tiger
        {
            frame = 35317,
            label = "Tiger",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 9545 combat",
                "turbobarcam_script_select_unit_team 9545",
            }
        },

        -- STEP #05 Banisher
        {
            frame = 35950,
            label = "Banisher",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 4720 combat",
                "turbobarcam_script_select_unit_team 4720",
            }
        },

        -- STEP #06 Fatboy
        {
            frame = 35952,
            label = "Fatboy",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 15749 combat",
                "turbobarcam_script_select_unit_team 15749",
            }
        },

        -- STEP #07 Banisher
        {
            frame = 38846,
            label = "Banisher",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17166 combat",
                "turbobarcam_script_select_unit_team 17166",
            }
        },

        -- STEP #08 Tzar
        {
            frame = 39776,
            label = "Tzar",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 26990 combat",
                "turbobarcam_script_select_unit_team 26990",
            }
        },

        -- STEP #09 Banisher
        {
            frame = 41955,
            label = "Banisher",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 9997 combat",
                "turbobarcam_script_select_unit_team 9997",
            }
        },

        -- STEP #10 Shiva
        {
            frame = 44238,
            label = "Shiva",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 7984 combat",
                "turbobarcam_script_select_unit_team 7984",
            }
        },

        -- STEP #11 Shiva
        {
            frame = 46082,
            label = "Shiva",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 15010 combat",
                "turbobarcam_script_select_unit_team 15010",
            }
        },

        -- STEP #12 Shiva
        {
            frame = 48965,
            label = "Shiva",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 26242 combat",
                "turbobarcam_script_select_unit_team 26242",
            }
        },

        -- STEP #13 Shiva
        {
            frame = 52068,
            label = "Shiva",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 11853 combat",
                "turbobarcam_script_select_unit_team 11853",
            }
        },

        -- STEP #14 Shiva
        {
            frame = 53024,
            label = "Shiva",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 24398 combat",
                "turbobarcam_script_select_unit_team 24398",
            }
        },

        -- STEP #15 Shiva
        {
            frame = 54523,
            label = "Shiva",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 9002 combat",
                "turbobarcam_script_select_unit_team 9002",
            }
        },

        -- STEP #16 Shiva
        {
            frame = 58739,
            label = "Shiva",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 10964 combat",
                "turbobarcam_script_select_unit_team 10964",
            }
        },

        -- STEP #17 Karganeth
        {
            frame = 60501,
            label = "Karganeth",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 29458 combat",
                "turbobarcam_script_select_unit_team 29458",
            }
        },

        -- STEP #18 Demon
        {
            frame = 61439,
            label = "Demon",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 13421 combat",
                "turbobarcam_script_select_unit_team 13421",
            }
        },

        -- STEP #19 Hailstorm
        {
            frame = 62628,
            label = "Hailstorm",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 19629 combat",
                "turbobarcam_script_select_unit_team 19629",
            }
        },

        -- STEP #20 Banisher
        {
            frame = 64319,
            label = "Banisher",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 11966 combat",
                "turbobarcam_script_select_unit_team 11966",
            }
        },

        -- STEP #21 Catapult
        {
            frame = 65288,
            label = "Catapult",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 3652 combat",
                "turbobarcam_script_select_unit_team 3652",
            }
        },

        -- STEP #22 Catapult
        {
            frame = 66094,
            label = "Catapult",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 16673 combat",
                "turbobarcam_script_select_unit_team 16673",
            }
        },

        -- STEP #23 Shiva
        {
            frame = 73309,
            label = "Shiva",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 22932 combat",
                "turbobarcam_script_select_unit_team 22932",
            }
        },

        -- STEP #24 Thor
        {
            frame = 74410,
            label = "Thor",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 7788 combat",
                "turbobarcam_script_select_unit_team 7788",
            }
        },

        -- STEP #25 Thor
        {
            frame = 76355,
            label = "Thor",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 16990 combat",
                "turbobarcam_script_select_unit_team 16990",
            }
        },

        -- STEP #26 Thor
        {
            frame = 78955,
            label = "Thor",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 10003 combat",
                "turbobarcam_script_select_unit_team 10003",
            }
        },

        -- STEP #27 Banisher
        {
            frame = 79549,
            label = "Banisher",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 27261 combat",
                "turbobarcam_script_select_unit_team 27261",
            }
        },

        -- STEP #28 Demon
        {
            frame = 80771,
            label = "Demon",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 8646 combat",
                "turbobarcam_script_select_unit_team 8646",
            }
        },

        -- STEP #29 Juggernaut
        {
            frame = 84610,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 1515 combat",
                "turbobarcam_script_select_unit_team 1515",
            }
        },

        -- STEP #30 Juggernaut
        {
            frame = 87900,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 14621 combat",
                "turbobarcam_script_select_unit_team 14621",
            }
        },

        -- STEP #31 Juggernaut
        {
            frame = 99484,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 10291 combat",
                "turbobarcam_script_select_unit_team 10291",
            }
        },

        -- STEP #32 Juggernaut
        {
            frame = 106484,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 25117 combat",
                "turbobarcam_script_select_unit_team 25117",
            }
        },

        {
            frame = 116574,
            label = "Nuke cam",
            commands = {
                "turbobarcam_unit_follow_set_fixed_look_target PROJECTILE 12241",
            }
        },

        {
            frame = 116739,
            label = "Clear nuke cam",
            commands = {
                "turbobarcam_unit_follow_clear_fixed_look_point",
            }
        },

        -- STEP #33 Juggernaut
        {
            frame = 118283,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 23841 combat",
                "turbobarcam_script_select_unit_team 23841",
            }
        },

        {
            frame = 120308,
            label = "Nuke cam",
            commands = {
                "turbobarcam_unit_follow_set_fixed_look_target PROJECTILE 4534",
            }
        },

        {
            frame = 120500,
            label = "Clear nuke cam",
            commands = {
                "turbobarcam_unit_follow_clear_fixed_look_point",
            }
        },

        -- STEP #34 Juggernaut
        {
            frame = 123968,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 15136 combat",
                "turbobarcam_script_select_unit_team 15136",
            }
        },

        -- STEP #35 Juggernaut
        {
            frame = 128490,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 313 combat",
                "turbobarcam_script_select_unit_team 313",
            }
        },

        {
            frame = 133432,
            label = "Nuke cam",
            commands = {
                "turbobarcam_unit_follow_set_fixed_look_target PROJECTILE 15023",
            }
        },

        {
            frame = 133722,
            label = "Clear nuke cam",
            commands = {
                "turbobarcam_unit_follow_clear_fixed_look_point",
            }
        },

        -- STEP #36 Behemoth
        {
            frame = 133752,
            label = "Behemoth",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 18503 combat",
                "turbobarcam_script_select_unit_team 18503",
            }
        },

        -- STEP #37 Behemoth
        {
            frame = 142632,
            label = "Behemoth",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 2013 combat",
                "turbobarcam_script_select_unit_team 2013",
            }
        },

        -- STEP #38 Behemoth
        {
            frame = 144260,
            label = "Behemoth",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 12841 combat",
                "turbobarcam_script_select_unit_team 12841",
            }
        },

        -- STEP #39 Juggernaut
        {
            frame = 148768,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 18887 combat",
                "turbobarcam_script_select_unit_team 18887",
            }
        },

        {
            frame = 149102,
            commands = {
                "turbobarcam_script_play_track music/original/warhigh/Nathan Sharples - Crashing Down.ogg"
            }
        },

        {
            frame = 151895,
            label = "Nuke cam",
            commands = {
                "turbobarcam_unit_follow_set_fixed_look_target PROJECTILE 16108",
            }
        },

        {
            frame = 152083,
            label = "Clear nuke cam",
            commands = {
                "turbobarcam_unit_follow_clear_fixed_look_point",
            }
        },

        -- STEP #40 Juggernaut
        {
            frame = 152258,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 18444 combat",
                "turbobarcam_script_select_unit_team 18444",
            }
        },

        -- STEP #41 Juggernaut
        {
            frame = 156609,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 10149 combat",
                "turbobarcam_script_select_unit_team 10149",
            }
        },

        -- STEP #42 Behemoth
        {
            frame = 158114,
            label = "Behemoth",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17264 combat",
                "turbobarcam_script_select_unit_team 17264",
            }
        },

        {
            frame = 158779,
            label = "Behemoth",
            commands = {
                "turbobarcam_smoothing position 30",
                "turbobarcam_smoothing rotation 30",
            }
        },
        {
            frame = 158790,
            commands = "turbobarcam_unit_follow_adjust_params temp;WEAPON.HEIGHT,2000"
        },
    }
}
