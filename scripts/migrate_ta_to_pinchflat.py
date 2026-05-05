#!/usr/bin/env python3
"""
Migrate TubeArchivist video files to Pinchflat folder structure.

TA structure:  <base>/UCxxxxxx/<videoId>.mp4
Pinchflat:     <base>/<ChannelName>/YYYY-MM-DD <Title>/<Title> [<videoId>].mp4
                                                       + .info.json, .description, -thumb.jpg

Usage:
    pip3 install yt-dlp
    python3 migrate_ta_to_pinchflat.py /root/HDD_INT/tube_archiver --dry-run
    python3 migrate_ta_to_pinchflat.py /root/HDD_INT/tube_archiver
"""

import argparse
import json
import logging
import os
import re
import shutil
import subprocess
import sys
import time

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("migrate_ta_to_pinchflat.log"),
    ],
)
log = logging.getLogger(__name__)

# Chars not allowed in filenames on most filesystems
UNSAFE_CHARS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
DELAY_BETWEEN_VIDEOS = 2  # seconds between yt-dlp calls to avoid rate limiting


def sanitize_filename(name: str) -> str:
    """Remove or replace characters unsafe for filenames, preserving Unicode."""
    name = UNSAFE_CHARS.sub("", name)
    name = name.strip(". ")
    return name


def is_ta_channel_folder(path: str) -> bool:
    """Check if a folder looks like a TA channel folder (UC... with bare .mp4 files)."""
    basename = os.path.basename(path)
    if not os.path.isdir(path):
        return False
    if not basename.startswith("UC"):
        return False
    # Check it has at least one .mp4 file directly inside
    for f in os.listdir(path):
        if f.endswith(".mp4") and os.path.isfile(os.path.join(path, f)):
            return True
    return False


def extract_video_id(filename: str) -> str:
    """Extract video ID from TA filename like '08eoJCBp2Ow.mp4' or '-2l4j0BOJrU.mp4'."""
    return os.path.splitext(filename)[0]


def fetch_metadata(video_id: str) -> dict | None:
    """Fetch video metadata from YouTube using yt-dlp --dump-json."""
    url = f"https://www.youtube.com/watch?v={video_id}"
    try:
        result = subprocess.run(
            ["yt-dlp", "--dump-json", "--no-download", url],
            capture_output=True,
            text=True,
            timeout=120,
        )
        if result.returncode != 0:
            log.warning("yt-dlp failed for %s: %s", video_id, result.stderr.strip())
            return None
        return json.loads(result.stdout)
    except subprocess.TimeoutExpired:
        log.warning("yt-dlp timed out for %s", video_id)
        return None
    except json.JSONDecodeError as e:
        log.warning("Failed to parse JSON for %s: %s", video_id, e)
        return None


def download_thumbnail(video_id: str, output_path: str) -> bool:
    """Download thumbnail for a video using yt-dlp."""
    url = f"https://www.youtube.com/watch?v={video_id}"
    try:
        result = subprocess.run(
            [
                "yt-dlp",
                "--skip-download",
                "--write-thumbnail",
                "--output", output_path,
                url,
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if result.returncode != 0:
            log.warning("Thumbnail download failed for %s: %s", video_id, result.stderr.strip())
            return False
        return True
    except subprocess.TimeoutExpired:
        log.warning("Thumbnail download timed out for %s", video_id)
        return False


def format_upload_date(upload_date: str) -> str:
    """Convert yt-dlp upload_date '20250726' to '2025-07-26'."""
    if len(upload_date) == 8:
        return f"{upload_date[:4]}-{upload_date[4:6]}-{upload_date[6:8]}"
    return upload_date


def migrate_video(
    mp4_path: str,
    video_id: str,
    channel_output_dir: str,
    dry_run: bool = False,
) -> bool:
    """Migrate a single TA video to Pinchflat structure."""
    log.info("Processing video: %s", video_id)

    # Fetch metadata
    metadata = fetch_metadata(video_id)
    if metadata is None:
        log.error("SKIP %s — could not fetch metadata (video may be deleted/private)", video_id)
        return False

    title = metadata.get("title", video_id)
    upload_date = metadata.get("upload_date", "00000000")
    description = metadata.get("description", "")
    channel_name = metadata.get("channel", metadata.get("uploader", "Unknown"))

    safe_title = sanitize_filename(title)
    date_str = format_upload_date(upload_date)

    # Folder: "YYYY-MM-DD Title"
    folder_name = f"{date_str} {safe_title}"
    folder_path = os.path.join(channel_output_dir, folder_name)

    # File base: "Title [videoId]"
    file_base = f"{safe_title} [{video_id}]"

    log.info("  -> %s/%s", os.path.basename(channel_output_dir), folder_name)

    if dry_run:
        log.info("  [DRY RUN] Would create: %s", folder_path)
        log.info("  [DRY RUN] Would move: %s -> %s.mp4", mp4_path, file_base)
        return True

    # Create subfolder
    os.makedirs(folder_path, exist_ok=True)

    # Move and rename .mp4
    dest_mp4 = os.path.join(folder_path, f"{file_base}.mp4")
    shutil.move(mp4_path, dest_mp4)
    log.info("  Moved MP4 -> %s", dest_mp4)

    # Write .info.json
    info_json_path = os.path.join(folder_path, f"{file_base}.info.json")
    with open(info_json_path, "w", encoding="utf-8") as f:
        json.dump(metadata, f, ensure_ascii=False, indent=2)
    log.info("  Wrote info.json")

    # Write .description
    desc_path = os.path.join(folder_path, f"{file_base}.description")
    with open(desc_path, "w", encoding="utf-8") as f:
        f.write(description)
    log.info("  Wrote .description")

    # Download thumbnail
    # yt-dlp writes thumbnail as <output>.jpg when using --convert-thumbnails jpg
    thumb_output = os.path.join(folder_path, f"{file_base}-thumb")
    if download_thumbnail(video_id, thumb_output):
        # yt-dlp may create <thumb_output>.webp or other extensions
        # Find the downloaded thumbnail
        expected_thumb = None
        for f in os.listdir(folder_path):
            if f.startswith(f"{file_base}-thumb") and f != f"{file_base}-thumb":
                expected_thumb = os.path.join(folder_path, f)
                break
        if expected_thumb and os.path.exists(expected_thumb):
            log.info("  Downloaded thumbnail")
        else:
            log.warning("  Thumbnail file not found after download")
    else:
        log.warning("  Could not download thumbnail")

    return True


def resolve_channel_name(channel_dir: str) -> str | None:
    """Get channel name by fetching metadata for the first video in a TA folder."""
    for f in sorted(os.listdir(channel_dir)):
        if f.endswith(".mp4") and os.path.isfile(os.path.join(channel_dir, f)):
            video_id = extract_video_id(f)
            metadata = fetch_metadata(video_id)
            if metadata:
                return metadata.get("channel", metadata.get("uploader"))
    return None


def migrate_channel(
    channel_dir: str,
    base_dir: str,
    dry_run: bool = False,
    resume_from: str | None = None,
) -> dict:
    """Migrate all videos in a TA channel folder to Pinchflat structure."""
    channel_id = os.path.basename(channel_dir)
    stats = {"total": 0, "success": 0, "failed": 0, "skipped": 0}

    # Collect all mp4 files
    mp4_files = sorted(
        f for f in os.listdir(channel_dir)
        if f.endswith(".mp4") and os.path.isfile(os.path.join(channel_dir, f))
    )
    stats["total"] = len(mp4_files)
    log.info("Channel %s: found %d videos", channel_id, len(mp4_files))

    if not mp4_files:
        return stats

    # Resolve channel name from first video
    log.info("Resolving channel name for %s...", channel_id)
    first_id = extract_video_id(mp4_files[0])
    first_meta = fetch_metadata(first_id)
    if first_meta is None:
        # Try a few more
        for f in mp4_files[1:4]:
            first_meta = fetch_metadata(extract_video_id(f))
            if first_meta:
                break
            time.sleep(DELAY_BETWEEN_VIDEOS)

    if first_meta is None:
        log.error("Could not resolve channel name for %s — all test videos failed", channel_id)
        return stats

    channel_name = sanitize_filename(
        first_meta.get("channel", first_meta.get("uploader", channel_id))
    )
    channel_output_dir = os.path.join(base_dir, channel_name)
    log.info("Channel name resolved: %s -> %s", channel_id, channel_name)

    if dry_run:
        log.info("[DRY RUN] Would create channel folder: %s", channel_output_dir)
    else:
        os.makedirs(channel_output_dir, exist_ok=True)

    # Process each video
    skip = resume_from is not None
    for mp4_file in mp4_files:
        video_id = extract_video_id(mp4_file)

        if skip:
            if video_id == resume_from:
                skip = False
            else:
                stats["skipped"] += 1
                continue

        mp4_path = os.path.join(channel_dir, mp4_file)
        success = migrate_video(mp4_path, video_id, channel_output_dir, dry_run=dry_run)

        if success:
            stats["success"] += 1
        else:
            stats["failed"] += 1

        time.sleep(DELAY_BETWEEN_VIDEOS)

    # If all videos moved and channel dir is empty, remove it
    if not dry_run:
        remaining = [
            f for f in os.listdir(channel_dir)
            if f.endswith(".mp4") and os.path.isfile(os.path.join(channel_dir, f))
        ]
        if not remaining:
            log.info("All videos migrated from %s — removing empty channel folder", channel_id)
            try:
                os.rmdir(channel_dir)
            except OSError:
                log.warning("Could not remove %s (may have other files)", channel_dir)

    return stats


def main():
    parser = argparse.ArgumentParser(
        description="Migrate TubeArchivist videos to Pinchflat folder structure"
    )
    parser.add_argument("base_dir", help="Base directory containing TA channel folders")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without making changes",
    )
    parser.add_argument(
        "--channel",
        help="Only migrate a specific channel folder (e.g., UCaNvcPv1KNQtGBI5iTRCwqg)",
    )
    parser.add_argument(
        "--resume-from",
        help="Resume from a specific video ID (skip all before it)",
    )
    args = parser.parse_args()

    base_dir = os.path.abspath(args.base_dir)
    if not os.path.isdir(base_dir):
        log.error("Base directory does not exist: %s", base_dir)
        sys.exit(1)

    # Check yt-dlp is available
    if shutil.which("yt-dlp") is None:
        log.error("yt-dlp is not installed. Install it: pip3 install yt-dlp")
        sys.exit(1)

    # Find TA channel folders
    if args.channel:
        channel_dirs = [os.path.join(base_dir, args.channel)]
        if not os.path.isdir(channel_dirs[0]):
            log.error("Channel folder not found: %s", channel_dirs[0])
            sys.exit(1)
    else:
        channel_dirs = [
            os.path.join(base_dir, d)
            for d in sorted(os.listdir(base_dir))
            if is_ta_channel_folder(os.path.join(base_dir, d))
        ]

    if not channel_dirs:
        log.info("No TA channel folders found in %s", base_dir)
        sys.exit(0)

    log.info("Found %d TA channel folder(s) to migrate:", len(channel_dirs))
    for d in channel_dirs:
        count = len([f for f in os.listdir(d) if f.endswith(".mp4")])
        log.info("  %s (%d videos)", os.path.basename(d), count)

    total_stats = {"total": 0, "success": 0, "failed": 0, "skipped": 0}

    for channel_dir in channel_dirs:
        stats = migrate_channel(
            channel_dir,
            base_dir,
            dry_run=args.dry_run,
            resume_from=args.resume_from,
        )
        for k in total_stats:
            total_stats[k] += stats[k]

    log.info("=" * 60)
    log.info("Migration complete!")
    log.info(
        "Total: %d | Success: %d | Failed: %d | Skipped: %d",
        total_stats["total"],
        total_stats["success"],
        total_stats["failed"],
        total_stats["skipped"],
    )
    if total_stats["failed"] > 0:
        log.info("Check migrate_ta_to_pinchflat.log for failed video IDs")


if __name__ == "__main__":
    main()
