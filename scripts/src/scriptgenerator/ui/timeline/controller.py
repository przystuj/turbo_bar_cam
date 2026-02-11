class TimelineController:
    def __init__(self, canvas, logic, renderer, callbacks, config):
        self.canvas = canvas
        self.logic = logic
        self.renderer = renderer
        self.callbacks = callbacks
        self.config = config

        # Drag State
        self.drag_mode = None
        self.drag_start_x = 0
        self.drag_segment_id = None
        self.drag_snapshot = {}
        self.HANDLE_WIDTH = 8

        self.setup_bindings()

    def setup_bindings(self):
        self.canvas.bind("<Motion>", self.on_canvas_motion)
        self.canvas.bind("<Button-1>", self.on_canvas_click)
        self.canvas.bind("<Double-Button-1>", self.on_double_click)
        self.canvas.bind("<B1-Motion>", self.on_canvas_drag)
        self.canvas.bind("<ButtonRelease-1>", self.on_canvas_release)
        self.canvas.bind("<Leave>", self.on_mouse_leave)
        self.canvas.bind("<MouseWheel>", self.on_zoom)
        self.canvas.bind("<Button-4>", self.on_zoom)
        self.canvas.bind("<Button-5>", self.on_zoom)
        self.canvas.bind("<Button-2>", self.start_pan)
        self.canvas.bind("<B2-Motion>", self.do_pan)
        self.canvas.bind("<Shift-MouseWheel>", self.on_shift_scroll)

    def on_zoom(self, event):
        mouse_x_screen = event.x
        mouse_x_canvas = self.canvas.canvasx(mouse_x_screen)
        frame_at_cursor = mouse_x_canvas / self.config.pixels_per_frame

        scale = 1.0
        if event.num == 5 or event.delta < 0: scale = 0.9
        elif event.num == 4 or event.delta > 0: scale = 1.1

        new_pixels = self.config.pixels_per_frame * scale
        if new_pixels < 0.005: new_pixels = 0.005
        if new_pixels > 20.0: new_pixels = 20.0

        self.config.pixels_per_frame = new_pixels
        # callbacks['redraw'](rebuild_blocks=False) - Redraw will be triggered by move_to/render_visible
        
        # Force processing of any pending geometry events to get accurate scrollregion/winfo_width
        self.canvas.update_idletasks()

        new_mouse_x_canvas = frame_at_cursor * self.config.pixels_per_frame
        target_left_edge = new_mouse_x_canvas - mouse_x_screen

        try:
            region = self.canvas.cget("scrollregion").split()
            if len(region) >= 4:
                # Update scrollregion first so xview_moveto works with new total width
                total_width = float(region[2])
                # We need to recalculate total_width because it depends on ppf
                if self.logic:
                    total_width = self.logic.calculate_total_width(self.config.pixels_per_frame)
                    self.canvas.config(scrollregion=(0, 0, total_width + 100, self.canvas.winfo_height()))
                
                scroll_width = total_width + 100
                
                if scroll_width > 0:
                    fraction = target_left_edge / scroll_width
                    if fraction < 0: fraction = 0
                    if fraction > 1: fraction = 1
                    self.canvas.xview_moveto(fraction)
            
            # Now redraw everything at new zoom level and position
            self.callbacks['redraw'](rebuild_blocks=False)
        except:
            self.callbacks['redraw'](rebuild_blocks=False)
        return "break"

    def start_pan(self, event):
        self.canvas.scan_mark(event.x, event.y)

    def do_pan(self, event):
        self.canvas.scan_dragto(event.x, event.y, gain=1)
        self.callbacks['render_visible']()

    def on_shift_scroll(self, event):
        if event.delta:
            self.canvas.xview_scroll(int(-1 * (event.delta / 120)), "units")
        elif event.num == 4:
            self.canvas.xview_scroll(-1, "units")
        elif event.num == 5:
            self.canvas.xview_scroll(1, "units")
        self.callbacks['render_visible']()
        return "break"

    def on_canvas_motion(self, event):
        x = self.canvas.canvasx(event.x)
        y = self.canvas.canvasy(event.y)
        frame = int(x / self.config.pixels_per_frame)
        if frame < 0: frame = 0

        if self.callbacks['hover']:
            self.callbacks['hover'](x, y, frame)

        if self.logic.selected_block_index is not None and self.logic.selected_block_index < len(self.logic.timeline_data):
            block = self.logic.timeline_data[self.logic.selected_block_index]
            # Show resize handles for regular unit blocks and the init (skip) block
            if block['type'] in ('block', 'init'):
                start_x = block['start'] * self.config.pixels_per_frame
                end_x = block['end'] * self.config.pixels_per_frame
                if abs(x - start_x) <= self.HANDLE_WIDTH or abs(x - end_x) <= self.HANDLE_WIDTH:
                    self.canvas.config(cursor="sb_h_double_arrow")
                else:
                    self.canvas.config(cursor="")
            else:
                self.canvas.config(cursor="")
        else:
            self.canvas.config(cursor="")

    def on_canvas_click(self, event):
        x = self.canvas.canvasx(event.x)
        y = self.canvas.canvasy(event.y)

        # Determine if click is in main timeline or unit details
        MAIN_Y_TOP = 20
        MAIN_Y_BOTTOM = MAIN_Y_TOP + 80 # ROW_HEIGHT
        UNIT_Y_TOP = MAIN_Y_BOTTOM + 30 + 10 # MAIN_Y_BOTTOM + MID_GAP + 10
        UNIT_Y_BOTTOM = UNIT_Y_TOP + 60

        is_main_timeline_area = (y <= MAIN_Y_BOTTOM)
        is_on_block_y = (MAIN_Y_TOP <= y <= MAIN_Y_BOTTOM)
        is_unit_lifecycle = (UNIT_Y_TOP <= y <= UNIT_Y_BOTTOM)

        # Check if clicked on an alternative
        if not is_main_timeline_area and not is_unit_lifecycle:
            # Check a small vertical range to be more robust against clicking text vs background
            items = self.canvas.find_overlapping(x-1, y-10, x+1, y+10)
            for item in items:
                tags = self.canvas.gettags(item)
                for tag in tags:
                    if tag.startswith("alt_"):
                        try:
                            alt_idx = int(tag.split("_")[1])
                            # If already selected, maybe confirmed? No, just keep selection for now
                            self.logic.selected_preview_index = alt_idx
                            self.callbacks['render_visible']()
                            if self.callbacks['on_select']: self.callbacks['on_select'](self.logic.timeline_data[self.logic.selected_block_index])
                            return
                        except: pass

        frame = int(x / self.config.pixels_per_frame)
        if frame < 0: frame = 0

        # Time cursor grab: if click near current time line on main timeline OR above it, start dragging it
        cur_x = self.logic.current_time * self.config.pixels_per_frame
        if abs(x - cur_x) <= 6:
            self.drag_mode = 'time_cursor'
            # Immediately set current time to clicked frame
            self.logic.current_time = frame
            self.callbacks['render_visible']()
            if 'on_time_change' in self.callbacks and self.callbacks['on_time_change']:
                self.callbacks['on_time_change'](self.logic.current_time)
            return

        # Priority Check: If a block is already selected, check its handles first
        if self.logic.selected_block_index is not None and self.logic.selected_block_index < len(self.logic.timeline_data):
            block = self.logic.timeline_data[self.logic.selected_block_index]
            # Allow resizing for both unit blocks and the init (skip) block
            if block['type'] in ('block', 'init'):
                start_x = block['start'] * self.config.pixels_per_frame
                end_x = block['end'] * self.config.pixels_per_frame

                # Check handles
                if abs(x - start_x) <= self.HANDLE_WIDTH:
                    self.drag_mode = 'resize_left'
                    self.drag_segment_id = id(block['segments'][0]) if (block['type'] == 'block' and block.get('segments')) else id(block)
                elif abs(x - end_x) <= self.HANDLE_WIDTH:
                    self.drag_mode = 'resize_right'
                    self.drag_segment_id = id(block['segments'][-1]) if (block['type'] == 'block' and block.get('segments')) else id(block)

                if self.drag_mode:
                    self.drag_start_x = x
                    self.drag_snapshot = {id(s): s.copy() for s in self.logic.original_timeline}
                    self.callbacks['render_visible']()
                    if self.callbacks['on_select']: self.callbacks['on_select'](block)
                    return

                # Subblock selection via clicking/dragging on MAIN TIMELINE
                # Must be clicking ON the actual block segment (y is within [MAIN_Y_TOP, MAIN_Y_BOTTOM])
                # and NOT just above it.
                if is_on_block_y and block['start'] <= frame <= block['end']:
                    self.drag_mode = 'subblock_select'
                    self.drag_start_frame = frame
                    # Single click makes a single frame subblock (handled by initializing end=start)
                    self.logic.subblock_start = frame
                    self.logic.subblock_end = frame
                    self.callbacks['render_visible']()
                    return

        # Normal Selection
        if not is_main_timeline_area:
            return # Don't select blocks from clicking lifecycle view background

        # Already checked time cursor priority above.
        # Now check if we clicked on a block segment.
        items = self.canvas.find_overlapping(x-1, y-1, x+1, y+1)
        found_idx = None
        for item in reversed(items):
            tags = self.canvas.gettags(item)
            if "segment" in tags:
                try:
                    found_idx = int(tags[1])
                    break
                except: pass

        # If clicked empty main area (no segment), start time cursor drag (catch behavior)
        if found_idx is None:
            self.drag_mode = 'time_cursor'
            self.logic.current_time = frame
            self.callbacks['render_visible']()
            if 'on_time_change' in self.callbacks and self.callbacks['on_time_change']:
                self.callbacks['on_time_change'](self.logic.current_time)
            return

        if found_idx is not None:
            block = self.logic.timeline_data[found_idx]
            self.logic.selected_block_id = self.logic.get_block_uid(block)
            self.logic.selected_block_index = found_idx
            self.logic.preview_units = []
            self.logic.selected_preview_index = None
            self.logic.subblock_start = None
            self.logic.subblock_end = None

            if block['type'] in ('block', 'init'):
                start_x = block['start'] * self.config.pixels_per_frame
                end_x = block['end'] * self.config.pixels_per_frame
                if abs(x - start_x) <= self.HANDLE_WIDTH:
                    self.drag_mode = 'resize_left'
                    self.drag_segment_id = id(block['segments'][0]) if (block['type'] == 'block' and block.get('segments')) else id(block)
                elif abs(x - end_x) <= self.HANDLE_WIDTH:
                    self.drag_mode = 'resize_right'
                    self.drag_segment_id = id(block['segments'][-1]) if (block['type'] == 'block' and block.get('segments')) else id(block)

                if self.drag_mode:
                    self.drag_start_x = x
                    self.drag_snapshot = {id(s): s.copy() for s in self.logic.original_timeline}

            self.callbacks['render_visible']()
            if self.callbacks['on_select']: self.callbacks['on_select'](block)
        else:
            self.logic.selected_block_id = None
            self.logic.selected_block_index = None
            self.logic.subblock_start = None
            self.logic.subblock_end = None
            self.callbacks['render_visible']()
            if self.callbacks['on_select']: self.callbacks['on_select'](None)

    def on_canvas_drag(self, event):
        if not self.drag_mode: return
        x = self.canvas.canvasx(event.x)

        if self.drag_mode == 'subblock_select':
            # Handle subblock dragging
            frame = int(x / self.config.pixels_per_frame)
            if self.logic.selected_block_index is not None:
                block = self.logic.timeline_data[self.logic.selected_block_index]
                # Clamp subblock within the parent block
                frame = max(block['start'], min(block['end'], frame))
                self.logic.subblock_end = frame
                self.callbacks['render_visible']()
            return
        elif self.drag_mode == 'time_cursor':
            # Dragging time cursor across the whole panel
            frame = int(x / self.config.pixels_per_frame)
            if frame < 0: frame = 0
            if self.logic.global_max_frame:
                frame = min(frame, int(self.logic.global_max_frame))
            if frame != self.logic.current_time:
                self.logic.current_time = frame
                self.callbacks['render_visible']()
                if 'on_time_change' in self.callbacks and self.callbacks['on_time_change']:
                    self.callbacks['on_time_change'](self.logic.current_time)
            return

        dx_pixels = x - self.drag_start_x
        dframes = int(dx_pixels / self.config.pixels_per_frame)

        # Snap to edges with Ctrl
        is_ctrl = (event.state & 0x0004) != 0

        for seg in self.logic.original_timeline:
            if id(seg) in self.drag_snapshot:
                snap = self.drag_snapshot[id(seg)]
                seg['start'] = snap['start']
                seg['end'] = snap['end']

        target_seg = next((s for s in self.logic.original_timeline if id(s) == self.drag_segment_id), None)
        if not target_seg: return
        orig_snap = self.drag_snapshot[self.drag_segment_id]

        # Lifespan constraints
        u_data = target_seg.get('unit_data', {})
        is_init = target_seg.get('type') == 'init'
        born_limit = u_data.get('bornFrame', 0)
        died_limit = u_data.get('diedFrame')
        if died_limit is None: died_limit = self.logic.global_max_frame

        if self.drag_mode == 'resize_left':
            proposed = orig_snap['start'] + dframes
            if is_ctrl:
                snap_point = self.find_snap_point(proposed, exclude_id=id(target_seg))
                if snap_point is not None: proposed = snap_point

            if not is_init and proposed < born_limit: proposed = born_limit
            if is_init and proposed < 0: proposed = 0
            if proposed > orig_snap['end'] - 30: proposed = orig_snap['end'] - 30
            target_seg['start'] = proposed
        elif self.drag_mode == 'resize_right':
            proposed = orig_snap['end'] + dframes
            if is_ctrl:
                snap_point = self.find_snap_point(proposed, exclude_id=id(target_seg))
                if snap_point is not None: proposed = snap_point

            # Allow extending up to 3s (90 frames) after death
            local_max_end = died_limit + 90
            if is_init:
                # Init block can be dragged forward up to global max frame
                local_max_end = self.logic.global_max_frame

            if proposed > local_max_end: proposed = local_max_end
            if proposed < orig_snap['start'] + 30: proposed = orig_snap['start'] + 30
            target_seg['end'] = proposed

        self.callbacks['redraw'](maintain_scroll=True)

    def find_snap_point(self, frame, exclude_id):
        # Snap within 10 pixels
        threshold_frames = 10 / self.config.pixels_per_frame

        best_snap = None
        min_dist = threshold_frames

        for s in self.logic.original_timeline:
            if id(s) == exclude_id: continue
            for p in [s['start'], s['end']]:
                dist = abs(p - frame)
                if dist < min_dist:
                    min_dist = dist
                    best_snap = p
        return best_snap

    def on_canvas_release(self, event):
        if self.drag_mode:
            if self.drag_mode == 'subblock_select':
                # Finalize subblock
                if self.logic.subblock_start is not None and self.logic.subblock_end is not None:
                    s1 = self.logic.subblock_start
                    s2 = self.logic.subblock_end

                    real_start = min(s1, s2)
                    real_end = max(s1, s2)

                    # Enforce minimum subblock size (90 frames) for drags
                    # If it was a single click or a very short drag, we clear it
                    if (real_end - real_start) < 90:
                        self.logic.subblock_start = None
                        self.logic.subblock_end = None
                    else:
                        self.logic.subblock_start = real_start
                        self.logic.subblock_end = real_end

                self.callbacks['render_visible']()
                # Trigger alternatives update if subblock is valid
                if self.logic.selected_block_index is not None:
                    block = self.logic.timeline_data[self.logic.selected_block_index]
                    if self.callbacks['on_select']: self.callbacks['on_select'](block)
            else:
                if self.drag_mode == 'time_cursor':
                    # Nothing to finalize for time cursor; already synced continuously
                    pass
                else:
                    # We finished dragging/resizing.
                    # Call a new logic method to resolve overlaps, passing the ID of the moved segment
                    self.logic.resolve_overlaps(moved_seg_id=self.drag_segment_id)
                    self.callbacks['redraw'](maintain_scroll=True)

        self.drag_mode = None
        self.drag_snapshot = {}
        if self.logic.selected_block_id and self.callbacks['on_select']:
            for b in self.logic.timeline_data:
                if self.logic.get_block_uid(b) == self.logic.selected_block_id:
                    self.callbacks['on_select'](b)
                    break
        self.canvas.config(cursor="")

    def on_double_click(self, event):
        x = self.canvas.canvasx(event.x)
        y = self.canvas.canvasy(event.y)
        frame = int(x / self.config.pixels_per_frame)
        if frame < 0: frame = 0

        # 1. Double click on alternative confirmed it
        MAIN_Y_BOTTOM = 10 + 80
        UNIT_Y_TOP = MAIN_Y_BOTTOM + 30 + 10
        UNIT_Y_BOTTOM = UNIT_Y_TOP + 60
        is_main_timeline = (y <= MAIN_Y_BOTTOM)
        is_unit_lifecycle = (UNIT_Y_TOP <= y <= UNIT_Y_BOTTOM)

        if not is_main_timeline and not is_unit_lifecycle:
            items = self.canvas.find_overlapping(x - 1, y - 10, x + 1, y + 10)
            for item in items:
                tags = self.canvas.gettags(item)
                for tag in tags:
                    if tag.startswith("alt_"):
                        try:
                            alt_idx = int(tag.split("_")[1])
                            self.logic.selected_preview_index = alt_idx
                            if self.callbacks['on_select']:
                                # This will trigger the confirm via side panel or we can call confirm directly if we had a callback
                                # For now, side panel has the callback, so let's use a special callback if provided
                                if 'on_confirm_alt' in self.callbacks:
                                    self.callbacks['on_confirm_alt']()
                            return
                        except: pass

        # 2. Double click on main block selects whole block as subblock
        if is_main_timeline:
            items = self.canvas.find_overlapping(x - 1, y - 1, x + 1, y + 1)
            found_idx = None
            for item in reversed(items):
                tags = self.canvas.gettags(item)
                if "segment" in tags:
                    try:
                        found_idx = int(tags[1])
                        break
                    except: pass

            if found_idx is not None:
                block = self.logic.timeline_data[found_idx]
                if block['type'] == 'block':
                    self.logic.selected_block_id = self.logic.get_block_uid(block)
                    self.logic.selected_block_index = found_idx
                    self.logic.subblock_start = block['start']
                    self.logic.subblock_end = block['end']
                    self.logic.preview_units = []
                    self.logic.selected_preview_index = None
                    self.callbacks['render_visible']()
                    if self.callbacks['on_select']: self.callbacks['on_select'](block)
                    return

        # 3. Legacy double click callback
        if not self.callbacks['on_double_click']: return
        if self.logic.selected_block_index is not None and self.logic.selected_block_index < len(self.logic.timeline_data):
            block = self.logic.timeline_data[self.logic.selected_block_index]
            if block['type'] == 'block' and block['start'] <= frame <= block['end']:
                self.callbacks['on_double_click'](frame, block)

    def on_mouse_leave(self, event):
        if self.callbacks['leave']: self.callbacks['leave']()

    def on_escape(self, event):
        if self.logic.preview_units:
            self.logic.preview_units = []
            self.logic.selected_preview_index = None
            self.callbacks['render_visible']()
        elif self.logic.subblock_start is not None:
            self.logic.subblock_start = None
            self.logic.subblock_end = None
            self.callbacks['render_visible']()
        elif self.logic.selected_block_id is not None:
            self.logic.selected_block_id = None
            self.logic.selected_block_index = None
            self.logic.subblock_start = None
            self.logic.subblock_end = None
            self.callbacks['render_visible']()
            if self.callbacks['on_select']: self.callbacks['on_select'](None)
