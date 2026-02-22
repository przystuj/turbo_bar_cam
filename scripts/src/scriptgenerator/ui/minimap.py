import tkinter as tk
from typing import Dict, List, Optional
from ..core import processing
from scriptgenerator.core import utils

class MinimapWidget(tk.Frame):
    def __init__(self, parent, width=300, height=300):
        super().__init__(parent, bg="#f0f0f0")
        self._unit_lookup_cb = None
        self.canvas_w = width
        self.canvas_h = height
        self.zoom_factor = 1.0
        self.offset_x = 0
        self.offset_y = 0

        # Time sync callback and suppression flag (to avoid feedback loops)
        self._time_change_cb = None
        self._suppress_time_cb = False

        # Main horizontal split: Canvas on left/top, Controls on right/bottom?
        # Let's do Canvas on top, Controls on bottom but above the scale.
        self.canvas = tk.Canvas(self, bg="white", highlightthickness=1, highlightbackground="#999")
        self.canvas.pack(side="top", fill="both", expand=True, padx=5, pady=5)

        # Controls Frame
        self.controls = tk.Frame(self, bg="#f0f0f0")
        self.controls.pack(side="top", fill="x", padx=5, pady=2)

        # Checkboxes for toggling units
        self.show_prev_var = tk.BooleanVar(value=False)
        self.show_next_var = tk.BooleanVar(value=False)
        self.show_alts_var = tk.BooleanVar(value=False)
        self.show_projs_var = tk.BooleanVar(value=False)

        self.cb_prev = tk.Checkbutton(self.controls, text="Prev", variable=self.show_prev_var, command=self.redraw, bg="#f0f0f0", font=("Arial", 8))
        self.cb_prev.pack(side="left")
        self.cb_next = tk.Checkbutton(self.controls, text="Next", variable=self.show_next_var, command=self.redraw, bg="#f0f0f0", font=("Arial", 8))
        self.cb_next.pack(side="left")
        self.cb_alts = tk.Checkbutton(self.controls, text="Alts", variable=self.show_alts_var, command=self.redraw, bg="#f0f0f0", font=("Arial", 8))
        self.cb_alts.pack(side="left")
        self.cb_projs = tk.Checkbutton(self.controls, text="Projs", variable=self.show_projs_var, command=self.redraw, bg="#f0f0f0", font=("Arial", 8))
        self.cb_projs.pack(side="left")

        # Comma separated unit IDs input
        tk.Label(self.controls, text=" IDs:", bg="#f0f0f0", font=("Arial", 8)).pack(side="left")
        self.ids_entry_var = tk.StringVar()
        self.ids_entry = tk.Entry(self.controls, textvariable=self.ids_entry_var, width=15, font=("Arial", 8))
        self.ids_entry.pack(side="left", padx=2)
        self.ids_entry.bind("<Return>", lambda e: self.redraw())
        self.ids_entry_var.trace_add("write", lambda *args: self.redraw())

        self.scale = tk.Scale(self, from_=0, to=1, orient="horizontal", label="Time 00:00 (0)", command=self._on_scale)
        self.scale.pack(side="top", fill="x", padx=5, pady=(0,5))

        self.map_w = 0
        self.map_h = 0
        self.time_min = 0
        self.time_max = 1
        self.current_time = 0

        self.selected: Optional[Dict] = None
        self.prev_unit: Optional[Dict] = None
        self.next_unit: Optional[Dict] = None
        self.alt_units: List[Dict] = []
        self.projectiles: List[Dict] = []

        # Hover/tooltip helpers
        self._item_meta = {}  # canvas_item_id -> { unit, f1, f2, status, x1,y1,x2,y2 }
        self._tooltip = None
        self._tooltip_label = None

        self.canvas.bind("<Configure>", self.on_resize)
        self.canvas.bind("<MouseWheel>", self.on_zoom)
        self.canvas.bind("<Button-4>", self.on_zoom)
        self.canvas.bind("<Button-5>", self.on_zoom)
        self.canvas.bind("<B1-Motion>", self.on_drag)
        self.canvas.bind("<Button-1>", self.on_drag_start)
        self.canvas.bind("<B2-Motion>", self.on_drag)
        self.canvas.bind("<Button-2>", self.on_drag_start)
        self.canvas.bind("<Motion>", self.on_mouse_move)
        self.canvas.bind("<Leave>", self.on_mouse_leave)

    def on_drag_start(self, event):
        self.drag_last_x = event.x
        self.drag_last_y = event.y

    def on_drag(self, event):
        dx = event.x - self.drag_last_x
        dy = event.y - self.drag_last_y
        self.offset_x += dx
        self.offset_y += dy
        self.drag_last_x = event.x
        self.drag_last_y = event.y
        self.redraw()

    def on_zoom(self, event):
        # Determine zoom direction
        if event.num == 4 or event.delta > 0:
            factor = 1.1
        elif event.num == 5 or event.delta < 0:
            factor = 0.9
        else:
            return

        new_zoom = self.zoom_factor * factor
        # Allow zooming out below 1.0 to see the whole map and surroundings
        min_zoom = 0.2
        max_zoom = 20.0
        if new_zoom < min_zoom:
            new_zoom = min_zoom
        elif new_zoom > max_zoom:
            new_zoom = max_zoom

        if new_zoom != self.zoom_factor:
            # Zoom towards mouse cursor
            # (old_x * zoom + offset) = canvas_x
            # new_offset = canvas_x - old_x * new_zoom
            # old_x = (canvas_x - offset) / zoom
            cx = (event.x - self.offset_x) / self.zoom_factor
            cy = (event.y - self.offset_y) / self.zoom_factor

            self.zoom_factor = new_zoom
            self.offset_x = event.x - cx * self.zoom_factor
            self.offset_y = event.y - cy * self.zoom_factor

            # Constrain offset to keep map in view? Maybe just redraw
            self.redraw()

    def on_resize(self, event):
        self.canvas_w = event.width
        self.canvas_h = event.height
        self.redraw()

    def _update_scale_label(self):
        try:
            t_str = utils.format_time(int(self.current_time))
        except Exception:
            # Fallback simple mm:ss at 30 FPS
            secs = int(self.current_time) // 30
            t_str = f"{secs//60:02d}:{secs%60:02d}"
        self.scale.config(label=f"Time {t_str} ({int(self.current_time)})")

    def set_context(self, map_width: int, map_height: int, time_min: int, time_max: int):
        self.map_w = max(1, int(map_width or 1))
        self.map_h = max(1, int(map_height or 1))
        self.time_min = int(time_min or 0)
        self.time_max = max(self.time_min + 1, int(time_max or (self.time_min + 1)))
        self.scale.config(from_=self.time_min, to=self.time_max)
        if self.current_time < self.time_min or self.current_time > self.time_max:
            self.current_time = self.time_min
            self.scale.set(self.current_time)
        self._update_scale_label()
        self.redraw()

    def set_selection(self, selected: Optional[Dict], prev_unit: Optional[Dict], next_unit: Optional[Dict], alternatives: List[Dict]):
        self.selected = selected
        self.prev_unit = prev_unit
        self.next_unit = next_unit
        self.alt_units = alternatives or []
        self.redraw()

    def set_projectiles(self, projectiles: List[Dict]):
        self.projectiles = projectiles or []
        self.redraw()

    def set_time(self, frame: int):
        self.current_time = max(self.time_min, min(self.time_max, int(frame)))
        # Suppress callback while updating Scale to avoid feedback loop
        self._suppress_time_cb = True
        try:
            self.scale.set(self.current_time)
        finally:
            self._suppress_time_cb = False
        self._update_scale_label()
        self.redraw()

    def _on_scale(self, _):
        try:
            self.current_time = int(self.scale.get())
        except Exception:
            pass
        self._update_scale_label()
        self.redraw()
        if not self._suppress_time_cb and self._time_change_cb:
            try:
                self._time_change_cb(self.current_time)
            except Exception:
                pass

    def _map_to_canvas(self, x: float, z: float):
        if self.map_w <= 0 or self.map_h <= 0:
            return 0, 0

        # Use uniform scaling to fix aspect ratio
        scale_x = self.canvas_w / self.map_w
        scale_z = self.canvas_h / self.map_h
        base_scale = min(scale_x, scale_z) * self.zoom_factor

        # Center the map if it's smaller than the canvas at zoom 1.0
        # But we also have offset_x/offset_y from panning.
        cx = x * base_scale + self.offset_x
        cy = z * base_scale + self.offset_y
        return cx, cy

    def _draw_unit_dot(self, x: float, z: float, color: str, r: int = 4, outline: str = "black", label: str = None, heading: float = None, selected: bool = False):
        cx, cy = self._map_to_canvas(x, z)
        # Draw dot
        actual_outline = outline
        actual_width = 1
        if selected:
            actual_outline = "white"
            actual_width = 2
        self.canvas.create_oval(cx - r, cy - r, cx + r, cy + r, fill=color, outline=actual_outline, width=actual_width)

        # Draw heading line (if provided)
        if heading is not None:
            import math
            # heading is in radians
            length = r + 10
            hx = cx + length * math.sin(heading)
            hy = cy - length * math.cos(heading) # Y is inverted in canvas
            self.canvas.create_line(cx, cy, hx, hy, fill=outline, width=2)

        # Draw label
        if label:
            self.canvas.create_text(cx + r + 2, cy, text=label, anchor="w", font=("Arial", 7), fill="black")

    def _get_target_at_frame(self, unit_data: Dict, frame: int) -> Optional[Dict]:
        if not unit_data or "targetHistory" not in unit_data or not unit_data["targetHistory"]:
            return None
        th = unit_data["targetHistory"]
        # Assume sorted; find last with frame <= query
        last = None
        for t in th:
            if t.get("frame", 0) <= frame:
                last = t
            else:
                break
        return last

    def _ensure_tooltip(self):
        if self._tooltip is None:
            self._tooltip = tk.Toplevel(self)
            self._tooltip.wm_overrideredirect(True)
            self._tooltip.attributes("-topmost", True)
            self._tooltip_label = tk.Label(self._tooltip, text="", bg="#111", fg="#fff", bd=1, relief="solid", font=("Arial", 8))
            self._tooltip_label.pack(ipadx=4, ipady=2)

    def _hide_tooltip(self):
        if self._tooltip is not None:
            self._tooltip.withdraw()

    def _update_tooltip(self, text: str, x: int, y: int):
        self._ensure_tooltip()
        self._tooltip_label.configure(text=text)
        # position tooltip slightly offset from cursor
        self._tooltip.geometry(f"+{x+12}+{y+12}")
        self._tooltip.deiconify()

    def on_mouse_leave(self, _event):
        self._hide_tooltip()

    def on_mouse_move(self, event):
        # hit test nearby items and show tooltip with status/target
        radius = 6
        items = self.canvas.find_overlapping(event.x - radius, event.y - radius, event.x + radius, event.y + radius)
        best = None
        best_dist = 1e9
        for it in items:
            meta = self._item_meta.get(it)
            if not meta:
                continue
            # distance from point to segment
            x1, y1, x2, y2 = meta["x1"], meta["y1"], meta["x2"], meta["y2"]
            # compute perpendicular distance
            import math
            vx = x2 - x1
            vy = y2 - y1
            wx = event.x - x1
            wy = event.y - y1
            c1 = vx*wx + vy*wy
            if c1 <= 0:
                px, py = x1, y1
            else:
                c2 = vx*vx + vy*vy
                if c2 <= 0:
                    px, py = x1, y1
                else:
                    t = max(0.0, min(1.0, c1 / c2))
                    px = x1 + t * vx
                    py = y1 + t * vy
            d = math.hypot(event.x - px, event.y - py)
            if d < best_dist:
                best_dist = d
                best = (it, px, py)
        if best and best_dist <= 8:
            it = best[0]
            meta = self._item_meta.get(it)
            if not meta:
                self._hide_tooltip()
                return
            # estimate frame by projection proportion between f1..f2
            x1, y1, x2, y2 = meta["x1"], meta["y1"], meta["x2"], meta["y2"]
            import math
            vx = x2 - x1
            vy = y2 - y1
            wx = event.x - x1
            wy = event.y - y1
            c2 = vx*vx + vy*vy
            t = 0.0 if c2 <= 0 else max(0.0, min(1.0, (vx*wx + vy*wy) / c2))
            f = int(round(meta["f1"] + t * (meta["f2"] - meta["f1"])))
            unit_data = meta["unit"]
            status, _, _ = processing.get_unit_status_at_frame(unit_data, f)
            tgt = self._get_target_at_frame(unit_data, f)
            tgt_txt = "None"
            if tgt:
                name = tgt.get("humanName") or tgt.get("name") or str(tgt.get("targetId", "?"))
                tier = tgt.get("tier")
                if tier is not None:
                    tgt_txt = f"{name} (T{tier})"
                else:
                    tgt_txt = str(name)
            text = f"Frame {f}\nStatus: {status}\nTarget: {tgt_txt}"
            # place tooltip near cursor (use root coords)
            x_root = self.winfo_rootx() + event.x
            y_root = self.winfo_rooty() + event.y
            self._update_tooltip(text, x_root, y_root)
        else:
            self._hide_tooltip()

    def _get_pos_and_heading(self, u: Optional[Dict]):
        if not u:
            return None, None

        # u might be a unit data dict or an alt_entry (which contains 'unit' key)
        unit_data = u.get('unit') if 'unit' in u else u

        p = processing.get_unit_position(unit_data, self.current_time)
        if p:
            return (p.get('x'), p.get('z')), p.get('heading')
        return None, None

    def set_time_change_callback(self, cb):
        self._time_change_cb = cb

    def set_unit_lookup(self, cb):
        """
        Provide a callback that resolves a unit by an input string/ID and returns unit_data dict.
        Signature: cb(id_str) -> Optional[Dict]
        """
        self._unit_lookup_cb = cb

    def _draw_path(self, u: Optional[Dict], color: str, thin: bool = False, with_tooltip: bool = True, limit_to_current_time: bool = False):
        if not u: return
        unit_data = u.get('unit') if 'unit' in u else u
        if "positionHistory" not in unit_data:
            return

        history = unit_data["positionHistory"]
        if not history or len(history) < 2:
            return

        if limit_to_current_time:
            history = [p for p in history if p["frame"] <= self.current_time]
            # Add current interpolated position as the last point if it's after the last history frame
            curr_pos, _ = self._get_pos_and_heading(u)
            if curr_pos and (not history or history[-1]["frame"] < self.current_time):
                history.append({"frame": self.current_time, "x": curr_pos[0], "z": curr_pos[1]})

        if not history or len(history) < 2:
            return

        # Status colors
        status_colors = {
            "ACTIVE": color,
            "IDLE": "#888888",
            "PAUSED": "#aaaaaa",
            "DEAD": "#ff0000"
        }

        # Thresholds for "stay" markings
        STAY_DIST_THRESHOLD = 10.0 # elmos
        STAY_TIME_THRESHOLD = 300 # frames (~10s)

        stay_points = []
        stay_start_idx = 0

        # Draw per-edge segments to enable hover hit-testing
        for i in range(1, len(history)):
            p1 = history[i-1]
            p2 = history[i]
            status, _, _ = processing.get_unit_status_at_frame(unit_data, p2["frame"])  # status at end of segment
            cx1, cy1 = self._map_to_canvas(p1["x"], p1["z"])
            cx2, cy2 = self._map_to_canvas(p2["x"], p2["z"])
            seg_color = status_colors.get(status, color)
            dash = (3, 2) if status != "ACTIVE" else None
            width = 1 if thin else (2 if status == "ACTIVE" else 1)
            item = self.canvas.create_line(cx1, cy1, cx2, cy2, fill=seg_color, width=width, dash=dash, tags=("pathseg",))
            # store meta for tooltip
            if with_tooltip:
                self._item_meta[item] = {
                    "unit": unit_data,
                    "f1": p1["frame"],
                    "f2": p2["frame"],
                    "status": status,
                    "x1": cx1, "y1": cy1, "x2": cx2, "y2": cy2,
                }

            # stay detection
            sp = history[stay_start_idx]
            dist_sq = (p2["x"] - sp["x"])**2 + (p2["z"] - sp["z"])**2
            if dist_sq > STAY_DIST_THRESHOLD**2:
                duration = p2["frame"] - sp["frame"]
                if duration >= STAY_TIME_THRESHOLD:
                    stay_points.append(sp)
                stay_start_idx = i
            elif i == len(history) - 1:
                duration = p2["frame"] - sp["frame"]
                if duration >= STAY_TIME_THRESHOLD:
                    stay_points.append(sp)

        # Highlight current position on the path
        curr_pos, _ = self._get_pos_and_heading(u)
        if curr_pos:
            cx, cy = self._map_to_canvas(curr_pos[0], curr_pos[1])
            self.canvas.create_oval(cx - 3, cy - 3, cx + 3, cy + 3, fill="white", outline=color, width=1)

        # Draw stay markings
        for sp in stay_points:
            cx, cy = self._map_to_canvas(sp["x"], sp["z"])
            r = 5
            self.canvas.create_oval(cx - r, cy - r, cx + r, cy + r, outline="#ffaa00", width=2)
            self.canvas.create_line(cx - r, cy - r, cx + r, cy + r, fill="#ffaa00", width=2)
            self.canvas.create_line(cx + r, cy - r, cx - r, cy + r, fill="#ffaa00", width=2)

    def _draw_grid(self, mx1, my1, mx2, my2):
        if self.map_w <= 0 or self.map_h <= 0: return

        # Base interval is 500 elmos
        base_interval = 500

        # Adaptive interval based on zoom to keep grid density reasonable
        if self.zoom_factor > 10:
            interval = 100
        elif self.zoom_factor > 4:
            interval = 250
        elif self.zoom_factor < 0.5:
            interval = 1000
        else:
            interval = 500

        # Draw vertical lines
        for x in range(0, self.map_w + 1, interval):
            cx1, cy1 = self._map_to_canvas(x, 0)
            cx2, cy2 = self._map_to_canvas(x, self.map_h)

            # Clip lines to map rectangle visually
            lx1 = cx1
            ly1 = max(cy1, my1)
            lx2 = cx2
            ly2 = min(cy2, my2)

            if ly1 < ly2:
                self.canvas.create_line(lx1, ly1, lx2, ly2, fill="#e0e0e0", width=1)
                # Label
                if self.zoom_factor > 2 or x % 1000 == 0:
                     self.canvas.create_text(lx1, ly1, text=str(x), anchor="sw", font=("Arial", 6), fill="#aaa")

        # Draw horizontal lines
        for z in range(0, self.map_h + 1, interval):
            cx1, cy1 = self._map_to_canvas(0, z)
            cx2, cy2 = self._map_to_canvas(self.map_w, z)

            lx1 = max(cx1, mx1)
            ly1 = cy1
            lx2 = min(cx2, mx2)
            ly2 = cy2

            if lx1 < lx2:
                self.canvas.create_line(lx1, ly1, lx2, ly2, fill="#e0e0e0", width=1)
                # Label
                if self.zoom_factor > 2 or z % 1000 == 0:
                    self.canvas.create_text(lx1, ly1, text=str(z), anchor="ne", font=("Arial", 6), fill="#aaa")

        # Draw scale indicator in bottom-right
        self._draw_scale_indicator(interval)

    def _draw_scale_indicator(self, interval):
        # Draw a bar representing the current interval
        # Use fixed uniform scale from _map_to_canvas logic
        scale_x = self.canvas_w / self.map_w
        scale_z = self.canvas_h / self.map_h
        base_scale = min(scale_x, scale_z) * self.zoom_factor
        bar_w = interval * base_scale

        px = self.canvas_w - 20
        py = self.canvas_h - 20

        self.canvas.create_line(px - bar_w, py, px, py, fill="black", width=2)
        self.canvas.create_line(px - bar_w, py - 5, px - bar_w, py + 5, fill="black", width=1)
        self.canvas.create_line(px, py - 5, px, py + 5, fill="black", width=1)
        self.canvas.create_text(px - bar_w/2, py - 5, text=f"{interval} elmos", anchor="s", font=("Arial", 8, "bold"))

    def _draw_projectile_path(self, unit_data: Dict, color: str):
        if "projectileHistory" not in unit_data:
            return

        history = unit_data["projectileHistory"]
        # projectileHistory might contain multiple projectiles interleaved or sequential.
        # id is the projectile id.
        projectiles = {}
        for p in history:
            pid = p.get('id')
            if pid not in projectiles:
                projectiles[pid] = []
            projectiles[pid].append(p)

        for pid, p_list in projectiles.items():
            # Only draw until current_time
            visible_p = [p for p in p_list if p["frame"] <= self.current_time]
            if len(visible_p) < 2:
                continue

            for i in range(1, len(visible_p)):
                p1 = visible_p[i-1]
                p2 = visible_p[i]
                cx1, cy1 = self._map_to_canvas(p1["x"], p1["z"])
                cx2, cy2 = self._map_to_canvas(p2["x"], p2["z"])
                self.canvas.create_line(cx1, cy1, cx2, cy2, fill=color, width=1, dash=(2, 2), tags=("projpath",))

            # Draw a small dot at the tip
            last_p = visible_p[-1]
            cx, cy = self._map_to_canvas(last_p["x"], last_p["z"])
            self.canvas.create_oval(cx - 2, cy - 2, cx + 2, cy + 2, fill=color, outline="white", width=1)

    def redraw(self):
        if not self.canvas.winfo_ismapped():
            # If not visible yet, resizing might not have happened correctly
            self.canvas_w = self.canvas.winfo_width()
            self.canvas_h = self.canvas.winfo_height()

        self.canvas.delete("all")
        self._item_meta.clear()

        # Draw map rectangle (background)
        mx1, my1 = self._map_to_canvas(0, 0)
        mx2, my2 = self._map_to_canvas(self.map_w, self.map_h)
        self.canvas.create_rectangle(mx1, my1, mx2, my2, outline="#666", fill="#fcfcfc")

        # Draw Gridlines (clipped to map bounds)
        self.canvas.create_rectangle(mx1, my1, mx2, my2, outline="#666", fill="#fcfcfc", tags="map_bg")
        self._draw_grid(mx1, my1, mx2, my2)

        # Draw selected path first (full detail)
        if self.selected:
            u_team = self.selected.get('teamId')
            color = "#3333ff" if u_team == 0 else ("#ff3333" if u_team == 1 else "#33ff33")
            self._draw_path(self.selected, color, thin=False, with_tooltip=True, limit_to_current_time=True)

        if self.show_projs_var.get():
            # Group by id just in case multiple samples for same id were passed
            for p in self.projectiles:
                # 1. Draw Trail
                trail = p.get('trail', [])
                if len(trail) >= 2:
                    for i in range(1, len(trail)):
                        t1 = trail[i-1]
                        t2 = trail[i]
                        tx1, ty1 = self._map_to_canvas(t1["x"], t1["z"])
                        tx2, ty2 = self._map_to_canvas(t2["x"], t2["z"])
                        # Fading trail effect would be nice but let's start with dashed lines
                        self.canvas.create_line(tx1, ty1, tx2, ty2, fill="#ff8800", width=3, dash=(2, 2), tags=("projectile_trail",))

                # 2. Draw Dot at current (or latest known) position
                cx, cy = self._map_to_canvas(p["x"], p["z"])
                # Projectiles can be colored by owner's team if ownerID is available?
                # For now let's use a distinct color or owner's team color if possible.
                # ownerID is the unit ID. We don't have owner's team here easily without more lookups.
                # Let's use orange for projectiles for now to make them stand out.
                self.canvas.create_oval(cx - 2, cy - 2, cx + 2, cy + 2, fill="#ffaa00", outline="black", width=1, tags=("projectile",))

        sel_team = self.selected.get('teamId') if self.selected else None

        TEAM_COLORS = {0: "#0000ff", 1: "#ff0000"}
        DEFAULT_COLOR = "#00ff00"

        # Draw alternatives paths and dots (only if enabled)
        if self.show_alts_var.get():
            for idx, alt in enumerate(self.alt_units):
                u = alt.get('unit') if isinstance(alt, dict) and 'unit' in alt else alt
                if not u: continue
                u_team = u.get('teamId') if isinstance(u, dict) else None
                color = TEAM_COLORS.get(u_team, DEFAULT_COLOR)
                # For alternatives, just draw the point, no path as per requirement
                pos, h = self._get_pos_and_heading(u)
                if pos:
                    label = str(idx + 1)
                    self._draw_unit_dot(pos[0], pos[1], color=color, r=4, outline="#333", label=label, heading=h)

        # Prev and Next paths and dots (only if enabled)
        if self.show_prev_var.get() and self.prev_unit:
            u = self.prev_unit
            u_team = u.get('teamId') if isinstance(u, dict) else None
            color = TEAM_COLORS.get(u_team, DEFAULT_COLOR)
            # For prev/next, just draw the point, no path as per requirement
            pos, h = self._get_pos_and_heading(u)
            if pos:
                self._draw_unit_dot(pos[0], pos[1], color=color, r=5, label="Previous", heading=h)
        if self.show_next_var.get() and self.next_unit:
            u = self.next_unit
            u_team = u.get('teamId') if isinstance(u, dict) else None
            color = TEAM_COLORS.get(u_team, DEFAULT_COLOR)
            # For prev/next, just draw the point, no path as per requirement
            pos, h = self._get_pos_and_heading(u)
            if pos:
                self._draw_unit_dot(pos[0], pos[1], color=color, r=5, label="Next", heading=h)

        # Extra: draw units by manually entered IDs
        ids_text = (self.ids_entry_var.get() or "").strip()
        manual_units = []
        if ids_text and self._unit_lookup_cb:
            for token in ids_text.split(','):
                tid = token.strip()
                if not tid:
                    continue
                try:
                    u = self._unit_lookup_cb(tid)
                except Exception:
                    u = None
                if u and isinstance(u, dict) and u.get('positionHistory'):
                    manual_units.append(u)
        # Render manual units with distinct color
        for u in manual_units:
            self._draw_path(u, "#3399ff", thin=True, with_tooltip=True)
            pos, h = self._get_pos_and_heading(u)
            if pos:
                self._draw_unit_dot(pos[0], pos[1], color="#3399ff", r=4, outline="#003366", label=str(u.get('unitId','?')), heading=h)

        # Selected on top (dot)
        pos, h = self._get_pos_and_heading(self.selected)
        if pos and self.selected:
            u_team = self.selected.get('teamId')
            color = "#3333ff" if u_team == 0 else ("#ff3333" if u_team == 1 else "#33ff33")
            label = str(self.selected.get('unitId', '?'))
            self._draw_unit_dot(pos[0], pos[1], color=color, r=6, label=label, heading=h, selected=True)
