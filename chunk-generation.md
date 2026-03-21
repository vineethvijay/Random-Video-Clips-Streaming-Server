# Chunk Generation Flow

This document describes how the chunk generator builds video chunks from your library: queue management, segment tracking, and clip extraction.

## Flow Diagram

```mermaid
flowchart TB
    %% Styles (match main Architecture diagram)
    classDef init fill:#f6f8fa,stroke:#d1d5da,stroke-width:2px,color:#24292e
    classDef process fill:#2b3137,stroke:#24292e,stroke-width:2px,color:#fafbfc
    classDef decision fill:#0366d6,stroke:#0366d6,stroke-width:2px,color:#ffffff
    classDef success fill:#28a745,stroke:#2ea043,stroke-width:2px,color:#ffffff
    classDef fallback fill:#f9826c,stroke:#f85149,stroke-width:2px,color:#ffffff

    subgraph init["Initialization"]
        direction TB
        A[Find all videos in VIDEO_DIR]:::init --> B{Queue exists?}:::decision
        B -->|No| C[Shuffle videos randomly]:::success
        B -->|Yes| D[Merge: keep LRU order + insert new videos at random positions]:::success
        C --> E[Save to queue]
        D --> E
        E --> F
    end

    subgraph loop["For each clip (until chunk full)"]
        direction TB
        F[Take video from head of queue]:::process --> G[Move video to bottom of queue]:::process
        G --> H[Get video duration via ffprobe]:::process
        H --> I[Random clip length: CLIP_MIN to CLIP_MAX]:::process
        I --> J{Segment tracker<br>available?}:::decision
        J -->|Yes| K[Find unused time ranges]:::process
        J -->|No| L[Random start: 0 to max_start]:::fallback
        K --> M{Unused range<br>long enough?}:::decision
        M -->|Yes| N[Random start within unused range]:::success
        M -->|No| L
        N --> O[Record used segment]
        L --> O
        O --> P[Extract clip with ffmpeg]:::process
        P --> Q{Chunk duration<br>reached?}:::decision
        Q -->|No| F
        Q -->|Yes| R[Concat clips → save chunk]:::success
    end

    style init fill:transparent,stroke:#6a737d,stroke-dasharray: 5 5
    style loop fill:transparent,stroke:#6a737d,stroke-dasharray: 5 5
```

## Behavior Summary

| Aspect | Behavior |
|--------|----------|
| **Which video** | Round-robin over a shuffled queue (LRU: take from head, move to bottom) |
| **New videos** | Inserted at random positions so they get a fair chance to appear soon |
| **Clip length** | Random between `CLIP_MIN` and `CLIP_MAX` |
| **Start time** | Random within unused segments (or fully random if no segment tracker) |
