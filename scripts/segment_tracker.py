#!/usr/bin/env python3
"""
Segment tracker: pick an unused (or least-used) time range in a video, and record used ranges.
Reads/writes a single JSON file (e.g. .used_segments.json in the chunk folder).
Usage:
  segment_tracker.py pick <json_path> <video_path> <duration_sec> <clip_len_sec>   -> prints start_sec
  segment_tracker.py record <json_path> <video_path> <start_sec> <end_sec>
"""

import json
import random
import sys
from pathlib import Path
from typing import List

FILENAME = "segment_tracker.py"
MAX_INTERVALS_PER_VIDEO = 150  # trim oldest if over this, to bound file size


def load_used(json_path: str) -> dict:
    if not Path(json_path).is_file():
        return {"videos": {}}
    try:
        with open(json_path, "r") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {"videos": {}}
    except (json.JSONDecodeError, OSError):
        return {"videos": {}}


def save_used(json_path: str, data: dict) -> None:
    Path(json_path).parent.mkdir(parents=True, exist_ok=True)
    with open(json_path, "w") as f:
        json.dump(data, f, indent=0)


def merge_intervals(intervals: List[List[float]]) -> List[List[float]]:
    """Merge overlapping or adjacent [start, end] intervals."""
    if not intervals:
        return []
    sorted_i = sorted(intervals, key=lambda x: x[0])
    out = [list(sorted_i[0])]
    for s, e in sorted_i[1:]:
        if s <= out[-1][1]:
            out[-1][1] = max(out[-1][1], e)
        else:
            out.append([s, e])
    return out


def free_intervals(duration: float, used: List[List[float]]) -> List[List[float]]:
    """[0, duration] minus merged used ranges."""
    merged = merge_intervals(used)
    free = []
    prev_end = 0.0
    for s, e in merged:
        if s > prev_end:
            free.append([prev_end, min(s, duration)])
        prev_end = max(prev_end, e)
    if prev_end < duration:
        free.append([prev_end, duration])
    return free


def pick_start(json_path: str, video_path: str, duration_sec: float, clip_len_sec: int) -> int:
    data = load_used(json_path)
    used = data.get("videos", {}).get(video_path, [])
    duration_sec = max(0, duration_sec)
    clip_len_sec = max(1, clip_len_sec)
    max_start = int(duration_sec - clip_len_sec)
    if max_start <= 0:
        return 0

    free = free_intervals(duration_sec, used)
    long_enough = [(a, b) for a, b in free if (b - a) >= clip_len_sec]
    if long_enough:
        a, b = random.choice(long_enough)
        # random start in [a, b - clip_len_sec]
        start = a + random.random() * max(0, (b - a) - clip_len_sec)
        return int(start)
    # fallback: random start
    return random.randint(0, max_start)


def record_used(json_path: str, video_path: str, start_sec: float, end_sec: float) -> None:
    data = load_used(json_path)
    videos = data.setdefault("videos", {})
    intervals = videos.setdefault(video_path, [])
    intervals.append([start_sec, end_sec])
    merged = merge_intervals(intervals)
    if len(merged) > MAX_INTERVALS_PER_VIDEO:
        merged = merged[-MAX_INTERVALS_PER_VIDEO:]
    videos[video_path] = merged
    save_used(json_path, data)


def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: {FILENAME} pick <json_path> <video_path> <duration_sec> <clip_len_sec>", file=sys.stderr)
        print(f"       {FILENAME} record <json_path> <video_path> <start_sec> <end_sec>", file=sys.stderr)
        sys.exit(2)
    cmd = sys.argv[1].lower()
    if cmd == "pick":
        if len(sys.argv) != 6:
            print(f"Usage: {FILENAME} pick <json_path> <video_path> <duration_sec> <clip_len_sec>", file=sys.stderr)
            sys.exit(2)
        _, json_path, video_path, dur_s, clip_s = sys.argv
        start = pick_start(json_path, video_path, float(dur_s), int(float(clip_s)))
        print(start)
    elif cmd == "record":
        if len(sys.argv) != 6:
            print(f"Usage: {FILENAME} record <json_path> <video_path> <start_sec> <end_sec>", file=sys.stderr)
            sys.exit(2)
        _, _, json_path, video_path, start_s, end_s = sys.argv
        record_used(json_path, video_path, float(start_s), float(end_s))
    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
