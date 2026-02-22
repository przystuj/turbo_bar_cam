import os
import re
import bisect
from typing import Dict, List, Optional, Tuple, Any

from scriptgenerator.config import constants


# ==============================================================================
# DATA PROCESSING LOGIC
# ==============================================================================

def get_clean_id(input_file):
    if not input_file: return None
    base_name = os.path.basename(input_file)
    # Basic sanitization for folder names
    clean = re.sub(r'_unitData.*', '', os.path.splitext(base_name)[0])
    return "".join([c for c in clean if c.isalnum() or c in (' ', '_', '-')]).strip()

def get_unit_status_at_frame(unit_data: Dict, frame: int) -> Tuple[str, int, int]:
    if "statusHistory" not in unit_data or not unit_data["statusHistory"]:
        return "IDLE", 0, 999999

    history = unit_data["statusHistory"]
    # Optimization: use cached start frames if available
    if "_status_start_frames" in unit_data:
        idx = bisect.bisect_right(unit_data["_status_start_frames"], frame) - 1
        if idx >= 0:
            segment = history[idx]
            return segment["status"], segment["startFrame"], segment.get("endFrame") or unit_data.get('diedFrame', 999999)
    else:
        # Fallback to linear if not preprocessed
        for segment in history:
            start = segment["startFrame"]
            end = segment.get("endFrame") or unit_data.get('diedFrame', 999999)
            if start <= frame < end:
                return segment["status"], start, end
    return "IDLE", 0, frame

def get_unit_position(unit: Dict, frame: int) -> Optional[Dict]:
    if "positionHistory" not in unit or not unit["positionHistory"]:
        return None
    history = unit["positionHistory"]

    # Optimization: Binary search for the closest frame
    # history is sorted by 'frame'
    frames = [p["frame"] for p in history]
    idx = bisect.bisect_left(frames, frame)

    if idx == 0:
        closest = history[0]
    elif idx == len(history):
        closest = history[-1]
    else:
        # Check which one is closer: idx or idx-1
        p1 = history[idx-1]
        p2 = history[idx]
        if abs(p1["frame"] - frame) <= abs(p2["frame"] - frame):
            closest = p1
        else:
            closest = p2

    if abs(closest["frame"] - frame) > 150: # 5 seconds leniency
        return None
    return closest

def get_watchable_duration(unit, start_frame):
    total_duration = 0
    current_frame = start_frame
    max_watchable = constants.ANCHOR_DURATION * 2
    while total_duration < max_watchable:
        status, _, end_frame = get_unit_status_at_frame(unit, current_frame)
        if status == "IDLE":
            break

        segment_duration = end_frame - current_frame
        # Sanity check for invalid end frames or huge segments
        if segment_duration <= 0:
            break
        if segment_duration > 100000:
            segment_duration = 10000

        total_duration += segment_duration
        current_frame = end_frame

        # Another safety check to prevent infinite loop if end_frame doesn't advance
        if current_frame <= start_frame + total_duration - segment_duration:
            break

    return total_duration

def calculate_score(unit, current_frame):
    status, _, _ = get_unit_status_at_frame(unit, current_frame)
    xp = unit.get("finalXP", 0)
    tier = unit.get("tier", 1)
    score = (xp * constants.WEIGHT_XP) + (tier * constants.WEIGHT_TIER)
    if unit["name"] in constants.PREFERRED_NAMES:
        score *= constants.PREFERENCE_MULTIPLIER
    if unit.get("defID", 0) in constants.PRIORITISE_IDS:
        score *= constants.ID_PRIORITY_MULTIPLIER

    if status == "IDLE":
        # Heavily penalize idle units but don't return 0
        # This allows them to show up as last resort candidates
        return score * 0.01

    return score

def refine_unit_status(unit):
    if "statusHistory" not in unit: return

    pos_hist = unit.get("positionHistory", [])
    target_hist = unit.get("targetHistory", [])

    if target_hist:
        target_hist.sort(key=lambda x: x["frame"])

    unit_tier = unit.get("tier", 1)
    new_history = []

    def get_pos_at(f):
        if not pos_hist: return None
        return get_unit_position(unit, f)

    # Pre-calculate stationary periods (>= 5s)
    if pos_hist:
        # Optimization: Don't re-calculate if already present
        if "_stationary_periods" in unit:
            return

        start = unit.get("bornFrame", 0)
        end = unit.get("diedFrame", 999999)
        sim_step = 30

        stationary_periods = []
        current_stat_start = None

        # Batch positions for faster distance calculation
        # Pre-fetching all positions at once to avoid repeated binary searches
        relevant_frames = range(start, end + 1, sim_step)
        positions = {f: get_pos_at(f) for f in relevant_frames}
        # Also need positions at f - STATIONARY_MIN_FRAMES
        for f in relevant_frames:
            prev_f = f - constants.STATIONARY_MIN_FRAMES
            if prev_f not in positions:
                positions[prev_f] = get_pos_at(prev_f)

        for f in relevant_frames:
            pos_curr = positions.get(f)
            pos_prev = positions.get(f - constants.STATIONARY_MIN_FRAMES)

            is_stationary = False
            if pos_curr and pos_prev:
                dx = pos_curr["x"] - pos_prev["x"]
                dz = pos_curr["z"] - pos_prev["z"]
                dist_sq = dx*dx + dz*dz
                if dist_sq < (constants.STATIONARY_CHECK_DIST * constants.STATIONARY_CHECK_DIST):
                    is_stationary = True

            if is_stationary:
                if current_stat_start is None:
                    current_stat_start = max(start, f - constants.STATIONARY_MIN_FRAMES)
            else:
                if current_stat_start is not None:
                    # Period ended at f - sim_step (or close to it)
                    stat_end = f - sim_step
                    if stat_end - current_stat_start >= constants.STATIONARY_MIN_FRAMES:
                        stationary_periods.append({"start": current_stat_start, "end": stat_end})
                    current_stat_start = None

        if current_stat_start is not None:
            if end - current_stat_start >= constants.STATIONARY_MIN_FRAMES:
                stationary_periods.append({"start": current_stat_start, "end": end})

    unit["_stationary_periods"] = stationary_periods

    def get_target_tier_at(f: int) -> Optional[int]:
        if not target_hist: return None

        # Optimization: use cached frames if available
        if "_target_start_frames" in unit:
            idx = bisect.bisect_right(unit["_target_start_frames"], f) - 1
            if idx >= 0:
                return target_hist[idx].get("tier")
            return None

        # Fallback
        last_tier = None
        for t in target_hist:
            if t["frame"] > f: break
            last_tier = t.get("tier", None)
        return last_tier

    for seg in unit["statusHistory"]:
        if seg["status"] != "ACTIVE":
            new_history.append(seg)
            continue

        start = seg["startFrame"]
        end = seg.get("endFrame", start + 1)
        if end > 9999999: end = unit.get("diedFrame", start + 10000)

        current_sub_start = start
        current_sub_status = "ACTIVE"

        t3_waste_timer = 0
        t1_lazy_timer = 0
        sim_step = 15

        for f in range(start, end, sim_step):
            is_moving = True
            pos_curr = get_pos_at(f)
            pos_prev = get_pos_at(f - constants.STATIONARY_CHECK_FRAMES)

            if pos_curr and pos_prev:
                dx = pos_curr["x"] - pos_prev["x"]
                dz = pos_curr["z"] - pos_prev["z"]
                dist_sq = dx*dx + dz*dz
                if dist_sq < (constants.STATIONARY_CHECK_DIST * constants.STATIONARY_CHECK_DIST):
                    is_moving = False

            target_tier = get_target_tier_at(f)
            calculated_status = "ACTIVE"

            if unit_tier >= 3:
                if not is_moving and target_tier == 1:
                    t3_waste_timer += sim_step
                else:
                    t3_waste_timer = 0

                if t3_waste_timer > constants.TIER_3_IDLE_THRESHOLD:
                    calculated_status = "IDLE"
                elif t3_waste_timer > constants.TIER_3_PAUSE_THRESHOLD:
                    calculated_status = "PAUSE"

            elif unit_tier == 1:
                if not is_moving:
                    t1_lazy_timer += sim_step
                else:
                    t1_lazy_timer = 0

                if t1_lazy_timer > constants.TIER_1_PAUSE_THRESHOLD:
                    calculated_status = "PAUSE"

            if calculated_status != current_sub_status:
                new_history.append({
                    "startFrame": current_sub_start,
                    "endFrame": f,
                    "status": current_sub_status
                })
                current_sub_status = calculated_status
                current_sub_start = f

        new_history.append({
            "startFrame": current_sub_start,
            "endFrame": end,
            "status": current_sub_status
        })

    unit["statusHistory"] = new_history

def preprocess_data(units, apply_filters=True, max_frame=None):
    """
    Processes raw unit data.
    Ensures data integrity (no None values for critical frames).
    """
    processed = {}
    default_max = max_frame if max_frame is not None else 99999999

    for uid, unit in units.items():
        # unique key for internal tracking
        unit['id'] = uid

        # 1. Critical Frame Checks
        if unit.get('bornFrame') is None:
            unit['bornFrame'] = 0

        if unit.get('diedFrame') is None:
            unit['diedFrame'] = default_max

        # Ensure unitId exists (Game ID)
        if 'unitId' not in unit:
            parts = uid.split('_')
            if len(parts) >= 2 and parts[0].isdigit():
                unit['unitId'] = int(parts[0])
            else:
                unit['unitId'] = uid

        # 2. History Processing
        if "statusHistory" in unit:
            history = unit["statusHistory"]
            if isinstance(history, dict): history = list(history.values())

            valid_history = []
            for seg in history:
                if not isinstance(seg, dict): continue
                if seg.get('startFrame') is None: seg['startFrame'] = unit['bornFrame']
                if seg.get('endFrame') is None: seg['endFrame'] = default_max
                if seg.get('status') is None: seg['status'] = "UNKNOWN"
                valid_history.append(seg)

            valid_history.sort(key=lambda x: x["startFrame"])
            unit["statusHistory"] = valid_history
            unit["_status_start_frames"] = [x["startFrame"] for x in valid_history]

        if "positionHistory" in unit:
            pos_hist = unit["positionHistory"]
            if isinstance(pos_hist, dict): pos_hist = list(pos_hist.values())
            valid_pos = [p for p in pos_hist if isinstance(p, dict) and p.get('frame') is not None]
            valid_pos.sort(key=lambda x: x["frame"])
            unit["positionHistory"] = valid_pos

        if "targetHistory" in unit:
            tgt_hist = unit["targetHistory"]
            if isinstance(tgt_hist, dict): tgt_hist = list(tgt_hist.values())

            valid_tgt = []
            for t in tgt_hist:
                if not isinstance(t, dict): continue
                if t.get('frame') is None: continue
                if t.get('tier') is None: t['tier'] = 1
                valid_tgt.append(t)

            valid_tgt.sort(key=lambda x: x["frame"])
            unit["targetHistory"] = valid_tgt
            unit["_target_start_frames"] = [x["frame"] for x in valid_tgt]

        if "projectileHistory" in unit:
            proj_hist = unit["projectileHistory"]
            if isinstance(proj_hist, dict): proj_hist = list(proj_hist.values())
            valid_proj = [p for p in proj_hist if isinstance(p, dict) and p.get('frame') is not None]
            valid_proj.sort(key=lambda x: x["frame"])
            unit["projectileHistory"] = valid_proj

        # 3. Filtering
        if apply_filters:
            if unit.get("name") in constants.IGNORE_NAMES: continue
            def_id = unit.get("defID")
            if def_id is not None and def_id in constants.IGNORE_IDS: continue

            game_id = unit.get('unitId')
            if game_id is not None:
                try:
                    if int(game_id) in constants.IGNORE_IDS: continue
                except (ValueError, TypeError):
                    if game_id in constants.IGNORE_IDS: continue

        refine_unit_status(unit)

        # Re-update cache after refinement
        if "statusHistory" in unit:
            unit["_status_start_frames"] = [x["startFrame"] for x in unit["statusHistory"]]

        processed[uid] = unit
    return processed

def find_best_unit(units, start_frame, min_duration, center_pos=None, radius=None, exclude_id=None, require_active_start=False):
    best_id = None
    best_score = -1
    score_end_frame = start_frame + min_duration

    for uid, unit in units.items():
        if exclude_id and uid == exclude_id: continue

        status, _, _ = get_unit_status_at_frame(unit, start_frame)
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

def get_candidates_at_frame(all_units, frame, ref_unit_id, count=5, db=None, ref_unit_full=None):
    """
    Finds alternative units at a specific frame.
    Prioritizes Score (Activity/XP/Tier), then orders by Distance from ref_unit.
    """
    candidates = []

    # Resolve reference position
    ref_pos = None
    if ref_unit_full:
        ref_pos = get_unit_position(ref_unit_full, frame)
    elif ref_unit_id:
        ref_unit = all_units.get(str(ref_unit_id)) or all_units.get(ref_unit_id)
        if ref_unit:
            # If we have DB, we might need to load full unit for position
            if db and 'positionHistory' not in ref_unit:
                ref_unit = db.get_unit_full(str(ref_unit_id))
            if ref_unit:
                ref_pos = get_unit_position(ref_unit, frame)

    for uid, unit in all_units.items():
        # Skip self
        if ref_unit_id and str(uid) == str(ref_unit_id): continue

        # Check basic life
        born = unit.get('bornFrame', 0)
        died = unit.get('diedFrame', 999999)

        if not (born <= frame <= died): continue

        # To calculate score accurately, we might need status history
        # For performance, we can do a rough score first, then refine for top candidates
        score = calculate_score(unit, frame)
        if score <= 0: continue

        # Calculate Distance
        dist = 99999999
        if ref_pos:
            # If we have DB, we need to load position for this unit
            u_pos_data = unit
            if db and 'positionHistory' not in unit:
                u_pos_data = db.get_unit_full(str(uid))
                # Update unit in all_units to cache it? Better not to bloat memory too much
                # but we need it for this calculation.

            if u_pos_data:
                u_pos = get_unit_position(u_pos_data, frame)
                if u_pos:
                    dx = ref_pos['x'] - u_pos['x']
                    dz = ref_pos['z'] - u_pos['z']
                    dist = (dx*dx + dz*dz)**0.5

        candidates.append({
            'id': uid,
            'unit': unit,
            'score': score,
            'dist': dist
        })

    # Strategy: Select top N by Score, then sort those by Distance
    # This ensures we get "Good" units that are also "Close" if possible.
    # If we sort purely by distance, we get boring scouts.
    # If we sort purely by score, we get cross-map jumps.

    # 1. Sort by Score Descending
    candidates.sort(key=lambda x: x['score'], reverse=True)

    # 2. Take a pool of top candidates (e.g. 20)
    pool = candidates[:20]

    # 3. Sort pool by Distance Ascending
    pool.sort(key=lambda x: x['dist'])

    # 4. Return top 'count'
    return pool[:count]

def get_candidates_for_range(all_units, start_frame, end_frame, ref_unit_id, count=5, db=None, ref_unit_full=None):
    """
    Finds alternative units for a duration range.
    Uses multiple snapshots (sampling) to ensure the unit is good throughout the whole range.
    """
    candidates = []
    duration = end_frame - start_frame
    if duration <= 0:
        return get_candidates_at_frame(all_units, start_frame, ref_unit_id, count, db, ref_unit_full)

    # Sample up to 10 points across the range
    num_samples = 10
    samples = []
    if duration < 30: # Very small range, just use start and end
        samples = [start_frame, end_frame]
    else:
        step = duration / (num_samples - 1)
        samples = [int(start_frame + i * step) for i in range(num_samples)]

    # Resolve reference position at midpoint (or average positions?)
    mid_frame = (start_frame + end_frame) // 2
    ref_pos = None
    if ref_unit_full:
        ref_pos = get_unit_position(ref_unit_full, mid_frame)
    elif ref_unit_id:
        ref_unit = all_units.get(str(ref_unit_id)) or all_units.get(ref_unit_id)
        if ref_unit:
            if db and 'positionHistory' not in ref_unit:
                ref_unit = db.get_unit_full(str(ref_unit_id))
            if ref_unit:
                ref_pos = get_unit_position(ref_unit, mid_frame)

    # Debug counters
    total_units = len(all_units)
    skip_self = 0
    skip_life = 0
    skip_score = 0

    for uid, unit in all_units.items():
        if ref_unit_id and str(uid) == str(ref_unit_id):
            skip_self += 1
            continue

        # Check basic life
        born = unit['bornFrame']
        died = unit['diedFrame']

        if born is None or died is None:
            # if born is None: born = 0
            # if died is None: died = 999999
            pass # Preprocessing should have fixed this

        # Must be alive for at least 50% of the range (reduced from 80%)
        overlap_start = max(born, start_frame)
        overlap_end = min(died, end_frame)
        if (overlap_end - overlap_start) < (duration * 0.5):
            skip_life += 1
            continue

        # Calculate average score across samples
        scores = []
        sample_count = 0
        for s_frame in samples:
            # Check if alive at this specific sample
            if born <= s_frame <= died:
                scores.append(calculate_score(unit, s_frame))
                sample_count += 1
            else:
                # If dead, it gets a 0, but it might still be overall good
                scores.append(0)

        if not scores:
            skip_score += 1
            continue

        avg_score = sum(scores) / len(scores)

        # Also consider "Active Score" - score only during alive samples
        active_avg_score = sum(scores) / sample_count if sample_count > 0 else 0

        # Skip only truly zero units.
        # Using active_avg_score ensures we don't penalize units too much
        # for being dead during a small part of the range.
        if active_avg_score <= 0.05 and avg_score <= 0.01:
            skip_score += 1
            continue

        # Calculate Distance at midpoint
        dist = 99999999
        if ref_pos:
            u_pos_data = unit
            if db and 'positionHistory' not in unit:
                u_pos_data = db.get_unit_full(str(uid))

            if u_pos_data:
                u_pos = get_unit_position(u_pos_data, mid_frame)
                if u_pos:
                    dx = ref_pos['x'] - u_pos['x']
                    dz = ref_pos['z'] - u_pos['z']
                    dist = (dx*dx + dz*dz)**0.5

        candidates.append({
            'id': uid,
            'unit': unit,
            'score': avg_score,
            'active_score': active_avg_score,
            'dist': dist
        })

    # Strategy: Pick top pool by score, then sort by distance
    candidates.sort(key=lambda x: x['score'], reverse=True)

    pool = candidates[:60] # Increased pool for even more variety
    pool.sort(key=lambda x: x['dist'])
    return pool[:count]

def build_lookup_table(units: Dict[str, Dict]) -> Dict[str, List[Dict]]:
    lookup_table = {}
    for unique_id, u_data in units.items():
        gid = u_data.get('unitId')
        if gid is not None:
            k = str(gid)
            if k not in lookup_table: lookup_table[k] = []
            lookup_table[k].append(u_data)
    for k in lookup_table:
        lookup_table[k].sort(key=lambda x: x.get('bornFrame', 0))
    return lookup_table

def resolve_unit_id_input(input_id_str: str, start_frame: int, end_frame: int, units_registry: Dict, lookup_table: Dict) -> Optional[Dict]:
    if input_id_str in units_registry:
        return units_registry[input_id_str]
    if input_id_str in lookup_table:
        candidates = lookup_table[input_id_str]
        best_cand = None
        for u in candidates:
            born = u.get('bornFrame', 0)
            died = u.get('diedFrame', 999999)
            if max(start_frame, born) < min(end_frame, died):
                best_cand = u
                break
        if best_cand: return best_cand
        if candidates: return candidates[-1]
    return None
