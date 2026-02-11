from typing import List

def get_default_unit_commands(game_unit_id: str) -> List[str]:
    """
    Returns the default Lua commands for selecting and following a unit.
    """
    return [
        "turbobarcam_smoothing reset",
        f"turbobarcam_toggle_unit_follow_camera {game_unit_id} combat",
        f"turbobarcam_script_select_unit {game_unit_id}"
    ]
