#!/usr/bin/env python3
"""
Fetch TubeArchivist video metadata: model from description, thumbnail, title, channel.

Usage:
  tubearchivist_metadata.py <base_url> <token> <video_path_or_id>
  Prints JSON: {"model_info": "...", "thumbnail_url": "...", "title": "...", "channel": "..."} on stdout.
  If arg looks like a path (contains /), extracts video_id from path (channel_id/video_id.mp4).
"""
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

# TubeArchivist path: channel_id/video_id.mp4 — video_id is 11 chars (YouTube format: alnum, -, _)
VIDEO_ID_RE = re.compile(r"^[a-zA-Z0-9_-]{11}$")
MODEL_PATTERN = re.compile(r"Model\s*[-–:]\s*(.+?)(?:\n|$)", re.IGNORECASE | re.DOTALL)


def extract_video_id(filepath: str) -> str | None:
    """Extract TubeArchivist video ID from path (e.g. .../UCxxx/abc123.mp4 -> abc123)."""
    stem = Path(filepath).stem
    if stem and len(stem) == 11 and VIDEO_ID_RE.match(stem):
        return stem
    return None


def fetch_video_metadata(base_url: str, token: str, video_id: str) -> dict:
    """Fetch video metadata from TubeArchivist API. Returns dict with model_info, thumbnail_url, title, channel."""
    url = f"{base_url.rstrip('/')}/api/video/{video_id}/"
    req = urllib.request.Request(url, headers={"Authorization": f"Token {token}"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
    except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError, OSError):
        return {}
    out = {"model_info": None, "thumbnail_url": None, "title": None, "channel": None}
    desc = data.get("description") or data.get("description_html") or ""
    desc = re.sub(r"<[^>]+>", "", desc)
    m = MODEL_PATTERN.search(desc)
    if m:
        out["model_info"] = m.group(1).strip()
    out["title"] = data.get("title") or data.get("video_title")
    out["channel"] = data.get("channel_name") or data.get("channel")
    thumb = (
        data.get("vid_thumb_url")
        or data.get("thumbnail_url")
        or data.get("thumbnail")
        or data.get("thumbnails")
    )
    if isinstance(thumb, str) and thumb:
        out["thumbnail_url"] = thumb if thumb.startswith("http") else f"{base_url.rstrip('/')}{thumb}" if thumb.startswith("/") else thumb
    elif isinstance(thumb, list) and thumb:
        t = thumb[0]
        out["thumbnail_url"] = t.get("url") if isinstance(t, dict) else t
    if not out["thumbnail_url"]:
        out["thumbnail_url"] = f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"
    return out


def main() -> None:
    if len(sys.argv) != 4:
        print(json.dumps({"model_info": None, "thumbnail_url": None, "title": None, "channel": None}))
        sys.exit(1)
    _, base_url, token, path_or_id = sys.argv
    if not base_url or not token or not path_or_id:
        print(json.dumps({"model_info": None, "thumbnail_url": None, "title": None, "channel": None}))
        sys.exit(1)
    video_id = extract_video_id(path_or_id) if "/" in path_or_id else path_or_id
    if not video_id:
        print(json.dumps({"model_info": None, "thumbnail_url": None, "title": None, "channel": None}))
        sys.exit(0)
    result = fetch_video_metadata(base_url, token, video_id)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
