import os
import csv
import json
from scriptgenerator.core import commands as cmd_gen

# Try to import slpp for parsing source scripts and writing game output
try:
    from slpp import slpp as lua
except ImportError:
    lua = None

# ==============================================================================
# INTERNAL FILE FORMAT (Block/Unit Based) - JSON
# ==============================================================================

def save_internal_json(timeline, filename, log_func=None):
    """
    Saves the timeline in the internal block-based format using JSON.
    DOES NOT save heavy unit_data (histories). Only references/IDs.
    """
    # Group timeline into blocks
    blocks = []
    current_block = None

    for cut in timeline:
        cut_type = cut.get('type')
        if not cut_type: continue

        target_id = cut.get('target', 0)

        # Init and End are special blocks
        if cut_type == 'init':
            blocks.append({
                "type": "init",
                "start": cut['start'],
                "end": cut['end'],
                "segments": [cut] # Minimal segment data is fine
            })
            current_block = None
            continue

        if cut_type == 'end':
            if current_block: blocks.append(current_block)
            blocks.append({
                "type": "end",
                "start": cut['start'],
                "end": cut['end'],
                "segments": [cut]
            })
            current_block = None
            continue

        if current_block:
            prev_id = current_block.get('unit_id')

            should_merge = False
            if str(target_id) == str(prev_id):
                should_merge = True

            if should_merge:
                # Strip heavy data from segment before adding
                clean_seg = cut.copy()
                if 'unit_data' in clean_seg:
                    del clean_seg['unit_data'] # Don't save data in segment either

                # Ensure commands are preserved
                if 'commands' in cut:
                    clean_seg['commands'] = cut['commands']

                current_block['segments'].append(clean_seg)
                current_block['end'] = max(current_block['end'], cut['end'])
            else:
                blocks.append(current_block)
                current_block = None

        if not current_block:
            # Start new block
            u_data = cut.get('unit_data', {})

            # Prepare minimal segment
            clean_seg = cut.copy()
            if 'unit_data' in clean_seg: del clean_seg['unit_data']

            current_block = {
                "type": "unit",
                "unit_id": target_id,
                # Save display names for fallback, but not full history
                "name": u_data.get('name', 'Unknown'),
                "human_name": u_data.get('humanName', 'Unknown'),
                "playerId": u_data.get('playerId'),
                "teamId": u_data.get('teamId'),
                "start": cut['start'],
                "end": cut['end'],
                "segments": [clean_seg]
            }

    if current_block:
        blocks.append(current_block)

    # Post-process: merge adjacent unit blocks with same unit_id as cleanup of obsolete transitions
    merged_blocks = []
    for b in blocks:
        if merged_blocks and b.get('type') == 'unit' and merged_blocks[-1].get('type') == 'unit' and str(b.get('unit_id')) == str(merged_blocks[-1].get('unit_id')):
            merged_blocks[-1]['end'] = max(merged_blocks[-1]['end'], b['end'])
            merged_blocks[-1]['segments'].extend(b.get('segments', []))
        else:
            merged_blocks.append(b)

    data_to_save = {"blocks": merged_blocks}
    os.makedirs(os.path.dirname(filename), exist_ok=True)
    with open(filename, "w") as f:
        json.dump(data_to_save, f, indent=2)

    if log_func: log_func(f"[Internal] Saved {len(blocks)} blocks to {filename}")

def load_internal_json(filename):
    """
    Loads a JSON timeline. Returns a skeleton timeline.
    MUST be followed by enrich_timeline_with_unit_ids to be useful.
    """
    if not os.path.exists(filename): return []

    with open(filename, "r") as f:
        data = json.load(f)

    if 'blocks' in data:
        timeline = []
        blocks = data['blocks']
        blocks.sort(key=lambda b: b.get('start', 0))

        for block in blocks:
            segments = block.get('segments', [])
            segments.sort(key=lambda s: s.get('start', 0))

            for seg in segments:
                if block['type'] == 'unit':
                    seg['target'] = block.get('unit_id')
                    # Reconstruct temporary minimal unit_data
                    if 'unit_data' not in seg:
                        seg['unit_data'] = {
                            'id': block.get('unit_id'),
                            'name': block.get('name'),
                            'humanName': block.get('human_name')
                        }
                timeline.append(seg)
        return timeline
    return []

# ==============================================================================
# GAME OUTPUT FORMAT (Metadata + Steps)
# ==============================================================================

def write_game_script(timeline, filename, replay_name, version, log_func=None):
    """
    Writes the timeline to the game's LuaUI format.
    """
    if not lua:
        if log_func: log_func("Error: slpp not loaded, cannot export game script.")
        return

    replay_name = replay_name.replace(".lua", "")

    os.makedirs(os.path.dirname(filename), exist_ok=True)
    with open(filename, "w") as f:
        f.write("return {\n")

        # Metadata
        f.write("    metadata = {\n")
        f.write(f'        replayName = "{replay_name}",\n')
        f.write(f'        version = {version},\n')
        f.write("    },\n")

        f.write("    steps = {\n")

        last_target_game_id = None # Track the game ID, not the internal ID

        timeline.sort(key=lambda x: x['start'])

        for i, cut in enumerate(timeline):
            start_f = cut['start']
            type_ = cut['type']

            commands = []
            label_text = "Unknown"

            if type_ == 'init':
                label_text = "Init"
                commands = cut.get('commands', ["skip f30"])

            elif type_ == 'end':
                label_text = "END"
                commands = []

            elif type_ == 'cut':
                target_unique_key = cut['target']
                u_data = cut.get('unit_data', {})
                label_text = u_data.get('humanName', 'New Unit')

                # Resolve Game ID for commands
                game_unit_id = u_data.get('unitId', target_unique_key)

                if cut.get('commands'):
                    commands = cut['commands']
                else:
                    if game_unit_id != last_target_game_id:
                        commands = cmd_gen.get_default_unit_commands(game_unit_id)
                        last_target_game_id = game_unit_id

            # Construct Step
            f.write(f"\n        -- STEP #{i+1:02d} {label_text}")
            f.write("\n")
            f.write("        {\n")
            f.write(f'            frame = {start_f},\n')
            f.write(f'            label = "{label_text}",\n')
            f.write('            commands = {\n')

            for cmd in commands:
                f.write(f'                "{cmd}",\n')

            f.write('            }\n        },\n')

        f.write("    }\n}\n")
        if log_func: log_func(f"[Game] Script saved to: {filename}")

def get_game_file_version(filename):
    if not lua or not os.path.exists(filename):
        return None

    with open(filename, "r") as f:
        content = f.read().replace("return", "")
        data = lua.decode(content)
        if 'metadata' in data:
            return data['metadata'].get('version')
    return None

# ==============================================================================
# EXISTING HELPERS
# ==============================================================================

def enrich_timeline_with_unit_ids(timeline, units):
    if not units: return timeline

    current_unit_data = None
    fallback_data = {'humanName': 'Unknown', 'id': 0, 'unitId': 0}

    for cut in timeline:
        if cut['type'] not in ['cut']: continue

        # 1. Existing Data Check (Basic info from JSON)
        target_id = cut.get('target')

        found_unit = None
        if target_id is not None:
            found_unit = units.get(str(target_id)) or units.get(target_id)

        if found_unit:
            current_unit_data = found_unit
            # Update cut with full data
            cut['unit_data'] = current_unit_data
        else:
            if 'unit_data' not in cut:
                cut['unit_data'] = fallback_data

    return timeline

def write_csv_file(units, metadata, filename, log_func):
    os.makedirs(os.path.dirname(filename), exist_ok=True)
    global_end = 0
    if metadata and 'endFrame' in metadata:
        global_end = metadata['endFrame']
    else:
        for u in units.values():
            if "diedFrame" in u and u["diedFrame"]:
                global_end = max(global_end, u["diedFrame"])
            for s in u.get("statusHistory", []):
                if s.get("endFrame", 0) < 10000000:
                    global_end = max(global_end, s.get("endFrame", 0))

    with open(filename, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['Unique ID', 'Game Unit ID', 'Unit Name', 'Human Name', 'Final XP', 'Damage Dealt', 'Lifetime (s)'])
        sorted_units = sorted(units.values(), key=lambda u: u.get("finalXP", 0), reverse=True)

        for unit in sorted_units:
            uid = unit.get('id', 'Unknown')
            game_id = unit.get('unitId', uid)
            name = unit.get('name', 'Unknown')
            human_name = unit.get('humanName', 'Unknown')
            final_xp = unit.get('finalXP', 0)
            damage_dealt = unit.get('damageDealt', 0)
            born_frame = unit.get('bornFrame', 0)
            died_frame = unit.get('diedFrame')
            end_f = died_frame if died_frame else global_end
            lifetime_frames = max(0, end_f - born_frame)
            lifetime_seconds = round(lifetime_frames / 30.0, 2)
            writer.writerow([uid, game_id, name, human_name, final_xp, damage_dealt, lifetime_seconds])

    log_func(f"[Success] CSV Statistics saved to: {filename}")
