def format_time(frames: int) -> str:
    """
    Converts frame count (at 30 FPS) to MM:SS format.
    """
    seconds = frames // 30
    mm = seconds // 60
    ss = seconds % 60
    return f"{mm:02d}:{ss:02d}"


def get_unit_pos_at_frame(unit_data, frame):
    """
    Returns (x, z) for a unit at a given frame by interpolating positionHistory.
    """
    pos_history = unit_data.get('positionHistory', [])
    if not pos_history:
        return None

    # Sort if not already sorted (usually it should be from DB)
    # Binary search for the frame
    frames = [p['frame'] for p in pos_history]
    import bisect
    idx = bisect.bisect_left(frames, frame)

    if idx == 0:
        return pos_history[0]['x'], pos_history[0]['z']
    if idx >= len(pos_history):
        return pos_history[-1]['x'], pos_history[-1]['z']

    # Interpolate
    p1 = pos_history[idx - 1]
    p2 = pos_history[idx]
    
    f1, f2 = p1['frame'], p2['frame']
    if f1 == f2:
        return p1['x'], p1['z']
    
    t = (frame - f1) / (f2 - f1)
    x = p1['x'] + (p2['x'] - p1['x']) * t
    z = p1['z'] + (p2['z'] - p1['z']) * t
    return x, z


def calculate_distance(pos1, pos2):
    """
    Calculates Euclidean distance between two (x, z) points.
    """
    if not pos1 or not pos2:
        return None
    import math
    return math.sqrt((pos1[0] - pos2[0])**2 + (pos1[1] - pos2[1])**2)
