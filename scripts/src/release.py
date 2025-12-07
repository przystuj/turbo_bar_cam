import os
import re
import sys
import zipfile
import subprocess

def parse_version(filename):
    """
    Extracts version numbers from filenames like 'turbobarcam_v1.8.zip'.
    Returns a tuple (major, minor, patch) for sorting.
    """
    pattern = r"turbobarcam_v(\d+)\.(\d+)(?:\.(\d+))?\.zip"
    match = re.search(pattern, filename)
    if match:
        major = int(match.group(1))
        minor = int(match.group(2))
        patch = int(match.group(3)) if match.group(3) else 0
        return (major, minor, patch)
    return None

def main():
    # 1. Setup Paths
    # current_dir = where this script and keybindDocGenerator.py live
    current_dir = os.path.dirname(os.path.abspath(__file__))
    # root_dir = two levels up (../../)
    root_dir = os.path.abspath(os.path.join(current_dir, "../.."))
    luaui_dir = os.path.join(root_dir, "LuaUI")
    generator_script = os.path.join(current_dir, "keybindDocGenerator.py")

    print(f"Scanning root directory: {root_dir}")

    # 2. Find highest version
    highest_version = (0, 0, 0)
    found_any = False

    for f in os.listdir(root_dir):
        if f.startswith("turbobarcam_v") and f.endswith(".zip"):
            version = parse_version(f)
            if version:
                found_any = True
                if version > highest_version:
                    highest_version = version

    if not found_any:
        print("No existing 'turbobarcam_vX.X.X.zip' files found in root.")
        return

    print(f"Current highest version found: {highest_version[0]}.{highest_version[1]}.{highest_version[2]}")

    # 3. Bump the fix (patch) version
    new_version_tuple = (highest_version[0], highest_version[1], highest_version[2] + 1)
    new_version_str = f"{new_version_tuple[0]}.{new_version_tuple[1]}.{new_version_tuple[2]}"
    new_zip_name = f"turbobarcam_v{new_version_str}.zip"
    new_zip_path = os.path.join(root_dir, new_zip_name)

    print(f"Next version will be: {new_version_str}")

    # 4. Call the keybind generator script
    print(f"Running {generator_script}...")
    try:
        subprocess.run([sys.executable, generator_script], check=True, cwd=current_dir)
    except subprocess.CalledProcessError as e:
        print(f"Error running keybindDocGenerator: {e}")
        return

    # 5. Zip the ../../LuaUI directory
    print(f"Zipping {luaui_dir} to {new_zip_path}...")
    try:
        with zipfile.ZipFile(new_zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            for root, dirs, files in os.walk(luaui_dir):
                for file in files:
                    file_path = os.path.join(root, file)
                    arcname = os.path.relpath(file_path, os.path.dirname(luaui_dir))
                    zipf.write(file_path, arcname)
    except Exception as e:
        print(f"Failed to zip directory: {e}")
        return

    # 6. Git Operations
    print("Performing Git operations...")
    try:
        # Explicitly add the new ZIP file first (Force add in case zip is in .gitignore)
        # Note: We use cwd=root_dir so git commands run from the root of the repo
        subprocess.run(["git", "add", "-f", new_zip_name], check=True, cwd=root_dir)

        # Add all other changes (including the doc generator output)
        subprocess.run(["git", "add", "."], check=True, cwd=root_dir)

        # Commit
        commit_message = f"Dist {new_version_str}"
        subprocess.run(["git", "commit", "-m", commit_message], check=True, cwd=root_dir)

        print(f"Success! Created {new_zip_name} and committed to git.")

    except subprocess.CalledProcessError as e:
        print(f"Git operation failed: {e}")

if __name__ == "__main__":
    main()
