package com.homelab.streamer

import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import java.net.HttpURLConnection
import java.net.URL

@UnstableApi
class MainActivity : AppCompatActivity() {

    private lateinit var player: ExoPlayer
    private lateinit var playerView: PlayerView
    private lateinit var statusView: TextView
    private lateinit var splashView: LinearLayout
    private lateinit var optionsPanel: LinearLayout
    private lateinit var skipAudioView: TextView
    private lateinit var refreshView: TextView
    private var optionsSelectedIndex = 0

    private var retryCount = 0
    private var lastErrorText: String? = null
    private var backPressedOnce = false
    private var everPlayed = false

    // Watchdog: detects two failure modes that aren't surfaced as
    // PlaybackException by ExoPlayer:
    //   1. The live edge stops advancing (stuck clip_pusher) — currentPosition
    //      no longer moves while playWhenReady is true.
    //   2. The video decoder hangs but audio keeps playing — currentPosition
    //      keeps advancing (clocked by audio) yet no new video frames are
    //      rendered. This is the classic Tegra X1 "frozen frame" symptom.
    private val watchdogHandler = Handler(Looper.getMainLooper())
    private var lastObservedPositionMs: Long = -1L
    private var lastPositionChangeTs: Long = 0L
    private var watchdogRefreshCount = 0

    // Heartbeat from the video renderer. Updated whenever ExoPlayer reports
    // that a video frame was actually processed/dropped/sized — i.e. the
    // decoder is alive. If this stops ticking while audio plays, video is
    // stuck and we force-refresh.
    @Volatile private var lastVideoFrameTs: Long = 0L
    // Snapshot of player.currentPosition at the moment lastVideoFrameTs was
    // last updated. Used by the freeze detector to confirm audio has actually
    // advanced during the freeze (which proves it's a true video-only stall
    // rather than the whole pipeline being paused / buffering).
    private var lastVideoFramePositionMs: Long = 0L
    // Timestamp of the last soft-kick (live-edge seek) we issued, so we
    // don't spam them while waiting for the decoder to recover.
    private var lastSoftKickTs: Long = 0L

    companion object {
        private const val TAG = "HomelabStreamer"
        private const val STREAM_URL = "http://192.168.0.246/live/stream.m3u8"
        // Skip-audio is served by the API service via the cluster ingress
        // (NOT by the LAN-exposed nginx LB at 192.168.0.246, which only
        // serves the static frontend and rejects POSTs with 405).
        // We hit the ingress LB IP directly with a Host header so the call
        // works even when the Shield's DNS doesn't resolve homelab.local.
        private const val INGRESS_IP = "192.168.0.240"
        private const val INGRESS_HOST = "streamer.homelab.local"
        private const val SKIP_AUDIO_PATH = "/api/skip_to_next_audio"
        private const val WAKE_PATH = "/api/wake"
        private const val LIVE_TARGET_OFFSET_MS = 15_000L
        // Exponential backoff for transient stream errors (e.g. malformed
        // m3u8 served briefly while the server rotates audio). Cap stops it
        // from drifting too far and keeps the stream snappy once the
        // upstream settles.
        private const val RETRY_BASE_DELAY_MS = 400L
        private const val RETRY_MAX_DELAY_MS = 5_000L
        private const val BUFFERING_OVERLAY_DELAY_MS = 800L
        private const val STATUS_AUTOHIDE_MS = 4_000L
        private const val BACK_RESET_MS = 2_000L
        // If onResume is called and last frame is older than this, snap to live edge
        private const val RESUME_LIVE_SNAP_MS = 10_000L

        // Watchdog constants: if playback position hasn't changed in this
        // window while playWhenReady is true and no error is active, assume
        // the server stream is stuck and force-refresh the player.
        private const val WATCHDOG_POLL_MS = 2_000L
        private const val WATCHDOG_STALL_MS = 30_000L
        // Video-frame heartbeat: if no video frame has been rendered/processed
        // in this window AND the audio position has advanced by at least
        // [WATCHDOG_VIDEO_AUDIO_ADVANCE_MS] in the same window, treat it as a
        // frozen-video / audio-only stall. The dual condition protects us
        // from transient codec re-inits between concatenated chunks (which
        // can legitimately pause video frames for a couple of seconds while
        // audio keeps decoding).
        //
        // First we try a soft kick (seek to live edge) at
        // VIDEO_STALL_SOFT_MS — cheap and usually unwedges the decoder.
        // If the soft kick fails and the freeze persists past
        // VIDEO_STALL_HARD_MS, we tear down and reload.
        private const val WATCHDOG_VIDEO_STALL_SOFT_MS = 6_000L
        private const val WATCHDOG_VIDEO_STALL_HARD_MS = 12_000L
        private const val WATCHDOG_VIDEO_AUDIO_ADVANCE_MS = 3_000L
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Allow setting the "Host" request header on HttpURLConnection so we
        // can hit the cluster ingress by IP without depending on the Shield's
        // DNS resolving streamer.homelab.local. Must be set before any
        // HttpURLConnection is opened in this process.
        System.setProperty("sun.net.http.allowRestrictedHeaders", "true")

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_FULLSCREEN

        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }

        playerView = PlayerView(this).apply {
            useController = false
            keepScreenOn = true
            setShutterBackgroundColor(Color.BLACK)
        }
        root.addView(
            playerView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        splashView = buildSplash()
        root.addView(
            splashView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        statusView = TextView(this).apply {
            setTextColor(Color.WHITE)
            setBackgroundColor(0xCC000000.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            setPadding(40, 28, 40, 28)
            text = "Starting…\n$STREAM_URL"
        }
        val statusParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            setMargins(48, 48, 48, 48)
        }
        root.addView(statusView, statusParams)

        // Options panel pinned to top-right. Stays hidden in default
        // fullscreen mode — only revealed by DPAD_UP. Inside the panel,
        // UP/DOWN navigate, ENTER/OK confirms the highlighted action.
        skipAudioView = TextView(this).apply {
            text = "⏭  Skip audio"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            setPadding(40, 24, 40, 24)
        }
        refreshView = TextView(this).apply {
            text = "⟳  Hard refresh"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            setPadding(40, 24, 40, 24)
        }
        optionsPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            addView(skipAudioView)
            addView(refreshView)
        }
        val skipParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            setMargins(48, 48, 48, 48)
        }
        root.addView(optionsPanel, skipParams)

        setContentView(root)

        player = buildPlayer()
        playerView.player = player

        sendWake()
        loadAndPlay()
        startWatchdog()
    }

    private fun buildSplash(): LinearLayout {
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.BLACK)
        }
        val logo = ImageView(this).apply {
            setImageDrawable(ContextCompat.getDrawable(this@MainActivity, R.drawable.ic_launcher_foreground))
            val size = (resources.displayMetrics.density * 180).toInt()
            layoutParams = LinearLayout.LayoutParams(size, size)
        }
        val title = TextView(this).apply {
            text = "Homelab Streamer"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            gravity = Gravity.CENTER
            setPadding(0, 32, 0, 0)
        }
        val sub = TextView(this).apply {
            text = "Connecting…"
            setTextColor(0xFFBBBBBB.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            gravity = Gravity.CENTER
            setPadding(0, 16, 0, 0)
        }
        container.addView(logo)
        container.addView(title)
        container.addView(sub)
        return container
    }

    private fun hideSplash() {
        if (splashView.visibility != View.GONE) {
            splashView.animate()
                .alpha(0f)
                .setDuration(300)
                .withEndAction { splashView.visibility = View.GONE }
                .start()
        }
    }

    private fun buildPlayer(): ExoPlayer {
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(15_000, 60_000, 1_500, 3_000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent("homelab-streamer/1.6")
            .setConnectTimeoutMs(10_000)
            .setReadTimeoutMs(10_000)
            .setAllowCrossProtocolRedirects(true)

        val mediaSourceFactory = DefaultMediaSourceFactory(this)
            .setDataSourceFactory(httpFactory)
            .setLiveTargetOffsetMs(LIVE_TARGET_OFFSET_MS)

        // Shield Tegra X1 sometimes trips on certain H.264 frames (ERROR_CODE_DECODING_FAILED / 4003).
        // Allow ExoPlayer to recover by enabling decoder fallback + software fallback.
        val renderersFactory = DefaultRenderersFactory(this)
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)

        return ExoPlayer.Builder(this, renderersFactory)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()
            .apply {
                addListener(stateListener)
                addAnalyticsListener(videoHeartbeatListener)
            }
    }

    /**
     * Treat any of these video-renderer callbacks as proof that the video
     * decoder is still alive. While ExoPlayer is rendering, at least one of
     * `onVideoFrameProcessingOffset` or `onDroppedVideoFrames` fires roughly
     * once a second; if that stream stops while audio keeps playing we know
     * the video is frozen and trigger a refresh from the watchdog.
     */
    private val videoHeartbeatListener = object : AnalyticsListener {
        private fun heartbeat() {
            lastVideoFrameTs = System.currentTimeMillis()
            lastVideoFramePositionMs = player.currentPosition
        }

        override fun onVideoFrameProcessingOffset(
            eventTime: AnalyticsListener.EventTime,
            totalProcessingOffsetUs: Long,
            frameCount: Int,
        ) {
            heartbeat()
        }

        override fun onDroppedVideoFrames(
            eventTime: AnalyticsListener.EventTime,
            droppedFrames: Int,
            elapsedMs: Long,
        ) {
            // Drops still mean the renderer is alive and processing.
            heartbeat()
        }

        override fun onRenderedFirstFrame(
            eventTime: AnalyticsListener.EventTime,
            output: Any,
            renderTimeMs: Long,
        ) {
            heartbeat()
        }
    }

    private fun loadAndPlay() {
        val mediaItem = MediaItem.Builder()
            .setUri(STREAM_URL)
            .setLiveConfiguration(
                MediaItem.LiveConfiguration.Builder()
                    .setTargetOffsetMs(LIVE_TARGET_OFFSET_MS)
                    .setMinPlaybackSpeed(0.97f)
                    .setMaxPlaybackSpeed(1.03f)
                    .build()
            )
            .build()

        player.setMediaItem(mediaItem)
        player.playWhenReady = true
        player.prepare()
        setStatus("Preparing stream… (try ${retryCount + 1})\n$STREAM_URL")
    }

    private fun snapToLiveEdge() {
        try {
            player.seekToDefaultPosition()
        } catch (_: Throwable) { /* ignore */ }
    }

    private val watchdogRunnable = object : Runnable {
        override fun run() {
            try {
                // Only police playback when the user expects it to be playing
                // and we've actually started playing at least once.
                if (!player.playWhenReady || !everPlayed
                        || player.playbackState == Player.STATE_IDLE) {
                    lastObservedPositionMs = -1L
                } else {
                    val pos = player.currentPosition
                    val now = System.currentTimeMillis()
                    if (pos != lastObservedPositionMs) {
                        lastObservedPositionMs = pos
                        lastPositionChangeTs = now
                    } else if (lastPositionChangeTs > 0
                            && now - lastPositionChangeTs > WATCHDOG_STALL_MS) {
                        triggerHardRefresh(
                            "position stuck at $pos for " +
                            "${(now - lastPositionChangeTs) / 1000}s"
                        )
                        return@run
                    }

                    // Frozen-video / audio-only detection. Audio keeps the
                    // playback clock advancing even when the video decoder
                    // hangs, so the position-based check above can't catch
                    // this. Two conditions must hold to act:
                    //   1. No video-renderer callback in WATCHDOG_VIDEO_STALL_*_MS.
                    //   2. Audio (player position) has advanced significantly
                    //      in that same window — proving it's specifically a
                    //      video freeze, not a generic pipeline pause.
                    if (player.playbackState == Player.STATE_READY
                            && lastVideoFrameTs > 0) {
                        val videoStallMs = now - lastVideoFrameTs
                        val audioAdvancedMs = pos - lastVideoFramePositionMs
                        if (videoStallMs > WATCHDOG_VIDEO_STALL_HARD_MS
                                && audioAdvancedMs > WATCHDOG_VIDEO_AUDIO_ADVANCE_MS) {
                            triggerHardRefresh(
                                "no video frame in ${videoStallMs / 1000}s " +
                                "while audio advanced ${audioAdvancedMs / 1000}s"
                            )
                            return@run
                        }
                        // Soft kick: cheaper than a tear-down. Snap to the
                        // live edge — this often unwedges a stuck video
                        // decoder while keeping audio continuous. Throttled
                        // so we only try once per stall window.
                        if (videoStallMs > WATCHDOG_VIDEO_STALL_SOFT_MS
                                && audioAdvancedMs > WATCHDOG_VIDEO_AUDIO_ADVANCE_MS
                                && now - lastSoftKickTs > WATCHDOG_VIDEO_STALL_HARD_MS) {
                            lastSoftKickTs = now
                            Log.w(TAG,
                                "Watchdog: video stall ${videoStallMs / 1000}s " +
                                "while audio advanced ${audioAdvancedMs / 1000}s — soft-kicking to live edge")
                            try {
                                player.seekToDefaultPosition()
                            } catch (_: Throwable) { /* ignore */ }
                        }
                    }
                }
            } catch (t: Throwable) {
                Log.e(TAG, "watchdog error", t)
            }
            watchdogHandler.postDelayed(this, WATCHDOG_POLL_MS)
        }
    }

    private fun triggerHardRefresh(reason: String) {
        watchdogRefreshCount++
        Log.w(TAG, "Watchdog: $reason — hard-refreshing (count=$watchdogRefreshCount)")
        showStatus()
        setStatus("Reconnecting…")
        lastObservedPositionMs = -1L
        lastPositionChangeTs = 0L
        lastVideoFrameTs = 0L
        lastVideoFramePositionMs = 0L
        lastSoftKickTs = 0L
        player.stop()
        player.clearMediaItems()
        loadAndPlay()
        watchdogHandler.postDelayed(watchdogRunnable, WATCHDOG_POLL_MS)
    }

    private fun startWatchdog() {
        watchdogHandler.removeCallbacks(watchdogRunnable)
        lastObservedPositionMs = -1L
        lastPositionChangeTs = 0L
        lastVideoFrameTs = 0L
        lastVideoFramePositionMs = 0L
        watchdogHandler.postDelayed(watchdogRunnable, WATCHDOG_POLL_MS)
    }

    private fun stopWatchdog() {
        watchdogHandler.removeCallbacks(watchdogRunnable)
    }

    private fun setStatus(msg: String) {
        Log.i(TAG, msg)
        runOnUiThread { statusView.text = msg }
    }

    private fun hideStatusSoon() {
        statusView.postDelayed({ statusView.visibility = View.GONE }, STATUS_AUTOHIDE_MS)
    }

    private fun showStatus() {
        statusView.visibility = View.VISIBLE
    }

    /**
     * Show the top-right Options panel. Auto-hides after STATUS_AUTOHIDE_MS
     * unless the user confirms with ENTER / OK.
     */
    private fun showOptions() {
        optionsPanel.visibility = View.VISIBLE
        renderOptionsSelection()
        optionsPanel.removeCallbacks(hideOptionsRunnable)
        optionsPanel.postDelayed(hideOptionsRunnable, STATUS_AUTOHIDE_MS)
    }

    private fun hideOptions() {
        optionsPanel.removeCallbacks(hideOptionsRunnable)
        optionsPanel.visibility = View.GONE
    }

    private val hideOptionsRunnable = Runnable {
        optionsPanel.visibility = View.GONE
    }

    private fun isOptionsVisible(): Boolean = optionsPanel.visibility == View.VISIBLE

    private fun renderOptionsSelection() {
        val selectedBg = 0xE6404060.toInt()
        val unselectedBg = 0xE6202020.toInt()
        skipAudioView.setBackgroundColor(if (optionsSelectedIndex == 0) selectedBg else unselectedBg)
        refreshView.setBackgroundColor(if (optionsSelectedIndex == 1) selectedBg else unselectedBg)
        // Re-arm auto-hide on every interaction.
        optionsPanel.removeCallbacks(hideOptionsRunnable)
        optionsPanel.postDelayed(hideOptionsRunnable, STATUS_AUTOHIDE_MS)
    }

    private fun confirmSelectedOption() {
        when (optionsSelectedIndex) {
            0 -> skipAudio()
            1 -> hardRefresh()
        }
    }

    private fun hardRefresh() {
        hideOptions()
        showStatus()
        setStatus("Hard refreshing…")
        sendWake()
        player.stop()
        loadAndPlay()
        hideStatusSoon()
    }

    /**
     * Fire-and-forget POST to /api/wake. Tells the server to un-pause ffmpeg
     * after the idle auto-shutdown. Safe to call repeatedly — the server
     * always responds 200 and just refreshes its activity timer.
     */
    private fun sendWake() {
        Thread {
            try {
                val url = URL("http://$INGRESS_IP$WAKE_PATH")
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 3_000
                    readTimeout = 3_000
                    doOutput = true
                    setRequestProperty("Host", INGRESS_HOST)
                    setRequestProperty("Content-Length", "0")
                    outputStream.use { /* empty body */ }
                }
                Log.i(TAG, "sendWake -> HTTP ${conn.responseCode}")
                conn.disconnect()
            } catch (t: Throwable) {
                Log.w(TAG, "sendWake failed (will retry on HLS request via nginx mirror)", t)
            }
        }.start()
    }

    /**
     * Fire-and-forget POST to the streamer API to advance to the next audio
     * track. Runs on a background thread; errors are logged but never block
     * playback. We briefly flash the overlay so the user sees confirmation.
     */
    private fun skipAudio() {
        hideOptions()
        showStatus()
        setStatus("Skipping audio…")
        Thread {
            var ok = false
            var err: String? = null
            try {
                val url = URL("http://$INGRESS_IP$SKIP_AUDIO_PATH")
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 5_000
                    readTimeout = 5_000
                    doOutput = true
                    setRequestProperty("Host", INGRESS_HOST)
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Content-Length", "0")
                    outputStream.use { /* empty body */ }
                }
                ok = conn.responseCode in 200..299
                if (!ok) err = "HTTP ${conn.responseCode}"
                conn.disconnect()
            } catch (t: Throwable) {
                err = t.message ?: t::class.java.simpleName
                Log.w(TAG, "skipAudio failed", t)
            }
            runOnUiThread {
                setStatus(
                    if (ok) "⏭  Audio skipped"
                    else "⚠  Skip failed: $err"
                )
                hideStatusSoon()
            }
        }.start()
    }

    private val stateListener = object : Player.Listener {
        override fun onPlaybackStateChanged(state: Int) {
            when (state) {
                Player.STATE_IDLE -> {
                    if (lastErrorText == null) setStatus("Idle\n$STREAM_URL")
                }
                Player.STATE_BUFFERING -> {
                    // Server-side audio rotation typically resolves in <1s.
                    // Defer the "Buffering…" overlay so brief stalls stay
                    // invisible — only show it if we're still buffering past
                    // BUFFERING_OVERLAY_DELAY_MS.
                    if (everPlayed) {
                        playerView.removeCallbacks(showBufferingRunnable)
                        playerView.postDelayed(showBufferingRunnable, BUFFERING_OVERLAY_DELAY_MS)
                    }
                }
                Player.STATE_READY -> {
                    lastErrorText = null
                    // Stream is healthy again — reset the retry counter so
                    // the next transient blip starts at the base delay
                    // rather than the long backoff tail.
                    retryCount = 0
                    everPlayed = true
                    playerView.removeCallbacks(showBufferingRunnable)
                    // Seed the video heartbeat: we know the renderer is alive
                    // when we first reach READY. The watchdog freeze-check
                    // uses this as its reference until real frames flow.
                    lastVideoFrameTs = System.currentTimeMillis()
                    lastVideoFramePositionMs = player.currentPosition
                    hideSplash()
                    setStatus("Playing ✓  •  live")
                    hideStatusSoon()
                }
                Player.STATE_ENDED -> setStatus("Stream ended — retrying…\n$STREAM_URL")
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            retryCount++
            // Exponential backoff: 400ms, 800ms, 1.6s, 3.2s, capped at 5s.
            // The capped tail gives the server's m3u8 publisher time to
            // finish a rotation rather than us hammering at 400ms forever.
            val delayMs = (RETRY_BASE_DELAY_MS shl (retryCount - 1).coerceAtMost(8))
                .coerceAtMost(RETRY_MAX_DELAY_MS)
            val cause = error.cause
            val detail = buildString {
                append("PLAYBACK ERROR\n")
                append("code: ${error.errorCodeName} (${error.errorCode})\n")
                append("msg: ${error.message}\n")
                if (cause != null) append("cause: ${cause::class.java.simpleName}: ${cause.message}\n")
                append("\nRetry $retryCount in ${delayMs}ms…\n")
                append(STREAM_URL)
            }
            Log.e(TAG, detail, error)
            lastErrorText = detail
            // Quiet, minimal overlay during transient errors (e.g. brief
            // malformed m3u8 while the server rotates the audio mix).
            // Full detail is logged to logcat above.
            showStatus()
            setStatus("Reconnecting…")

            playerView.postDelayed({
                if (!isFinishing) {
                    player.stop()
                    player.clearMediaItems()
                    loadAndPlay()
                }
            }, delayMs)
        }
    }

    private val showBufferingRunnable = Runnable {
        if (everPlayed) {
            showStatus()
            setStatus("Buffering…")
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        return when (keyCode) {
            // Media-next / fast-forward — always skip audio, even if the
            // overlay isn't currently visible. Most TV remotes have a ⏭ key.
            KeyEvent.KEYCODE_MEDIA_NEXT,
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD,
            KeyEvent.KEYCODE_MEDIA_SKIP_FORWARD -> {
                skipAudio(); true
            }
            // D-pad RIGHT triggers skip-audio only when the overlay is
            // already showing (so a single press just reveals the hint and
            // a second press confirms). Keeps idle-state remote presses from
            // accidentally skipping.
            KeyEvent.KEYCODE_DPAD_RIGHT -> {
                if (isOptionsVisible()) {
                    confirmSelectedOption()
                } else {
                    showStatus(); hideStatusSoon()
                }
                true
            }
            // D-pad UP toggles the top-right Options panel and navigates
            // selection upward when already open. Shield remote has no
            // MENU/INFO key, so UP is the dedicated way in.
            KeyEvent.KEYCODE_DPAD_UP -> {
                if (!isOptionsVisible()) {
                    optionsSelectedIndex = 0
                    showOptions()
                } else if (optionsSelectedIndex > 0) {
                    optionsSelectedIndex -= 1
                    renderOptionsSelection()
                } else {
                    hideOptions()
                }
                true
            }
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> {
                if (isOptionsVisible()) {
                    confirmSelectedOption()
                } else {
                    if (player.isPlaying) player.pause() else player.play()
                    showStatus(); hideStatusSoon()
                }
                true
            }
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                if (player.isPlaying) player.pause() else player.play()
                showStatus(); hideStatusSoon()
                true
            }
            KeyEvent.KEYCODE_MEDIA_STOP -> {
                player.stop(); loadAndPlay(); true
            }
            KeyEvent.KEYCODE_DPAD_DOWN -> {
                if (isOptionsVisible() && optionsSelectedIndex < 1) {
                    optionsSelectedIndex += 1
                    renderOptionsSelection()
                    true
                } else {
                    showStatus(); hideStatusSoon(); true
                }
            }
            KeyEvent.KEYCODE_DPAD_LEFT,
            KeyEvent.KEYCODE_INFO, KeyEvent.KEYCODE_MENU -> {
                showStatus()
                val pos = player.currentPosition
                val dur = player.duration
                val behind = if (dur != C.TIME_UNSET && dur > 0) (dur - pos) / 1000 else -1
                val info = buildString {
                    append("Homelab Streamer\n")
                    append(STREAM_URL)
                    if (behind >= 0) append("\nbehind live: ${behind}s")
                }
                setStatus(info)
                hideStatusSoon()
                true
            }
            else -> super.onKeyDown(keyCode, event)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (backPressedOnce) {
            super.onBackPressed()
            return
        }
        backPressedOnce = true
        Toast.makeText(this, "Press back again to exit", Toast.LENGTH_SHORT).show()
        playerView.postDelayed({ backPressedOnce = false }, BACK_RESET_MS)
    }

    override fun onStop() {
        super.onStop()
        player.pause()
    }

    override fun onStart() {
        super.onStart()
        if (!::player.isInitialized) return
        // Tell the server we're back so it un-pauses ffmpeg before we hit the
        // playlist. Cheap, fire-and-forget.
        sendWake()
        when (player.playbackState) {
            Player.STATE_IDLE -> loadAndPlay()
            Player.STATE_READY, Player.STATE_BUFFERING -> {
                // Coming back from sleep / home — jump to live edge if we drifted
                val dur = player.duration
                val pos = player.currentPosition
                if (dur != C.TIME_UNSET && dur - pos > RESUME_LIVE_SNAP_MS) {
                    snapToLiveEdge()
                }
                player.play()
            }
            else -> player.play()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopWatchdog()
        player.release()
    }
}
