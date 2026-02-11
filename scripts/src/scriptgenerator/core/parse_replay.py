import gzip
import os
import platform
import re
import shutil
import struct
import subprocess
import tkinter as tk
import urllib.request
import zipfile
import time
import queue
import threading
from tkinter import filedialog

# --- User Configuration ---
CONFIG = {
    # Directory where engines and games will be downloaded/stored
    "DATA_DIR": r"S:\Gry\BeyondAllReason\Beyond-All-Reason\data",

    # Path to 7z executable.
    "7Z_PATH": r"C:\Program Files\7-Zip\7z.exe",

    "ENGINE_BASE_URL": "https://github.com/beyond-all-reason/spring/releases/download",
}

# --------------------------

def select_demo_file():
    root = tk.Tk()
    root.withdraw()
    file_path = filedialog.askopenfilename(
        title="Select BAR Demo File",
        filetypes=[("BAR Replays", "*.sdfz *.bar *.sdf"), ("All Files", "*.*")]
    )
    return file_path

def get_replay_duration(demo_path):
    """
    Scans the replay packets to find the final game time (quit packet or end of stream).
    Returns total_frames (approx).
    """
    print("Scanning replay for duration...")
    try:
        with gzip.open(demo_path, 'rb') as f:
            # 1. Read Header Info
            # Offset 304: ScriptSize (int)
            # Offset 308: DemoStreamSize (int)
            # Offset 352: Start of Script
            f.seek(304)
            header_info = f.read(8)
            script_size, demo_stream_size = struct.unpack('<II', header_info)

            # Packet stream starts after the script
            # 352 is the fixed offset where script starts
            packet_start = 352 + script_size
            packet_end = packet_start + demo_stream_size

            f.seek(packet_start)

            last_time = 0.0

            # 2. Fast Packet Scan
            # We don't decode the data, we just read headers and jump
            while f.tell() < packet_end:
                # Read 9 bytes: Time(4) + Length(4) + Type(1)
                chunk = f.read(9)
                if len(chunk) < 9: break

                pkt_time, pkt_len, pkt_type = struct.unpack('<fIB', chunk)

                last_time = pkt_time

                # PacketType 3 is QUIT
                if pkt_type == 3:
                    break

                # Skip the payload
                # Length includes the Type byte which we already read, so skip Length - 1
                skip = pkt_len - 1
                if skip > 0:
                    f.seek(skip, 1) # Relative seek

            # Spring usually runs at 30 logic frames per second
            total_frames = int(last_time * 30)
            print(f"Duration found: {last_time:.2f}s (~{total_frames} frames)")
            return total_frames

    except Exception as e:
        print(f"Warning: Could not calculate duration: {e}")
        return 0

def parse_replay(demo_path):
    print(f"Parsing replay metadata: {demo_path}")
    metadata = {}

    try:
        with gzip.open(demo_path, 'rb') as f:
            head_data = f.read(1024 * 1024) # Read enough to get script

        magic = head_data[0:15].decode('ascii', errors='ignore')
        if magic == "spring demofile":
            raw_engine = head_data[24:280].decode('ascii', errors='ignore').strip('\x00')
            metadata['engine'] = raw_engine

            script_size = struct.unpack('<I', head_data[304:308])[0]
            script_start = 352

            if len(head_data) >= script_start + script_size:
                metadata['script_content'] = head_data[script_start: script_start + script_size].decode('ascii', errors='ignore')

    except Exception:
        pass

    if 'script_content' in metadata:
        txt = metadata['script_content']
        map_match = re.search(r'mapname=(.*?);', txt, re.IGNORECASE)
        game_match = re.search(r'gametype=(.*?);', txt, re.IGNORECASE)

        if 'engine' not in metadata:
            eng_match = re.search(r'engine=(.*?);', txt, re.IGNORECASE)
            if eng_match: metadata['engine'] = eng_match.group(1)

        if map_match: metadata['map'] = map_match.group(1).strip()
        if game_match: metadata['game'] = game_match.group(1).strip()

    if 'map' not in metadata or 'game' not in metadata:
        raise ValueError(f"Could not parse 'mapname' or 'gametype'.")
    if 'engine' not in metadata:
        raise ValueError("Could not determine Engine version.")

    full_eng = metadata['engine']
    if "spring_bar_.rel2501." in full_eng:
        parts = full_eng.split("spring_bar_.rel2501.")
        if len(parts) > 1:
            metadata['engine_version'] = parts[1].split('_')[0]
        else:
            metadata['engine_version'] = full_eng
    else:
        metadata['engine_version'] = full_eng

    return metadata

def ensure_engine(version):
    engine_base_dir = os.path.join(CONFIG["DATA_DIR"], "engine")
    install_dir = os.path.join(engine_base_dir, f"recoil_{version}")
    headless_path = os.path.join(install_dir, "spring-headless.exe")

    if os.path.exists(headless_path):
        return headless_path

    print(f"Downloading Engine {version}...")
    os.makedirs(install_dir, exist_ok=True)
    os_str = "windows" if platform.system() == "Windows" else "linux"
    filename = f"spring_bar_.rel2501.{version}_{os_str}-64-minimal-portable.7z"
    url = f"{CONFIG['ENGINE_BASE_URL']}/{version}/{filename}"

    archive_path = os.path.join(install_dir, "engine.7z")
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response, open(archive_path, 'wb') as out_file:
            shutil.copyfileobj(response, out_file)
    except Exception as e:
        if os.path.exists(install_dir): shutil.rmtree(install_dir)
        raise RuntimeError(f"Download failed: {e}")

    cmd = [CONFIG["7Z_PATH"], "x", "-y", f"-o{install_dir}", archive_path]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    os.remove(archive_path)
    return headless_path

def ensure_content(engine_dir, game_version, map_name):
    pr_downloader = os.path.join(engine_dir, "pr-downloader.exe")
    # Silence output unless error
    subprocess.run([pr_downloader, "--filesystem-writepath", CONFIG["DATA_DIR"], "--download-game", game_version],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([pr_downloader, "--filesystem-writepath", CONFIG["DATA_DIR"], "--download-map", map_name],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def run_headless_demo(demo_path, progress_callback=None):
    if not demo_path: return None

    # 1. Parse Metadata & Duration
    try:
        meta = parse_replay(demo_path)
        total_frames = get_replay_duration(demo_path)
        print(f"Loaded: {meta['engine_version']} | {meta['map']}")
    except Exception as e:
        print(f"Setup Error: {e}")
        return None

    # 2. Prepare Engine/Content
    try:
        engine_exe = ensure_engine(meta['engine_version'])
        # ensure_content(os.path.dirname(engine_exe), meta['game'], meta['map'])
    except Exception as e:
        print(f"Download Error: {e}")
        return None

    # 3. Generate Script
    safe_demo_path = demo_path.replace("\\", "/")
    script_content = f'[game] {{ demofile={safe_demo_path}; }}'
    script_file_path = os.path.join(CONFIG["DATA_DIR"], "_script.txt")
    with open(script_file_path, "w", encoding="utf-8") as f:
        f.write(script_content)

    # 4. Run Headless
    cmd = [engine_exe, "--write-dir", CONFIG["DATA_DIR"], "--isolation", script_file_path]

    # Pre-determine the expected result path based on the demo filename
    # Lua logger logic: LuaUI/unitData/ + basename(demo_path) + .lua
    demo_base = os.path.splitext(os.path.basename(demo_path))[0]
    expected_result_path = os.path.join(CONFIG["DATA_DIR"], "LuaUI", "unitData", f"{demo_base}.lua")

    print(f"--- STARTING HEADLESS SIMULATION (Target: {expected_result_path}) ---")

    creation_flags = 0
    if platform.system() == "Windows":
        creation_flags = subprocess.HIGH_PRIORITY_CLASS

    result_path = None

    def reader(pipe, q):
        try:
            for line in iter(pipe.readline, ''):
                q.put(line)
        finally:
            pipe.close()

    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            cwd=os.path.dirname(engine_exe),
            text=True,
            bufsize=1,
            creationflags=creation_flags
        )

        q = queue.Queue()
        t = threading.Thread(target=reader, args=(process.stdout, q))
        t.daemon = True
        t.start()

        last_log_time = time.time()
        last_activity_time = time.time()

        while True:
            try:
                line = q.get(timeout=5.0)
                last_activity_time = time.time()
            except queue.Empty:
                if process.poll() is not None:
                    break
                # Check for timeout
                if time.time() - last_activity_time > 300.0:
                    print(f"ERROR: Process timed out after 300s of inactivity. Killing...")
                    process.kill()
                    if progress_callback:
                        progress_callback(0, total_frames, "ERROR: Process timed out (300s inactivity)")
                    break
                continue

            if line:
                line = line.strip()
                now = time.time()

                # Check for absolute path from logger
                if "Absolute path:" in line:
                    parts = line.split("Absolute path:")
                    if len(parts) > 1:
                        result_path = parts[1].strip()
                        print(f"RESULT_FILE:{result_path}")

                # Check for frame updates
                frame_match = re.search(r'\[f=(\d+)\]', line)
                if frame_match:
                    current_frame = int(frame_match.group(1))
                    pct = (current_frame / total_frames * 100) if total_frames > 0 else 0

                    # Update line with percentage for logs
                    line_with_pct = f"[{pct:3.0f}%] {line}"

                    # Throttle frame logs: Only print every 1.0 second
                    if (now - last_log_time) > 1.0:
                        msg = f"Frame: {current_frame}/{total_frames} | {line_with_pct}"
                        print(msg)
                        if progress_callback:
                            progress_callback(current_frame, total_frames, line_with_pct)
                        last_log_time = now
                else:
                    # Non-frame log, print and send to callback immediately
                    print(line)
                    if progress_callback:
                        progress_callback(0, total_frames, line)

        rc = process.poll()
        print("-" * 30)
        print(f"Finished. Exit code: {rc}")

        # If we didn't get a result_path from logs (or want to override),
        # use the expected one if it exists.
        if os.path.exists(expected_result_path):
            result_path = expected_result_path
            print(f"Verified output file: {result_path}")
        elif not result_path:
            # Fallback check for any files starting with demo_base in that dir
            out_dir = os.path.join(CONFIG["DATA_DIR"], "LuaUI", "unitData")
            if os.path.exists(out_dir):
                candidates = [os.path.join(out_dir, f) for f in os.listdir(out_dir) if f.startswith(demo_base) and f.endswith(".lua")]
                if candidates:
                    # Sort by modification time to get the newest one
                    candidates.sort(key=os.path.getmtime, reverse=True)
                    result_path = candidates[0]
                    print(f"Found alternative output file: {result_path}")

        return result_path

    except Exception as e:
        print(f"Execution Error: {e}")
        return None

if __name__ == "__main__":
    if not os.path.exists(CONFIG["7Z_PATH"]):
        print("Config Error: 7-Zip path incorrect.")
    else:
        demo_file = select_demo_file()
        if demo_file:
            run_headless_demo(demo_file)
