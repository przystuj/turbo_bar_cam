import json
import os

CONFIG_FILE = "settings.json"

DEFAULT_CONFIG = {
    "last_input_file": "",
    "ignore_names": "",
    "ignore_ids": "",
    "preferred_names": "",
    "prioritise_ids": ""
}

def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r") as f:
                data = json.load(f)
                for k, v in DEFAULT_CONFIG.items():
                    if k not in data:
                        data[k] = v
                return data
        except (json.JSONDecodeError, IOError):
            return DEFAULT_CONFIG.copy()
    return DEFAULT_CONFIG.copy()

def save_config(config_data):
    try:
        with open(CONFIG_FILE, "w") as f:
            json.dump(config_data, f, indent=4)
    except IOError as e:
        print(f"Failed to save config: {e}")
