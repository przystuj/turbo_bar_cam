return {
    steps = {
        {
            frame = "30",
            commands = {
                "skip f50013" -- Start,
            }
        },

        -- CUT #01 Shiva (Anchor Start)
        {
            frame = "50013",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 26242 combat",
                "turbobarcam_script_select_unit 26242",
            }
        },

        -- CUT #02 Fast Forward (Gap) [FF]
        {
            frame = "51153",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #03 Catapult (New Anchor)
        {
            frame = "65203",
            commands = {
                "setspeed 1",
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 3652 combat",
                "turbobarcam_script_select_unit 3652",
            }
        },

        -- CUT #04 Fast Forward (Gap) [FF]
        {
            frame = "65803",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #05 Catapult (New Anchor)
        {
            frame = "66033",
            commands = {
                "setspeed 1",
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 16673 combat",
                "turbobarcam_script_select_unit 16673",
            }
        },

        -- CUT #06 Vanguard (Chain)
        {
            frame = "73983",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 27318 combat",
                "turbobarcam_script_select_unit 27318",
            }
        },

        -- CUT #07 Fast Forward (Gap) [FF]
        {
            frame = "78423",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #08 Shiva (New Anchor)
        {
            frame = "78883",
            commands = {
                "setspeed 1",
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 26242 combat",
                "turbobarcam_script_select_unit 26242",
            }
        },

        -- CUT #09 Shiva (Chain)
        {
            frame = "79813",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 8359 combat",
                "turbobarcam_script_select_unit 8359",
            }
        },

        -- CUT #10 Fast Forward (Gap) [FF]
        {
            frame = "80413",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #11 Juggernaut (New Anchor)
        {
            frame = "86063",
            commands = {
                "setspeed 1",
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 14289 combat",
                "turbobarcam_script_select_unit 14289",
            }
        },

        -- CUT #12 Fast Forward (Gap) [FF]
        {
            frame = "86753",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #13 Juggernaut (New Anchor)
        {
            frame = "88143",
            commands = {
                "setspeed 1",
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 20638 combat",
                "turbobarcam_script_select_unit 20638",
            }
        },

        -- CUT #14 Fast Forward (Gap) [FF]
        {
            frame = "89073",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #15 Wasp (New Anchor)
        {
            frame = "90393",
            commands = {
                "setspeed 1",
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 268 combat",
                "turbobarcam_script_select_unit 268",
            }
        },

        -- CUT #16 Fast Forward (Gap) [FF]
        {
            frame = "92463",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #17 Vanguard (New Anchor)
        {
            frame = "93053",
            commands = {
                "setspeed 1",
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 27318 combat",
                "turbobarcam_script_select_unit 27318",
            }
        },

        -- CUT #18 Fast Forward (Gap) [FF]
        {
            frame = "93653",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #19 Vanguard (New Anchor)
        {
            frame = "94763",
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #20 Fast Forward (Gap) [FF]
        {
            frame = "95573",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #21 Grunt (New Anchor)
        {
            frame = "96123",
            commands = {
                "setspeed 1",
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17000 combat",
                "turbobarcam_script_select_unit 17000",
            }
        },

        -- CUT #22 Shiva (Chain)
        {
            frame = "97023",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 8359 combat",
                "turbobarcam_script_select_unit 8359",
            }
        },

        -- CUT #23 Juggernaut (Chain)
        {
            frame = "98823",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 18324 combat",
                "turbobarcam_script_select_unit 18324",
            }
        },

        -- CUT #24 Behemoth (Chain)
        {
            frame = "99903",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 24420 combat",
                "turbobarcam_script_select_unit 24420",
            }
        },

        -- CUT #27 Mammoth (Chain)
        {
            frame = "104343",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 22012 combat",
                "turbobarcam_script_select_unit 22012",
            }
        },

        -- CUT #28 Fast Forward (Gap) [FF]
        {
            frame = "105633",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #29 Mammoth (New Anchor)
        {
            frame = "105863",
            commands = {
                "setspeed 1",
            }
        },

        -- CUT #30 Fast Forward (Gap) [FF]
        {
            frame = "108083",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #31 Mammoth (New Anchor)
        {
            frame = "108123",
            commands = {
                "setspeed 1",
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 8128 combat",
                "turbobarcam_script_select_unit 8128",
            }
        },

        -- CUT #32 Juggernaut (Chain)
        {
            frame = "110133",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17676 combat",
                "turbobarcam_script_select_unit 17676",
            }
        },

        -- CUT #33 Mammoth (Chain)
        {
            frame = "110343",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 2811 combat",
                "turbobarcam_script_select_unit 2811",
            }
        },

        -- CUT #34 Mammoth (Chain)
        {
            frame = "110613",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 8128 combat",
                "turbobarcam_script_select_unit 8128",
            }
        },

        -- CUT #35 Mammoth (Chain)
        {
            frame = "111453",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 23201 combat",
                "turbobarcam_script_select_unit 23201",
            }
        },

        -- CUT #36 Fast Forward (Gap) [FF]
        {
            frame = "111693",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #37 Behemoth (New Anchor)
        {
            frame = "111743",
            commands = {
                "setspeed 1",
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 4401 combat",
                "turbobarcam_script_select_unit 4401",
            }
        },

        -- CUT #38 Fast Forward (Gap) [FF]
        {
            frame = "112283",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #39 Behemoth (New Anchor)
        {
            frame = "112543",
            commands = {
                "setspeed 1",
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 25442 combat",
                "turbobarcam_script_select_unit 25442",
            }
        },

        -- CUT #40 Behemoth (Chain)
        {
            frame = "113503",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 13365 combat",
                "turbobarcam_script_select_unit 13365",
            }
        },

        -- CUT #41 Fast Forward (Gap) [FF]
        {
            frame = "113893",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #42 Behemoth (New Anchor)
        {
            frame = "114183",
            commands = {
                "setspeed 1",
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 24420 combat",
                "turbobarcam_script_select_unit 24420",
            }
        },

        -- CUT #43 Behemoth (Chain)
        {
            frame = "115713",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 25442 combat",
                "turbobarcam_script_select_unit 25442",
            }
        },

        -- CUT #44 Behemoth (Chain)
        {
            frame = "116193",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 4401 combat",
                "turbobarcam_script_select_unit 4401",
            }
        },

        -- CUT #45 Fast Forward (Gap) [FF]
        {
            frame = "116703",
            commands = {
                "setspeed 3",
            }
        },

        -- CUT #46 Vanguard (New Anchor)
        {
            frame = "117633",
            commands = {
                "setspeed 1",
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 1249 combat",
                "turbobarcam_script_select_unit 1249",
            }
        },

        -- CUT #47 Behemoth (Chain)
        {
            frame = "118263",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 27321 combat",
                "turbobarcam_script_select_unit 27321",
            }
        },

        -- CUT #48 Behemoth (Chain)
        {
            frame = "118443",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 13365 combat",
                "turbobarcam_script_select_unit 13365",
            }
        },

        -- CUT #50 Behemoth (Chain)
        {
            frame = "122883",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 11239 combat",
                "turbobarcam_script_select_unit 11239",
            }
        },

        -- CUT #51 Behemoth (Chain)
        {
            frame = "127323",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17264 combat",
                "turbobarcam_script_select_unit 17264",
            }
        },

        -- CUT #52 Vanguard (Chain)
        {
            frame = "127563",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 1249 combat",
                "turbobarcam_script_select_unit 1249",
            }
        },

        -- CUT #53 Behemoth (Chain)
        {
            frame = "128523",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17784 combat",
                "turbobarcam_script_select_unit 17784",
            }
        },

        -- CUT #54 Behemoth (Chain)
        {
            frame = "128883",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 27321 combat",
                "turbobarcam_script_select_unit 27321",
            }
        },

        -- CUT #55 Manticore (Chain)
        {
            frame = "129273",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 1207 combat",
                "turbobarcam_script_select_unit 1207",
            }
        },

        -- CUT #56 Vanguard (Chain)
        {
            frame = "130113",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 1249 combat",
                "turbobarcam_script_select_unit 1249",
            }
        },

        -- CUT #57 Behemoth (Chain)
        {
            frame = "130353",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17784 combat",
                "turbobarcam_script_select_unit 17784",
            }
        },

        -- CUT #58 Behemoth (Chain)
        {
            frame = "130773",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 25442 combat",
                "turbobarcam_script_select_unit 25442",
            }
        },

        -- CUT #59 Behemoth (Chain)
        {
            frame = "131073",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 8891 combat",
                "turbobarcam_script_select_unit 8891",
            }
        },

        -- CUT #60 Behemoth (Chain)
        {
            frame = "131673",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 4401 combat",
                "turbobarcam_script_select_unit 4401",
            }
        },

        -- CUT #61 Behemoth (Chain)
        {
            frame = "132273",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17784 combat",
                "turbobarcam_script_select_unit 17784",
            }
        },

        -- CUT #62 Behemoth (Chain)
        {
            frame = "132633",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 8891 combat",
                "turbobarcam_script_select_unit 8891",
            }
        },

        -- CUT #63 Behemoth (Chain)
        {
            frame = "133473",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 12082 combat",
                "turbobarcam_script_select_unit 12082",
            }
        },

        -- CUT #64 Behemoth (Chain)
        {
            frame = "134223",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17784 combat",
                "turbobarcam_script_select_unit 17784",
            }
        },

        -- CUT #65 Vanguard (Chain)
        {
            frame = "134433",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 1249 combat",
                "turbobarcam_script_select_unit 1249",
            }
        },

        -- CUT #66 Behemoth (Chain)
        {
            frame = "135303",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17264 combat",
                "turbobarcam_script_select_unit 17264",
            }
        },

        -- CUT #67 Behemoth (Chain)
        {
            frame = "136293",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 22311 combat",
                "turbobarcam_script_select_unit 22311",
            }
        },

        -- CUT #68 Behemoth (Chain)
        {
            frame = "136983",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 25442 combat",
                "turbobarcam_script_select_unit 25442",
            }
        },

        -- CUT #69 Behemoth (Chain)
        {
            frame = "137343",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 27321 combat",
                "turbobarcam_script_select_unit 27321",
            }
        },

        -- CUT #70 Behemoth (Chain)
        {
            frame = "137643",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 12082 combat",
                "turbobarcam_script_select_unit 12082",
            }
        },

        -- CUT #71 Mammoth (Chain)
        {
            frame = "138753",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 13964 combat",
                "turbobarcam_script_select_unit 13964",
            }
        },

        -- CUT #72 Behemoth (Chain)
        {
            frame = "139593",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17784 combat",
                "turbobarcam_script_select_unit 17784",
            }
        },

        -- CUT #73 Behemoth (Chain)
        {
            frame = "140403",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 22311 combat",
                "turbobarcam_script_select_unit 22311",
            }
        },

        -- CUT #74 Mammoth (Chain)
        {
            frame = "141393",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 13964 combat",
                "turbobarcam_script_select_unit 13964",
            }
        },

        -- CUT #75 Behemoth (Chain)
        {
            frame = "142293",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 27321 combat",
                "turbobarcam_script_select_unit 27321",
            }
        },

        -- CUT #76 Behemoth (Chain)
        {
            frame = "143793",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 4401 combat",
                "turbobarcam_script_select_unit 4401",
            }
        },

        -- CUT #77 Behemoth (Chain)
        {
            frame = "146793",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 27321 combat",
                "turbobarcam_script_select_unit 27321",
            }
        },

        -- CUT #78 Behemoth (Chain)
        {
            frame = "147693",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 25731 combat",
                "turbobarcam_script_select_unit 25731",
            }
        },

        -- CUT #79 Behemoth (Chain)
        {
            frame = "148503",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 12841 combat",
                "turbobarcam_script_select_unit 12841",
            }
        },

        -- CUT #80 Behemoth (Chain)
        {
            frame = "148773",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 25731 combat",
                "turbobarcam_script_select_unit 25731",
            }
        },

        -- CUT #81 Behemoth (Chain)
        {
            frame = "151563",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 27321 combat",
                "turbobarcam_script_select_unit 27321",
            }
        },

        -- CUT #82 Behemoth (Chain)
        {
            frame = "153573",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 13365 combat",
                "turbobarcam_script_select_unit 13365",
            }
        },

        -- CUT #83 Juggernaut (Chain)
        {
            frame = "155463",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 18324 combat",
                "turbobarcam_script_select_unit 18324",
            }
        },

        -- CUT #84 Juggernaut (Chain)
        {
            frame = "155673",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 6055 combat",
                "turbobarcam_script_select_unit 6055",
            }
        },

        -- CUT #85 Mammoth (Chain)
        {
            frame = "156033",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 19800 combat",
                "turbobarcam_script_select_unit 19800",
            }
        },

        -- CUT #86 Behemoth (Chain)
        {
            frame = "157143",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17264 combat",
                "turbobarcam_script_select_unit 17264",
            }
        },

        -- CUT #87 Behemoth (Chain)
        {
            frame = "157353",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 22311 combat",
                "turbobarcam_script_select_unit 22311",
            }
        },

        -- CUT #88 Behemoth (Chain)
        {
            frame = "158883",
            commands = {
                "turbobarcam_smoothing reset",
                "turbobarcam_toggle_unit_follow_camera 17264 combat",
                "turbobarcam_script_select_unit 17264",
            }
        },
        {
            frame = "9999999",
            commands = {
                "setspeed 1",
            }
        },
    }
}
