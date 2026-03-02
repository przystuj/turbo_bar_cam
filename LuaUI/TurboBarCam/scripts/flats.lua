return {
    metadata = {
        replayName = "2025-11-08_21-35-27-907_Flats and Forests v2_2025.04.08",
        version = 5,
    },
    steps = {

        -- STEP #01 Init
        {
            frame = 0,
            label = "Init",
            commands = {
                "skip f24950",
                "specteam 4",
                "option notifications_spoken 0",
            }
        },
        {
            frame = 20000,
            commands = {
                "togglelos",
                "turbobarcam_anchor_focus 3 snap",
            }
        },
        {
            frame = 24960,
            commands = {
                "turbobarcam_smoothing position 90",
                "turbobarcam_smoothing rotation 0",
                "turbobarcam_anchor_focus 4"
            }
        },
        {
            frame = 25050,
            commands = "turbobarcam_script_show_players_list"
        },
        {
            frame = 25280,
            commands = "turbobarcam_script_show_players_list"
        },

        -- STEP #02 Tiger
        {
            frame = 25313,
            label = "Tiger",
            commands = {
                "turbobarcam_smoothing position 6",
                "turbobarcam_smoothing rotation 6",
                "turbobarcam_toggle_unit_follow_camera 21711 combat",
                "turbobarcam_script_select_unit_team 21711",
            }
        },
        {
            frame = "+150",
            label = "Tiger",
            commands = {
                "turbobarcam_smoothing reset",
            }
        },
        {
            frame = 29741,
            label = "Tiger - FF",
            commands = {
                "setspeed 7",
            }
        },
        {
            frame = 30335,
            label = "Tiger - FF End",
            commands = {
                "setspeed 1",
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
            frame = 35970,
            label = "Fatboy",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 15749 combat",
            }
        },
        {
            frame = "+15",
            label = "Fatboy",
            commands = {
                "turbobarcam_script_select_unit_team 15749",
            }
        },

        -- STEP #07 Banisher
        {
            frame = 38876,
            label = "Banisher",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17166 combat",
            }
        },
        {
            frame = "+15",
            label = "Banisher",
            commands = {
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
            frame = 42399,
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
            frame = 51220,
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
            frame = 58874,
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

        -- STEP #18 Hailstorm
        {
            frame = 61602,
            label = "anchor",
            commands = {
                "turbobarcam_smoothing position 40",
                "turbobarcam_smoothing rotation 3",
                "setspeed 2",
            }
        },
        {
            frame = 61610,
            label = "anchor",
            commands = {
                "turbobarcam_anchor_focus 2",
            }
        },
        {
            frame = 62700,
            label = "Hailstorm",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 19629 combat",
                "turbobarcam_script_select_unit_team 19629",
                "setspeed 1",
            }
        },

        -- STEP #19 Banisher
        {
            frame = 64375,
            label = "Banisher",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 11966 combat",
                "turbobarcam_script_select_unit_team 11966",
            }
        },

        {
            frame = 65067,
            label = "anchor",
            commands = {
                "turbobarcam_smoothing position 40",
                "turbobarcam_smoothing rotation 2",
                "setspeed 2",
            }
        },

        {
            frame = 65075,
            label = "anchor",
            commands = {
                "turbobarcam_anchor_focus 1",
            }
        },


        -- STEP #20 Catapult
        {
            frame = 65967,
            label = "Catapult",
            commands = {
                "setspeed 1",
                "turbobarcam_smoothing position 6",
                "turbobarcam_smoothing rotation 6",
                "turbobarcam_toggle_unit_follow_camera 16673 combat",
                "turbobarcam_script_select_unit_team 16673",
            }
        },
        {
            frame = "+150",
            label = "Catapult",
            commands = {
                "turbobarcam_smoothing reset",
            }
        },

        -- STEP #22 Shiva
        {
            frame = 73353,
            label = "Shiva",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 22932 combat",
                "turbobarcam_script_select_unit_team 22932",
            }
        },

        -- STEP #23 Thor
        {
            frame = 74468,
            label = "Thor",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 7788 combat",
                "turbobarcam_script_select_unit_team 7788",
            }
        },

        -- STEP #24 Thor
        {
            frame = 76355,
            label = "Thor",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 16990 combat",
                "turbobarcam_script_select_unit_team 16990",
            }
        },

        -- STEP #25 Thor
        {
            frame = 78955,
            label = "Thor",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 10003 combat",
                "turbobarcam_script_select_unit_team 10003",
            }
        },

        -- STEP #26 Banisher
        {
            frame = 79549,
            label = "Banisher",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 27261 combat",
                "turbobarcam_script_select_unit_team 27261",
            }
        },

        -- STEP #27 Shiva
        {
            frame = 82241,
            label = "Shiva",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 16015 combat",
                "turbobarcam_script_select_unit_team 16015",
            }
        },

        -- STEP #28 Juggernaut
        {
            frame = 83180,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 1515 combat",
                "turbobarcam_script_select_unit_team 1515",
            }
        },


        {
            frame = 87880,
            label = "slow down game",
            commands = {
                "setspeed 0.7",
                "turbobarcam_script_toggle_music",
            }
        },

        -- STEP #29 Juggernaut
        {
            frame = 87900,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 14621 combat",
                "turbobarcam_script_select_unit_team 14621",
            }
        },


        -- STEP #30 Juggernaut
        {
            frame = 99484,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 10291 combat",
                "turbobarcam_script_select_unit_team 10291",
            }
        },

        -- STEP #31 Juggernaut
        {
            frame = 105066,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 25833 combat",
                "turbobarcam_script_select_unit_team 25833",
            }
        },



        -- NUKE CAM 64:40
        {
            frame = 116518,
            label = "Nuke cam 64:40",
            commands = {
                "turbobarcam_smoothing position 10",
                "turbobarcam_position_override y 1000",
                "turbobarcam_unit_follow_set_fixed_look_target PROJECTILE 12241",
            }
        },

        -- STEP #32 Juggernaut
        {
            frame = 116596,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing position 20",
                "turbobarcam_smoothing rotation 5",
                "turbobarcam_position_override reset",
                "turbobarcam_toggle_unit_follow_camera 23841 combat",
                "turbobarcam_script_select_unit_team 23841",
            }
        },

        {
            frame = 116686,
            label = "Clear nuke cam",
            commands = {
                "turbobarcam_smoothing position 6",
                "turbobarcam_unit_follow_clear_fixed_look_point",
            }
        },

        {
            frame = "+120",
            label = "Clear nuke cam",
            commands = {
                "turbobarcam_smoothing reset",
            }
        },










        -- NUKE CAM 66:55
        {
            frame = 120250,
            label = "Nuke cam 66:55",
            commands = {
                "turbobarcam_unit_follow_set_fixed_look_target PROJECTILE 13605",
            }
        },
        {
            frame = 120351,
            label = "Slow for FPS",
            commands = {
                "setspeed 0.25",
            }
        },
        {
            frame = 120432,
            label = "Slow for FPS",
            commands = {
                "setspeed 0.7",
            }
        },
        {
            frame = 120600,
            label = "Clear nuke cam",
            commands = {
                "turbobarcam_unit_follow_clear_fixed_look_point",
            }
        },




        -- STEP #33 Juggernaut
        {
            frame = 123968,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 15136 combat",
                "turbobarcam_script_select_unit_team 15136",
            }
        },

        -- STEP #34 Juggernaut
        {
            frame = 128490,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 313 combat",
                "turbobarcam_script_select_unit_team 313",
            }
        },






        --- Nuke cam 74:00
        {
            frame = 133350,
            label = "Nuke cam 74:00",
            commands = {
                "turbobarcam_position_override y 800",
                "turbobarcam_unit_follow_set_fixed_look_target PROJECTILE 15844",
            }
        },
        {
            frame = 133900,
            label = "Clear nuke cam",
            commands = {
                "turbobarcam_position_override reset",
                "turbobarcam_unit_follow_clear_fixed_look_point",
            }
        },





        -- STEP #35 Behemoth
        {
            frame = 133940,
            label = "Behemoth",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 18503 combat",
                "turbobarcam_script_select_unit_team 18503",
            }
        },





        --- Nuke cam 78:00
        {
            frame = 141070,
            commands = {
                "turbobarcam_position_override y 800",
            }
        },
        {
            frame = 141079,
            label = "Nuke cam 78:00",
            commands = {
                "turbobarcam_unit_follow_set_fixed_look_target PROJECTILE 7871",
            }
        },
        {
            frame = 141370,
            commands = {
                "turbobarcam_position_override reset",
            }
        },
        {
            frame = 141400,
            label = "Clear nuke cam",
            commands = {
                "turbobarcam_unit_follow_clear_fixed_look_point",
            }
        },






        -- STEP #36 Behemoth
        {
            frame = 142632,
            label = "Behemoth",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 2013 combat",
                "turbobarcam_script_select_unit_team 2013",
            }
        },

        -- STEP #37 Behemoth
        {
            frame = 144260,
            label = "Behemoth",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 12841 combat",
                "turbobarcam_script_select_unit_team 12841",
            }
        },





        {
            frame = 145965,
            label = "Slow for FPS",
            commands = {
                "setspeed 0.25",
            }
        },
        {
            frame = 145970,
            label = "Nuke cam",
            commands = {
                "turbobarcam_smoothing position 30",
                "turbobarcam_position_override y 3000 z -4000",
                "turbobarcam_unit_follow_set_fixed_look_target PROJECTILE 15001",
            }
        },
        {
            frame = 146150,
            label = "Slow for FPS",
            commands = {
                "setspeed 0.7",
            }
        },

        {
            frame = 146200,
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_position_override reset",
            }
        },
        {
            frame = 146260,
            label = "Clear nuke cam",
            commands = {
                "turbobarcam_unit_follow_clear_fixed_look_point",
            }
        },





        -- STEP #38 Juggernaut
        {
            frame = 148768,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 20425 combat",
                "turbobarcam_script_select_unit_team 20425",
            }
        },
        {
            frame = 151298,
            label = "Nuke cam",
            commands = {
                "turbobarcam_unit_follow_set_fixed_look_target PROJECTILE 15846",
            }
        },

        {
            frame = 151548,
            label = "Nuke cam",
            commands = {
                "turbobarcam_unit_follow_set_fixed_look_target PROJECTILE 16108",
            }
        },

        {
            frame = 151780,
            commands = {
                "turbobarcam_smoothing position 30",
                "turbobarcam_position_override y 800 z 500",
            }
        },

        {
            frame = 151840,
            label = "Slow for FPS",
            commands = {
                "setspeed 0.25",
            }
        },
        {
            frame = 152027,
            label = "Slow for FPS",
            commands = {
                "setspeed 0.7",
            }
        },

        {
            frame = 152050,
            commands = {
                "turbobarcam_position_override reset",
            }
        },

        {
            frame = 152083,
            label = "Clear nuke cam",
            commands = {
                "turbobarcam_unit_follow_clear_fixed_look_point",
            }
        },

        {
            frame = "+60",
            label = "Clear nuke cam",
            commands = {
                "turbobarcam_smoothing reset",
            }
        },

        -- STEP #39 Juggernaut
        {
            frame = 152258,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 18444 combat",
                "turbobarcam_script_select_unit_team 18444",
            }
        },

        -- STEP #40 Juggernaut
        {
            frame = 154745,
            label = "Juggernaut",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 10149 combat",
                "turbobarcam_script_select_unit_team 10149",
            }
        },




        -- NUKE CAM
        {
            frame = 156595,
            label = "Nuke cam",
            commands = {
                "turbobarcam_unit_follow_set_fixed_look_target PROJECTILE 16150",
                "setspeed 0.25",
            }
        },
        {
            frame = 156820,
            label = "Clear nuke cam",
            commands = {
                "setspeed 1",
                "turbobarcam_unit_follow_clear_fixed_look_point",
            }
        },



        -- STEP #41 Behemoth
        {
            frame = 158114,
            label = "Behemoth",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17264 combat",
                "turbobarcam_script_select_unit_team 17264",
            }
        },

        -- STEP #42 New Block
        {
            frame = 158779,
            label = "Ending",
            commands = {
                "turbobarcam_smoothing position 40",
                "turbobarcam_smoothing rotation 40",
                "turbobarcam_unit_follow_toggle_combat_mode",
            }
        },
        {
            frame = 158790,
            commands = {
                "turbobarcam_position_override y 3000 z -8000",
            }
        },
        {
            frame = 159550,
            commands = {
                "turbobarcam_position_override reset",
            }
        },
    }
}
