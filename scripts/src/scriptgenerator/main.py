import os
import re
import threading
from tkinter import messagebox, ttk, scrolledtext, filedialog, simpledialog

import tkinter as tk
from slpp import slpp as lua

from scriptgenerator.config import constants as config
from scriptgenerator.config import manager as config_manager
from scriptgenerator.core import commands
from scriptgenerator.core import generator as timeline
from scriptgenerator.core import io as io_handlers
from scriptgenerator.core import processing
from scriptgenerator.core.project import ProjectManager
from scriptgenerator.core.parse_replay import run_headless_demo
from scriptgenerator.ui.timeline.widget import TimelineWidget
from scriptgenerator.ui.side_panel import SidePanel
from scriptgenerator.ui.minimap import MinimapWidget


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("TurboBarCam Script Generator")
        self.geometry("1400x950")

        try:
            self.state('zoomed')
        except:
            try:
                self.attributes('-zoomed', True)
            except:
                pass

        if lua is None:
            messagebox.showerror("Dependency Error", "The 'slpp' module is missing. Please add slpp.py to the folder.")
            self.destroy()
            return

        self.project_manager = ProjectManager()
        self.config_data = config_manager.load_config()

        self.loaded_units_registry = {}
        self.unit_lookup_table = {}
        self.metadata = {}
        self.minimap_win = None

        # Details Panel Vars
        self.var_human_name = tk.StringVar()
        self.var_name = tk.StringVar()
        self.var_start = tk.StringVar()
        self.var_end = tk.StringVar()
        self.var_unit_id = tk.StringVar()
        self.selected_block_ref = None

        self.create_widgets()

        self.bind("<Delete>", self.on_delete_key)
        self.bind("<Escape>", self.on_escape)
        self.bind("<Left>", lambda e: self.on_alt_prev())
        self.bind("<Right>", lambda e: self.on_alt_next())

    def on_escape(self, event):
        # 1. Clear alternative selection/preview
        if self.timeline_widget.logic.preview_units:
            self.timeline_widget.set_preview_units([])
            self.alternatives_panel.set_confirm_state(False)
            self.alternatives_panel.set_status("Alternatives cleared")
            return

        # Reset hover info just in case
        self.timeline_widget.on_mouse_leave()

        # 2. Clear subblock or block selection via timeline widget
        self.timeline_widget.controller.on_escape(event)

    def save_settings(self):
        self.config_data["ignore_names"] = self.entry_ignore_names.get()
        self.config_data["ignore_ids"] = self.entry_ignore_ids.get()
        self.config_data["preferred_names"] = self.entry_pref_names.get()
        self.config_data["prioritise_ids"] = self.entry_prio_ids.get()

        if self.project_manager.current_project_dir:
            self.project_manager.save_project_settings(self.config_data)
        config_manager.save_config(self.config_data)

    # --- TIME SYNC CALLBACKS ---
    def on_time_change_from_timeline(self, frame):
        # Update minimaps when timeline cursor moves
        try:
            if self.minimap:
                self.minimap.set_time(int(frame))
            if hasattr(self, 'detached_minimap') and self.minimap_win and self.minimap_win.winfo_exists():
                self.detached_minimap.set_time(int(frame))
        except Exception:
            pass

    def on_minimap_time_changed(self, frame):
        # Update timeline when minimap scrubber changes
        try:
            self.timeline_widget.set_current_time(int(frame))
            # Keep both minimaps consistent if both visible
            if hasattr(self, 'detached_minimap') and self.minimap_win and self.minimap_win.winfo_exists():
                self.detached_minimap.set_time(int(frame))
            if self.minimap:
                self.minimap.set_time(int(frame))
        except Exception:
            pass

    def create_widgets(self):
        # MAIN LAYOUT
        main_paned = tk.PanedWindow(self, orient="horizontal", sashwidth=4, bg="#ccc")
        main_paned.pack(fill="both", expand=True)

        self.left_frame = tk.Frame(main_paned)
        main_paned.add(self.left_frame, stretch="always")

        # Details Panel on the right
        self.details_panel = tk.Frame(main_paned, width=320, bg="#f0f0f0", borderwidth=1, relief="raised")
        main_paned.add(self.details_panel, stretch="never")

        # --- LEFT FRAME ---
        project_frame = tk.LabelFrame(self.left_frame, text="Project Management", padx=10, pady=10)
        project_frame.pack(fill="x", padx=10, pady=5)

        tk.Label(project_frame, text="Active Project:").pack(side="left", padx=5)
        self.project_combo = ttk.Combobox(project_frame, state="readonly", width=40)
        self.project_combo.pack(side="left", padx=5)
        self.project_combo.bind("<<ComboboxSelected>>", self.on_project_select)

        tk.Button(project_frame, text="New Project...", bg="#ccffcc", command=self.create_new_project).pack(side="left",
                                                                                                            padx=5)
        tk.Button(project_frame, text="Rename Project", command=self.rename_project).pack(side="left", padx=5)

        settings_frame = tk.LabelFrame(self.left_frame, text="Tuning & Filters (Saved per Project)", padx=10, pady=10)
        settings_frame.pack(fill="x", padx=10, pady=5)

        def create_setting_row(parent, label_text, config_key, row):
            lbl = tk.Label(parent, text=label_text, width=20, anchor="e")
            lbl.grid(row=row, column=0, padx=5, pady=2)
            entry = tk.Entry(parent)
            entry.grid(row=row, column=1, sticky="ew", padx=5, pady=2)
            entry.insert(0, self.config_data.get(config_key, config_manager.DEFAULT_CONFIG[config_key]))
            parent.grid_columnconfigure(1, weight=1)
            return entry

        self.entry_ignore_names = create_setting_row(settings_frame, "Ignore Names:", "ignore_names", 0)
        self.entry_ignore_ids = create_setting_row(settings_frame, "Ignore IDs:", "ignore_ids", 1)
        self.entry_pref_names = create_setting_row(settings_frame, "Preferred Names:", "preferred_names", 2)
        self.entry_prio_ids = create_setting_row(settings_frame, "Prioritise IDs:", "prioritise_ids", 3)

        version_frame = tk.LabelFrame(self.left_frame, text="Version Control (Local JSON versions)", padx=10, pady=10)
        version_frame.pack(fill="x", padx=10, pady=5)

        self.version_list = ttk.Combobox(version_frame, state="readonly")
        self.version_list.pack(side="left", fill="x", expand=True)
        self.version_list.bind("<<ComboboxSelected>>", self.on_version_select)

        tk.Button(version_frame, text="Refresh", command=lambda: self.refresh_version_list()).pack(side="left",
                                                                                                   padx=(5, 0))
        self.btn_apply = tk.Button(version_frame, text="APPLY TO GAME (Export Lua)", bg="#add8e6",
                                   command=self.apply_version)
        self.btn_apply.pack(side="right", padx=(5, 0))

        control_frame = tk.Frame(self.left_frame, padx=10, pady=10)
        control_frame.pack(fill="x")

        self.btn_generate = tk.Button(control_frame, text="GENERATE NEW TIMELINE", bg="#dddddd", height=2,
                                      command=self.start_generation)
        self.btn_generate.pack(side="left", fill="x", expand=True, padx=(0, 2))
        self.btn_update = tk.Button(control_frame, text="RE-GENERATE SELECTED", bg="#ffcccc", height=2,
                                    command=self.start_update)
        self.btn_update.pack(side="left", fill="x", expand=True, padx=2)

        save_frame = tk.LabelFrame(control_frame, text="Save Editor Changes", padx=5, pady=2)
        save_frame.pack(side="left", fill="y", padx=5)
        tk.Button(save_frame, text="Overwrite Selected", bg="#ffffcc",
                  command=lambda: self.save_editor_state(False)).pack(side="left", padx=2, fill="y")
        tk.Button(save_frame, text="Save as New Version", bg="#ffffcc",
                  command=lambda: self.save_editor_state(True)).pack(side="left", padx=2, fill="y")

        self.btn_csv = tk.Button(control_frame, text="EXPORT CSV", bg="#ccffcc", height=2, command=self.start_csv)
        self.btn_csv.pack(side="right", fill="x", padx=(10, 0))

        timeline_outer_frame = tk.LabelFrame(self.left_frame,
                                             text="Visual Timeline (Drag Edges to Resize | Scroll/MMB to Nav)", padx=10,
                                             pady=10)
        timeline_outer_frame.pack(fill="both", expand=True, padx=10, pady=5)

        self.hover_label = tk.Label(timeline_outer_frame, text="Hover over timeline for details", fg="gray")
        self.timeline_widget = TimelineWidget(
            timeline_outer_frame,
            self.hover_label,
            on_select_callback=self.on_timeline_select,
            on_double_click_callback=self.on_timeline_double_click,
            on_confirm_alt_callback=self.on_alt_confirm,
            on_time_change_callback=self.on_time_change_from_timeline
        )
        self.hover_label.pack(anchor="w")

        self.populate_details_panel_widgets()
        self.refresh_project_list()

    def populate_details_panel_widgets(self):
        # We'll use a main container to allow packing sections
        container = tk.Frame(self.details_panel, bg="#f0f0f0")
        container.pack(fill="both", expand=True)

        # Embedded Minimap
        minimap_frame = tk.LabelFrame(container, text="Minimap", bg="#f0f0f0")
        minimap_frame.pack(fill="x", padx=5, pady=5)
        self.minimap = MinimapWidget(minimap_frame, width=300, height=200)
        self.minimap.pack(fill="both", expand=True)
        # Sync: minimap -> timeline
        self.minimap.set_time_change_callback(self.on_minimap_time_changed)

        # Minimap launcher (for separate window if desired)
        top_tools = tk.Frame(container, bg="#f0f0f0")
        top_tools.pack(fill="x", padx=5, pady=(0,5))
        tk.Button(top_tools, text="Detach Minimap", command=self.open_minimap).pack(side="left")

        # 1. Block Details Section
        details_frame = tk.Frame(container, bg="#f0f0f0")
        details_frame.pack(fill="x", side="top")

        header = tk.Frame(details_frame, bg="#ddd", pady=5)
        header.pack(fill="x")
        tk.Label(header, text="Selected Block Details", bg="#ddd", font=("Arial", 10, "bold")).pack()

        form_frame = tk.Frame(details_frame, bg="#f0f0f0", padx=10, pady=10)
        form_frame.pack(fill="x")

        def add_row(label, var, readonly=False):
            f = tk.Frame(form_frame, bg="#f0f0f0")
            f.pack(fill="x", pady=2)
            tk.Label(f, text=label, bg="#f0f0f0", anchor="w").pack(fill="x")
            state = "readonly" if readonly else "normal"
            e = tk.Entry(f, textvariable=var, state=state)
            e.pack(fill="x")
            if not readonly:
                e.bind("<Return>", self.update_block_data)
                e.bind("<FocusOut>", self.update_block_data)
            return e

        add_row("Human Name", self.var_human_name, readonly=True)
        add_row("Name", self.var_name, readonly=True)
        add_row("Start Frame", self.var_start)
        add_row("End Frame", self.var_end)
        add_row("Unit ID", self.var_unit_id)

        tk.Label(form_frame, text="Commands (Lua):", bg="#f0f0f0", anchor="w").pack(fill="x", pady=(10, 0))
        self.txt_commands = scrolledtext.ScrolledText(form_frame, height=10, font=("Consolas", 9))
        self.txt_commands.pack(fill="x", pady=2)
        self.txt_commands.bind("<KeyRelease>", self.update_commands_data)

        # 2. Alternatives Controls Section
        alt_header = tk.Frame(container, bg="#ddd", pady=5)
        alt_header.pack(fill="x", pady=(10, 0))
        tk.Label(alt_header, text="Alternatives Control", bg="#ddd", font=("Arial", 10, "bold")).pack()

        self.alternatives_panel = SidePanel(
            container,
            on_next_callback=self.on_alt_next,
            on_prev_callback=self.on_alt_prev,
            on_confirm_callback=self.on_alt_confirm
        )
        self.alternatives_panel.pack(fill="x", side="top", padx=5, pady=5)
        self.alt_current_page = 1
        self.alt_candidates = []

        # 3. Execution Log Section (Bottom)
        log_outer_frame = tk.LabelFrame(container, text="Execution Log", padx=5, pady=5)
        log_outer_frame.pack(fill="both", expand=True, padx=5, pady=5)
        self.log_text = scrolledtext.ScrolledText(log_outer_frame, state="disabled", font=("Consolas", 8), height=10)
        self.log_text.pack(fill="both", expand=True)

    def on_delete_key(self, event):
        if not self.selected_block_ref: return
        block = self.selected_block_ref
        if block.get('type') == 'gap': return
        name = block.get('unit_data', {}).get('humanName', 'Unknown')
        if messagebox.askyesno("Confirm Delete", f"Delete block '{name}'?"):
            uid = self.timeline_widget.selected_block_id
            if self.timeline_widget.delete_block(uid):
                self.selected_block_ref = None
                self.on_timeline_select(None)
                self.log(f"Deleted block: {name}")

    # --- PROJECT LOGIC ---
    def load_project_settings(self):
        new_data = self.project_manager.load_project_settings()
        if new_data:
            self.config_data = new_data
            self.entry_ignore_names.delete(0, tk.END)
            self.entry_ignore_names.insert(0, self.config_data.get("ignore_names", ""))
            self.entry_ignore_ids.delete(0, tk.END)
            self.entry_ignore_ids.insert(0, self.config_data.get("ignore_ids", ""))
            self.entry_pref_names.delete(0, tk.END)
            self.entry_pref_names.insert(0, self.config_data.get("preferred_names", ""))
            self.entry_prio_ids.delete(0, tk.END)
            self.entry_prio_ids.insert(0, self.config_data.get("prioritise_ids", ""))
            self.log("Loaded project settings.")
        else:
            self.log("Using default settings.")

    def refresh_project_list(self):
        projects = self.project_manager.list_projects()
        self.projects_list = projects
        self.project_combo['values'] = [p[0] for p in projects]

    def on_project_select(self, event):
        selection = self.project_combo.get()
        if not selection: return
        project_id = None
        for name, pid in self.projects_list:
            if name == selection:
                project_id = pid
                break
        if not project_id: return

        # Loading Indicator
        self.log(f"Loading Project: {selection}...")
        self.update_idletasks()

        path = self.project_manager.select_project(project_id)
        self.log(f"Project path: {path}")
        self.load_project_settings()
        self.load_project_source_data()
        self.refresh_version_list()

    def create_new_project(self):
        filename = filedialog.askopenfilename(
            title="Select Source Unit Data File",
            filetypes=[("Lua/Replay", "*.lua *.sdfz"), ("All Files", "*.*")]
        )
        if not filename: return

        if filename.lower().endswith(".sdfz"):
            if messagebox.askyesno("Replay Selected", "Do you want to parse this replay now using headless mode?"):
                self.start_replay_parsing(filename)
                return
            else:
                # If they say no, we can't really use .sdfz as a source data file directly
                return

        default_name = os.path.splitext(os.path.basename(filename))[0]
        project_name = simpledialog.askstring("New Project", "Enter Project Name:", initialvalue=default_name)
        if not project_name: return

        self.project_manager.create_project(filename, project_name)
        self.refresh_project_list()
        self.project_combo.set(project_name)
        self.on_project_select(None)
        self.save_settings()
        if messagebox.askyesno("Generate", "Generate initial timeline (v1) now?"):
            self.start_generation()

    def start_replay_parsing(self, replay_path):
        self.prepare_ui_for_process()
        self.log(f"--- Starting Replay Parsing: {os.path.basename(replay_path)} ---")

        def run_parsing():
            def progress_cb(current, total, line):
                pct = (current / total * 100) if total > 0 else 0
                self.after(0, lambda: self.hover_label.config(text=f"Parsing Replay: {pct:.1f}% (Frame {current}/{total})"))
                # Log all lines to execution log
                self.after(0, lambda: self.log(f"[Spring] {line}"))

            try:
                result_lua = run_headless_demo(replay_path, progress_callback=progress_cb)

                if result_lua and os.path.exists(result_lua):
                    self.after(0, lambda: self.log(f"Successfully parsed: {result_lua}"))
                    self.after(0, lambda: self.finish_replay_parsing(result_lua))
                else:
                    self.after(0, lambda: messagebox.showerror("Parsing Failed", "Could not find the output lua file in logs."))
                    self.after(0, self.restore_ui)
            except Exception as e:
                self.after(0, lambda: self.log(f"Parsing Error: {e}"))
                self.after(0, self.restore_ui)

        thread = threading.Thread(target=run_parsing, daemon=True)
        thread.start()

    def finish_replay_parsing(self, lua_path):
        self.restore_ui()
        default_name = os.path.splitext(os.path.basename(lua_path))[0]
        project_name = simpledialog.askstring("New Project", "Parsing Complete! Enter Project Name:", initialvalue=default_name)
        if not project_name: return

        self.project_manager.create_project(lua_path, project_name)
        self.refresh_project_list()
        self.project_combo.set(project_name)
        self.on_project_select(None)
        self.save_settings()
        if messagebox.askyesno("Generate", "Generate initial timeline (v1) now?"):
            self.start_generation()

    def rename_project(self):
        if not self.project_manager.current_project_dir: return
        current_name = self.project_combo.get()
        new_name = simpledialog.askstring("Rename", "New Project Name:", initialvalue=current_name)
        if not new_name: return
        self.project_manager.rename_current_project(new_name)
        self.refresh_project_list()
        self.project_combo.set(new_name)

    def load_project_source_data(self):
        source_path = self.project_manager.get_source_file_path()
        if not source_path: return
        if not os.path.exists(source_path):
            self.log(f"Error: Source file missing: {source_path}")
            return
        try:
            self.log("Loading source data (SQLite cache)...")
            self.update_idletasks()
            raw_units, metadata = self.project_manager.get_source_data(source_path, lua)
            self.metadata = metadata or {}
            end_frame = metadata.get('endFrame', 0)
            if end_frame == 0:
                for u in raw_units.values():
                    died_val = u.get('diedFrame')
                    if died_val is not None:
                        end_frame = max(end_frame, died_val)
            self.timeline_widget.set_global_max_frame(end_frame)
            self.log("Preprocessing unit data...")
            self.update_idletasks()
            # preprocess_data now only deals with minimal units
            units = processing.preprocess_data(raw_units, apply_filters=False, max_frame=end_frame)
            self.loaded_units_registry = units
            self.unit_lookup_table = processing.build_lookup_table(units)
            self.timeline_widget.set_unit_registry(units)
            # Inject database into timeline widget for on-demand history loading
            self.timeline_widget.db = self.project_manager.db
            self.log(f"Loaded {len(units)} units from source. Max Frame: {end_frame}")
        except Exception as e:
            self.log(f"Error loading source data: {e}")
            import traceback
            traceback.print_exc()


    def on_timeline_select(self, block_data):
        self.selected_block_ref = block_data

        # Check if an alternative is currently selected to enable confirm button
        preview_idx = self.timeline_widget.logic.selected_preview_index
        if preview_idx is not None:
            self.alternatives_panel.set_confirm_state(True)
            self.alternatives_panel.set_status(f"Alternative #{preview_idx+1} selected. Click 'Confirm Selection' to insert.")
            # If we just selected an alternative bar, we DON'T want to re-run the search
            # and potentially change the candidate list we are picking from.
            return

        if not block_data or block_data.get('type') == 'gap':
            # If it's a GAP, prepare to show alternatives to fill it
            is_gap = bool(block_data and block_data.get('type') == 'gap')

            self.var_human_name.set("Empty Slot" if is_gap else "")
            self.var_name.set("")
            if block_data:
                self.var_start.set(str(block_data.get('start', '')))
                self.var_end.set(str(block_data.get('end', '')))
                self.var_unit_id.set("")
            else:
                self.var_start.set("")
                self.var_end.set("")
                self.var_unit_id.set("")
            self.txt_commands.delete("1.0", tk.END)
            self.txt_commands.config(state="disabled")

            # For gaps: compute and show alternatives to fill the gap
            if is_gap:
                # Set subblock to the gap range for consistent visuals/labels
                self.timeline_widget.logic.subblock_start = block_data.get('start', 0)
                self.timeline_widget.logic.subblock_end = block_data.get('end', 0)
                self.show_alternatives_for_selection()
                self.update_minimap()
            else:
                # No selection: clear alternatives
                self.alt_candidates = []
                self.alt_current_page = 1
                self.timeline_widget.set_preview_units([])
                self.alternatives_panel.set_page(1)
                self.alternatives_panel.set_confirm_state(False)
                self.alternatives_panel.set_status("Select block")
            return
        self.txt_commands.config(state="normal")
        u_data = block_data.get('unit_data', {})
        self.var_human_name.set(str(u_data.get('humanName', '')))
        self.var_name.set(str(u_data.get('name', '')))
        self.var_start.set(str(block_data.get('start', '')))
        self.var_end.set(str(block_data.get('end', '')))
        game_id = u_data.get('unitId', block_data.get('unit_id', ''))
        self.var_unit_id.set(str(game_id))

        cmds = []
        segments = block_data.get('segments', [])
        if segments:
            cmds = segments[0].get('commands', [])
        elif 'commands' in block_data:
            cmds = block_data['commands']
        self.txt_commands.delete("1.0", tk.END)
        if cmds:
            self.txt_commands.insert("1.0", "\n".join(cmds))

        self.show_alternatives_for_selection()
        self.update_minimap()

    def show_alternatives_for_selection(self):
        if not self.selected_block_ref:
            self.alt_candidates = []
            self.timeline_widget.set_preview_units([])
            self.alternatives_panel.set_confirm_state(False)
            self.alternatives_panel.set_status("Select block")
            return

        # If a GAP is selected, fetch alternatives for the full gap range
        if self.selected_block_ref.get('type') == 'gap':
            gap_start = int(self.selected_block_ref.get('start', 0))
            gap_end = int(self.selected_block_ref.get('end', gap_start))

            # Use a fairly large pool to paginate from
            fetch_count = 60

            self.alt_candidates = processing.get_candidates_for_range(
                self.loaded_units_registry, gap_start, gap_end, None, fetch_count,
                db=self.project_manager.db, ref_unit_full=None
            )

            # Set subblock to gap to drive labels and minimap
            self.timeline_widget.logic.subblock_start = gap_start
            self.timeline_widget.logic.subblock_end = gap_end

            self.alt_current_page = 1
            self.update_alternatives_view()
            return

        # NEW: Only show if subblock is fully selected
        if self.timeline_widget.logic.subblock_start is None or self.timeline_widget.logic.subblock_end is None:
            self.alt_candidates = []
            self.timeline_widget.set_preview_units([])
            self.alternatives_panel.set_confirm_state(False)
            self.alternatives_panel.set_status("Select sub-block range")
            return

        block = self.selected_block_ref
        start_f = self.timeline_widget.logic.subblock_start
        end_f = self.timeline_widget.logic.subblock_end

        ref_id = block.get('unit_id')
        if not ref_id and block.get('unit_data'):
            ref_id = block['unit_data'].get('id')

        # Always fetch a good pool of candidates
        fetch_count = 60

        ref_unit = None
        if ref_id and self.project_manager.db:
            ref_unit = self.project_manager.db.get_unit_full(str(ref_id))

        self.alt_candidates = processing.get_candidates_for_range(
            self.loaded_units_registry, start_f, end_f, ref_id, fetch_count,
            db=self.project_manager.db, ref_unit_full=ref_unit
        )

        self.alt_current_page = 1
        self.update_alternatives_view()

    def update_alternatives_view(self):
        # Show paginated alternatives
        self.timeline_widget.logic.selected_preview_index = None

        start_idx = (self.alt_current_page - 1) * 5
        end_idx = start_idx + 5
        page_candidates = self.alt_candidates[start_idx:end_idx]

        self.timeline_widget.set_preview_units(page_candidates)

        if hasattr(self.alternatives_panel, 'set_page'):
            self.alternatives_panel.set_page(self.alt_current_page)
        self.alternatives_panel.set_confirm_state(False)

        if not self.alt_candidates:
            self.alternatives_panel.set_status("No alternatives found")
        else:
            self.alternatives_panel.set_status(f"Found {len(self.alt_candidates)} candidates. Click an alternative bar to select.")

        # Sync minimap with new page of alternatives
        self.update_minimap()

    def on_alt_next(self):
        if not self.alt_candidates: return
        total_pages = (len(self.alt_candidates) + 4) // 5
        if self.alt_current_page < total_pages:
            self.alt_current_page += 1
        else:
            self.alt_current_page = 1
        self.update_alternatives_view()

    def on_alt_prev(self):
        if not self.alt_candidates: return
        total_pages = (len(self.alt_candidates) + 4) // 5
        if self.alt_current_page > 1:
            self.alt_current_page -= 1
        else:
            self.alt_current_page = total_pages
        self.update_alternatives_view()

    def on_alt_confirm(self):
        logic = self.timeline_widget.logic
        if logic.selected_preview_index is not None and logic.preview_units:
            selected_alt = logic.preview_units[logic.selected_preview_index]
            unit_id = selected_alt['id']
            self.apply_unit_update(str(unit_id))
            # After confirming, clear alternatives
            self.timeline_widget.set_preview_units([])
            self.alt_candidates = []
            self.alternatives_panel.set_confirm_state(False)
            self.alternatives_panel.set_status("Unit inserted")

    def on_timeline_double_click(self, frame, block_data):
        # We might want to keep double-click for quick selection or just rely on single-click + subblock
        pass

    def on_alternative_preview(self, unit_data):
        pass

    def on_alternative_confirm(self, new_unit_unique_id):
        pass

    def open_minimap(self):
        try:
            if self.minimap_win and self.minimap_win.winfo_exists():
                # bring to front and refresh
                self.minimap_win.lift()
            else:
                self.minimap_win = tk.Toplevel(self)
                self.minimap_win.title("Minimap (Detached)")
                # We create a NEW minimap widget for the detached window
                self.detached_minimap = MinimapWidget(self.minimap_win, width=400, height=400)
                self.detached_minimap.pack(fill="both", expand=True)
                # Sync: detached minimap -> timeline
                self.detached_minimap.set_time_change_callback(self.on_minimap_time_changed)
            self.update_minimap()
        except Exception as e:
            self.log(f"Failed to open minimap: {e}")

    def update_minimap(self):
        # Update both embedded and detached minimaps if they exist
        minimaps = []
        if self.minimap:
            minimaps.append(self.minimap)
        if hasattr(self, 'detached_minimap') and self.minimap_win and self.minimap_win.winfo_exists():
            minimaps.append(self.detached_minimap)

        if not minimaps:
            return

        # Context: map size and time range
        map_w = self.metadata.get('mapWidth') or self.metadata.get('map_size_x') or 0
        map_h = self.metadata.get('mapHeight') or self.metadata.get('map_size_z') or 0
        gmax = self.timeline_widget.logic.global_max_frame

        # Selected, prev, next
        selected_u = None
        prev_u = None
        next_u = None
        logic = self.timeline_widget.logic
        idx = logic.selected_block_index
        tl = logic.timeline_data if logic else []

        if idx is not None and 0 <= idx < len(tl):
            blk = tl[idx]
            selected_u = blk.get('unit_data')
            # prev
            j = idx - 1
            while j >= 0:
                if tl[j].get('type') in ['unit', 'block'] and tl[j].get('unit_data'):
                    prev_u = tl[j].get('unit_data')
                    break
                j -= 1
            # next
            j = idx + 1
            while j < len(tl):
                if tl[j].get('type') in ['unit', 'block'] and tl[j].get('unit_data'):
                    next_u = tl[j].get('unit_data')
                    break
                j += 1

        # Alternatives
        alts = logic.preview_units if logic else []

        # Time: prefer timeline current_time, else subblock center, else selected born
        current_frame = 0
        if logic and getattr(logic, 'current_time', None) is not None:
            current_frame = int(logic.current_time)
        if (not current_frame) and logic and logic.subblock_start is not None and logic.subblock_end is not None:
            current_frame = int((logic.subblock_start + logic.subblock_end) / 2)
        if (not current_frame) and selected_u and 'bornFrame' in selected_u:
            current_frame = int(selected_u.get('bornFrame', 0))

        for m in minimaps:
            # provide unit lookup for manual ID rendering in minimap
            if hasattr(m, 'set_unit_lookup'):
                m.set_unit_lookup(self.lookup_unit)
            m.set_context(int(map_w or 0), int(map_h or 0), 0, int(gmax or 1))
            m.set_selection(selected_u, prev_u, next_u, alts)
            m.set_time(current_frame)


    def update_block_data(self, event=None):
        if not self.selected_block_ref: return
        try:
            input_id_str = self.var_unit_id.get().strip()
            u_data = processing.resolve_unit_id_input(
                input_id_str,
                int(self.var_start.get()),
                int(self.var_end.get()),
                self.loaded_units_registry,
                self.unit_lookup_table
            )
            target_unique_id = None
            if u_data:
                target_unique_id = u_data['id']
            elif input_id_str:
                target_unique_id = input_id_str
            else:
                target_unique_id = ""
            if target_unique_id:
                self.apply_unit_update(target_unique_id)
        except ValueError:
            return

    def apply_unit_update(self, new_unique_id_str):
        if not self.selected_block_ref: return
        try:
            new_start = int(self.var_start.get())
            new_end = int(self.var_end.get())
        except ValueError:
            return

        u_data = None
        new_cmds = None
        if new_unique_id_str:
            u_data = self.lookup_unit(new_unique_id_str)
            new_cmds = self.generate_commands(u_data.get('unitId', new_unique_id_str))

        uid = self.timeline_widget.selected_block_id

        # Check for subblock insertion
        if self.timeline_widget.logic.subblock_start is not None and self.timeline_widget.logic.subblock_end is not None:
            sub_start = self.timeline_widget.logic.subblock_start
            sub_end = self.timeline_widget.logic.subblock_end
            new_uid = self.timeline_widget.insert_into_block(uid, sub_start, sub_end, u_data, new_cmds)
        else:
            new_uid = self.timeline_widget.update_block(uid, new_start, new_end, u_data, new_cmds)

        if new_uid:
            # Re-select the newly created block
            # Note: widget.draw_timeline(maintain_scroll=True) was already called
            # inside insert_into_block/update_block, which rebuilt logic.timeline_data.
            found = False
            for b in self.timeline_widget.timeline_data:
                if self.timeline_widget.logic.get_block_uid(b) == new_uid:
                    self.timeline_widget.logic.selected_block_id = new_uid
                    self.on_timeline_select(b)
                    # Automatically select the newly created block as subblock
                    self.timeline_widget.logic.subblock_start = b['start']
                    self.timeline_widget.logic.subblock_end = b['end']
                    self.timeline_widget.render_visible_section()
                    found = True
                    break

    def lookup_unit(self, id_str):
        if id_str in self.loaded_units_registry:
            return self.loaded_units_registry[id_str]
        return {"id": id_str, "unitId": id_str, "name": "Unknown", "humanName": "Unknown Unit"}

    def generate_commands(self, game_unit_id):
        return commands.get_default_unit_commands(game_unit_id)

    def update_commands_data(self, event=None):
        if not self.selected_block_ref: return
        text = self.txt_commands.get("1.0", tk.END).strip()
        cmds = text.split('\n') if text else []
        block = self.selected_block_ref
        segments = block.get('segments', []) if block['type'] == 'block' else [block]
        if segments: segments[0]['commands'] = cmds

    def log(self, message):
        self.log_text.config(state="normal")
        self.log_text.insert(tk.END, message + "\n")
        self.log_text.see(tk.END)
        self.log_text.config(state="disabled")

    def update_backend_params(self):
        config.update_filters(
            self.entry_ignore_names.get(),
            self.entry_ignore_ids.get(),
            self.entry_pref_names.get(),
            self.entry_prio_ids.get()
        )
        self.save_settings()

    def refresh_version_list(self, target_selection=None):
        versions = self.project_manager.get_versions()
        clean_name = processing.get_clean_id(self.project_combo.get())
        game_file_path = os.path.join(config.GAME_OUTPUT_DIR, f"{clean_name}.lua")
        current_active = io_handlers.get_game_file_version(game_file_path)

        display_values = []
        for v_str in versions:
            try:
                v_num = int(re.search(r'v(\d+)\.json$', v_str).group(1))
                if current_active is not None and v_num == current_active:
                    display_values.append(f"{v_str} (current)")
                else:
                    display_values.append(v_str)
            except:
                display_values.append(v_str)
        self.version_list['values'] = display_values
        if display_values:
            index = 0
            if target_selection:
                if target_selection.endswith(".lua"): target_selection = target_selection.replace(".lua", ".json")
                for i, val in enumerate(display_values):
                    if val.startswith(target_selection):
                        index = i
                        break
            self.version_list.current(index)
        else:
            self.version_list.set('')
        self.on_version_select(None)

    def on_version_select(self, event):
        raw_selection = self.version_list.get()
        selection = raw_selection.split(" (current)")[0]
        if not selection:
            self.btn_update.config(state="disabled", text="RE-GENERATE SELECTED")
            return
        self.btn_update.config(state="normal", text=f"RE-GENERATE {selection}")
        path = os.path.join(self.project_manager.current_project_dir, selection)
        timeline_data = io_handlers.load_internal_json(path)
        if not timeline_data:
            self.log("Failed to load JSON timeline.")
            return
        if not self.loaded_units_registry:
            self.load_project_source_data()
        timeline_data = io_handlers.enrich_timeline_with_unit_ids(timeline_data, self.loaded_units_registry)
        self.timeline_widget.should_autofit = True
        self.timeline_widget.draw_timeline(timeline_data)

    def apply_version(self):
        raw_selection = self.version_list.get()
        selection = raw_selection.split(" (current)")[0]
        if not selection: return
        project_name = self.project_combo.get()
        clean_project_name = processing.get_clean_id(project_name)
        try:
            version_num = int(re.search(r'v(\d+)\.json$', selection).group(1))
        except:
            version_num = 1
        source_path = os.path.join(self.project_manager.current_project_dir, selection)
        target_path = os.path.join(config.GAME_OUTPUT_DIR, f"{clean_project_name}.lua")
        timeline_data = io_handlers.load_internal_json(source_path)
        if not timeline_data: return
        timeline_data = io_handlers.enrich_timeline_with_unit_ids(timeline_data, self.loaded_units_registry)
        try:
            meta = self.project_manager.get_current_project_meta()
            source_filename = meta.get("source_file", "source")
            io_handlers.write_game_script(timeline_data, target_path, source_filename, version_num, self.log)
            self.log(f"APPLIED TO GAME: {selection} (v{version_num}) -> {target_path}")
            self.refresh_version_list(target_selection=selection)
        except Exception as e:
            messagebox.showerror("Error", f"Failed to write game file: {e}")

    def prepare_ui_for_process(self):
        self.btn_generate.config(state="disabled")
        self.btn_update.config(state="disabled")
        self.btn_csv.config(state="disabled")
        self.log_text.config(state="normal")
        self.log_text.delete(1.0, tk.END)
        self.log_text.config(state="disabled")
        self.hover_label.config(text="Processing...")
        self.save_settings()
        self.on_timeline_select(None)

    def restore_ui(self):
        self.btn_generate.config(state="normal")
        self.btn_csv.config(state="normal")
        self.on_version_select(None)
        if not self.timeline_widget.timeline_data:
            self.hover_label.config(text="No timeline generated.")
        else:
            self.hover_label.config(text="Hover over timeline for details")

    def start_generation(self):
        if not self.project_manager.current_project_dir:
            messagebox.showerror("Error", "No project selected.")
            return
        if messagebox.askokcancel("Confirm Reset", "Generate new timeline? Discards manual edits in current view."):
            self.update_backend_params()
            self.prepare_ui_for_process()
            self.timeline_widget.reset()
            source_file = self.project_manager.get_source_file_path()
            thread = threading.Thread(target=self.run_logic, args=(source_file, None))
            thread.start()

    def start_update(self):
        if not self.project_manager.current_project_dir: return
        raw_selection = self.version_list.get()
        selection = raw_selection.split(" (current)")[0]
        if not selection: return
        if messagebox.askokcancel("Confirm Re-Generate", f"Re-generate {selection}?"):
            self.update_backend_params()
            self.prepare_ui_for_process()
            self.timeline_widget.reset()
            source_file = self.project_manager.get_source_file_path()
            thread = threading.Thread(target=self.run_logic, args=(source_file, selection))
            thread.start()

    def save_editor_state(self, new_version=False):
        timeline_data = self.timeline_widget.original_timeline
        if not timeline_data or not self.project_manager.current_project_dir: return

        if new_version:
            target_filename = self.project_manager.get_next_version_filename()
        else:
            raw_selection = self.version_list.get()
            selection = raw_selection.split(" (current)")[0]
            if not selection: return
            target_filename = selection

        version_path = os.path.join(self.project_manager.current_project_dir, target_filename)
        try:
            io_handlers.save_internal_json(timeline_data, version_path, self.log)
            self.log(f"SAVED MANUAL EDITS: {target_filename}")
            self.refresh_version_list(target_selection=target_filename)
        except Exception as e:
            self.log(f"Save Error: {e}")

    def start_csv(self):
        if not self.project_manager.current_project_dir: return
        self.update_backend_params()
        self.prepare_ui_for_process()
        source_file = self.project_manager.get_source_file_path()
        thread = threading.Thread(target=self.run_csv_logic, args=(source_file,))
        thread.start()

    def run_csv_logic(self, input_file):
        def ui_log(msg):
            self.after(0, self.log, msg)

        try:
            ui_log(f"--- Loading: {input_file} ---")
            # We need full data for CSV usually
            # But preprocess_data now expects minimal units.
            # Let's adjust run_csv_logic to fetch full units from DB.
            raw_units_min, metadata = self.project_manager.get_source_data(input_file, lua)

            ui_log("Fetching full unit data from DB for CSV...")
            full_units = {}
            for uid in raw_units_min.keys():
                u_full = self.project_manager.db.get_unit_full(uid)
                if u_full:
                    full_units[uid] = u_full

            data = processing.preprocess_data(full_units, apply_filters=True, max_frame=metadata.get('endFrame'))
            csv_path = os.path.join(self.project_manager.current_project_dir, "stats.csv")
            io_handlers.write_csv_file(data, metadata, csv_path, ui_log)
        except Exception as e:
            ui_log(f"CRITICAL ERROR: {str(e)}")
            import traceback
            traceback.print_exc()
        finally:
            self.after(0, self.restore_ui)

    def run_logic(self, input_file, target_filename=None):
        def ui_log(msg):
            self.after(0, self.log, msg)

        try:
            ui_log(f"--- Loading {input_file} ---")
            raw_units_min, metadata = self.project_manager.get_source_data(input_file, lua)

            ui_log("Fetching full unit data for generation...")
            # For generation we MUST have histories
            full_units = {}
            for uid in raw_units_min.keys():
                u_full = self.project_manager.db.get_unit_full(uid)
                if u_full:
                    full_units[uid] = u_full

            data = processing.preprocess_data(full_units, apply_filters=True, max_frame=metadata.get('endFrame'))
            meta_end = metadata.get('endFrame', 0)
            if not data:
                ui_log("Error: No valid unit data found.")
                return
            timeline_data, final_end_frame = timeline.generate_timeline(data, ui_log, meta_end)

            if not target_filename:
                target_filename = self.project_manager.get_next_version_filename()

            version_path = os.path.join(self.project_manager.current_project_dir, target_filename)
            ui_log(f"Saving to: {target_filename}")

            io_handlers.save_internal_json(timeline_data, version_path, ui_log)
            self.after(0, lambda: self.refresh_version_list(target_selection=target_filename))
        except Exception as e:
            ui_log(f"CRITICAL ERROR: {str(e)}")
            import traceback
            traceback.print_exc()
        finally:
            self.after(0, self.restore_ui)


if __name__ == "__main__":
    app = App()
    app.mainloop()
