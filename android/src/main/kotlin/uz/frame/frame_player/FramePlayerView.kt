package uz.frame.frame_player

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
 @OptIn(UnstableApi::class)
class FramePlayerView(context: Context, viewId: Int, messenger: BinaryMessenger) : PlatformView {

    private val playerContainer: FrameLayout = FrameLayout(context)
    private val player: ExoPlayer
    private val playerView: PlayerView
    private val methodChannel: MethodChannel
    private val handler = Handler(Looper.getMainLooper())
    private val updateInterval: Long = 1000
    private var selectedAudioLanguage: String? = null
    private var selectedSubtitleLanguage: String? = null
    private var isSliderBeingDragged = false
    init {
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                DefaultLoadControl.DEFAULT_MIN_BUFFER_MS,
                DefaultLoadControl.DEFAULT_MAX_BUFFER_MS,
                DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS,
                DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS
            )
            .build()
        player = ExoPlayer.Builder(context)
            .setLoadControl(loadControl)
            .build()

        playerView = PlayerView(context).apply {
            id = View.generateViewId()
            keepScreenOn = true
            useController = false
            setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
            player = this@FramePlayerView.player
        }

        // Create layout parameters to center the PlayerView in the FrameLayout
        val layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ).apply {
            gravity = android.view.Gravity.CENTER
        }
        playerContainer.addView(playerView, layoutParams)

        val mediaItem = MediaItem.Builder()
            .setUri("https://files.etibor.uz/media/backup_beekeeper/master.m3u8")
            .build()
        player.setMediaItem(mediaItem)
        player.prepare()
        player.play()
        methodChannel = MethodChannel(messenger, "fluff_view_channel_$viewId")
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_READY) {
                    val duration = player.duration
                    methodChannel.invokeMethod("updateDuration", duration / 1000.0) // Send duration in seconds
                    updateAudioAndSubtitleOptions()

                }
                when (state) {
                    Player.STATE_BUFFERING -> {
                        val bufferedPercentage = player.bufferedPercentage
                        methodChannel.invokeMethod("updateBuffer", bufferedPercentage.toDouble())
                    }
                    Player.STATE_READY -> {
                        methodChannel.invokeMethod("updateBuffer", 100)
                    }
                    Player.STATE_ENDED, Player.STATE_IDLE -> {
                        methodChannel.invokeMethod("updateBuffer", 0)
                    }
                }
            }

            override fun onTracksChanged(tracks: Tracks) {
                updateAudioAndSubtitleOptions()
            }

            override fun onPlayerError(error: PlaybackException) {
                Log.e("ExoPlayerView", "Player error: ${error.message}")
            }
        })

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "seekTo" -> {
                    val position = call.argument<Double>("value")
                    if (position != null) {
                        val seekPosition = (position * player.duration).toLong()
                        player.seekTo(seekPosition)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Position is null", null)
                    }
                }
                "play" -> {
                    player.play()
                    result.success(true)
                }
                "pause" -> {
                    player.pause()
                    result.success(true)
                }
                "10+" ->{
                    seekBy(10)
                }
                "10-" ->{
                    seekBy(-10)
                }
                "changeAudio" -> {
                    val language = call.argument<String>("language")
                    if (language != null) {
                        changeAudio(language)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Language is null", null)
                    }
                }
                "changeSubtitle" -> {
                    val language = call.argument<String>("language")
                    if (language != null) {
                        changeSubtitle(language)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Language is null", null)
                    }
                }
                "changeVideoQuality" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        changeVideoQuality(url)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "URL is null", null)
                    }
                }
                "setPlaybackSpeed" -> {
                    val speed = call.argument<Double>("speed")
                    if (speed != null) {
                        setPlaybackSpeed(speed.toFloat())
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Speed is null", null)
                    }
                }
                "isSliderBeingDragged" -> {
                    val isDragging = call.argument<Boolean>("isDragging")
                    if (isDragging != null) {
                        isSliderBeingDragged = isDragging
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "isDragging is null", null)
                    }
                }
                else -> result.notImplemented()

            }

        }
        startPeriodicUpdates()
    }

    private fun startPeriodicUpdates() {
        handler.postDelayed(object : Runnable {
            override fun run() {
                if (!isSliderBeingDragged) {
                    val currentPosition =
                        player.currentPosition.toFloat() / player.duration.toFloat()
                    val bufferedPercentage = player.bufferedPercentage
                    methodChannel.invokeMethod("updateBuffer", bufferedPercentage.toDouble())
                    methodChannel.invokeMethod("updateSlider", currentPosition)
                }
                handler.postDelayed(this, updateInterval)
            }
        }, updateInterval)
    }

    private fun seekBy(seconds: Long) {
        val currentPosition = player.currentPosition
        val newPosition = currentPosition + seconds * 1000
        player.seekTo(newPosition.coerceIn(0, player.duration))
    }
    private fun changeAudio(language: String) {

        val tracks = player.currentTracks ?: return
        var trackFound = false
        for (trackGroup in tracks.groups) {
            for (i in 0 until trackGroup.mediaTrackGroup.length) {
                val format = trackGroup.mediaTrackGroup.getFormat(i)
                if (format.language != null && format.language == language && format.sampleMimeType?.startsWith("audio") == true) {
                    Log.d("ExoPlayerView", "Found audio track: $language")
                    player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
                        .setPreferredAudioLanguage(language)
                        .build()
                    trackFound = true
                    break
                }
            }
            if (trackFound) break
        }
        if (!trackFound) {
            Log.e("ExoPlayerView", "Audio track not found: $language")
        }
    }


    private fun changeSubtitle(language: String) {
        val tracks = player.currentTracks ?: return
        for (trackGroup in tracks.groups) {
            for (i in 0 until trackGroup.mediaTrackGroup.length) {
                val format = trackGroup.mediaTrackGroup.getFormat(i)
                if (format.language != null && format.language == language && format.sampleMimeType?.startsWith("text") == true) {
                    player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
                        .setPreferredTextLanguage(language)
                        .build()
                    return
                }
            }
        }
    }

    private fun updateAudioAndSubtitleOptions() {
        val mappedTrackInfo = player.currentTracks ?: return
        val audioOptions = mutableListOf<String>()
        val subtitleOptions = mutableListOf<String>()

        for (trackGroup in mappedTrackInfo.groups) {
            for (i in 0 until trackGroup.length) {
                val format = trackGroup.getTrackFormat(i)
                if (format.language != null) {
                    if (format.sampleMimeType?.startsWith("audio") == true) {
                        audioOptions.add(format.language ?: "Unknown")
                        Log.d("ExoPlayerView", "Audio language: ${format.language}")
                    } else if (format.sampleMimeType?.startsWith("text") == true) {
                        subtitleOptions.add(format.language ?: "Unknown")
                        Log.d("ExoPlayerView", "Subtitle language: ${format.language}")
                    }
                }
            }
        }

        methodChannel.invokeMethod("updateAudio", audioOptions)
        methodChannel.invokeMethod("updateSubtitles", subtitleOptions)
    }

    private fun changeVideoQuality(url: String) {
        storeCurrentSelections()
        val currentPosition = player.currentPosition
        val newMediaItem = MediaItem.Builder()
            .setUri("https://files.etibor.uz/media/backup_beekeeper/" + url)
            .build()
        val initialMediaItem = MediaItem.Builder()
            .setUri("https://files.etibor.uz/media/backup_beekeeper/master.m3u8") // The original URL
            .build()
        player.setMediaItem(initialMediaItem)
        player.addMediaItem(newMediaItem)
        player.prepare()
        player.seekTo(currentPosition)
        player.play()
        reapplySelections()
    }

    private fun storeCurrentSelections() {
        val trackGroups = player.currentTracks.groups
        selectedAudioLanguage = null
        selectedSubtitleLanguage = null
        trackGroups.forEach { group ->
            for (i in 0 until group.length) {
                val format = group.getTrackFormat(i)
                if (group.isTrackSelected(i)) {
                    if (format.sampleMimeType?.startsWith("audio") == true) {
                        selectedAudioLanguage = format.language
                    } else if (format.sampleMimeType?.startsWith("text") == true) {
                        selectedSubtitleLanguage = format.language
                    }
                }
            }
        }
    }

    @OptIn(UnstableApi::class) private fun reapplySelections() {
        val trackSelector = player.trackSelector as? DefaultTrackSelector ?: return
        val parametersBuilder = trackSelector.buildUponParameters()
        selectedAudioLanguage?.let {
            parametersBuilder.setPreferredAudioLanguage(it)
        }
        selectedSubtitleLanguage?.let {
            parametersBuilder.setPreferredTextLanguage(it)
        }

        trackSelector.setParameters(parametersBuilder)
    }
    private fun setPlaybackSpeed(speed: Float) {
        player.setPlaybackSpeed(speed)
    }

    override fun getView(): View {
        return playerContainer
    }

    override fun dispose() {
        player.release()
    }
}