import sqlite3
import json
import os
from typing import Dict, List, Optional, Tuple

class TimelineDatabase:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.conn = sqlite3.connect(db_path, check_same_thread=False)
        self.create_tables()

    def create_tables(self):
        cursor = self.conn.cursor()
        # Units table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS units (
                id TEXT PRIMARY KEY,
                unitId INTEGER,
                name TEXT,
                humanName TEXT,
                defID INTEGER,
                tier INTEGER,
                teamId INTEGER,
                bornFrame INTEGER,
                diedFrame INTEGER,
                finalXP REAL,
                damageTaken REAL,
                damageDealt REAL
            )
        ''')
        # Status History
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS status_history (
                unit_id TEXT,
                startFrame INTEGER,
                endFrame INTEGER,
                status TEXT,
                FOREIGN KEY(unit_id) REFERENCES units(id)
            )
        ''')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_status_unit ON status_history(unit_id, startFrame)')

        # Position History
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS position_history (
                unit_id TEXT,
                frame INTEGER,
                x REAL,
                z REAL,
                FOREIGN KEY(unit_id) REFERENCES units(id)
            )
        ''')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_pos_unit ON position_history(unit_id, frame)')

        # Target History
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS target_history (
                unit_id TEXT,
                frame INTEGER,
                targetId INTEGER,
                name TEXT,
                humanName TEXT,
                tier INTEGER,
                FOREIGN KEY(unit_id) REFERENCES units(id)
            )
        ''')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_target_unit ON target_history(unit_id, frame)')

        # Stationary Periods (precalculated)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS stationary_periods (
                unit_id TEXT,
                startFrame INTEGER,
                endFrame INTEGER,
                FOREIGN KEY(unit_id) REFERENCES units(id)
            )
        ''')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_stationary_unit ON stationary_periods(unit_id, startFrame)')

        # Metadata
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT
            )
        ''')

        # Projectile History
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS projectile_history (
                unit_id TEXT,
                frame INTEGER,
                id INTEGER,
                ownerID INTEGER,
                x REAL,
                y REAL,
                z REAL,
                ownerHumanName TEXT,
                FOREIGN KEY(unit_id) REFERENCES units(id)
            )
        ''')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_projectile_unit ON projectile_history(unit_id, frame)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_projectile_id_frame ON projectile_history(id, frame)')

        # Projectile Index (per projectile lifespan and meta)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS projectile_index (
                id INTEGER PRIMARY KEY,
                ownerID INTEGER,
                ownerHumanName TEXT,
                startFrame INTEGER,
                endFrame INTEGER
            )
        ''')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_proj_index_bounds ON projectile_index(startFrame, endFrame)')

        self.conn.commit()

    def clear_data(self):
        cursor = self.conn.cursor()
        cursor.execute('DELETE FROM status_history')
        cursor.execute('DELETE FROM position_history')
        cursor.execute('DELETE FROM target_history')
        cursor.execute('DELETE FROM stationary_periods')
        cursor.execute('DELETE FROM units')
        cursor.execute('DELETE FROM metadata')
        cursor.execute('DELETE FROM projectile_history')
        try:
            cursor.execute('DELETE FROM projectile_index')
        except sqlite3.Error:
            pass
        self.conn.commit()

    def save_data(self, units_dict: Dict, metadata: Dict, global_projectile_history: Optional[List] = None):
        self.clear_data()
        cursor = self.conn.cursor()

        # Get metadata endFrame for capping
        default_max = metadata.get('endFrame', 999999)

        # Save Metadata
        for k, v in metadata.items():
            cursor.execute('INSERT INTO metadata (key, value) VALUES (?, ?)', (k, json.dumps(v)))

        # Accumulator for projectile lifespans
        proj_bounds: Dict[int, Dict] = {}

        def track_proj_bounds(pid, frame_v, owner_id, owner_name):
            b = proj_bounds.get(pid)
            if not b:
                proj_bounds[pid] = {
                    'startFrame': int(frame_v),
                    'endFrame': int(frame_v),
                    'ownerID': owner_id,
                    'ownerHumanName': owner_name,
                }
            else:
                if frame_v < b['startFrame']:
                    b['startFrame'] = int(frame_v)
                if frame_v > b['endFrame']:
                    b['endFrame'] = int(frame_v)

        # Save Units and their histories
        for uid, u in units_dict.items():
            cursor.execute('''
                INSERT INTO units (id, unitId, name, humanName, defID, tier, teamId, bornFrame, diedFrame, finalXP, damageTaken, damageDealt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                uid, u.get('unitId'), u.get('name'), u.get('humanName'), u.get('defID'),
                u.get('tier'), u.get('teamId'), u.get('bornFrame'), u.get('diedFrame'), u.get('finalXP'),
                u.get('damageTaken'), u.get('damageDealt')
            ))

            # Status
            sh = u.get('statusHistory', [])
            if isinstance(sh, dict): sh = sh.values()
            for s in sh:
                s_end = s.get('endFrame')
                if s_end is None or s_end >= 999999:
                    s_end = u.get('diedFrame') or default_max

                cursor.execute('INSERT INTO status_history (unit_id, startFrame, endFrame, status) VALUES (?, ?, ?, ?)',
                               (uid, s['startFrame'], s_end, s['status']))

            # Position
            ph = u.get('positionHistory', [])
            if isinstance(ph, dict): ph = ph.values()
            for p in ph:
                cursor.execute('INSERT INTO position_history (unit_id, frame, x, z) VALUES (?, ?, ?, ?)',
                               (uid, p['frame'], p['x'], p['z']))

            # Target
            th = u.get('targetHistory', [])
            if isinstance(th, dict): th = th.values()
            for t in th:
                cursor.execute('INSERT INTO target_history (unit_id, frame, targetId, name, humanName, tier) VALUES (?, ?, ?, ?, ?, ?)',
                               (uid, t['frame'], t.get('targetId'), t.get('name'), t.get('humanName'), t.get('tier')))

            # Stationary periods (precalculated if available)
            sp_list = u.get('_stationary_periods', [])
            if isinstance(sp_list, dict): sp_list = sp_list.values()
            for sp in sp_list:
                s_start = sp.get('start') or sp.get('startFrame')
                s_end = sp.get('end') or sp.get('endFrame')
                if s_start is None or s_end is None:
                    continue
                cursor.execute('INSERT INTO stationary_periods (unit_id, startFrame, endFrame) VALUES (?, ?, ?)',
                               (uid, int(s_start), int(s_end)))

            # Projectile (Unit-specific)
            proj_h = u.get('projectileHistory', [])
            if isinstance(proj_h, dict): proj_h = proj_h.values()
            for p in proj_h:
                frame_v = p.get('frame')
                pid = p.get('id')
                owner_id = p.get('ownerID')
                owner_name = p.get('ownerHumanName')
                if frame_v is None or pid is None:
                    continue
                cursor.execute('''
                    INSERT INTO projectile_history (unit_id, frame, id, ownerID, x, y, z, ownerHumanName)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ''', (uid, int(frame_v), int(pid), owner_id, p.get('x'), p.get('y'), p.get('z'), owner_name))

                track_proj_bounds(pid, frame_v, owner_id, owner_name)

        # Save Global Projectile History
        if global_projectile_history:
            for p in global_projectile_history:
                frame_v = p.get('frame')
                pid = p.get('id')
                owner_id = p.get('ownerID')
                owner_name = p.get('ownerHumanName')
                if frame_v is None or pid is None:
                    continue
                # For global projectiles, unit_id can be None or a special marker
                cursor.execute('''
                    INSERT INTO projectile_history (unit_id, frame, id, ownerID, x, y, z, ownerHumanName)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ''', (None, int(frame_v), int(pid), owner_id, p.get('x'), p.get('y'), p.get('z'), owner_name))

                track_proj_bounds(pid, frame_v, owner_id, owner_name)

        # Populate projectile_index from accumulated bounds
        for pid, info in proj_bounds.items():
            cursor.execute('''
                INSERT OR REPLACE INTO projectile_index (id, ownerID, ownerHumanName, startFrame, endFrame)
                VALUES (?, ?, ?, ?, ?)
            ''', (int(pid), info.get('ownerID'), info.get('ownerHumanName'), int(info['startFrame']), int(info['endFrame'])))

        self.conn.commit()

    def get_metadata(self) -> Dict:
        cursor = self.conn.cursor()
        cursor.execute('SELECT key, value FROM metadata')
        return {row[0]: json.loads(row[1]) for row in cursor.fetchall()}

    def get_all_units_minimal(self) -> Dict:
        """Returns units without history, useful for initial loading and registry."""
        cursor = self.conn.cursor()

        # Get metadata endFrame for fallback
        cursor.execute('SELECT value FROM metadata WHERE key = "endFrame"')
        row = cursor.fetchone()
        default_max = 999999
        if row:
            try:
                default_max = json.loads(row[0])
            except: pass

        cursor.execute('SELECT * FROM units')
        cols = [column[0] for column in cursor.description]
        units = {}
        for row in cursor.fetchall():
            u = dict(zip(cols, row))
            if u.get('bornFrame') is None: u['bornFrame'] = 0
            if u.get('diedFrame') is None: u['diedFrame'] = default_max
            units[u['id']] = u
        return units

    def get_unit_full(self, unit_id: str) -> Optional[Dict]:
        cursor = self.conn.cursor()

        # Get metadata endFrame for fallback
        cursor.execute('SELECT value FROM metadata WHERE key = "endFrame"')
        row = cursor.fetchone()
        default_max = 999999
        if row:
            try:
                default_max = json.loads(row[0])
            except: pass

        cursor.execute('SELECT * FROM units WHERE id = ?', (unit_id,))
        row = cursor.fetchone()
        if not row: return None

        cols = [column[0] for column in cursor.description]
        unit = dict(zip(cols, row))

        # Ensure critical frames are not None
        if unit.get('bornFrame') is None: unit['bornFrame'] = 0
        if unit.get('diedFrame') is None: unit['diedFrame'] = default_max

        # Load histories
        cursor.execute('SELECT startFrame, endFrame, status FROM status_history WHERE unit_id = ? ORDER BY startFrame', (unit_id,))
        unit['statusHistory'] = [{'startFrame': r[0], 'endFrame': r[1], 'status': r[2]} for r in cursor.fetchall()]
        # Sanitize history endFrames too
        for s in unit['statusHistory']:
            if s['endFrame'] >= 999999: s['endFrame'] = unit['diedFrame']

        unit['_status_start_frames'] = [s['startFrame'] for s in unit['statusHistory']]

        cursor.execute('SELECT frame, x, z FROM position_history WHERE unit_id = ? ORDER BY frame', (unit_id,))
        unit['positionHistory'] = [{'frame': r[0], 'x': r[1], 'z': r[2]} for r in cursor.fetchall()]

        cursor.execute('SELECT frame, targetId, name, humanName, tier FROM target_history WHERE unit_id = ? ORDER BY frame', (unit_id,))
        unit['targetHistory'] = [{'frame': r[0], 'targetId': r[1], 'name': r[2], 'humanName': r[3], 'tier': r[4]} for r in cursor.fetchall()]
        unit['_target_start_frames'] = [t['frame'] for t in unit['targetHistory']]

        # Load stationary periods if present
        cursor.execute('SELECT startFrame, endFrame FROM stationary_periods WHERE unit_id = ? ORDER BY startFrame', (unit_id,))
        rows = cursor.fetchall()
        if rows:
            unit['_stationary_periods'] = [{'start': r[0], 'end': r[1]} for r in rows]

        return unit

    def get_all_projectiles_at_frame(self, frame: int) -> List[Dict]:
        """
        Returns a single sample per active projectile at given frame.
        Active = frame is within [startFrame, endFrame] from projectile_index.
        Position sample picked is the latest known at or before the given frame.
        """
        cursor = self.conn.cursor()

        # Debug logging
        print(f"[DB] Fetching projectiles at frame {frame}")

        # Prefer using projectile_index if present
        try:
            cursor.execute('''
                SELECT ph.id, ph.x, ph.y, ph.z, pi.ownerID, pi.ownerHumanName, ph.frame
                FROM projectile_index pi
                JOIN projectile_history ph ON ph.id = pi.id
                WHERE pi.startFrame <= ? AND pi.endFrame >= ?
                  AND ph.frame = (
                      SELECT MAX(frame) FROM projectile_history WHERE id = pi.id AND frame <= ?
                  )
            ''', (frame, frame, frame))
            rows = cursor.fetchall()
            if not rows:
                # Extra debug: check if any projectiles exist at all in the DB
                cursor.execute('SELECT COUNT(*) FROM projectile_index')
                idx_count = cursor.fetchone()[0]
                cursor.execute('SELECT COUNT(*) FROM projectile_history')
                hist_count = cursor.fetchone()[0]
                print(f"[DB] No active projectiles found. Index count: {idx_count}, History count: {hist_count}")
            else:
                print(f"[DB] Found {len(rows)} active projectiles")

            return [
                {'id': r[0], 'x': r[1], 'y': r[2], 'z': r[3], 'ownerID': r[4], 'ownerHumanName': r[5], 'sample_frame': r[6]}
                for r in rows
            ]
        except sqlite3.Error as e:
            print(f"[DB] Error in get_all_projectiles_at_frame: {e}")
            # Fallback: derive lifespans on-the-fly without projectile_index
            cursor.execute('''
                SELECT ph1.id, ph1.x, ph1.y, ph1.z, ph1.ownerID, ph1.ownerHumanName, ph1.frame
                FROM projectile_history ph1
                WHERE ph1.frame = (
                    SELECT MAX(frame) FROM projectile_history ph2 WHERE ph2.id = ph1.id AND ph2.frame <= ?
                )
                  AND EXISTS (
                    SELECT 1 FROM projectile_history ph3 WHERE ph3.id = ph1.id AND ph3.frame >= ?
                  )
            ''', (frame, frame))
            rows = cursor.fetchall()
            return [
                {'id': r[0], 'x': r[1], 'y': r[2], 'z': r[3], 'ownerID': r[4], 'ownerHumanName': r[5], 'sample_frame': r[6]}
                for r in rows
            ]

    def get_projectile_trail(self, proj_id: int, current_frame: int, trail_length_frames: int = 150) -> List[Dict]:
        """
        Returns history samples for a projectile within a trailing window.
        """
        cursor = self.conn.cursor()
        start_f = max(0, current_frame - trail_length_frames)
        cursor.execute('''
            SELECT x, y, z, frame FROM projectile_history
            WHERE id = ? AND frame <= ? AND frame >= ?
            ORDER BY frame ASC
        ''', (proj_id, current_frame, start_f))
        rows = cursor.fetchall()
        return [{'x': r[0], 'y': r[1], 'z': r[2], 'frame': r[3]} for r in rows]

    def close(self):
        self.conn.close()
