import json
import re
from collections import defaultdict

ACTIONS_PATH = "../../LuaUI/TurboBarCam/actions.lua"
KEYBINDS_PATH = "../../LuaUI/TurboBarCam/turbobarcam.uikeys.txt"
I18N_PATH = "../../LuaUI/TurboBarCam/i18n.json"
RESULT_PATH = "../../README_KEYBINDS.md"

# --- Configuration for Mode Grouping and Ordering ---
MODE_ORDER = [
    "General Controls",
    "Anchor Point Mode",
    "DollyCam Mode",
    "Unit Follow Mode",
    "Group Tracking Mode",
    "Orbit Mode",
    "Overview Mode",
    "Projectile Camera Mode",
    "Unit Tracking Mode",
    "Spectator Actions",
    "Development Actions",
    "Other Actions"  # Fallback for anything not categorized
]

MODE_PREFIX_MAP = {
    "turbobarcam_anchor_": "Anchor Point Mode",
    "turbobarcam_dollycam_": "DollyCam Mode",
    "turbobarcam_unit_follow_": "Unit Follow Mode",
    "turbobarcam_group_tracking_": "Group Tracking Mode",
    "turbobarcam_orbit_": "Orbit Mode",
    "turbobarcam_overview_": "Overview Mode",
    "turbobarcam_projectile_": "Projectile Camera Mode",
    "turbobarcam_tracking_camera_": "Unit Tracking Mode",
    "turbobarcam_dev_": "Development Actions",
    "turbobarcam_spec_": "Spectator Actions",  # e.g. turbobarcam_spec_unit_group
}

SPECIFIC_ACTION_TO_MODE_MAP = {
    "turbobarcam_toggle_unit_follow_camera": "Unit Follow Mode",
    "turbobarcam_toggle_group_tracking_camera": "Group Tracking Mode",
    "turbobarcam_toggle_tracking_camera": "Unit Tracking Mode",
    "turbobarcam_toggle": "General Controls",
    "turbobarcam_debug": "General Controls",
    "turbobarcam_toggle_zoom": "General Controls",
    "turbobarcam_set_fov": "General Controls",
    "turbobarcam_toggle_require_unit_selection": "General Controls",
    "turbobarcam_stop_tracking": "General Controls",
    "turbobarcam_toggle_playercam_selection": "Spectator Actions",
}

OTHER_ACTIONS = [
    "turbobarcam_unit_follow_set_fixed_look_point"
]


def get_mode_for_action(action_name):
    if action_name in SPECIFIC_ACTION_TO_MODE_MAP:
        return SPECIFIC_ACTION_TO_MODE_MAP[action_name]
    for prefix, mode_name in MODE_PREFIX_MAP.items():
        if action_name.startswith(prefix):
            return mode_name
    print(
        f"Warning: Action '{action_name}' could not be automatically categorized into a primary mode based on prefixes/specific map.")
    return "Other Actions"


# --- Data Extraction Functions ---

def extract_actions_from_lua(lua_content):
    """Extracts action names from actions.lua content."""
    actions = set()
    # Regex to find Actions.registerAction("action_name", ...)
    # It allows for action names with underscores and alphanumeric characters.
    regex = r'Actions\.registerAction\s*\(\s*["\'](turbobarcam_[a-zA-Z0-9_]+)["\']'
    for match in re.finditer(regex, lua_content):
        actions.add(match.group(1))
    return actions


def load_i18n_data(i18n_content):
    """Loads i18n data from JSON content."""
    return json.loads(i18n_content)


def extract_keybinds(uikeys_content):
    """
    Extracts keybinds from uikeys.txt content.
    Returns a dict: {base_action_name: [{"key": key_combo, "params": bound_params_str}, ...]}
    """
    keybinds = defaultdict(list)
    # Regex to capture: 1=key, 2=rest of the command string
    # Handles keys like "Ctrl+Shift+numpad.", "sc_[", "numpad*", "numpad/", "Ctrl+sc_\"
    # Added *, /, \ to the allowed characters in a key name.
    # The key regex part is ([\w.+\-_/*\\\[\]<>]+)
    # \w: word characters (alphanumeric and underscore)
    # .: literal dot
    # +: literal plus
    # -: literal hyphen
    # _: literal underscore (already in \w)
    # /*\\: literal asterisk, forward slash, backslash (escaped)
    # \[\]<>: literal brackets and angle brackets
    bind_regex = re.compile(r'^\s*bind\s+([\w.+\-_/*\\\[\]<>]+)\s+(.*)', re.IGNORECASE)

    lines = uikeys_content.splitlines()
    for line_number, line_text in enumerate(lines, 1):
        line = line_text.strip()
        if not line or line.startswith('//'):
            continue

        match = bind_regex.match(line)
        if match:
            key_combo = match.group(1)
            key_combo = str.replace(key_combo, "sc_", "")
            command_full = match.group(2).strip()

            # Handle "chain" commands: extract turbobarcam actions from them
            commands_to_process = []
            if command_full.lower().startswith("chain"):
                # Split the chain by '|'
                chain_parts = command_full.split('|')
                # The first part is "chain force action_args" or similar, skip "chain" itself
                first_chain_command_part = chain_parts[0].lower().split(maxsplit=1)

                current_command = ""
                if len(first_chain_command_part) > 1:
                    current_command = first_chain_command_part[1].strip() # remove "chain"

                # Process the first command in the chain if it's a turbobarcam action
                if current_command.lower().startswith("force"):
                    current_command = current_command.split(maxsplit=1)[1] if len(current_command.split(maxsplit=1)) > 1 else ""
                    current_command = current_command.strip()
                if current_command.startswith("turbobarcam_"):
                    commands_to_process.append(current_command)

                # Process subsequent commands in the chain
                for i in range(1, len(chain_parts)):
                    part = chain_parts[i].strip()
                    if part.lower().startswith("force"): # "force" is often part of a chain segment
                        part = part.split(maxsplit=1)[1] if len(part.split(maxsplit=1)) > 1 else ""
                        part = part.strip()
                    if part.startswith("turbobarcam_"):
                        commands_to_process.append(part)
            else:
                if command_full.startswith("turbobarcam_"):
                    commands_to_process.append(command_full)

            for cmd_str in commands_to_process:
                action_parts = cmd_str.split(maxsplit=1)
                base_action_name = action_parts[0]
                bound_params_str = action_parts[1] if len(action_parts) > 1 else ""
                keybinds[base_action_name].append({"key": key_combo, "params": bound_params_str.strip()})
        # Avoid warning for known non-bind lines that are common
        elif not (line.lower().startswith("unbindkeyset") or
                  line.lower().startswith("unbind") or
                  line.lower().startswith("unbindaction") or
                  line.lower().startswith("removebind")):
            print(f"Warning: Could not parse keybind line #{line_number}: {line_text}")

    return keybinds


# --- Main Script Logic ---

def generate_markdown(lua_actions, i18n_data, keybinds_map):
    """Generates the Markdown content."""
    processed_actions = {}  # {action_name: {label, desc, params_info, keybind_str, mode}}

    # Populate processed_actions with i18n data and connect to lua_actions
    all_action_names = set(lua_actions) | set(i18n_data.keys())

    for action_name in sorted(list(all_action_names)):
        if (action_name not in lua_actions) and (action_name not in OTHER_ACTIONS):
            print(f"Warning: i18n entry for '{action_name}' exists, but action not found in actions.lua.")
        if action_name not in i18n_data:
            print(f"Warning: Action '{action_name}' from actions.lua is missing an i18n entry.")

        i18n_entry = i18n_data.get(action_name, {})
        label = i18n_entry.get("label", action_name)  # Fallback label
        description = i18n_entry.get("description", "No description available.")
        params_info = i18n_entry.get("parameters", "N/A")
        if params_info is None or str(params_info).strip().lower() == "none":
            params_info = "N/A"

        # Format keybinds for this action
        binds_for_action = keybinds_map.get(action_name, [])
        keybind_cell_parts = []
        if binds_for_action:
            for bind_info in binds_for_action:
                key_str = f"`{bind_info['key']}`"
                if bind_info['params']:
                    key_str = f" `{bind_info['key']} {bind_info['params']}`"
                keybind_cell_parts.append(key_str)
            keybind_str = "<br>".join(keybind_cell_parts)
        else:
            keybind_str = "N/A"

        processed_actions[action_name] = {
            "label": label,
            "description": description.replace("\n", "<br>"),  # Ensure multiline descriptions work
            "params_info": params_info.replace("\n", "<br>"),
            "keybind_str": keybind_str,
            "mode": get_mode_for_action(action_name)
        }

    # Group actions by mode
    actions_by_mode = defaultdict(list)
    for action_name, data in processed_actions.items():
        actions_by_mode[data["mode"]].append({
            "name": action_name,
            **data
        })

    # Build Markdown string
    md_lines = ["# TurboBarCam Keybinds", ""]
    md_lines.append(
        "This document outlines the available actions for TurboBarCam, their descriptions, parameters, and configured keybinds.")
    md_lines.append("")

    for mode_name in MODE_ORDER:
        if mode_name not in actions_by_mode or not actions_by_mode[mode_name]:
            continue

        md_lines.append(f"## {mode_name}")
        md_lines.append("")
        md_lines.append("| Action | <div style=\"width:400px\">Description</div> | <div style=\"width:400px\">Keybind</div> | Parameters |")
        md_lines.append("|---|---|---|---|")

        # Sort actions within a mode by label for consistent ordering
        sorted_actions_in_mode = sorted(actions_by_mode[mode_name], key=lambda x: x["label"])

        for action_data in sorted_actions_in_mode:
            # Action cell: Label in bold, then action_name on new line in backticks
            action_cell = f"**{action_data['label']}**<br>`{action_data['name']}`"
            description_cell = action_data['description']
            keybind_cell = action_data['keybind_str']
            params_cell = action_data['params_info']
            md_lines.append(f"| {action_cell} | {description_cell} | {keybind_cell} | {params_cell} |")
        md_lines.append("")

    return "\n".join(md_lines)


if __name__ == '__main__':
    # --- Load File Contents (replace with actual file reading) ---
    try:
        with open(ACTIONS_PATH, "r", encoding="utf-8") as f:
            lua_file_content = f.read()
    except FileNotFoundError:
        print("Error: actions.lua not found.")
        exit(1)

    try:
        with open(I18N_PATH, "r", encoding="utf-8") as f:
            i18n_file_content = f.read()
    except FileNotFoundError:
        print("Error: i18n.json not found.")
        exit(1)

    try:
        with open(KEYBINDS_PATH, "r", encoding="utf-8") as f:
            uikeys_file_content = f.read()
    except FileNotFoundError:
        print("Error: turbobarcam.uikeys.txt not found.")
        exit(1)
    # --- ---

    lua_actions_set = extract_actions_from_lua(lua_file_content)
    i18n_data_dict = load_i18n_data(i18n_file_content)
    keybinds_data_map = extract_keybinds(uikeys_file_content)

    markdown_output = generate_markdown(lua_actions_set, i18n_data_dict, keybinds_data_map)

    try:
        with open(RESULT_PATH, "w", encoding="utf-8") as f:
            f.write(markdown_output)
        print("Successfully generated README_KEYBINDS.md")
    except IOError:
        print("Error: Could not write to README_KEYBINDS.md")
