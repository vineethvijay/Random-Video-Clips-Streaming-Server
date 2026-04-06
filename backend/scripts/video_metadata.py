#!/usr/bin/env python3
"""
Fetch video metadata from local yt-dlp .info.json files (Pinchflat) or fall back
to legacy TubeArchivist path conventions.

Usage:
  video_metadata.py <video_path>
  video_metadata.py --model-only <video_path>

Prints JSON: {"model_info": "...", "thumbnail_url": "...", "title": "...", "channel": "..."} on stdout.

Supports two video path formats:
  - Pinchflat:    CHANNEL/DATE Title/Title [video_id].mp4  (with .info.json sidecar)
  - TubeArchivist: UCxxx/video_id.mp4                      (11-char stem, no sidecar)
"""
import glob
import json
import os
import re
import sys
from pathlib import Path

# YouTube video ID: 11 chars (alnum, -, _)
VIDEO_ID_RE = re.compile(r"^[a-zA-Z0-9_-]{11}$")
# Pinchflat filename: "Title [video_id].mp4"
BRACKET_ID_RE = re.compile(r"\[([a-zA-Z0-9_-]{11})\]")
MODEL_PATTERN = re.compile(r"Model\s*[-–:]\s*(.+?)(?:\n|$)", re.IGNORECASE | re.DOTALL)


def extract_video_id(filepath: str) -> str | None:
    """Extract YouTube video ID from path. Supports Pinchflat and TubeArchivist formats."""
    stem = Path(filepath).stem
    # Pinchflat: "Title [video_id]"
    m = BRACKET_ID_RE.search(stem)
    if m:
        return m.group(1)
    # TubeArchivist legacy: stem IS the video_id (11 chars)
    if stem and len(stem) == 11 and VIDEO_ID_RE.match(stem):
        return stem
    return None


def find_info_json(video_path: str) -> str | None:
    """Find the .info.json sidecar for a video file."""
    p = Path(video_path)
    # Pinchflat: same stem with .info.json
    info = p.with_suffix(".info.json")
    if info.is_file():
        return str(info)
    # Try without double extension (e.g. video.mp4 -> video.info.json)
    info2 = p.parent / (p.stem + ".info.json")
    if info2.is_file():
        return str(info2)
    # Search directory for any .info.json containing the video_id
    vid = extract_video_id(video_path)
    if vid:
        pattern = str(p.parent / f"*{vid}*.info.json")
        matches = glob.glob(pattern)
        if matches:
            return matches[0]
    return None


def find_thumbnail(video_path: str, video_id: str | None) -> str | None:
    """Find a local thumbnail file (.webp, .jpg, .png) next to the video."""
    p = Path(video_path)
    for ext in (".webp", ".jpg", ".png"):
        thumb = p.with_suffix(ext)
        if thumb.is_file():
            return str(thumb)
        thumb2 = p.parent / (p.stem + ext)
        if thumb2.is_file():
            return str(thumb2)
    return None


def read_info_json(info_path: str) -> dict:
    """Read and parse a yt-dlp .info.json file. Returns metadata dict."""
    out = {"model_info": None, "thumbnail_url": None, "title": None, "channel": None}
    try:
        with open(info_path, "r") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        return out

    # Title
    out["title"] = data.get("title") or data.get("fulltitle")

    # Channel
    out["channel"] = data.get("channel") or data.get("uploader") or data.get("uploader_id")

    # Model from description
    desc = data.get("description") or ""
    m = MODEL_PATTERN.search(desc)
    if m:
        out["model_info"] = m.group(1).strip()

    # Thumbnail
    video_id = data.get("id")
    thumb = data.get("thumbnail")
    if isinstance(thumb, str) and thumb.startswith("http"):
        out["thumbnail_url"] = thumb
    elif video_id:
        out["thumbnail_url"] = f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"

    return out


def get_video_metadata(video_path: str) -> dict:
    """Get metadata for a video file. Tries .info.json first, falls back to path-based extraction."""
    out = {"model_info": None, "thumbnail_url": None, "title": None, "channel": None}
    video_id = extract_video_id(video_path)

    # Try local .info.json (Pinchflat)
    info_path = find_info_json(video_path)
    if info_path:
        out = read_info_json(info_path)

    # Fill in thumbnail from local file or YouTube
    if not out.get("thumbnail_url"):
        local_thumb = find_thumbnail(video_path, video_id)
        if local_thumb:
            out["thumbnail_url"] = local_thumb
        elif video_id:
            out["thumbnail_url"] = f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"

    # Fallback model from env
    if not out.get("model_info"):
        fallback = os.environ.get("WATERMARK_FALLBACK", "").strip()
        if fallback:
            out["model_info"] = fallback

    return out


def shorten_model(s: str) -> str:
    """Shorten for display: https://www.instagram.com/xxx -> instagram.com/xxx, max 42 chars."""
    s = (s or "").strip().replace("\n", "").replace("\r", "")
    if s.startswith("https://"):
        s = s[8:]
    if s.startswith("http://"):
        s = s[7:]
    if s.startswith("www."):
        s = s[4:]
    return s[:42] if len(s) > 42 else s


def main() -> None:
    model_only = "--model-only" in sys.argv
    args = [a for a in sys.argv[1:] if a != "--model-only"]

    if len(args) != 1:
        if not model_only:
            print(json.dumps({"model_info": None, "thumbnail_url": None, "title": None, "channel": None}))
        sys.exit(0)

    video_path = args[0]
    result = get_video_metadata(video_path)

    if model_only:
        model = result.get("model_info")
        model = model.strip() if isinstance(model, str) else ""
        print(shorten_model(model))
    else:
        print(json.dumps(result))


if __name__ == "__main__":
    main()
