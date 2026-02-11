from scriptgenerator.config import constants
from scriptgenerator.core import processing


def generate_timeline(data, log_func, meta_end_frame=0):
    timeline = []
    calc_max_frame = 0
    for u in data.values():
        died_frame = u.get("diedFrame")
        if died_frame:
            calc_max_frame = max(calc_max_frame, died_frame)
        for s in u.get("statusHistory", []):
            if s.get("endFrame", 0) < 10000000:
                calc_max_frame = max(calc_max_frame, s.get("endFrame", 0))

    end_frame = max(calc_max_frame, meta_end_frame)

    log_func(f"Generating Timeline (Max Frame: {end_frame})...")

    # 1. Determine Start (Initial Skip)
    start_anchor = None
    start_frame = 0
    step_check = 30

    # Fast search for the first viable moment
    while start_frame < end_frame:
        uid, score = processing.find_best_unit(data, start_frame, constants.ANCHOR_DURATION)
        if uid:
            start_anchor = uid
            break
        start_frame += step_check
        if start_frame % 5000 == 0:
            log_func(f"Searching for start anchor: frame {start_frame}...")

    init_end = max(30, start_frame)
    timeline.append({
        "type": "init", "start": 0, "end": init_end, "target": 0,
        "unit_data": {'humanName': "Init"}, "note": "Start", "commands": [f"skip f{init_end}"]
    })

    current_frame = init_end
    current_target_id = start_anchor

    # Fallback if no anchor found at all (empty replay?)
    if not current_target_id:
        log_func("Warning: No viable units found for initial anchor.")
        # We will try to pick *any* unit that is alive or just end

    last_cut_start = current_frame

    # 2. Continuous Loop
    while current_frame < end_frame:
        if current_frame % 1000 == 0:
            log_func(f"Progress: {current_frame}/{end_frame} ({(current_frame/end_frame*100):.1f}%)")

        should_switch = False
        switch_reason = ""
        next_target_id = None

        unit = data.get(current_target_id)

        # Check if we MUST switch (Unit died or disappeared)
        is_dead_or_gone = False
        if not unit:
            is_dead_or_gone = True
        else:
            died_val = unit.get("diedFrame")
            if died_val is not None and died_val <= current_frame:
                is_dead_or_gone = True

        if is_dead_or_gone:
            should_switch = True
            switch_reason = "Unit Died/Gone"
        else:
            # Check conditions to switch voluntarily
            status, _, next_status_change = processing.get_unit_status_at_frame(unit, current_frame)

            # If the current unit is not ACTIVE, we look for alternatives more aggressively
            if (current_frame - last_cut_start) > constants.MIN_SWAP_COOLDOWN:
                # Condition A: Current is IDLE/PAUSE, try to find active
                if status != "ACTIVE":
                    best, score = processing.find_best_unit(data, current_frame, constants.MIN_NEIGHBOR_DURATION)
                    if best and best != current_target_id:
                        should_switch = True
                        switch_reason = f"Current {status}, switching to Active"
                        next_target_id = best

                # Condition B: Found a significantly better unit
                if not should_switch:
                    curr_score = processing.calculate_score(unit, current_frame)
                    best, best_score = processing.find_best_unit(data, current_frame, constants.ANCHOR_DURATION)

                    # Ensure we don't swap just for a tiny gain
                    if best and best != current_target_id and best_score > (curr_score * constants.SWAP_SCORE_THRESHOLD):
                        should_switch = True
                        switch_reason = "Found better unit"
                        next_target_id = best

        if should_switch:
            # Commit the previous block
            if current_target_id:
                timeline.append({
                    "type": "cut",
                    "start": last_cut_start,
                    "end": current_frame,
                    "target": current_target_id,
                    "unit_data": data.get(current_target_id, {}),
                    "note": switch_reason
                })

            # Resolve the next target
            if not next_target_id:
                # Try standard search
                best, _ = processing.find_best_unit(data, current_frame, constants.MIN_NEIGHBOR_DURATION)
                next_target_id = best

            if not next_target_id:
                # If standard search failed (e.g., everyone idles), try to find ANY live unit
                if is_dead_or_gone:
                    fallback_best = None
                    for u in data.values():
                        died_val = u.get("diedFrame")
                        if (died_val if died_val is not None else end_frame) > current_frame:
                            fallback_best = u['id']
                            break
                    next_target_id = fallback_best

            if next_target_id:
                # Distance-based transition delay when switching due to death
                if is_dead_or_gone and timeline and timeline[-1]['end'] == current_frame and unit is not None:
                    prev_pos = processing.get_unit_position(unit, current_frame)
                    next_unit = data.get(next_target_id)
                    next_pos = processing.get_unit_position(next_unit, current_frame) if next_unit else None
                    if prev_pos and next_pos:
                        dx = (next_pos['x'] - prev_pos['x'])
                        dz = (next_pos['z'] - prev_pos['z'])
                        dist = (dx*dx + dz*dz) ** 0.5
                        # Map distance [<=500 -> 0, >=1500 -> 30 frames]
                        if dist <= 500:
                            delay_frames = 0
                        elif dist >= 1500:
                            delay_frames = 30
                        else:
                            ratio = (dist - 500.0) / 1000.0
                            delay_frames = int(round(30 * ratio))
                        if delay_frames > 0:
                            timeline[-1]['end'] = min(current_frame + delay_frames, end_frame)
                            current_frame = min(current_frame + delay_frames, end_frame)

                log_func(f"Frame {current_frame}: Switching to {next_target_id} ({switch_reason})")
                current_target_id = next_target_id
                last_cut_start = current_frame
            else:
                log_func(f"Frame {current_frame}: No next target found, stopping.")
                break

        if not should_switch:
            # How far can we safely skip?
            # 1. To the next status change of current unit
            # 2. To the end of MIN_SWAP_COOLDOWN
            # 3. To the next death of current unit
            # 4. To the next global check interval (e.g. 30 frames)

            # For simplicity and safety, we jump 30 frames at most,
            # or to the next status change if it's sooner.
            next_jump = current_frame + 30

            # Never jump past end_frame
            next_jump = min(next_jump, end_frame)

            # If we haven't reached cooldown yet, jump to cooldown end
            # We only do this if we ARE NOT in a "must switch" situation,
            # but wait, this block is only reached if not should_switch.
            cooldown_end = last_cut_start + constants.MIN_SWAP_COOLDOWN + 1
            if current_frame < cooldown_end:
                next_jump = min(next_jump, cooldown_end)

            # If unit dies sooner
            if unit:
                died_val = unit.get("diedFrame")
                if died_val is not None and died_val > current_frame:
                    next_jump = min(next_jump, died_val)

            old_frame = current_frame
            current_frame = max(current_frame + 1, next_jump)
            # log_func(f"  Jump: {old_frame} -> {current_frame} (target: {current_target_id})")
        else:
            current_frame += 1

    # Add a final segment
    if current_target_id and last_cut_start < current_frame:
        timeline.append({
            "type": "cut",
            "start": last_cut_start,
            "end": current_frame,
            "target": current_target_id,
            "unit_data": data.get(current_target_id, {}),
            "note": "End of Replay"
        })

    # Add End marker
    timeline.append({"type": "end", "start": current_frame, "end": current_frame + 30, "target": 0, "unit_data": {'humanName': "END"}, "note": "Finish"})

    return timeline, end_frame
