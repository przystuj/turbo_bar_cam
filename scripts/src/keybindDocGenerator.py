import json
import re
from collections import defaultdict
import os

# --- Configuration ---
ACTIONS_PATH = "../../LuaUI/TurboBarCam/actions.lua"
KEYBINDS_PATH = "../../LuaUI/TurboBarCam/turbobarcam.uikeys.txt"
I18N_PATH = "../../LuaUI/TurboBarCam/i18n.json"
RESULT_PATH = "../../README_KEYBINDS.md"
RESULT_PATH2 = "../../LuaUI/RmlWidgets/gui_turbobarcam/rml/keybinds.rml"

MODE_ORDER = [
    "General Controls", "Anchor Point Mode", "DollyCam Mode", "Unit Follow Mode",
    "Group Tracking Mode", "Orbit Mode", "Projectile Camera Mode",
    "Unit Tracking Mode", "Spectator Actions", "Development Actions", "Other Actions"
]

MODE_PREFIX_MAP = {
    "turbobarcam_anchor_": "Anchor Point Mode", "turbobarcam_dollycam_": "DollyCam Mode",
    "turbobarcam_unit_follow_": "Unit Follow Mode", "turbobarcam_group_tracking_": "Group Tracking Mode",
    "turbobarcam_orbit_": "Orbit Mode", "turbobarcam_projectile_": "Projectile Camera Mode",
    "turbobarcam_tracking_camera_": "Unit Tracking Mode",
    "turbobarcam_dev_": "Development Actions", "turbobarcam_spec_": "Spectator Actions",
}

SPECIFIC_ACTION_TO_MODE_MAP = {
    "turbobarcam_toggle_unit_follow_camera": "Unit Follow Mode",
    "turbobarcam_toggle_group_tracking_camera": "Group Tracking Mode",
    "turbobarcam_toggle_tracking_camera": "Unit Tracking Mode",
    "turbobarcam_toggle": "General Controls", "turbobarcam_debug": "General Controls",
    "turbobarcam_toggle_zoom": "General Controls", "turbobarcam_set_fov": "General Controls",
    "turbobarcam_toggle_require_unit_selection": "General Controls",
    "turbobarcam_stop_tracking": "General Controls", "turbobarcam_toggle_playercam_selection": "Spectator Actions",
}

OTHER_ACTIONS = ["turbobarcam_unit_follow_set_fixed_look_point"]

def get_mode_for_action(action_name):
    if action_name in SPECIFIC_ACTION_TO_MODE_MAP: return SPECIFIC_ACTION_TO_MODE_MAP[action_name]
    for prefix, mode_name in MODE_PREFIX_MAP.items():
        if action_name.startswith(prefix): return mode_name
    print(f"Warning: Action '{action_name}' could not be automatically categorized.")
    return "Other Actions"

def extract_actions_from_lua(lua_content):
    actions = set()
    regex = r'Actions\.registerAction\s*\(\s*["\'](turbobarcam_[a-zA-Z0-9_]+)["\']'
    for match in re.finditer(regex, lua_content):
        actions.add(match.group(1))
    return actions

def load_i18n_data(i18n_content):
    return json.loads(i18n_content)

def extract_keybinds(uikeys_content):
    keybinds = defaultdict(list)
    bind_regex = re.compile(r'^\s*bind\s+([\w.+\-_/*\\\[\]<>]+)\s+(.*)', re.IGNORECASE)
    lines = uikeys_content.splitlines()
    for line_number, line_text in enumerate(lines, 1):
        line = line_text.strip()
        if not line or line.startswith('//'): continue
        match = bind_regex.match(line)
        if match:
            key_combo = str.replace(match.group(1), "sc_", "")
            command_full = match.group(2).strip()
            commands_to_process = []
            if command_full.lower().startswith("chain"):
                chain_parts = command_full.split('|')
                first_chain_command_part = chain_parts[0].lower().split(maxsplit=1)
                current_command = first_chain_command_part[1].strip() if len(first_chain_command_part) > 1 else ""
                if current_command.lower().startswith("force"):
                    current_command = current_command.split(maxsplit=1)[1] if len(current_command.split(maxsplit=1)) > 1 else ""
                if current_command.startswith("turbobarcam_"): commands_to_process.append(current_command.strip())
                for i in range(1, len(chain_parts)):
                    part = chain_parts[i].strip()
                    if part.lower().startswith("force"): part = part.split(maxsplit=1)[1] if len(part.split(maxsplit=1)) > 1 else ""
                    if part.startswith("turbobarcam_"): commands_to_process.append(part.strip())
            elif command_full.startswith("turbobarcam_"):
                commands_to_process.append(command_full)
            for cmd_str in commands_to_process:
                action_parts = cmd_str.split(maxsplit=1)
                base_action_name = action_parts[0]
                bound_params_str = action_parts[1] if len(action_parts) > 1 else ""
                keybinds[base_action_name].append({"key": key_combo, "params": bound_params_str.strip()})
        elif not (line.lower().startswith("unbind") or line.lower().startswith("removebind")):
            print(f"Warning: Could not parse keybind line #{line_number}: {line_text}")
    return keybinds

def process_data_for_docs(lua_actions, i18n_data, keybinds_map):
    processed_actions = {}
    all_action_names = set(lua_actions) | set(i18n_data.keys())
    for action_name in sorted(list(all_action_names)):
        if (action_name not in lua_actions) and (action_name not in OTHER_ACTIONS): print(f"Warning: i18n entry for '{action_name}' exists, but action not found in actions.lua.")
        if action_name not in i18n_data: print(f"Warning: Action '{action_name}' from actions.lua is missing an i18n entry.")
        i18n_entry = i18n_data.get(action_name, {})
        label = i18n_entry.get("label", action_name)
        description = i18n_entry.get("description", "No description available.")
        binds_for_action = keybinds_map.get(action_name, [])
        keybind_cell_parts = [f'<span class="code">{b["key"]}</span>' for b in binds_for_action] or ["N/A"]
        uikeys_params_cell_parts = [f'<span class="code">{b["params"]}</span>' if b['params'] else "N/A" for b in binds_for_action] or ["N/A"]
        processed_actions[action_name] = {
            "label": label, "description": description.replace("\n", "<br/>"),
            "keybind_str": "<br/>".join(keybind_cell_parts),
            "uikeys_params_str": "<br/>".join(uikeys_params_cell_parts),
            "mode": get_mode_for_action(action_name)
        }
    actions_by_mode = defaultdict(list)
    for action_name, data in processed_actions.items():
        actions_by_mode[data["mode"]].append({"name": action_name, **data})
    return actions_by_mode

def generate_markdown(actions_by_mode):
    md_lines = ["# TurboBarCam Keybinds", "", "This document outlines the available actions for TurboBarCam, their descriptions, configured keybinds, and parameters used in those keybinds.", ""]
    for mode_name in MODE_ORDER:
        if mode_name not in actions_by_mode or not actions_by_mode[mode_name]: continue
        md_lines.extend([f"## {mode_name}", "", "| Action | <div style=\"width:400px\">Description</div> | <div style=\"width:200px\">Keybind</div> | <div style=\"width:200px\">Parameters</div> |", "|---|---|---|---|"])
        sorted_actions = sorted(actions_by_mode[mode_name], key=lambda x: x["label"])
        for action in sorted_actions:
            action_cell = f"**{action['label']}**<br>`{action['name']}`"
            keybind_md = action['keybind_str'].replace('<span class="code">', '`').replace('</span>', '`')
            params_md = action['uikeys_params_str'].replace('<span class="code">', '`').replace('</span>', '`')
            md_lines.append(f"| {action_cell} | {action['description']} | {keybind_md} | {params_md} |")
        md_lines.append("")
    return "\n".join(md_lines)

def generate_rml(actions_by_mode):
    """Generates the RML content using the final flexbox div layout."""
    rml_lines = [
        '<rml>',
        '    <head>',
        '        <title>TurboBarCam Keybinds</title>',
        '        <link type="text/rcss" href="keybinds.rcss"/>',
        '    </head>',
        '    <body id="keybinds-body">',
        '        <div id="help-container">',
        '            <handle move_target="help-container">',
        '                <div id="help-title-bar">',
        '                    <span>TurboBarCam Keybinds</span>',
        '                    <div id="help-close-button">X</div>',
        '                </div>',
        '            </handle>',
        '            <div id="help-content-wrapper" style="margin-top: 10dp">',
        '                <div id="scroller">',
        '                   <div class="flex-table">',
    ]

    for mode_name in MODE_ORDER:
        if mode_name not in actions_by_mode or not actions_by_mode[mode_name]:
            continue

        rml_lines.append(f'                        <h2>{mode_name}</h2>')
        rml_lines.append('                        <div class="flex-row header-row">')
        rml_lines.append('                            <div class="flex-cell action-col"><b>Action</b></div>')
        rml_lines.append('                            <div class="flex-cell desc-col"><b>Description</b></div>')
        rml_lines.append('                            <div class="flex-cell key-col"><b>Keybind</b></div>')
        rml_lines.append('                            <div class="flex-cell key-col"><b>Parameters</b></div>')
        rml_lines.append('                        </div>')

        sorted_actions = sorted(actions_by_mode[mode_name], key=lambda x: x["label"])
        for action in sorted_actions:
            action_cell = f"<b>{action['label']}</b><br/><span class=\"code\">{action['name']}</span>"
            description_cell = action['description']
            keybind_cell = action['keybind_str']
            params_cell = action['uikeys_params_str']

            rml_lines.append('                        <div class="flex-row keybind-row">')
            rml_lines.append(f"                            <div class=\"flex-cell action-col\">{action_cell}</div>")
            rml_lines.append(f"                            <div class=\"flex-cell desc-col\">{description_cell}</div>")
            rml_lines.append(f"                            <div class=\"flex-cell key-col\">{keybind_cell}</div>")
            rml_lines.append(f"                            <div class=\"flex-cell key-col\">{params_cell}</div>")
            rml_lines.append('                        </div>')

    rml_lines.extend([
        '                   </div>',
        '                </div>',
        '            </div>',
        '        </div>',
        '    </body>',
        '</rml>'
    ])

    return "\n".join(rml_lines)

if __name__ == '__main__':
    try:
        with open(ACTIONS_PATH, "r", encoding="utf-8") as f: lua_file_content = f.read()
        with open(I18N_PATH, "r", encoding="utf-8") as f: i18n_file_content = f.read()
        with open(KEYBINDS_PATH, "r", encoding="utf-8") as f: uikeys_file_content = f.read()
    except FileNotFoundError as e:
        print(f"Error: Could not read input file. {e}")
        exit(1)
    processed_data = process_data_for_docs(
        extract_actions_from_lua(lua_file_content),
        load_i18n_data(i18n_file_content),
        extract_keybinds(uikeys_file_content)
    )
    markdown_output = generate_markdown(processed_data)
    rml_output = generate_rml(processed_data)
    try:
        with open(RESULT_PATH, "w", encoding="utf-8") as f: f.write(markdown_output)
        print(f"Successfully generated {RESULT_PATH}")
        with open(RESULT_PATH2, "w", encoding="utf-8") as f: f.write(rml_output)
        print(f"Successfully generated {RESULT_PATH2}")
    except IOError as e:
        print(f"Error: Could not write output files. {e}")
