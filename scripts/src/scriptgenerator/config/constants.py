# ==============================================================================
# CONFIGURATION & CONSTANTS
# ==============================================================================

PROJECTS_DIR = "./projects"
GAME_OUTPUT_DIR = "../../../LuaUI/TurboBarCam/scripts/"

# FILTERS & OVERRIDES (Defaults can be overwritten by GUI)
IGNORE_NAMES = set()
IGNORE_IDS = set()
PREFERRED_NAMES = set()
PRIORITISE_IDS = set()

# TUNING CONSTANTS
WEIGHT_REMAINING_LIFE = 1.0
WEIGHT_TOTAL_LIFE     = 0.5
WEIGHT_XP             = 500.0
WEIGHT_TIER           = 2000.0
PREFERENCE_MULTIPLIER = 2.0
ID_PRIORITY_MULTIPLIER = 10.0

SWAP_SCORE_THRESHOLD = 2.5
MIN_SWAP_COOLDOWN = 300
ANCHOR_DURATION = 450
NEARBY_SEARCH_RADIUS = 500
MIN_NEIGHBOR_DURATION = 200

# LOGIC CONSTANTS
TIER_3_PAUSE_THRESHOLD = 300  # 10s
TIER_3_IDLE_THRESHOLD = 600   # 20s
TIER_1_PAUSE_THRESHOLD = 150  # 5s
STATIONARY_MIN_FRAMES = 150   # 5s
STATIONARY_CHECK_DIST = 10.0
STATIONARY_CHECK_FRAMES = 30

# ==============================================================================
# UI COLORS
# ==============================================================================
COLOR_ACTIVE = "#77dd77"
COLOR_PAUSE  = "#ffcc00"
COLOR_IDLE   = "#e0e0e0"
COLOR_STATIONARY = "#ff8800"
COLOR_UNKNOWN = "#d0d0d0"
COLOR_GAP    = "#aaaaaa"

COLOR_TIER1  = "#66aaff"
COLOR_TIER2  = "#aa66ff"
COLOR_TIER3  = "#ff6666"
COLOR_GROUND = "#E08543"

# ==============================================================================
# CONFIGURATION HELPERS
# ==============================================================================

def update_filters(ignore_names_str, ignore_ids_str, pref_names_str, prio_ids_str):
    """Parses comma-separated strings from GUI and updates global filters."""
    global IGNORE_NAMES, IGNORE_IDS, PREFERRED_NAMES, PRIORITISE_IDS

    def parse_str_set(s):
        return {x.strip() for x in s.split(',') if x.strip()}

    def parse_int_set(s):
        res = set()
        for x in s.split(','):
            x = x.strip()
            if x.isdigit():
                res.add(int(x))
        return res

    IGNORE_NAMES = parse_str_set(ignore_names_str)
    IGNORE_IDS = parse_int_set(ignore_ids_str)
    PREFERRED_NAMES = parse_str_set(pref_names_str)
    PRIORITISE_IDS = parse_int_set(prio_ids_str)
