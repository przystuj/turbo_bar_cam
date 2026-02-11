import tkinter as tk
import bisect

from scriptgenerator.config import constants
from scriptgenerator.ui.timeline.controller import TimelineController
from scriptgenerator.ui.timeline.logic import TimelineLogic
from scriptgenerator.ui.timeline.renderer import TimelineRenderer


class TimelineConfig:
    def __init__(self):
        self.pixels_per_frame = 0.008

class TimelineWidget:
    def __init__(self, parent_frame, hover_label, on_select_callback=None, on_double_click_callback=None, on_confirm_alt_callback=None, on_time_change_callback=None):
        self.config = TimelineConfig()
        self.logic = TimelineLogic()
        self.should_autofit = True
        self.canvas_height = 360
        self.hover_label = hover_label
        self.unit_registry = {}
        self.db = None # Database reference for on-demand history loading
        self.on_time_change_callback = on_time_change_callback

        # UI Setup
        self.create_legend(parent_frame)
        canvas_wrapper = tk.Frame(parent_frame)
        canvas_wrapper.pack(fill="both", expand=True, side="top")

        self.timeline_canvas = tk.Canvas(canvas_wrapper, height=self.canvas_height, bg="white", highlightthickness=0)
        self.h_scroll = tk.Scrollbar(parent_frame, orient="horizontal", command=self.on_scroll_command)
        self.timeline_canvas.configure(xscrollcommand=self.h_scroll.set)

        self.timeline_canvas.pack(side="top", fill="both", expand=True)
        self.h_scroll.pack(side="top", fill="x")

        # Sub-modules
        self.renderer = TimelineRenderer(self.timeline_canvas, self.config)

        callbacks = {
            'redraw': self.draw_timeline,
            'render_visible': self.render_visible_section,
            'hover': self.update_hover_info,
            'leave': self.on_mouse_leave,
            'on_select': on_select_callback,
            'on_double_click': on_double_click_callback,
            'on_confirm_alt': on_confirm_alt_callback,
            'on_time_change': self.on_time_change_callback
        }

        self.controller = TimelineController(self.timeline_canvas, self.logic, self.renderer, callbacks, self.config)

        self.timeline_canvas.bind("<Configure>", self.on_resize)

    def on_scroll_command(self, *args):
        self.timeline_canvas.xview(*args)
        self.render_visible_section()

    def on_resize(self, event):
        self.canvas_height = event.height
        self.draw_timeline(rebuild_blocks=False)

    def set_unit_registry(self, units):
        self.unit_registry = units

    def set_global_max_frame(self, max_frame):
        self.logic.global_max_frame = max_frame

    def set_preview_units(self, units):
        self.logic.preview_units = units
        self.logic.selected_preview_index = None
        self.render_visible_section()

    def set_current_time(self, frame):
        try:
            frame = int(frame)
        except Exception:
            return
        if frame < 0:
            frame = 0
        if self.logic.global_max_frame:
            frame = min(frame, int(self.logic.global_max_frame))
        if frame != self.logic.current_time:
            self.logic.current_time = frame
            self.render_visible_section()

    def select_preview(self, index):
        if 0 <= index < len(self.logic.preview_units):
            self.logic.selected_preview_index = index
            self.render_visible_section()
            return True
        return False

    def reset(self):
        self.timeline_canvas.delete("all")
        self.logic.reset()
        self.should_autofit = True

    def delete_block(self, block_uid):
        if self.logic.delete_block(block_uid):
            self.draw_timeline(maintain_scroll=True)
            return True
        return False

    def update_block(self, block_uid, new_start, new_end, new_unit_data=None, new_commands=None):
        res_uid = self.logic.update_block(block_uid, new_start, new_end, new_unit_data, new_commands)
        if res_uid:
            self.draw_timeline(maintain_scroll=True)
            return res_uid
        return None

    def insert_into_block(self, block_uid, start, end, unit_data, commands):
        res_uid = self.logic.insert_into_block(block_uid, start, end, unit_data, commands)
        if res_uid:
            self.draw_timeline(maintain_scroll=True)
            return res_uid
        return None

    def draw_timeline(self, timeline_list=None, maintain_scroll=False, rebuild_blocks=True):
        if timeline_list is not None:
            self.logic.original_timeline = timeline_list

        if rebuild_blocks:
            self.logic.process_data(self.logic.original_timeline)

        if self.should_autofit:
            self.config.pixels_per_frame = self.logic.calculate_autofit_ppf(self.timeline_canvas.winfo_width())
            self.should_autofit = False

        total_width = self.logic.calculate_total_width(self.config.pixels_per_frame)
        self.timeline_canvas.config(scrollregion=(0, 0, total_width + 100, self.canvas_height))
        self.render_visible_section()

    def render_visible_section(self):
        self.timeline_canvas.delete("all")

        # Use canvasx to get accurate visible bounds instead of manual xview calculations
        canvas_w = self.timeline_canvas.winfo_width()
        if canvas_w <= 1: # Canvas not yet fully rendered
            canvas_w = 800

        view_start_x = self.timeline_canvas.canvasx(0) - 100
        view_end_x = self.timeline_canvas.canvasx(canvas_w) + 100

        region = self.timeline_canvas.cget("scrollregion").split()
        total_scroll_w = float(region[2]) if len(region) >= 4 and float(region[2]) != 0 else 1.0

        # Performance: Load missing histories from database before rendering
        if self.db:
            visible_units = set()
            ppf = self.config.pixels_per_frame
            start_f = view_start_x / ppf
            end_f = view_end_x / ppf

            # Use binary search to find visible blocks for history loading
            start_idx = max(0, bisect.bisect_left(self.logic.start_times, start_f - self.logic.max_block_duration) - 1)
            for i in range(start_idx, len(self.logic.timeline_data)):
                b = self.logic.timeline_data[i]
                if b['start'] > end_f:
                    break
                if b['end'] > start_f and b['type'] == 'block':
                    uid = b.get('unit_id')
                    if uid:
                        u_data = b.get('unit_data', {})
                        if 'statusHistory' not in u_data:
                            visible_units.add(uid)

            # If selected or preview units are visible, ensure they have histories too
            if self.logic.selected_block_id:
                sel_idx = -1
                for i, b in enumerate(self.logic.timeline_data):
                    if self.logic.get_block_uid(b) == self.logic.selected_block_id:
                        uid = b.get('unit_id')
                        if uid: visible_units.add(uid)
                        sel_idx = i
                        break
                
                # Also ensure neighbors of selected block are loaded for distance display
                if sel_idx != -1:
                    if sel_idx > 0:
                        prev_b = self.logic.timeline_data[sel_idx - 1]
                        if prev_b['type'] == 'block' and prev_b.get('unit_id'):
                            visible_units.add(prev_b['unit_id'])
                    if sel_idx < len(self.logic.timeline_data) - 1:
                        next_b = self.logic.timeline_data[sel_idx + 1]
                        if next_b['type'] == 'block' and next_b.get('unit_id'):
                            visible_units.add(next_b['unit_id'])

            if self.logic.preview_units:
                for alt in self.logic.preview_units:
                    uid = alt['id']
                    if uid: visible_units.add(uid)

            # Bulk load visible unit histories
            from scriptgenerator.core import processing
            for uid in visible_units:
                u_full = self.db.get_unit_full(uid)
                if u_full:
                    # IMPORTANT: Calculate stationary periods for newly loaded data
                    processing.refine_unit_status(u_full)
                            
                    # Update registry and any block referencing this unit
                    self.unit_registry[uid] = u_full
                    for b in self.logic.timeline_data:
                        if b.get('unit_id') == uid:
                            b['unit_data'] = u_full
                    
                    if self.logic.preview_units:
                        for alt in self.logic.preview_units:
                            if alt.get('id') == uid:
                                alt['unit'] = u_full

        self.renderer.draw_scene(view_start_x, view_end_x, total_scroll_w, self.logic)

    def update_hover_info(self, x, y, frame):
        info = self.logic.get_data_at_frame(frame)
        text = f"Frame: {frame}"
        if info:
            if isinstance(info, dict) and 'block' in info:
                block = info['block']
                u_data = block.get('unit_data', {})
                name = u_data.get('humanName', 'Unknown')
                status = info.get('status', 'Unknown')
                s_start = info.get('status_start')
                s_end = info.get('status_end')
                if s_start is not None and s_end is not None:
                    # Clip to block boundaries
                    real_start = max(s_start, block['start'])
                    real_end = min(s_end, block['end'])
                    dur = max(0, real_end - real_start) / 30.0
                    text += f" | Unit: {name} ({status}: {dur:.1f}s)"
                else:
                    text += f" | Unit: {name} ({status})"

                target = info.get('target')
                if target:
                    t_humanName = target.get('humanName') or target.get('name') or "Unknown"
                    t_name = target.get('name') or "Unknown"
                    t_id = target.get('targetId', '?')
                    text += f" | Target: {t_humanName} ({t_name} {t_id})"
            else:
                # Gap or simple block
                block = info
                u_data = block.get('unit_data', {})
                name = u_data.get('humanName', 'Gap')
                text += f" | {name}"

        self.hover_label.config(text=text)

    def on_mouse_leave(self):
        self.hover_label.config(text="Hover over timeline for details")

    def create_legend(self, parent):
        legend_frame = tk.Frame(parent, pady=5)
        legend_frame.pack(side="top", fill="x")
        
        # Row 1: Colors Legend
        row1 = tk.Frame(legend_frame)
        row1.pack(side="top", fill="x")
        tk.Label(row1, text="Legend: ", font=("Arial", 8, "bold")).pack(side="left")
        def add_item(p, text, color):
            lbl = tk.Label(p, text=f"  {text}  ", bg=color, font=("Arial", 8))
            lbl.pack(side="left", padx=2)
        add_item(row1, "Active", constants.COLOR_ACTIVE)
        add_item(row1, "Pause", constants.COLOR_PAUSE)
        add_item(row1, "Idle", constants.COLOR_IDLE)
        add_item(row1, "Stationary (>=5s)", constants.COLOR_STATIONARY)
        add_item(row1, "Unknown", constants.COLOR_UNKNOWN)
        add_item(row1, "Gap", constants.COLOR_GAP)
        tk.Label(row1, text="| Tiers: ", font=("Arial", 8, "bold")).pack(side="left", padx=5)
        add_item(row1, "T1", constants.COLOR_TIER1)
        add_item(row1, "T2", constants.COLOR_TIER2)
        add_item(row1, "T3+", constants.COLOR_TIER3)
        add_item(row1, "Ground", constants.COLOR_GROUND)

        # Row 2: Controls/Keybinds
        row2 = tk.Frame(legend_frame)
        row2.pack(side="top", fill="x", pady=(2,0))
        tk.Label(row2, text="Controls: ", font=("Arial", 8, "bold")).pack(side="left")
        controls_text = "Scroll: Zoom | MMB/Shift+Scroll: Pan | Click: Select | Drag Main: Sub-block | Double-click Main: Sub-block whole | Double-click Alt: Confirm"
        tk.Label(row2, text=controls_text, font=("Arial", 8), fg="#555").pack(side="left", padx=5)

    # Property accessors for compatibility
    @property
    def timeline_data(self): return self.logic.timeline_data
    @property
    def original_timeline(self): return self.logic.original_timeline
    @property
    def selected_block_id(self): return self.logic.selected_block_id
    @selected_block_id.setter
    def selected_block_id(self, val): self.logic.selected_block_id = val
