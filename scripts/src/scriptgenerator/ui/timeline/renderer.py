import bisect
import time
from scriptgenerator.core import utils
from scriptgenerator.config import constants


class TimelineRenderer:
    def __init__(self, canvas, config):
        self.canvas = canvas
        self.config = config

    def draw_scene(self, view_min_x, view_max_x, total_width, data_provider):
        start_t = time.time()

        # Constants
        ROW_HEIGHT = 80
        MARGIN_TOP = 20
        MID_GAP = 30
        MAIN_Y_TOP = MARGIN_TOP
        MAIN_Y_BOTTOM = MARGIN_TOP + ROW_HEIGHT
        UNIT_Y_TOP = MAIN_Y_BOTTOM + MID_GAP + 10
        UNIT_Y_BOTTOM = UNIT_Y_TOP + 60

        # Multiple Alternatives rows
        ALT_START_Y = UNIT_Y_BOTTOM + MID_GAP + 10
        ALT_ROW_HEIGHT = 64
        ALT_GAP = 30 # Increased from 15

        # Draw Background Lines (Culled to view for performance)
        line_start = max(0, view_min_x)
        line_end = min(total_width + 500, view_max_x)

        if line_start < line_end:
            self.canvas.create_line(line_start, MAIN_Y_BOTTOM + 20, line_end, MAIN_Y_BOTTOM + 20, fill="#eeeeee", width=2, dash=(4, 4))
            self.canvas.create_line(line_start, UNIT_Y_BOTTOM + 20, line_end, UNIT_Y_BOTTOM + 20, fill="#eeeeee", width=2, dash=(4, 4))

            # Additional lines for alternatives if needed
            for i in range(5):
                y = ALT_START_Y + i * (ALT_ROW_HEIGHT + ALT_GAP) + ALT_ROW_HEIGHT + 10
                self.canvas.create_line(line_start, y, line_end, y, fill="#f5f5f5", width=1, dash=(2, 2))

        selected_block_data = None

        ppf = self.config.pixels_per_frame

        # Performance: When zoomed in significantly, we can skip drawing status bars for every block
        # that is not the selected one if they are too small to see anyway.
        # Threshold: if pixels per frame is very high, we draw everything.
        # If pixels per frame is low (zoomed out), we only draw status bars for the selected one or large ones.
        is_high_zoom = ppf > 0.5

        # Optimization: Binary Search start index
        start_frame_view = view_min_x / ppf

        # Look back enough to cover the max possible block duration
        safe_start_frame = start_frame_view - data_provider.max_block_duration
        if safe_start_frame < 0: safe_start_frame = 0

        # Use bisect_left and go back one index to be extra safe against edge cases
        start_index = max(0, bisect.bisect_left(data_provider.start_times, safe_start_frame) - 1)

        # Iterate from binary search result
        timeline_data = data_provider.timeline_data
        for i in range(start_index, len(timeline_data)):
            block = timeline_data[i]

            x1 = block['start'] * ppf
            x2 = block['end'] * ppf
            if (x2 - x1) < 2: x2 = x1 + 2

            # Optimization: Early Exit
            if x1 > view_max_x:
                break

            # Culling Check
            if x2 < view_min_x:
                continue

            b_type = block['type']
            y_top = MAIN_Y_TOP
            y_bottom = MAIN_Y_BOTTOM

            block_uid = data_provider.get_block_uid(block)
            is_selected = (block_uid == data_provider.selected_block_id) and (block_uid is not None)

            outline_color = "#999999"
            line_width = 1
            if is_selected:
                outline_color = "#FF0000"
                line_width = 3
                data_provider.selected_block_index = i
                selected_block_data = block

            if b_type == 'end':
                x2 = x1 + 25
                self.canvas.create_rectangle(x1, y_top - 5, x2, y_bottom + 5, fill="#444", outline="black", tags=("segment", str(i)))
                self.canvas.create_text((x1 + x2) / 2, (y_top + y_bottom) / 2, text="END", angle=90, fill="white", font=("Arial", 8, "bold"), tags=("segment", str(i)))

            elif b_type == 'init':
                self.canvas.create_rectangle(x1, y_top, x2, y_bottom, fill="#aaeedd", outline="#55aaaa", tags=("segment", str(i)))
                if (x2 - x1) > 20:
                    self.canvas.create_text((x1 + x2) / 2, (y_top + y_bottom) / 2, text="Skip", font=("Tahoma", 9, "bold"), tags=("segment", str(i)))

            elif b_type == 'gap':
                self.canvas.create_rectangle(x1, y_top, x2, y_bottom, fill="#cccccc", outline=outline_color, width=line_width, tags=("segment", str(i)))
                if (x2 - x1) > 30:
                    self.canvas.create_text((x1 + x2) / 2, (y_top + y_bottom) / 2, text="GAP", font=("Tahoma", 8), fill="#888", tags=("segment", str(i)))

            elif b_type == 'block':
                u_data = block.get('unit_data', {})
                name = u_data.get('humanName', 'Unknown')
                internal_name = u_data.get('name', '')
                display_id = u_data.get('unitId', block.get('unit_id', ''))

                fill_color = "#aaffaa"
                if name == "Unknown ID" or name == "Unknown" or name == "Empty" or name == "New Block":
                    fill_color = "#d0d0d0"
                if name == "Unknown Unit":
                    fill_color = "#99ee99"

                # Draw block background
                self.canvas.create_rectangle(x1, y_top, x2, y_bottom, fill=fill_color, outline=outline_color, width=line_width, tags=("segment", str(i), "block"))

                # Draw separator at the end of the block
                self.canvas.create_line(x2, y_top, x2, y_bottom, fill="#666666", width=1, tags=("segment", str(i)))

                if (x2 - x1) > 20:
                    dur_sec = (block['end'] - block['start']) / 30.0
                    dur_str = f"{dur_sec:.1f}s"
                    pid = u_data.get('playerId')
                    tid = u_data.get('teamId')
                    pt_str = f" P{pid} T{tid}" if (pid is not None and tid is not None) else ""
                    sub_text = f"{internal_name} ({display_id}){pt_str}"

                    # Optimization: Only draw detailed text if block is wide enough
                    if (x2 - x1) > 60:
                        time_str = utils.format_time(block['start'])
                        # Approximate width of timestamp: ~45px for "00:00"

                        if (x2 - x1) > 120:
                            self.canvas.create_text(x1 + 5, y_top + 5, text=time_str, anchor="nw", font=("Consolas", 8), fill="#444", tags=("segment", str(i)))

                        center_y = y_top + 20
                        # Calculate available width for name
                        avail_w = (x2 - x1) - 10
                        char_limit = max(2, int(avail_w / 7))

                        display_name = name
                        if len(display_name) > char_limit:
                            display_name = display_name[:max(0, char_limit - 2)] + ".."

                        self.canvas.create_text((x1 + x2) / 2, center_y - 5, text=dur_str, font=("Tahoma", 7), fill="#333", tags=("segment", str(i)), anchor="s")
                        self.canvas.create_text((x1 + x2) / 2, center_y + 10, text=display_name, font=("Tahoma", 9, "bold"), fill="black", tags=("segment", str(i)), anchor="s")
                        self.canvas.create_text((x1 + x2) / 2, center_y + 25, text=sub_text, font=("Tahoma", 7), fill="#222", tags=("segment", str(i)), anchor="s")
                    else:
                        # Short label for small blocks
                        short_name = name[:max(1, int((x2 - x1) / 8))]
                        self.canvas.create_text((x1 + x2) / 2, y_top + 15, text=short_name, font=("Tahoma", 8), fill="black", tags=("segment", str(i)))

                # Draw statuses (Simplified for performance)
                if is_selected or (x2 - x1) > 100 or is_high_zoom:
                    self._draw_status_history(u_data, block['start'], block['end'], y_bottom, 32, ppf, view_min_x, view_max_x, str(i))

        # 4. Draw Lifecycle Rows (Unit Detail & Alternatives)
        if selected_block_data and selected_block_data['type'] == 'block':
            self.draw_unit_lifecycle(selected_block_data.get('unit_data'), UNIT_Y_TOP, UNIT_Y_BOTTOM, ppf, view_min_x, view_max_x, data_provider.global_max_frame, selected_block=selected_block_data, data_provider=data_provider)

        # Draw Alternatives
        if data_provider.preview_units:
            # Pre-calculate subblock center for alternative labels
            subblock_center_x = None
            if data_provider.subblock_start is not None:
                sb1 = data_provider.subblock_start
                sb2 = data_provider.subblock_end if data_provider.subblock_end is not None else sb1
                subblock_center_x = ((sb1 + sb2) / 2) * ppf

            for idx, alt_entry in enumerate(data_provider.preview_units):

                alt_u_data = alt_entry['unit']
                dist = alt_entry['dist']

                y_t = ALT_START_Y + idx * (ALT_ROW_HEIGHT + ALT_GAP) + 15 # Added space for label
                y_b = y_t + ALT_ROW_HEIGHT

                is_preview_selected = (data_provider.selected_preview_index == idx)

                self.draw_unit_lifecycle(
                    alt_u_data, y_t, y_b, ppf, view_min_x, view_max_x,
                    data_provider.global_max_frame,
                    data_provider=data_provider,
                    alt_info={'dist': dist, 'selected': is_preview_selected, 'index': idx, 'subblock_center_x': subblock_center_x}
                )

        # 5. Draw Overlays (Vertical Lines & Labels) LAST so they are on top
        # Subblock highlight - vertical lines
        if data_provider and data_provider.subblock_start is not None:
            sb1 = data_provider.subblock_start
            sb2 = data_provider.subblock_end if data_provider.subblock_end is not None else sb1
            real_sb1 = min(sb1, sb2)
            real_sb2 = max(sb1, sb2)
            sx1 = real_sb1 * ppf
            sx2 = real_sb2 * ppf

            # Subblock vertical lines across ALL rows
            # Determine bottom-most Y
            max_y = ALT_START_Y + (len(data_provider.preview_units) if data_provider.preview_units else 0) * (ALT_ROW_HEIGHT + ALT_GAP)
            if not data_provider.preview_units: max_y = UNIT_Y_BOTTOM + 20

            self.canvas.create_line(sx1, MAIN_Y_TOP, sx1, max_y, fill="blue", width=2, dash=(2, 2), tags="subblock_main")
            if sx2 - sx1 > 1:
                self.canvas.create_line(sx2, MAIN_Y_TOP, sx2, max_y, fill="blue", width=2, dash=(2, 2), tags="subblock_main")

        # Current Block highlight - vertical lines
        if selected_block_data:
            sel_x1 = selected_block_data['start'] * ppf
            sel_x2 = selected_block_data['end'] * ppf

            max_y = ALT_START_Y + (len(data_provider.preview_units) if data_provider.preview_units else 0) * (ALT_ROW_HEIGHT + ALT_GAP)
            if not data_provider.preview_units: max_y = UNIT_Y_BOTTOM + 20

            self.canvas.create_line(sel_x1, MAIN_Y_TOP, sel_x1, max_y, fill="#ff0000", width=2, dash=(4, 4), tags="selection_main")
            self.canvas.create_line(sel_x2, MAIN_Y_TOP, sel_x2, max_y, fill="#ff0000", width=2, dash=(4, 4), tags="selection_main")

            # Add labels for selection
            label_x = (sel_x1 + sel_x2) / 2
            label_x = max(view_min_x + 50, min(view_max_x - 50, label_x))
            self.canvas.create_text(label_x, MAIN_Y_TOP - 2, text="SELECTED", fill="#ff0000", anchor="s", font=("Arial", 8, "bold"), tags="selection_main")

        # Current time cursor as dotted line across all rows
        if hasattr(data_provider, 'current_time') and data_provider.current_time is not None:
            cur_x = data_provider.current_time * ppf
            max_y = ALT_START_Y + (len(data_provider.preview_units) if data_provider.preview_units else 0) * (ALT_ROW_HEIGHT + ALT_GAP)
            if not data_provider.preview_units: max_y = UNIT_Y_BOTTOM + 20
            if view_min_x - 10 <= cur_x <= view_max_x + 10:
                # Extend higher: go to 0 instead of MAIN_Y_TOP
                self.canvas.create_line(cur_x, 0, cur_x, max_y, fill="#444444", width=2, dash=(2, 4), tags="current_time")
                # Optional small label near top - also moved up
                self.canvas.create_text(min(max(cur_x, view_min_x + 30), view_max_x - 30), 2, text=f"t={int(data_provider.current_time)}", fill="#444444", anchor="nw", font=("Arial", 7), tags="current_time")

            # Draw distance to previous and next blocks
            sel_idx = data_provider.selected_block_index
            if sel_idx is not None:
                timeline_data = data_provider.timeline_data

                # Ensure selected_block_data is available even if it was culled from view
                if selected_block_data is None and 0 <= sel_idx < len(timeline_data):
                    selected_block_data = timeline_data[sel_idx]

                if selected_block_data:
                    # Prepare coordinates for label placement
                    sel_x1 = selected_block_data['start'] * ppf
                    sel_x2 = selected_block_data['end'] * ppf

                    # Distance to PREVIOUS block
                    if sel_idx > 0:
                        prev_b = timeline_data[sel_idx - 1]
                        if prev_b['type'] == 'block':
                            u_current = selected_block_data.get('unit_data')
                            u_prev = prev_b.get('unit_data')
                            if u_current and u_prev:
                                # Hide distance labels if block is too small (needs 2x more space than name label)
                                if (sel_x2 - sel_x1) > 240:
                                    frame = selected_block_data['start']
                                    pos_curr = utils.get_unit_pos_at_frame(u_current, frame)
                                    pos_prev = utils.get_unit_pos_at_frame(u_prev, frame)
                                    dist = utils.calculate_distance(pos_curr, pos_prev)
                                    if dist is not None:
                                        label = f"dist: {int(dist)}"
                                        self.canvas.create_text(sel_x1 + 5, MAIN_Y_TOP + 25, text=label, anchor="nw",
                                                                font=("Arial", 8, "bold"), fill="#0055aa", tags="selection_main")

                    # Distance to NEXT block
                    if sel_idx < len(timeline_data) - 1:
                        next_b = timeline_data[sel_idx + 1]
                        if next_b['type'] == 'block':
                            u_current = selected_block_data.get('unit_data')
                            u_next = next_b.get('unit_data')
                            if u_current and u_next:
                                # Hide distance labels if block is too small (needs 2x more space than name label)
                                if (sel_x2 - sel_x1) > 240:
                                    frame = selected_block_data['end']
                                    pos_curr = utils.get_unit_pos_at_frame(u_current, frame)
                                    pos_next = utils.get_unit_pos_at_frame(u_next, frame)
                                    dist = utils.calculate_distance(pos_curr, pos_next)
                                    if dist is not None:
                                        label = f"dist: {int(dist)}"
                                        self.canvas.create_text(sel_x2 - 5, MAIN_Y_TOP + 25, text=label, anchor="ne",
                                                                font=("Arial", 8, "bold"), fill="#0055aa", tags="selection_main")

        if data_provider.subblock_start is not None:
            sb_x1 = data_provider.subblock_start * ppf
            sb_x2 = (data_provider.subblock_end if data_provider.subblock_end is not None else data_provider.subblock_start) * ppf

            # Calculate duration in seconds
            dur_frames = abs(sb_x2 - sb_x1) / ppf
            dur_sec = dur_frames / 30.0
            sb_text = f"REPLACE ({dur_sec:.1f}s)"

            label_sb_x = (sb_x1 + sb_x2) / 2
            label_sb_x = max(view_min_x + 50, min(view_max_x - 50, label_sb_x))
            self.canvas.create_text(label_sb_x, max_y + 2, text=sb_text, fill="blue", anchor="n", font=("Arial", 8, "bold"), tags="subblock_main")

        # 6. Draw Alternative Labels (LAST so they are in front of dotted lines)
        if data_provider.preview_units:
            for idx, alt_entry in enumerate(data_provider.preview_units):

                alt_u_data = alt_entry['unit']

                # Get the relevant units and frames for distance calculations
                u_curr = selected_block_data.get('unit_data') if selected_block_data else None
                u_prev = None
                u_next = None

                sel_idx = data_provider.selected_block_index
                timeline_data = data_provider.timeline_data
                if sel_idx is not None:
                    if sel_idx > 0:
                        prev_b = timeline_data[sel_idx - 1]
                        if prev_b['type'] == 'block':
                            u_prev = prev_b.get('unit_data')
                    if sel_idx < len(timeline_data) - 1:
                        next_b = timeline_data[sel_idx + 1]
                        if next_b['type'] == 'block':
                            u_next = next_b.get('unit_data')

                # Calculate the 3 distances
                dist_sel = "-"
                dist_prev = "-"
                dist_next = "-"

                if u_curr and data_provider.subblock_start is not None:
                    f = data_provider.subblock_start
                    p1 = utils.get_unit_pos_at_frame(alt_u_data, f)
                    p2 = utils.get_unit_pos_at_frame(u_curr, f)
                    d = utils.calculate_distance(p1, p2)
                    if d is not None: dist_sel = int(d)

                if u_prev and selected_block_data:
                    f = selected_block_data['start']
                    p1 = utils.get_unit_pos_at_frame(alt_u_data, f)
                    p2 = utils.get_unit_pos_at_frame(u_prev, f)
                    d = utils.calculate_distance(p1, p2)
                    if d is not None: dist_prev = int(d)

                if u_next and selected_block_data:
                    f = selected_block_data['end']
                    p1 = utils.get_unit_pos_at_frame(alt_u_data, f)
                    p2 = utils.get_unit_pos_at_frame(u_next, f)
                    d = utils.calculate_distance(p1, p2)
                    if d is not None: dist_next = int(d)

                y_t = ALT_START_Y + idx * (ALT_ROW_HEIGHT + ALT_GAP) + 15

                tags = ("lifecycle", "alternative", f"alt_{idx}")

                # Format label with 3 distances
                name = alt_u_data.get('humanName', 'Unit')
                uid = alt_u_data.get('unitId', '?')
                label = f"{name} ({uid}) | Dist: S:{dist_sel} P:{dist_prev} N:{dist_next}"

                # Positioning X at subblock center if available
                subblock_center_x = None
                if data_provider.subblock_start is not None:
                    sb1 = data_provider.subblock_start
                    sb2 = data_provider.subblock_end if data_provider.subblock_end is not None else sb1
                    subblock_center_x = ((sb1 + sb2) / 2) * ppf

                text_x = subblock_center_x
                x1 = alt_u_data.get('bornFrame', 0) * ppf
                x2 = (alt_u_data.get('diedFrame') or data_provider.global_max_frame or 999999) * ppf

                if text_x is None:
                    text_x = max(x1 + 10, view_min_x + 10) # Fallback to sticky left

                # Keep label within visible part of the unit bar and viewport
                text_x = max(x1 + 5, min(x2 - 5, text_x)) # Within unit bar
                text_x = max(view_min_x + 5, min(view_max_x - 5, text_x)) # Within viewport

                # Add background to label for better readability against dotted lines
                # Estimate text width (roughly 6px per char)
                char_count = len(label)
                tw = char_count * 6 + 10
                # Padding: user asked for same padding at top as bottom (approx 3px)
                # Text is anchor="s" at y_t - 5.
                # Label rect should cover the text. Font is 9pt bold (~12px height).
                # Rect from y_t - 18 to y_t - 2 gives 16px height.
                # If text center is at y_t - 11, then 18 is 7px above center, 2 is 9px below center.
                # Adjusted for symmetrical padding:
                self.canvas.create_rectangle(text_x - tw/2, y_t - 20, text_x + tw/2, y_t - 2, fill="white", outline="#0055aa", tags=tags)
                self.canvas.create_text(text_x, y_t - 5, text=label, anchor="s", font=("Arial", 9, "bold"), fill="#0055aa", tags=tags)

        end_t = time.time()
        # Only log if it's slow (> 16ms for 60fps)
        if (end_t - start_t) > 0.016:
            print(f"[Telemetry] draw_scene took {(end_t - start_t) * 1000:.2f}ms. View: {view_min_x:.0f}-{view_max_x:.0f}, ppf: {ppf:.4f}, start_index: {start_index}")

    def _draw_status_history(self, u_data, block_start, block_end, y_bottom, bar_height, ppf, view_min_x, view_max_x, tag_id):
        status_hist = u_data.get('statusHistory', [])
        if not status_hist: return

        h_y1 = y_bottom - bar_height
        h_y2 = y_bottom

        start_view_f = view_min_x / ppf
        end_view_f = view_max_x / ppf

        # PERFORMANCE FIX: Binary search for visible history segments (bounded by view)
        hist_start_idx = 0
        if "_status_start_frames" in u_data:
            search_start = max(block_start, start_view_f)
            hist_start_idx = bisect.bisect_left(u_data["_status_start_frames"], search_start)
            if hist_start_idx > 0: hist_start_idx -= 1

        for k in range(hist_start_idx, len(status_hist)):
            seg = status_hist[k]
            if seg['startFrame'] > min(block_end, end_view_f): break  # Early exit

            s_start = seg['startFrame']
            s_end = seg.get('endFrame') or u_data.get('diedFrame', 999999)
            draw_start = max(block_start, s_start)
            draw_end = min(block_end, s_end)

            if draw_start < draw_end:
                sx1 = max(view_min_x - 5, draw_start * ppf)
                sx2 = min(view_max_x + 5, draw_end * ppf)

                if sx1 < sx2:
                    # Optimization: Skip drawing if segment is too thin to see (sub-pixel)
                    if sx2 - sx1 < 0.3: continue

                    s_status = seg['status']
                    s_color = constants.COLOR_IDLE
                    if s_status == "ACTIVE":
                        s_color = constants.COLOR_ACTIVE
                    elif s_status == "PAUSE":
                        s_color = constants.COLOR_PAUSE

                    self.canvas.create_rectangle(sx1, h_y1, sx2, h_y2, fill=s_color, outline="#999999", width=1, tags=("segment", tag_id))

                    if s_status == "ACTIVE":
                        # Only draw targets if the segment is wide enough to actually see them
                        if (sx2 - sx1) > 2:
                            self._draw_targets(u_data, draw_start, draw_end, h_y1 + (bar_height / 2), h_y2, ppf, view_min_x, view_max_x, tag_id)

        # Draw Stationary Periods (highlight)
        stationary_periods = u_data.get('_stationary_periods', [])
        for sp in stationary_periods:
            sp_start = sp['start']
            sp_end = sp['end']
            draw_start = max(block_start, sp_start)
            draw_end = min(block_end, sp_end)

            if draw_start < draw_end:
                sp_x1 = max(view_min_x - 5, draw_start * ppf)
                sp_x2 = min(view_max_x + 5, draw_end * ppf)

                if sp_x1 < sp_x2:
                    if sp_x2 - sp_x1 < 0.3: continue
                    # Draw as a top highlight on the status bar
                    self.canvas.create_rectangle(sp_x1, h_y1, sp_x2, h_y1 + 4, fill=constants.COLOR_STATIONARY, outline="", tags=("segment", tag_id))

    def _draw_targets(self, u_data, draw_start, draw_end, t_y1, t_y2, ppf, view_min_x, view_max_x, tag_id, is_lifecycle=False):
        tgt_hist = u_data.get('targetHistory', [])
        if not tgt_hist: return

        start_view_f = view_min_x / ppf
        end_view_f = view_max_x / ppf

        # Binary search for targets (bounded by view)
        t_start_idx = 0
        if "_target_start_frames" in u_data:
            search_start = max(draw_start, start_view_f)
            t_start_idx = bisect.bisect_left(u_data["_target_start_frames"], search_start)
            if t_start_idx > 0: t_start_idx -= 1

        # We need to merge consecutive targets with the same human name
        # We'll iterate through the history and group them
        i = t_start_idx
        while i < len(tgt_hist):
            tgt = tgt_hist[i]
            t_frame = tgt['frame']
            if t_frame > min(draw_end, end_view_f): break  # Early exit

            # Determine human name for merging
            current_human_name = tgt.get('humanName')
            if tgt.get('targetId') == "ground":
                current_human_name = "Ground"

            # Find how many subsequent targets have the same name
            next_i = i + 1
            while next_i < len(tgt_hist):
                next_tgt = tgt_hist[next_i]
                if next_tgt['frame'] > draw_end: break

                next_human_name = next_tgt.get('humanName')
                if next_tgt.get('targetId') == "ground":
                    next_human_name = "Ground"

                if next_human_name == current_human_name:
                    next_i += 1
                else:
                    break

            # The block ends at the frame of the first different target, or draw_end
            t_block_end_frame = tgt_hist[next_i]['frame'] if next_i < len(tgt_hist) else draw_end

            t_draw_start = max(draw_start, t_frame)
            t_draw_end = min(draw_end, t_block_end_frame)

            if t_draw_start < t_draw_end:
                tx1 = max(view_min_x - 5, t_draw_start * ppf)
                tx2 = min(view_max_x + 5, t_draw_end * ppf)

                if tx1 < tx2:
                    # Optimization: Skip drawing if target is too thin to see
                    if tx2 - tx1 >= 0.3:
                        target_id = tgt.get('targetId')
                        tier = tgt.get('tier', 1)
                        t_color = constants.COLOR_TIER1

                        if target_id == "ground":
                            t_color = constants.COLOR_GROUND
                        elif tier == 2:
                            t_color = constants.COLOR_TIER2
                        elif tier >= 3:
                            t_color = constants.COLOR_TIER3

                        tags = ("segment", tag_id, "target") if not is_lifecycle else "lifecycle"
                        self.canvas.create_rectangle(tx1, t_y1, tx2, t_y2, fill=t_color, outline="", tags=tags)

                        # Add text label if it's the lifecycle view and wide enough
                        if is_lifecycle and (tx2 - tx1) > 10:
                            label_name = current_human_name or "Unknown"
                            # Crop text if needed
                            # Each character is ~6px
                            avail_w = (tx2 - tx1) - 4
                            char_limit = int(avail_w / 6)

                            if char_limit >= 3:
                                if len(label_name) > char_limit:
                                    label_name = label_name[:max(0, char_limit - 2)] + ".."
                                self.canvas.create_text((tx1 + tx2) / 2, (t_y1 + t_y2) / 2, text=label_name,
                                                        font=("Arial", 8, "bold"), fill="black", tags=tags)
                            elif char_limit >= 1:
                                # Just first letter for very small blocks
                                self.canvas.create_text((tx1 + tx2) / 2, (t_y1 + t_y2) / 2, text=label_name[0],
                                                        font=("Arial", 7, "bold"), fill="black", tags=tags)

            i = next_i

    def draw_unit_lifecycle(self, u_data, y_top, y_bottom, ppf, vx1, vx2, global_max_frame, selected_block=None, data_provider=None, alt_info=None):
        if not u_data: return
        born_frame = u_data.get('bornFrame', 0)
        died_frame = u_data.get('diedFrame') or global_max_frame or 999999

        x1 = born_frame * ppf
        x2 = died_frame * ppf
        if x2 < x1 + 2: x2 = x1 + 2

        # Cull logic for the main container
        if x2 < vx1 or x1 > vx2: return

        # Background
        fill_color = "#f9f9f9"
        outline_color = "#bbbbbb"
        width = 1
        tags = "lifecycle"

        if alt_info:
            tags = ("lifecycle", "alternative", f"alt_{alt_info['index']}")
            if alt_info.get('selected'):
                fill_color = "#eef5ff"
                outline_color = "blue"
                width = 2

        self.canvas.create_rectangle(x1, y_top, x2, y_bottom, fill=fill_color, outline=outline_color, width=width, tags=tags)

        # Text visibility check
        if x1 > vx1:
            self.canvas.create_text(x1, y_top - 5, text=f"Born: {utils.format_time(born_frame)}", anchor="sw", font=("Arial", 7), fill="#666", tags=tags)
        if x2 < vx2:
            self.canvas.create_text(x2, y_top - 5, text=f"Died: {utils.format_time(died_frame)}", anchor="se", font=("Arial", 7), fill="#666", tags=tags)

        if not alt_info and not selected_block and x1 < vx2 and x2 > vx1:
            pid = u_data.get('playerId')
            tid = u_data.get('teamId')
            pt_str = f" [P{pid} T{tid}]" if (pid is not None and tid is not None) else ""
            label = f"{u_data.get('humanName', 'Unit')} ({u_data.get('unitId', '?')}){pt_str}"
            text_x = max(x1 + 10, vx1 + 10)  # Sticky label
            if text_x < x2 - 50:
                self.canvas.create_text(text_x, y_top + 10, text=label, anchor="nw", font=("Arial", 8, "bold"), fill="blue", tags=tags)

        status_hist = u_data.get('statusHistory', [])
        bar_height = 64
        h_y1 = y_bottom - bar_height
        h_y2 = y_bottom

        self.canvas.create_rectangle(x1, h_y1, x2, h_y2, fill="#e0e0e0", outline="#999999", width=1, tags="lifecycle")

        # PERFORMANCE FIX: Binary Search for visible segments
        start_view_frame = vx1 / ppf
        end_view_frame = vx2 / ppf

        hist_start_idx = 0
        if "_status_start_frames" in u_data:
            hist_start_idx = bisect.bisect_left(u_data["_status_start_frames"], start_view_frame)
            if hist_start_idx > 0: hist_start_idx -= 1

        for k in range(hist_start_idx, len(status_hist)):
            seg = status_hist[k]
            if seg['startFrame'] > end_view_frame: break  # Early exit

            s_start = seg['startFrame']
            s_end = seg.get('endFrame') or died_frame
            s_status = seg['status']
            if s_start < s_end:
                sx1 = max(vx1 - 5, s_start * ppf)
                sx2 = min(vx2 + 5, s_end * ppf)
                if sx2 < sx1: continue

                s_color = constants.COLOR_IDLE
                if s_status == "ACTIVE":
                    s_color = constants.COLOR_ACTIVE
                elif s_status == "PAUSE":
                    s_color = constants.COLOR_PAUSE
                elif s_status.upper() == "IDLE":
                    s_color = constants.COLOR_IDLE

                # Optimization: Skip drawing if segment is too thin to see
                if sx2 - sx1 < 0.3: continue

                self.canvas.create_rectangle(sx1, h_y1, sx2, h_y2, fill=s_color, outline="#999999", width=1, tags="lifecycle")

                if s_status == "ACTIVE":
                    # For lifecycle, targets should be full height of the bar
                    target_y1 = h_y1
                    self._draw_targets(u_data, s_start, s_end, target_y1, h_y2, ppf, vx1, vx2, None, is_lifecycle=True)

        # 4. Draw Stationary Periods (highlight)
        stationary_periods = u_data.get('_stationary_periods', [])
        for sp in stationary_periods:
            sp_start = sp['start']
            sp_end = sp['end']
            if sp_start < end_view_frame and sp_end > start_view_frame:
                sp_x1 = max(vx1 - 5, sp_start * ppf)
                sp_x2 = min(vx2 + 5, sp_end * ppf)
                if sp_x2 - sp_x1 < 0.3: continue
                # Draw on top of the status bar, maybe as a thinner bar or just a different color
                # Here we draw it as a top highlight on the status bar
                self.canvas.create_rectangle(sp_x1, h_y1, sp_x2, h_y1 + 4, fill=constants.COLOR_STATIONARY, outline="", tags="lifecycle")

        # Selection highlight - removed redundant horizontal lines
        if False and selected_block: # Disabled here as it is drawn globally in draw_scene
            sel_x1 = max(vx1 - 10, selected_block['start'] * ppf)
            sel_x2 = min(vx2 + 10, selected_block['end'] * ppf)

            if sel_x1 < sel_x2:
                # Horizontal lines
                self.canvas.create_line(sel_x1, y_top - 15, sel_x2, y_top - 15, fill="#ff0000", width=1, dash=(4, 4), tags="lifecycle")
                self.canvas.create_line(sel_x1, y_bottom + 15, sel_x2, y_bottom + 15, fill="#ff0000", width=1, dash=(4, 4), tags="lifecycle")

                label_x = (selected_block['start'] * ppf + selected_block['end'] * ppf) / 2
                label_x = max(vx1 + 50, min(vx2 - 50, label_x))
                self.canvas.create_text(label_x, y_top - 17, text="CURRENT BLOCK", fill="#ff0000", anchor="s", font=("Arial", 6, "bold"), tags="lifecycle")

        # Subblock highlight - removed redundant vertical lines
        if False and selected_block and data_provider and data_provider.subblock_start is not None:
            sb1 = data_provider.subblock_start
            sb2 = data_provider.subblock_end if data_provider.subblock_end is not None else sb1

            real_sb1 = min(sb1, sb2)
            real_sb2 = max(sb1, sb2)

            sx1 = max(vx1 - 10, real_sb1 * ppf)
            sx2 = min(vx2 + 10, real_sb2 * ppf)

            if sx2 - sx1 > 1:
                # Vertical lines
                self.canvas.create_line(sx1, y_top - 15, sx1, y_bottom + 15, fill="blue", width=2, dash=(2, 2), tags="lifecycle")
                self.canvas.create_line(sx2, y_top - 15, sx2, y_bottom + 15, fill="blue", width=2, dash=(2, 2), tags="lifecycle")

                label_x = (real_sb1 * ppf + real_sb2 * ppf) / 2
                label_x = max(vx1 + 50, min(vx2 - 50, label_x))
                self.canvas.create_text(label_x, y_bottom + 17, text="SUB-BLOCK", fill="blue", anchor="n", font=("Arial", 6, "bold"), tags="lifecycle")
            else:
                # Single line indicator for subblock start (or very small subblock)
                self.canvas.create_line(sx1, y_top - 15, sx1, y_bottom + 15, fill="blue", width=2, dash=(2, 2), tags="lifecycle")
                self.canvas.create_text(sx1, y_bottom + 17, text="SUB-START", fill="blue", anchor="n", font=("Arial", 6, "bold"), tags="lifecycle")
