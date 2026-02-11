import bisect

class TimelineLogic:
    def __init__(self):
        self.timeline_data = []
        self.original_timeline = []
        self.start_times = []
        self.max_block_duration = 0

        self.selected_block_index = None
        self.selected_block_id = None
        self.subblock_start = None
        self.subblock_end = None
        self.preview_units = []  # List of {unit_data, dist, id}
        self.selected_preview_index = None
        self.global_max_frame = 0

        # Current time cursor (for sync with minimap)
        self.current_time = 0

    def reset(self):
        self.timeline_data = []
        self.original_timeline = []
        self.start_times = []
        self.selected_block_index = None
        self.selected_block_id = None
        self.subblock_start = None
        self.subblock_end = None
        self.preview_units = []
        self.selected_preview_index = None
        self.current_time = 0

    def get_block_uid(self, block):
        if block['type'] == 'block' and block.get('segments'):
            return id(block['segments'][0])
        elif block['type'] in ['init', 'end', 'cut']:
            return id(block)
        elif block['type'] == 'gap':
            return f"gap_{block['start']}_{block['end']}"
        return None

    def process_data(self, timeline_list):
        visual_blocks = []
        current_block = None
        sorted_timeline = sorted(timeline_list, key=lambda x: x['start'])

        for cut in sorted_timeline:
            c_type = cut['type']
            if c_type in ['init', 'end']:
                if current_block:
                    visual_blocks.append(current_block)
                    current_block = None
                visual_blocks.append(cut)
                continue

            c_unique_id = None
            if c_type == 'cut':
                c_unique_id = cut.get('target')
                if c_unique_id is None:
                    c_unique_id = cut.get('unit_data', {}).get('id')
                c_unique_id = str(c_unique_id)

            merged = False
            if current_block and current_block.get('type') == 'block':
                prev_id = current_block.get('unit_id')
                if c_type == 'cut' and c_unique_id == prev_id:
                    current_block['segments'].append(cut)
                    current_block['end'] = cut['end']
                    merged = True

            if not merged:
                if current_block:
                    visual_blocks.append(current_block)
                    current_block = None
                if c_type == 'cut':
                    current_block = {
                        'type': 'block', 'start': cut['start'], 'end': cut['end'],
                        'unit_id': c_unique_id, 'unit_data': cut.get('unit_data', {}), 'segments': [cut]
                    }
                else:
                    visual_blocks.append(cut)
        if current_block: visual_blocks.append(current_block)

        final_visuals = []
        last_end = 0
        if visual_blocks:
            last_end = visual_blocks[0]['end']
            final_visuals.append(visual_blocks[0])
            for i in range(1, len(visual_blocks)):
                block = visual_blocks[i]
                if block['start'] > last_end:
                    final_visuals.append({
                        'type': 'gap', 'start': last_end, 'end': block['start'],
                        'unit_data': {'humanName': 'Empty', 'name': 'Gap'}
                    })
                final_visuals.append(block)
                last_end = block['end']

        self.timeline_data = final_visuals

        # Optimization Pre-calc
        self.start_times = []
        self.max_block_duration = 0
        for b in self.timeline_data:
            self.start_times.append(b['start'])
            dur = b['end'] - b['start']
            if dur > self.max_block_duration:
                self.max_block_duration = dur

    def insert_into_block(self, block_uid, start, end, unit_data, commands):
        target_block = None
        for b in self.timeline_data:
            if self.get_block_uid(b) == block_uid:
                target_block = b
                break

        if not target_block or target_block['type'] != 'block': return None

        # Ensure unit_data is healthy
        if unit_data:
            if 'bornFrame' not in unit_data: unit_data['bornFrame'] = 0
            if 'diedFrame' not in unit_data: unit_data['diedFrame'] = self.global_max_frame or 999999

        orig_unit_data = target_block.get('unit_data')
        orig_id = target_block.get('unit_id')
        total_start = target_block['start']
        total_end = target_block['end']

        # Remove all original segments of this block
        segments_to_remove = target_block.get('segments', [])
        for seg in segments_to_remove:
            if seg in self.original_timeline:
                self.original_timeline.remove(seg)

        # 1. Pre-part
        if total_start < start:
            self.original_timeline.append({
                "type": "cut", "start": total_start, "end": start,
                "target": orig_id, "unit_data": orig_unit_data, "note": "Split Pre", "commands": []
            })

        # 2. The Inserted Part
        new_seg = {
            "type": "cut", "start": start, "end": end,
            "target": unit_data.get('id'), "unit_data": unit_data,
            "note": "Inserted Alternative", "commands": commands or []
        }
        self.original_timeline.append(new_seg)

        # 3. Post-part
        if total_end > end:
            self.original_timeline.append({
                "type": "cut", "start": end, "end": total_end,
                "target": orig_id, "unit_data": orig_unit_data, "note": "Split Post", "commands": []
            })

        self.resolve_overlaps(moved_seg_id=id(new_seg))
        return id(new_seg)

    def calculate_autofit_ppf(self, canvas_width):
        total_frames = 1
        for block in self.timeline_data:
            if block['end'] > total_frames: total_frames = block['end']
        if self.selected_block_id: total_frames = max(total_frames, self.global_max_frame)
        if self.preview_units:
            for alt in self.preview_units:
                u = alt.get('unit', {})
                total_frames = max(total_frames, u.get('diedFrame', self.global_max_frame))

        if total_frames > 0:
            if canvas_width < 100: canvas_width = 800
            return (canvas_width - 50) / total_frames
        return 0.008

    def calculate_total_width(self, ppf):
        total_frames = 1
        for block in self.timeline_data:
            if block['end'] > total_frames: total_frames = block['end']
        if self.selected_block_id: total_frames = max(total_frames, self.global_max_frame)
        if self.preview_units:
            for alt in self.preview_units:
                u = alt.get('unit', {})
                total_frames = max(total_frames, u.get('diedFrame', self.global_max_frame))

        return total_frames * ppf

    def get_data_at_frame(self, frame):
        """
        Returns block and unit status/target info at a specific frame.
        """
        # Find block
        idx = bisect.bisect_right(self.start_times, frame) - 1
        if idx < 0 or idx >= len(self.timeline_data):
            return None

        block = self.timeline_data[idx]
        if frame < block['start'] or frame > block['end']:
            return None

        if block['type'] != 'block':
            return block

        # It's a block, get more info from unit_data if available
        u_data = block.get('unit_data', {})
        if not u_data:
            return block

        from scriptgenerator.core import processing
        status, s_start, s_end = processing.get_unit_status_at_frame(u_data, frame)

        target_info = None
        tgt_hist = u_data.get('targetHistory', [])
        if tgt_hist:
            if "_target_start_frames" in u_data:
                t_idx = bisect.bisect_right(u_data["_target_start_frames"], frame) - 1
                if t_idx >= 0:
                    target_info = tgt_hist[t_idx]
            else:
                for t in reversed(tgt_hist):
                    if t['frame'] <= frame:
                        target_info = t
                        break

        return {
            'block': block,
            'status': status,
            'status_start': s_start,
            'status_end': s_end,
            'target': target_info
        }

    def delete_block(self, block_uid):
        """
        Removes all segments associated with a block UID from the original timeline.
        """
        target_block = None
        for b in self.timeline_data:
            if self.get_block_uid(b) == block_uid:
                target_block = b
                break

        if not target_block or target_block['type'] == 'gap':
            return False

        segments = target_block.get('segments', [target_block])
        for seg in segments:
            if seg in self.original_timeline:
                self.original_timeline.remove(seg)

        return True

    def resolve_overlaps(self, moved_seg_id=None):
        """
        Ensures that blocks do not overlap. If a block's edge was moved,
        it should override (resize or delete) other blocks it now covers.
        """
        if not self.original_timeline: return

        # Sort by start frame
        self.original_timeline.sort(key=lambda x: x['start'])

        # Pre-pass: ensure all segments have born/died frames set if missing
        for s in self.original_timeline:
            u_data = s.get('unit_data', {})
            if 'bornFrame' not in u_data: u_data['bornFrame'] = 0
            if 'diedFrame' not in u_data:
                u_data['diedFrame'] = self.global_max_frame or 999999

        if moved_seg_id:
            moved_idx = next((i for i, s in enumerate(self.original_timeline) if id(s) == moved_seg_id), None)
            if moved_idx is not None:
                moved_seg = self.original_timeline[moved_idx]

                # Overlap with segments BEFORE
                for i in range(moved_idx - 1, -1, -1):
                    other = self.original_timeline[i]
                    if other['end'] > moved_seg['start']:
                        if other['start'] >= moved_seg['start']:
                            # Completely covered from left or moved into it
                            other['end'] = other['start'] # Mark for deletion
                        else:
                            other['end'] = moved_seg['start']
                    else:
                        break # No more overlaps possible before

                # Overlap with segments AFTER
                for i in range(moved_idx + 1, len(self.original_timeline)):
                    other = self.original_timeline[i]
                    if other['start'] < moved_seg['end']:
                        if other['end'] <= moved_seg['end']:
                            # Completely covered
                            other['start'] = other['end'] # Mark for deletion
                        else:
                            other['start'] = moved_seg['end']
                    else:
                        break # No more overlaps possible after

        new_timeline = []
        # Fallback/Regular cleanup: ensure no overlaps remain
        self.original_timeline.sort(key=lambda x: x['start'])

        for i, current in enumerate(self.original_timeline):
            if current['start'] >= current['end']: continue # Skip deleted/invalid

            if not new_timeline:
                new_timeline.append(current)
                continue

            prev = new_timeline[-1]
            if current['start'] >= prev['end']:
                new_timeline.append(current)
            else:
                # Still overlapping? This shouldn't happen if moved_seg_id was used correctly,
                # but for safety: current overrides prev if we got here.
                if current['start'] <= prev['start']:
                    if current['end'] >= prev['end']:
                        new_timeline[-1] = current
                    else:
                        prev['start'] = current['end']
                        new_timeline.insert(-1, current)
                else:
                    prev['end'] = current['start']
                    if prev['end'] > prev['start']:
                        new_timeline.append(current)
                    else:
                        new_timeline[-1] = current

        self.original_timeline = [b for b in new_timeline if b['end'] > b['start']]
        
        # Sync init block commands with its end frame after resolving overlaps
        for b in self.original_timeline:
            if b.get('type') == 'init':
                cmd = f"skip f{b['end']}"
                cmds = b.get('commands') or []
                other_cmds = [c for c in cmds if not (isinstance(c, str) and c.startswith('skip '))]
                b['commands'] = [cmd] + other_cmds

        self.process_data(self.original_timeline)

    def update_block(self, block_uid, new_start, new_end, new_unit_data=None, new_commands=None):
        target_block = None
        for b in self.timeline_data:
            if self.get_block_uid(b) == block_uid:
                target_block = b
                break

        if not target_block: return None

        # Apply lifespan constraints
        u_to_check = new_unit_data if new_unit_data else target_block.get('unit_data', {})
        is_init = target_block.get('type') == 'init'
        if u_to_check:
            born = u_to_check.get('bornFrame', 0)
            died = u_to_check.get('diedFrame')
            if died is None: died = self.global_max_frame

            if not is_init and new_start < born: new_start = born
            if is_init and new_start < 0: new_start = 0
            # Allow extending up to 3s (90 frames) after death
            local_max_end = died + 90
            if is_init:
                local_max_end = self.global_max_frame

            if new_end > local_max_end: new_end = local_max_end
            # Ensure minimum duration
            if new_end < new_start + 30:
                if new_end >= died: new_start = max(born if not is_init else 0, new_end - 30)
                else: new_end = min(local_max_end, new_start + 30)

        needs_redraw = False
        new_uid = block_uid

        # Handle GAP (filling it)
        if target_block['type'] == 'gap':
            if not new_unit_data: return None
            new_block = {
                "type": "cut", "start": new_start, "end": new_end,
                "target": new_unit_data.get('id'),
                "unit_data": new_unit_data, "note": "Filled Gap",
                "commands": new_commands or []
            }
            # Insert into original_timeline at correct position
            insert_idx = 0
            for i, b in enumerate(self.original_timeline):
                if b['start'] >= new_start:
                    insert_idx = i
                    break
                insert_idx = i + 1
            self.original_timeline.insert(insert_idx, new_block)
            return id(new_block)

        # Handle existing block/cut
        segments = target_block.get('segments', []) if target_block['type'] == 'block' else [target_block]
        if segments:
            last_seg = segments[-1]
            old_end = last_seg['end']

            if new_end < old_end:
                last_seg['end'] = new_end
                new_gap_block = {
                    "type": "cut", "start": new_end, "end": old_end, "target": 0,
                    "unit_data": {"id": 0, "name": "Empty", "humanName": "New Block"},
                    "note": "User Created Block", "commands": []
                }
                try:
                    idx = self.original_timeline.index(last_seg)
                    self.original_timeline.insert(idx + 1, new_gap_block)
                    needs_redraw = True
                except ValueError: pass
            elif new_end > old_end:
                last_seg['end'] = new_end
                needs_redraw = True

            first_seg = segments[0]
            if new_start != first_seg['start']:
                first_seg['start'] = new_start
                needs_redraw = True

            # Special handling: keep init block's skip command in sync with its end
            if target_block.get('type') == 'init':
                # Ensure commands exist and have a single skip command matching new end
                cmd = f"skip f{last_seg['end']}"
                if 'commands' in last_seg:
                    # Replace any existing skip with updated one; keep non-skip commands as-is
                    cmds = last_seg.get('commands') or []
                    # Filter out existing skip commands
                    other_cmds = [c for c in cmds if not (isinstance(c, str) and c.startswith('skip '))]
                    last_seg['commands'] = [cmd] + other_cmds
                else:
                    last_seg['commands'] = [cmd]

        # Update unit data if provided
        if new_unit_data:
            current_id = str(target_block.get('unit_id', ''))
            if not current_id: current_id = str(target_block.get('target', ''))

            new_id = str(new_unit_data.get('id', ''))
            if new_id and new_id != current_id:
                for seg in segments:
                    seg['unit_data'] = new_unit_data
                    seg['target'] = new_id
                    if new_commands is not None:
                        seg['commands'] = new_commands

                if target_block['type'] == 'block':
                    target_block['unit_data'] = new_unit_data
                    target_block['unit_id'] = new_id
                needs_redraw = True

        return new_uid if needs_redraw else None
