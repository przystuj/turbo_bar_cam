import os
import csv
import re

# ==============================================================================
# CONFIGURATION & CONSTANTS
# ==============================================================================

INTERNAL_SCRIPTS_DIR = "./scripts"
GAME_OUTPUT_DIR = "../../../LuaUI/TurboBarCam/scripts/"

# FILTERS & OVERRIDES
IGNORE_NAMES = {"armrock", "corwolv", "corstorm", "armart"}
IGNORE_IDS = {18226}
PREFERRED_NAMES = {"corgol", "cormart"}
PRIORITISE_IDS = {9437}

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
MAX_WATCHABLE_PAUSE = 150
FAST_FORWARD_SPEED = 3

# ==============================================================================
# LOGIC / BACKEND
# ==============================================================================

def get_clean_id(input_file):
    if not input_file: return None
    base_name = os.path.basename(input_file)
    return re.sub(r'_veterancyData.*', '', os.path.splitext(base_name)[0])

def get_unit_status_at_frame(unit_data, frame):
    if "statusHistory" not in unit_data:
        return "IDLE", frame
    for segment in unit_data["statusHistory"]:
        start = segment["startFrame"]
        end = segment.get("endFrame", 9999999)
        if start <= frame < end:
            return segment["status"], end
    return "IDLE", frame

def get_unit_position(unit, frame):
    if "positionHistory" not in unit or not unit["positionHistory"]:
        return None
    history = unit["positionHistory"]
    closest = min(history, key=lambda p: abs(p["frame"] - frame))
    return closest

def get_watchable_duration(unit, start_frame):
    total_duration = 0
    current_frame = start_frame
    while total_duration < (ANCHOR_DURATION * 2):
        status, end_frame = get_unit_status_at_frame(unit, current_frame)
        if status == "IDLE":
            break
        if status == "PAUSE":
            pause_len = end_frame - current_frame
            if pause_len > MAX_WATCHABLE_PAUSE:
                break

        segment_duration = end_frame - current_frame
        if segment_duration > 100000: segment_duration = 10000

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
        unit['id'] = uid
        if unit["name"] in IGNORE_NAMES: continue
        if unit["id"] in IGNORE_IDS: continue

        if "statusHistory" in unit:
            history = unit["statusHistory"]
            if isinstance(history, dict): history = list(history.values())
            history.sort(key=lambda x: x["startFrame"])
            unit["statusHistory"] = history

        if "positionHistory" in unit:
            pos_hist = unit["positionHistory"]
            if isinstance(pos_hist, dict): pos_hist = list(pos_hist.values())
            pos_hist.sort(key=lambda x: x["frame"])
            unit["positionHistory"] = pos_hist

        processed[uid] = unit
    return processed

def find_best_unit(units, start_frame, min_duration, center_pos=None, radius=None, exclude_id=None, require_active_start=False):
    best_id = None
    best_score = -1
    score_end_frame = start_frame + min_duration

    for uid, unit in units.items():
        if exclude_id and uid == exclude_id: continue

        status, _ = get_unit_status_at_frame(unit, start_frame)
        if status == "IDLE": continue
        if require_active_start and status != "ACTIVE": continue

        if center_pos and radius:
            u_pos = get_unit_position(unit, start_frame)
            if not u_pos: continue
            dx = center_pos["x"] - u_pos["x"]
            dz = center_pos["z"] - u_pos["z"]
            if (dx*dx + dz*dz) > (radius * radius): continue

        watchable_time = get_watchable_duration(unit, start_frame)
        if watchable_time < min_duration: continue

        s1 = calculate_score(unit, start_frame)
        s2 = calculate_score(unit, (start_frame + score_end_frame) // 2)
        s3 = calculate_score(unit, score_end_frame)
        avg_score = (s1 + s2 + s3) / 3

        if avg_score > best_score:
            best_score = avg_score
            best_id = uid

    return best_id, best_score

def format_time(frames):
    seconds = frames // 30
    mm = seconds // 60
    ss = seconds % 60
    return f"{mm:02d}:{ss:02d}"

def generate_timeline(data, log_func):
    timeline = []
    end_frame = 0
    for u in data.values():
        if "diedFrame" in u and u["diedFrame"]:
            end_frame = max(end_frame, u["diedFrame"])
        for s in u.get("statusHistory", []):
            if s.get("endFrame", 0) < 9999999:
                end_frame = max(end_frame, s.get("endFrame", 0))

    current_frame = 0
    current_target_id = None

    log_func(f"Generating Timeline (Max Frame: {end_frame})...")

    while current_frame < end_frame:
        # 1. SEARCH FOR ANCHOR
        if current_target_id is None:
            anchor_id, score = find_best_unit(data, current_frame, ANCHOR_DURATION)

            if anchor_id:
                unit = data[anchor_id]
                status, seg_end = get_unit_status_at_frame(unit, current_frame)
                actual_start = current_frame

                if status == "IDLE":
                    for seg in unit["statusHistory"]:
                        if seg["startFrame"] > current_frame:
                            actual_start = seg["startFrame"]
                            break

                if actual_start > current_frame + 30:
                    timeline.append({"type": "gap", "start": current_frame, "end": actual_start, "target": -1, "note": "Gap to Anchor"})
                    current_frame = actual_start

                log_func(f"-> Anchor Found: {unit.get('humanName','Unknown')} at {format_time(current_frame)} (Score: {int(score)})")
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

                # IDLE / DIED
                if status == "IDLE":
                    timeline.append({"type": "cut", "start": cut_start, "end": current_frame, "target": current_target_id, "unit_data": unit, "note": "Anchor End (Idle)"})
                    current_target_id = None
                    break

                # PAUSE
                if status == "PAUSE":
                    pause_duration = seg_end - current_frame
                    if pause_duration > MAX_WATCHABLE_PAUSE:
                        current_pos = get_unit_position(unit, current_frame)
                        neighbor_id = None
                        if current_pos:
                            neighbor_id, _ = find_best_unit(
                                data, current_frame, MIN_NEIGHBOR_DURATION,
                                center_pos=current_pos, radius=NEARBY_SEARCH_RADIUS,
                                exclude_id=current_target_id, require_active_start=True
                            )

                        if neighbor_id:
                            if current_frame > cut_start:
                                timeline.append({"type": "cut", "start": cut_start, "end": current_frame, "target": current_target_id, "unit_data": unit, "note": "Pre-Pause (Switching to Neighbor)"})
                            current_target_id = neighbor_id
                            unit = data[neighbor_id]
                            cut_start = current_frame
                            continue

                        if current_frame > cut_start:
                            timeline.append({"type": "cut", "start": cut_start, "end": current_frame, "target": current_target_id, "unit_data": unit, "note": "Pre-Pause"})

                        timeline.append({"type": "gap", "start": current_frame, "end": seg_end, "target": -1, "note": "Skipping Long Pause"})
                        current_frame = seg_end
                        cut_start = current_frame
                        continue

                # SWAP CHECK
                if current_frame % 30 == 0 and (current_frame - cut_start) > MIN_SWAP_COOLDOWN:
                    current_score = calculate_score(unit, current_frame)
                    best_swap_id, best_swap_score = find_best_unit(data, current_frame, ANCHOR_DURATION)

                    if best_swap_id and best_swap_id != current_target_id:
                        if best_swap_score > (current_score * SWAP_SCORE_THRESHOLD):
                            timeline.append({"type": "cut", "start": cut_start, "end": current_frame, "target": current_target_id, "unit_data": unit, "note": "Swap to Better Unit"})
                            current_target_id = best_swap_id
                            break

                current_frame += 1
                if current_frame >= end_frame:
                    timeline.append({"type": "cut", "start": cut_start, "end": current_frame, "target": current_target_id, "unit_data": unit, "note": "End of Replay"})
                    current_target_id = None
                    break

    return timeline

def write_lua_file(timeline, filename, log_func):
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
                current_speed = FAST_FORWARD_SPEED if type_ == 'gap' else 1

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

                if current_speed != last_speed:
                    f.write(f'                "setspeed {current_speed}",\n')
                    last_speed = current_speed

                if type_ == 'cut':
                    if target != last_target:
                        f.write('                "turbobarcam_smoothing reset",\n')
                        f.write(f'                "turbobarcam_toggle_unit_follow_camera {target} combat",\n')
                        f.write(f'                "turbobarcam_script_select_unit {target}",\n')
                        last_target = target

                f.write('            }\n        },\n')

            f.write("    }\n}\n")
            log_func(f"[Success] Script saved to: {filename}")
    except IOError as e:
        log_func(f"[Error] Could not write to file: {e}")

def write_csv_file(units, metadata, filename, log_func):
    """
    Generates a CSV file with unit statistics.
    """
    try:
        os.makedirs(os.path.dirname(filename), exist_ok=True)

        # Determine global end frame for lifetime calculation if diedFrame is missing
        global_end = 0
        if metadata and 'endFrame' in metadata:
            global_end = metadata['endFrame']
        else:
            for u in units.values():
                if "diedFrame" in u and u["diedFrame"]:
                    global_end = max(global_end, u["diedFrame"])
                for s in u.get("statusHistory", []):
                    if s.get("endFrame", 0) < 9999999:
                        global_end = max(global_end, s.get("endFrame", 0))

        with open(filename, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            # Header
            writer.writerow(['Unit ID', 'Unit Name', 'Human Name', 'Final XP', 'Damage Dealt', 'Lifetime (s)'])

            # Data Rows
            # Sort by Final XP descending for better readability
            sorted_units = sorted(units.values(), key=lambda u: u.get("finalXP", 0), reverse=True)

            for unit in sorted_units:
                uid = unit.get('id', 'Unknown')
                name = unit.get('name', 'Unknown')
                human_name = unit.get('humanName', 'Unknown')
                final_xp = unit.get('finalXP', 0)
                damage_dealt = unit.get('damageDealt', 0)

                born_frame = unit.get('bornFrame', 0)
                died_frame = unit.get('diedFrame')

                end_f = died_frame if died_frame else global_end

                lifetime_frames = max(0, end_f - born_frame)
                lifetime_seconds = round(lifetime_frames / 30.0, 2)

                writer.writerow([uid, name, human_name, final_xp, damage_dealt, lifetime_seconds])

        log_func(f"[Success] CSV Statistics saved to: {filename}")
    except IOError as e:
        log_func(f"[Error] Could not write CSV file: {e}")
