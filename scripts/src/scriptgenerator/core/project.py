import os
import shutil
import glob
import json
import re

from scriptgenerator.config import manager, constants
from scriptgenerator.core import processing, database


class ProjectManager:
    def __init__(self, projects_dir=None):
        self.projects_dir = projects_dir if projects_dir else constants.PROJECTS_DIR
        self.current_project_dir = None
        self.config_data = {}
        self.db = None

    def ensure_projects_dir(self):
        if not os.path.exists(self.projects_dir):
            os.makedirs(self.projects_dir, exist_ok=True)

    def list_projects(self):
        self.ensure_projects_dir()
        projects = []
        for item in os.listdir(self.projects_dir):
            p_path = os.path.join(self.projects_dir, item)
            if os.path.isdir(p_path):
                meta_path = os.path.join(p_path, "project.json")
                display_name = item
                if os.path.exists(meta_path):
                    try:
                        with open(meta_path, "r") as f:
                            meta = json.load(f)
                            display_name = meta.get("name", item)
                    except: pass
                projects.append((display_name, item))
        projects.sort(key=lambda x: x[0])
        return projects

    def select_project(self, project_id):
        self.current_project_dir = os.path.join(self.projects_dir, project_id)
        self.load_project_settings()
        
        # Open SQLite database for the project
        db_path = os.path.join(self.current_project_dir, "data.db")
        if self.db:
            self.db.close()
        self.db = database.TimelineDatabase(db_path)
        
        return self.current_project_dir

    def get_current_project_meta(self):
        if not self.current_project_dir: return {}
        meta_path = os.path.join(self.current_project_dir, "project.json")
        if os.path.exists(meta_path):
            try:
                with open(meta_path, "r") as f:
                    return json.load(f)
            except: pass
        return {}

    def create_project(self, filename, project_name):
        clean_id = processing.get_clean_id(filename)
        base_id = clean_id
        counter = 1
        while os.path.exists(os.path.join(self.projects_dir, clean_id)):
            clean_id = f"{base_id}_{counter}"
            counter += 1

        new_dir = os.path.join(self.projects_dir, clean_id)
        os.makedirs(new_dir, exist_ok=True)

        original_filename = os.path.basename(filename)
        dest_source = os.path.join(new_dir, original_filename)
        shutil.copy2(filename, dest_source)

        meta = {"name": project_name, "source_file": original_filename}
        with open(os.path.join(new_dir, "project.json"), "w") as f:
            json.dump(meta, f)

        return clean_id

    def rename_current_project(self, new_name):
        if not self.current_project_dir: return
        meta_path = os.path.join(self.current_project_dir, "project.json")
        meta = {}
        if os.path.exists(meta_path):
            with open(meta_path, "r") as f: meta = json.load(f)
        meta["name"] = new_name
        with open(meta_path, "w") as f: json.dump(meta, f)

    def load_project_settings(self):
        if not self.current_project_dir: return
        settings_path = os.path.join(self.current_project_dir, "settings.json")
        new_data = manager.DEFAULT_CONFIG.copy()
        if os.path.exists(settings_path):
            try:
                with open(settings_path, "r") as f:
                    project_conf = json.load(f)
                    for k, v in project_conf.items():
                        new_data[k] = v
            except: pass
        self.config_data = new_data
        return new_data

    def save_project_settings(self, data):
        if not self.current_project_dir: return
        self.config_data = data
        settings_path = os.path.join(self.current_project_dir, "settings.json")
        try:
            with open(settings_path, "w") as f:
                json.dump(data, f, indent=4)
        except: pass

    def get_source_file_path(self):
        if not self.current_project_dir: return None
        meta = self.get_current_project_meta()
        source_filename = meta.get("source_file", "source.lua")
        return os.path.join(self.current_project_dir, source_filename)

    def get_versions(self):
        if not self.current_project_dir: return []
        files = glob.glob(os.path.join(self.current_project_dir, "v*.json"))
        def extract_version(fname):
            try:
                match = re.search(r'v(\d+)\.json$', fname)
                return int(match.group(1)) if match else 0
            except: return 0
        files.sort(key=extract_version, reverse=True)
        return [os.path.basename(f) for f in files]

    def get_next_version_filename(self):
        if not self.current_project_dir: return "v1.json"
        files = glob.glob(os.path.join(self.current_project_dir, "v*.json"))
        next_ver = 1
        if files:
            try:
                versions = [int(re.search(r'v(\d+)\.json$', f).group(1)) for f in files]
                if versions: next_ver = max(versions) + 1
            except: pass
        return f"v{next_ver}.json"

    def get_source_data(self, filepath, lua_loader, force_reload=False):
        if not self.db:
            # If called before select_project, we need a temp db path or wait
            # But usually select_project is called first.
            return {}, {}

        dir_name = os.path.dirname(filepath)
        file_name = os.path.basename(filepath)
        base_name = os.path.splitext(file_name)[0]
        
        # Check if database has data
        if not force_reload:
            metadata = self.db.get_metadata()
            if metadata:
                lua_mtime = os.path.getmtime(filepath)
                db_mtime = metadata.get('_source_mtime', 0)
                if db_mtime >= lua_mtime:
                    # Cache is valid in SQLite
                    return self.db.get_all_units_minimal(), metadata

        # If we reach here, we need to reload from Lua
        if lua_loader:
            with open(filepath, "r") as f:
                content = f.read()
                # Safely remove comments and leading 'return'
                content = re.sub(r'--.*', '', content)
                content = re.sub(r'^(\s*)return(\s*)', r'\1', content, count=1, flags=re.MULTILINE)
                data = lua_loader.decode(content)
            
            if not isinstance(data, dict):
                return {}, {}

            raw_units = data.get('units', {})
            metadata = data.get('metadata', {})
            global_projectile_history = data.get('projectileHistory', [])
            metadata['_source_mtime'] = os.path.getmtime(filepath)
            
            # Preprocess once before saving to DB to avoid runtime recalculation (status refinement + stationary)
            try:
                processed_units = processing.preprocess_data(raw_units, apply_filters=False, max_frame=metadata.get('endFrame'))
            except Exception:
                processed_units = raw_units
            
            # Save to SQLite (includes precalculated stationary periods)
            self.db.save_data(processed_units, metadata, global_projectile_history)
            
            return self.db.get_all_units_minimal(), metadata

        return {}, {}
