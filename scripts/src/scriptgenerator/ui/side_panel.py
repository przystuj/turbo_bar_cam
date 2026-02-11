import tkinter as tk
import time

class SidePanel(tk.Frame):
    def __init__(self, parent, on_next_callback, on_prev_callback, on_confirm_callback):
        super().__init__(parent, bg="#f0f0f0", borderwidth=1, relief="flat")
        # Removed pack_propagate(False) and fixed height to allow dynamic layout in side panel

        self.on_next_callback = on_next_callback
        self.on_prev_callback = on_prev_callback
        self.on_confirm_callback = on_confirm_callback
        self.selected_unit_id = None

        # --- Controls (Vertical for side panel) ---
        tk.Label(self, text="Alternatives:", bg="#f0f0f0", font=("Arial", 10, "bold")).pack(side="top", anchor="w", padx=10, pady=(5,0))

        nav_frame = tk.Frame(self, bg="#f0f0f0")
        nav_frame.pack(side="top", fill="x", padx=10, pady=5)

        self.btn_prev = tk.Button(nav_frame, text="<", command=self.on_prev_callback, width=3)
        self.btn_prev.pack(side="left")

        self.lbl_page = tk.Label(nav_frame, text="Page 1", bg="#f0f0f0", width=8)
        self.lbl_page.pack(side="left")

        self.btn_next = tk.Button(nav_frame, text=">", command=self.on_next_callback, width=3)
        self.btn_next.pack(side="left")

        self.btn_confirm = tk.Button(self, text="Confirm Selection", bg="#ccffcc", state="disabled", command=self.confirm_selection)
        self.btn_confirm.pack(side="top", fill="x", padx=10, pady=5)

        self.lbl_status = tk.Label(self, text="Select sub-block", bg="#f0f0f0", fg="gray", wraplength=280, justify="left")
        self.lbl_status.pack(side="top", anchor="w", padx=10, pady=5)

    def set_status(self, text, is_error=False):
        self.lbl_status.config(text=text, fg="red" if is_error else "gray")

    def set_page(self, page_num):
        self.lbl_page.config(text=f"Page {page_num}")

    def set_confirm_state(self, enabled):
        self.btn_confirm.config(state="normal" if enabled else "disabled")

    def confirm_selection(self):
        if self.on_confirm_callback:
            self.on_confirm_callback()

    # Legacy methods for compatibility during transition
    def populate(self, units_list, current_frame):
        pass

    def get_count(self):
        return 5
