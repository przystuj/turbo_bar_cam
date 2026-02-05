from slpp import slpp as lua
import os
import re
import tkinter as tk
from tkinter import filedialog

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SEARCH_DIRECTORY = r"S:\Gry\BeyondAllReason\Beyond-All-Reason\data\LuaUI\veterancyData"
OUTPUT_DIRECTORY = "../../LuaUI/TurboBarCam/scripts/"

# ------------------------------------------------------------------------------
# FILTERS & OVERRIDES
# ------------------------------------------------------------------------------

IGNORE_NAMES = {
    "armrock", "corwolv", "corstorm", "armart"
}

IGNORE_IDS = {
    18226,
}

PREFERRED_NAMES = {
    "corgol", "cormart"
}

PRIORITISE_IDS = {
    9437
}

# ------------------------------------------------------------------------------
# TUNING CONSTANTS
# ------------------------------------------------------------------------------

# SCORING
WEIGHT_REMAINING_LIFE = 1.0
WEIGHT_TOTAL_LIFE     = 0.5
WEIGHT_XP             = 500.0
WEIGHT_TIER           = 2000.0
PREFERENCE_MULTIPLIER = 2.0
ID_PRIORITY_MULTIPLIER = 10.0

# THRESHOLDS
SWAP_SCORE_THRESHOLD = 2.5   # New unit must be 2.5x better to swap
MIN_SWAP_COOLDOWN = 300      # 10s: Don't swap again too soon
ANCHOR_DURATION = 450        # 15s: Minimum duration to be considered an Anchor
NEARBY_SEARCH_RADIUS = 500   # Elmos: Search radius for neighbors during pauses
MIN_NEIGHBOR_DURATION = 200  # Neighbor must be active for at least this long

# TIMING
MAX_WATCHABLE_PAUSE = 150    # 5s: Pauses shorter than this are watched.
FAST_FORWARD_SPEED = 3       # Speed during gaps

# ==============================================================================
# DATA PROCESSING
# ==============================================================================

def get_unit_status_at_frame(unit_data, frame):
    """
    Returns 'ACTIVE', 'PAUSE', or 'IDLE' and the end frame of that segment.
    """
    if "statusHistory" not in unit_data:
        return "IDLE", frame

    for segment in unit_data["statusHistory"]:
        start = segment["startFrame"]
        # Handle open-ended segments (nil endFrame)
        end = segment.get("endFrame", 9999999)

        if start <= frame < end:
            return segment["status"], end

    return "IDLE", frame

def get_unit_position(unit, frame):
    """
    Returns the {x, z} dict closest to the given frame.
    """
    if "positionHistory" not in unit or not unit["positionHistory"]:
        return None

    history = unit["positionHistory"]
    closest = min(history, key=lambda p: abs(p["frame"] - frame))
    return closest

def get_watchable_duration(unit, start_frame):
    """
    Calculates how long we can actually watch this unit from start_frame
    before it dies, goes IDLE, or hits a Long Pause that forces a cut.
    """
    total_duration = 0
    current_frame = start_frame

    # Safety cap to prevent infinite loops in bad data
    while total_duration < (ANCHOR_DURATION * 2):
        status, end_frame = get_unit_status_at_frame(unit, current_frame)

        # 1. If IDLE, the show is over.
        if status == "IDLE":
            break

        # 2. If PAUSE, check if it's too long
        if status == "PAUSE":
            pause_len = end_frame - current_frame
            if pause_len > MAX_WATCHABLE_PAUSE:
                break # Long pause -> Cut
            else:
                pass # Short pause -> Keep watching

        segment_duration = end_frame - current_frame
        total_duration += segment_duration
        current_frame = end_frame

    return total_duration

def calculate_score(unit, current_frame):
    status, _ = get_unit_status_at_frame(unit, current_frame)

    if status == "IDLE":
        return 0

    xp = unit.get("finalXP", 0)
    tier = unit.get("tier", 1)

    score = (xp * WEIGHT_XP) + (tier * WEIGHT_TIER)

    if unit["name"] in PREFERRED_NAMES:
        score *= PREFERENCE_MULTIPLIER

    if unit.get("defID", 0) in PRIORITISE_IDS:
        score *= ID_PRIORITY_MULTIPLIER

    return score

def preprocess_data(units):
    processed = {}
    for uid, unit in units.items():
        unit['id'] = uid # Ensure ID is present in the object

        if unit["name"] in IGNORE_NAMES:
            continue

        if unit["id"] in IGNORE_IDS:
            continue

        # Handle slpp decoding Lua arrays as dicts (statusHistory)
        if "statusHistory" in unit:
            history = unit["statusHistory"]
            if isinstance(history, dict):
                history = list(history.values())
            history.sort(key=lambda x: x["startFrame"])
            unit["statusHistory"] = history

        # Handle slpp decoding Lua arrays as dicts (positionHistory)
        if "positionHistory" in unit:
            pos_hist = unit["positionHistory"]
            if isinstance(pos_hist, dict):
                pos_hist = list(pos_hist.values())
            pos_hist.sort(key=lambda x: x["frame"])
            unit["positionHistory"] = pos_hist

        processed[uid] = unit
    return processed

# ==============================================================================
# PATHFINDER ALGORITHM
# ==============================================================================

def find_best_unit(units, start_frame, min_duration, center_pos=None, radius=None, exclude_id=None, require_active_start=False):
    """
    Unified search function.
    - units: Dataset
    - start_frame: Current frame
    - min_duration: Unit must be watchable for at least this long (Look Ahead)
    - center_pos/radius: Optional spatial filter
    - exclude_id: Optional ID to ignore (e.g. current target)
    - require_active_start: If True, unit must be ACTIVE immediately (no starting pauses)
    """
    best_id = None
    best_score = -1

    # Calculate scoring endpoints
    score_end_frame = start_frame + min_duration

    for uid, unit in units.items():
        if exclude_id and uid == exclude_id:
            continue

        # 1. Status Check
        status, _ = get_unit_status_at_frame(unit, start_frame)
        if status == "IDLE":
            continue
        if require_active_start and status != "ACTIVE":
            continue

        # 2. Position Filter (if applicable)
        if center_pos and radius:
            u_pos = get_unit_position(unit, start_frame)
            if not u_pos:
                continue
            dx = center_pos["x"] - u_pos["x"]
            dz = center_pos["z"] - u_pos["z"]
            dist_sq = dx*dx + dz*dz
            if dist_sq > (radius * radius):
                continue

        # 3. Duration/Look-ahead Check
        # Uses the unified logic to ensure unit survives and doesn't hit a long pause
        watchable_time = get_watchable_duration(unit, start_frame)
        if watchable_time < min_duration:
            continue

        # 4. Scoring (Average over duration)
        # Using average score ensures we pick units that stay valuable
        s1 = calculate_score(unit, start_frame)
        s2 = calculate_score(unit, (start_frame + score_end_frame) // 2)
        s3 = calculate_score(unit, score_end_frame)
        avg_score = (s1 + s2 + s3) / 3

        if avg_score > best_score:
            best_score = avg_score
            best_id = uid

    return best_id, best_score

def find_cinematic_path(data):
    timeline = []
    end_frame = 0

    # Find global max frame
    for u in data.values():
        if "diedFrame" in u and u["diedFrame"]:
            end_frame = max(end_frame, u["diedFrame"])
        for s in u.get("statusHistory", []):
            if s.get("endFrame", 0) < 9999999:
                end_frame = max(end_frame, s.get("endFrame", 0))

    current_frame = 0
    current_target_id = None

    print(f"Generating Timeline (Max Frame: {end_frame})...")

    while current_frame < end_frame:

        # 1. SEARCH FOR ANCHOR
        if current_target_id is None:
            print(f"Searching for Anchor... from {format_time(current_frame)}")

            anchor_id, score = find_best_unit(
                data,
                current_frame,
                ANCHOR_DURATION,
                require_active_start=False
            )

            if anchor_id:
                unit = data[anchor_id]

                # Check for gap between 'now' and 'actual start'
                status, seg_end = get_unit_status_at_frame(unit, current_frame)
                actual_start = current_frame

                if status == "IDLE":
                    for seg in unit["statusHistory"]:
                        if seg["startFrame"] > current_frame:
                            actual_start = seg["startFrame"]
                            break

                # Insert Gap if needed
                if actual_start > current_frame + 30:
                    timeline.append({
                        "type": "gap",
                        "start": current_frame,
                        "end": actual_start,
                        "target": -1,
                        "note": "Gap to Anchor"
                    })
                    current_frame = actual_start

                print(f"-> Anchor Found: {unit['humanName']} at {format_time(current_frame)} (Score: {int(score)})")
                current_target_id = anchor_id
            else:
                current_frame += 150
                continue

        # 2. TRACK TARGET
        if current_target_id:
            unit = data[current_target_id]
            cut_start = current_frame

            while True:
                status, seg_end = get_unit_status_at_frame(unit, current_frame)

                # CASE A: IDLE
                if status == "IDLE":
                    timeline.append({
                        "type": "cut",
                        "start": cut_start,
                        "end": current_frame,
                        "target": current_target_id,
                        "unit_data": unit,
                        "note": "Anchor End (Idle)"
                    })
                    current_target_id = None
                    break

                # CASE B: PAUSE
                if status == "PAUSE":
                    pause_duration = seg_end - current_frame

                    if pause_duration > MAX_WATCHABLE_PAUSE:

                        # --- NEIGHBOR LOGIC ---
                        current_pos = get_unit_position(unit, current_frame)
                        neighbor_id = None

                        if current_pos:
                            neighbor_id, _ = find_best_unit(
                                data,
                                current_frame,
                                MIN_NEIGHBOR_DURATION, # Enforces minimum duration
                                center_pos=current_pos,
                                radius=NEARBY_SEARCH_RADIUS,
                                exclude_id=current_target_id,
                                require_active_start=True
                            )

                        if neighbor_id:
                            # 1. Finalize current cut
                            if current_frame > cut_start:
                                timeline.append({
                                    "type": "cut",
                                    "start": cut_start,
                                    "end": current_frame,
                                    "target": current_target_id,
                                    "unit_data": unit,
                                    "note": "Pre-Pause (Switching to Neighbor)"
                                })

                            # 2. Switch context
                            current_target_id = neighbor_id
                            unit = data[neighbor_id]
                            cut_start = current_frame

                            # 3. Restart loop
                            continue

                        # If no neighbor found, fallback to FF
                        if current_frame > cut_start:
                            timeline.append({
                                "type": "cut",
                                "start": cut_start,
                                "end": current_frame,
                                "target": current_target_id,
                                "unit_data": unit,
                                "note": "Pre-Pause"
                            })

                        timeline.append({
                            "type": "gap",
                            "start": current_frame,
                            "end": seg_end,
                            "target": -1,
                            "note": "Skipping Long Pause"
                        })

                        current_frame = seg_end
                        cut_start = current_frame
                        continue
                    else:
                        pass

                # CASE C: SWAP
                if current_frame % 30 == 0 and (current_frame - cut_start) > MIN_SWAP_COOLDOWN:
                    current_score = calculate_score(unit, current_frame)

                    best_swap_id, best_swap_score = find_best_unit(
                        data,
                        current_frame,
                        ANCHOR_DURATION,
                        require_active_start=False
                    )

                    if best_swap_id and best_swap_id != current_target_id:
                        if best_swap_score > (current_score * SWAP_SCORE_THRESHOLD):
                            timeline.append({
                                "type": "cut",
                                "start": cut_start,
                                "end": current_frame,
                                "target": current_target_id,
                                "unit_data": unit,
                                "note": "Swap to Better Unit"
                            })
                            current_target_id = best_swap_id
                            break

                current_frame += 1

                if current_frame >= end_frame:
                    timeline.append({
                        "type": "cut",
                        "start": cut_start,
                        "end": current_frame,
                        "target": current_target_id,
                        "unit_data": unit,
                        "note": "End of Replay"
                    })
                    current_target_id = None
                    break

    return timeline

# ==============================================================================
# OUTPUT GENERATION
# ==============================================================================

def format_time(frames):
    seconds = frames // 30
    mm = seconds // 60
    ss = seconds % 60
    return f"{mm:02d}:{ss:02d}"

def print_summary(timeline):
    print("\n" + "="*80)
    print(f"CINEMATIC CAMERA PATH ({len(timeline)} Cuts)")
    print("="*80)

    for i, cut in enumerate(timeline):
        start_f = cut['start']
        end_f = cut['end']
        start_str = format_time(start_f)
        end_str = format_time(end_f)
        dur_str = format_time(end_f - start_f)

        spd = ""
        if cut['type'] == 'gap':
            spd = f"[x{FAST_FORWARD_SPEED}]"

        if cut['target'] == -1:
            print(f"CUT #{i+1:02d}{spd} | {start_str} -> {end_str} | Dur: {dur_str} | {start_f} -> {end_f}")
            print(f"         Target: Fast Forward (ff) ID: -1 | Note: {cut.get('note', '')}")
        else:
            u = cut.get('unit_data', {})
            h_name = u.get('humanName', 'Unknown')
            i_name = u.get('name', 'N/A')
            uid = u.get('id', cut['target'])

            print(f"CUT #{i+1:02d}{spd} | {start_str} -> {end_str} | Dur: {dur_str} | {start_f} -> {end_f}")
            print(f"         Target: {h_name} ({i_name}) ID: {uid} | Note: {cut.get('note', '')}")

        print("-" * 80)

def save_to_lua(timeline, filename):
    try:
        os.makedirs(os.path.dirname(filename), exist_ok=True)
        with open(filename, "w") as f:
            f.write("return {\n    steps = {\n")

            if timeline:
                first_start = timeline[0]['start']
                f.write(f'        {{ frame = 30, commands = {{ "skip f{first_start}" }} }},\n')

            last_speed = 1
            last_target = None

            for i, cut in enumerate(timeline):
                start_f = cut['start']
                target = cut['target']
                type_ = cut['type']

                # Logic: Gap = FF Speed, Cut = Normal Speed
                current_speed = FAST_FORWARD_SPEED if type_ == 'gap' else 1

                # Comment generation
                u_name = "Fast Forward"
                if type_ == 'cut':
                    u_data = cut.get('unit_data', {})
                    u_name = u_data.get('humanName', 'Unknown')

                note = cut.get('note', '')
                f.write(f"\n        -- CUT #{i+1:02d} {u_name} ({note})")
                if current_speed > 1: f.write(" [FF]")
                f.write("\n")

                f.write("        {\n")
                f.write(f'            frame = {start_f},\n')
                f.write('            commands = {\n')

                # 1. Handle Speed
                if current_speed != last_speed:
                    f.write(f'                "setspeed {current_speed}",\n')
                    last_speed = current_speed

                # 2. Handle Camera Tracking (Only for cuts)
                if type_ == 'cut':
                    if target != last_target:
                        f.write('                "turbobarcam_smoothing reset",\n')
                        f.write(f'                "turbobarcam_toggle_unit_follow_camera {target} combat",\n')
                        f.write(f'                "turbobarcam_script_select_unit {target}",\n')
                        last_target = target

                f.write('            }\n        },\n')

            f.write("    }\n}\n")
            print(f"\n[Success] Script saved to: {filename}")
    except IOError as e:
        print(f"\n[Error] Could not write to file: {e}")

if __name__ == "__main__":
    root = tk.Tk()
    root.withdraw()

    selected_file = filedialog.askopenfilename(initialdir=SEARCH_DIRECTORY, title="Select Veterancy Data")
    if selected_file:
        print(f"--- Loading {selected_file} ---")
        try:
            with open(selected_file, "r") as f:
                content = f.read().replace("return", "")
                file_content = lua.decode(content)
                data = preprocess_data(file_content['units'])

            if data:
                timeline = find_cinematic_path(data)
                print_summary(timeline)

                base_name = os.path.basename(selected_file)
                clean_name = re.sub(r'_veterancyData.*', '', os.path.splitext(base_name)[0])
                output_path = os.path.normpath(os.path.join(OUTPUT_DIRECTORY, f"{clean_name}.lua"))

                save_to_lua(timeline, output_path)

        except Exception as e:
            print(f"CRITICAL ERROR: {e}")
            import traceback
            traceback.print_exc()
