import os
import json
import threading
import shutil
import glob
import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext
from tkinter import ttk

import backend

# Try to import slpp; handle error if missing
try:
    from slpp import slpp as lua
except ImportError:
    print("Error: 'slpp' module not found. Please ensure slpp.py is in the directory.")
    lua = None

CONFIG_FILE = "turbobarcam_settings.json"

DEFAULT_CONFIG = {
    "last_input_file": ""
}

class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("TurboBarCam Script Generator")
        self.geometry("900x800")

        if lua is None:
            messagebox.showerror("Dependency Error", "The 'slpp' module is missing. Please add slpp.py to the folder.")
            self.destroy()
            return

        self.config_data = self.load_config()
        self.create_widgets()

    def load_config(self):
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, "r") as f:
                    return json.load(f)
            except:
                return DEFAULT_CONFIG.copy()
        return DEFAULT_CONFIG.copy()

    def save_config(self):
        with open(CONFIG_FILE, "w") as f:
            json.dump(self.config_data, f)

    def create_widgets(self):
        # --- INPUT FILE ---
        input_frame = tk.LabelFrame(self, text="Veterancy Data File (Input)", padx=10, pady=10)
        input_frame.pack(fill="x", padx=10, pady=5)

        self.entry_input = tk.Entry(input_frame)
        self.entry_input.pack(side="left", fill="x", expand=True)
        self.entry_input.insert(0, self.config_data.get("last_input_file", ""))
        self.entry_input.bind("<FocusOut>", lambda e: self.refresh_version_list())

        btn_browse_in = tk.Button(input_frame, text="Browse...", command=self.browse_input)
        btn_browse_in.pack(side="right", padx=(5, 0))

        # --- VERSION CONTROL ---
        version_frame = tk.LabelFrame(self, text="Version Control (Saved in ./scripts/)", padx=10, pady=10)
        version_frame.pack(fill="x", padx=10, pady=5)

        self.version_list = ttk.Combobox(version_frame, state="readonly")
        self.version_list.pack(side="left", fill="x", expand=True)
        self.version_list.bind("<<ComboboxSelected>>", self.on_version_select)

        btn_refresh = tk.Button(version_frame, text="Refresh", command=self.refresh_version_list)
        btn_refresh.pack(side="left", padx=(5, 0))

        self.btn_apply = tk.Button(version_frame, text="APPLY SELECTED VERSION", bg="#add8e6", command=self.apply_version)
        self.btn_apply.pack(side="right", padx=(5, 0))

        # --- CONTROLS ---
        control_frame = tk.Frame(self, padx=10, pady=10)
        control_frame.pack(fill="x")

        # 3 Buttons Layout
        self.btn_generate = tk.Button(control_frame, text="GENERATE NEW VERSION", bg="#dddddd", height=2, command=self.start_generation)
        self.btn_generate.pack(side="left", fill="x", expand=True, padx=(0, 2))

        self.btn_update = tk.Button(control_frame, text="UPDATE SELECTED VERSION", bg="#ffcccc", height=2, command=self.start_update)
        self.btn_update.pack(side="left", fill="x", expand=True, padx=2)

        self.btn_csv = tk.Button(control_frame, text="GENERATE CSV", bg="#ccffcc", height=2, command=self.start_csv)
        self.btn_csv.pack(side="left", fill="x", expand=True, padx=(2, 0))

        # --- LOGS ---
        log_frame = tk.LabelFrame(self, text="Execution Log", padx=10, pady=10)
        log_frame.pack(fill="both", expand=True, padx=10, pady=5)

        self.log_text = scrolledtext.ScrolledText(log_frame, state="disabled", font=("Consolas", 9))
        self.log_text.pack(fill="both", expand=True)

        # Initial refresh
        self.refresh_version_list()

    def browse_input(self):
        filename = filedialog.askopenfilename(
            title="Select Veterancy Data File",
            filetypes=[("Lua/Text Files", "*.lua *.txt"), ("All Files", "*.*")]
        )
        if filename:
            self.entry_input.delete(0, tk.END)
            self.entry_input.insert(0, filename)
            self.config_data["last_input_file"] = filename
            self.save_config()
            self.refresh_version_list()

    def log(self, message):
        self.log_text.config(state="normal")
        self.log_text.insert(tk.END, message + "\n")
        self.log_text.see(tk.END)
        self.log_text.config(state="disabled")

    def refresh_version_list(self):
        input_file = self.entry_input.get()
        if not input_file:
            self.version_list['values'] = []
            self.version_list.set('')
            return

        clean_id = backend.get_clean_id(input_file)
        version_dir = os.path.join(backend.INTERNAL_SCRIPTS_DIR, clean_id)

        # Check existing versions in local ./scripts/ID/
        versions = []
        if os.path.exists(version_dir):
            files = glob.glob(os.path.join(version_dir, "v*.lua"))

            def extract_version(fname):
                try:
                    match = backend.re.search(r'v(\d+)\.lua$', fname)
                    return int(match.group(1)) if match else 0
                except:
                    return 0

            files.sort(key=extract_version, reverse=True)
            versions = [os.path.basename(f) for f in files]

        # CHECK APPLIED FOLDER
        game_file_path = os.path.join(backend.GAME_OUTPUT_DIR, f"{clean_id}.lua")
        if os.path.exists(game_file_path):
            versions.insert(0, "Current (in Game)")

        self.version_list['values'] = versions
        if versions:
            self.version_list.current(0)
        else:
            self.version_list.set('')

        self.on_version_select(None)

    def on_version_select(self, event):
        selection = self.version_list.get()
        if not selection or selection == "Current (in Game)":
            self.btn_update.config(state="disabled", text="UPDATE SELECTED VERSION")
        else:
            self.btn_update.config(state="normal", text=f"UPDATE {selection}")

    def apply_version(self):
        selection = self.version_list.get()
        if not selection:
            messagebox.showwarning("Warning", "No version selected.")
            return

        input_file = self.entry_input.get()
        clean_id = backend.get_clean_id(input_file)

        # Determine source path
        if selection == "Current (in Game)":
            target_path = os.path.join(backend.GAME_OUTPUT_DIR, f"{clean_id}.lua")
            if os.path.exists(target_path):
                messagebox.showinfo("Info", "This version is already active in the game folder.")
                return
            else:
                messagebox.showerror("Error", "The file disappeared from the game folder!")
                self.refresh_version_list()
                return
        else:
            source_path = os.path.join(backend.INTERNAL_SCRIPTS_DIR, clean_id, selection)

        # Hardcoded game output path
        target_path = os.path.join(backend.GAME_OUTPUT_DIR, f"{clean_id}.lua")

        # Ensure output directory exists
        if not os.path.exists(backend.GAME_OUTPUT_DIR):
            try:
                os.makedirs(backend.GAME_OUTPUT_DIR)
            except OSError as e:
                messagebox.showerror("Error", f"Could not create output directory:\n{backend.GAME_OUTPUT_DIR}\n\n{e}")
                return

        # Check if output file exists
        if os.path.exists(target_path):
            if not messagebox.askyesno("Confirm Overwrite", f"A script for this replay is already active in the game folder.\n\nOverwrite with {selection}?"):
                return

        try:
            shutil.copy2(source_path, target_path)
            self.log(f"APPLIED: {selection} -> {target_path}")
            messagebox.showinfo("Success", f"Applied version {selection} to game folder.")
            self.refresh_version_list()
        except Exception as e:
            messagebox.showerror("Error", f"Failed to copy file: {e}")

    def prepare_ui_for_process(self):
        self.btn_generate.config(state="disabled")
        self.btn_update.config(state="disabled")
        self.btn_csv.config(state="disabled")
        self.log_text.config(state="normal")
        self.log_text.delete(1.0, tk.END)
        self.log_text.config(state="disabled")
        self.save_config()

    def restore_ui(self):
        self.btn_generate.config(state="normal")
        self.btn_csv.config(state="normal")
        self.on_version_select(None)

    def start_generation(self):
        input_file = self.entry_input.get()
        if not input_file or not os.path.exists(input_file):
            messagebox.showerror("Error", "Please select a valid input file.")
            return

        self.prepare_ui_for_process()
        thread = threading.Thread(target=self.run_logic, args=(input_file, None))
        thread.start()

    def start_update(self):
        input_file = self.entry_input.get()
        selection = self.version_list.get()

        if not input_file or not os.path.exists(input_file):
            messagebox.showerror("Error", "Please select a valid input file.")
            return

        if not selection or selection == "Current (in Game)":
            messagebox.showerror("Error", "Cannot update this selection.")
            return

        self.prepare_ui_for_process()
        thread = threading.Thread(target=self.run_logic, args=(input_file, selection))
        thread.start()

    def start_csv(self):
        input_file = self.entry_input.get()
        if not input_file or not os.path.exists(input_file):
            messagebox.showerror("Error", "Please select a valid input file.")
            return

        self.prepare_ui_for_process()
        thread = threading.Thread(target=self.run_csv_logic, args=(input_file,))
        thread.start()

    def run_csv_logic(self, input_file):
        def ui_log(msg):
            self.after(0, self.log, msg)

        try:
            ui_log(f"--- Loading for CSV: {input_file} ---")

            with open(input_file, "r") as f:
                content = f.read().replace("return", "")
                file_content = lua.decode(content)

            ui_log("Preprocessing data...")
            raw_units = file_content.get('units', {})
            metadata = file_content.get('metadata', None)
            data = backend.preprocess_data(raw_units)

            if not data:
                ui_log("Error: No valid unit data found.")
                return

            # CSV Path
            clean_id = backend.get_clean_id(input_file)
            version_dir = os.path.join(backend.INTERNAL_SCRIPTS_DIR, clean_id)
            csv_filename = f"{clean_id}.csv"
            csv_path = os.path.join(version_dir, csv_filename)

            backend.write_csv_file(data, metadata, csv_path, ui_log)

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

            with open(input_file, "r") as f:
                content = f.read().replace("return", "")
                file_content = lua.decode(content)

            ui_log("Preprocessing data...")
            raw_units = file_content.get('units', {})
            data = backend.preprocess_data(raw_units)

            if not data:
                ui_log("Error: No valid unit data found.")
                return

            timeline = backend.generate_timeline(data, ui_log)

            # --- FULL VERBOSE OUTPUT ---
            ui_log("\n" + "="*80)
            ui_log(f"CINEMATIC CAMERA PATH ({len(timeline)} Cuts)")
            ui_log("="*80)

            for i, cut in enumerate(timeline):
                start_f = cut['start']
                end_f = cut['end']
                start_str = backend.format_time(start_f)
                end_str = backend.format_time(end_f)
                dur_str = backend.format_time(end_f - start_f)

                spd = ""
                if cut['type'] == 'gap':
                    spd = f"[x{backend.FAST_FORWARD_SPEED}]"

                if cut['target'] == -1:
                    ui_log(f"CUT #{i+1:02d}{spd} | {start_str} -> {end_str} | Dur: {dur_str} | {start_f} -> {end_f}")
                    ui_log(f"         Target: Fast Forward (ff) ID: -1 | Note: {cut.get('note', '')}")
                else:
                    u = cut.get('unit_data', {})
                    h_name = u.get('humanName', 'Unknown')
                    i_name = u.get('name', 'N/A')
                    uid = u.get('id', cut['target'])

                    ui_log(f"CUT #{i+1:02d}{spd} | {start_str} -> {end_str} | Dur: {dur_str} | {start_f} -> {end_f}")
                    ui_log(f"         Target: {h_name} ({i_name}) ID: {uid} | Note: {cut.get('note', '')}")

                ui_log("-" * 80)

            # --- PREPARE DIRECTORIES ---
            clean_id = backend.get_clean_id(input_file)
            version_dir = os.path.join(backend.INTERNAL_SCRIPTS_DIR, clean_id)
            os.makedirs(version_dir, exist_ok=True)

            # --- SAVE LUA SCRIPT ---
            if target_filename:
                # Update specific file
                version_path = os.path.join(version_dir, target_filename)
                ui_log(f"Updating existing version: {target_filename}")
            else:
                # Determine next version
                existing_files = glob.glob(os.path.join(version_dir, "v*.lua"))
                next_ver = 1
                if existing_files:
                    try:
                        versions = []
                        for f in existing_files:
                            match = backend.re.search(r'v(\d+)\.lua$', f)
                            if match:
                                versions.append(int(match.group(1)))

                        if versions:
                            next_ver = max(versions) + 1
                    except:
                        pass

                target_filename = f"v{next_ver}.lua"
                version_path = os.path.join(version_dir, target_filename)

            backend.write_lua_file(timeline, version_path, ui_log)

            # Update GUI
            self.after(0, self.refresh_version_list)
            self.after(0, lambda: messagebox.showinfo("Generated", f"Script saved as {target_filename}"))

        except Exception as e:
            ui_log(f"CRITICAL ERROR: {str(e)}")
            import traceback
            traceback.print_exc()
        finally:
            self.after(0, self.restore_ui)

if __name__ == "__main__":
    app = App()
    app.mainloop()
