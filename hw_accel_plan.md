# Hardware Accelerated Generation Plan

## Goal Description
The server running the video streamer (at `192.168.0.11`) has 16GB of RAM but is currently bottlenecked by software encoding (`libx264`) dragging the CPU to 250% load. The user wants to:
1. Speed up generation using Hardware Acceleration.
2. Utilize the available VM RAM to speed up read/write during intermediate processing.

We checked the server. The NVIDIA NVML driver is out of sync (`Driver/library version mismatch`), meaning the NVIDIA GPU is temporarily unusable without a host reboot/driver reinstallation. However, there is an Intel UHD Graphics 630 iGPU available at `/dev/dri`.

We will configure the `chunk-generator` to run via **Intel Quick Sync Video (QSV)** and allocate a substantial portion of the 10GB free RAM to a `tmpfs` RAM disk to accelerate the temporary clip extraction.

## Proposed Changes
### [MODIFY] [docker-compose.yml]
- Add `devices:` instruction to the `chunk-generator` service to map `/dev/dri:/dev/dri`.
- Change `tmpfs` allocation for `/tmp` inside the generator to `4G` (4 Gigabytes) so that intermediate extraction hits RAM, not disk. 

### [MODIFY] [generate_chunk.sh]
- Update the ffmpeg extraction line to utilize QSV:
  - Add `-hwaccel qsv` and `-c:v h264_qsv`.
  - The scale filter will need to use `vpp_qsv` or standard software scale followed by HW encode. For maximum compatibility and simplest transition, we can just replace `-c:v libx264 -preset fast -crf 23` with `-c:v h264_qsv -preset fast -global_quality 23 -look_ahead 1`.

## Verification Plan
1. Push changes via `rsync`.
2. Restart the generator container on the remote server.
3. Observe the `docker logs chunk-generator` to ensure `h264_qsv` initializes successfully without failing back to software.
4. Check `top` on the server during generation to confirm CPU usage has dramatically dropped compared to the previous ~250% utilization.
