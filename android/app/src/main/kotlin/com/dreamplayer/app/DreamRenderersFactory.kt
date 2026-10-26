package com.dreamplayer.app

import android.content.Context
import android.os.Handler
import android.util.Log
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import io.github.anilbeesetti.nextlib.media3ext.ffdecoder.FfmpegAudioRenderer
import io.github.anilbeesetti.nextlib.media3ext.ffdecoder.FfmpegVideoRenderer
import androidx.media3.exoplayer.video.VideoRendererEventListener
import java.util.ArrayList

class DreamRenderersFactory(
    context: Context,
    /// Optional observer for video-renderer events (first rendered frame,
    /// decoder init). The factory owns the only [VideoRendererEventListener]
    /// Media3 hands to the renderers, so anything that needs those callbacks
    /// has to be plugged in here.
    private val videoObserver: VideoRendererEventListener? = null,
) : DefaultRenderersFactory(context) {
    init {
        setAllowedVideoJoiningTimeMs(0L)
    }

    companion object {
        /// Manual A/V sync: shifts audio relative to video (±5 s). Shared so
        /// the `setAudioDelay` channel handler can retune it mid-playback.
        val audioDelayProcessor = AudioDelayProcessor()

        /// Volume boost: make-up gain + peak limiter on the decoded PCM. Shared
        /// so the player can move the gain at gesture rate without rebuilding
        /// the sink, and because it is the ONLY boost path — no vendor audio
        /// effect is involved (issue #41).
        val audioBoostProcessor = BoostLimiterProcessor()
    }

    /// Inserts the audio-delay and audio-boost processors into every audio
    /// sink (platform and FFmpeg renderers both receive this sink from
    /// buildAudioRenderers).
    override fun buildAudioSink(
        context: Context,
        enableFloatOutput: Boolean,
        enableAudioTrackPlaybackParams: Boolean,
    ): AudioSink =
        DefaultAudioSink.Builder(context)
            .setEnableFloatOutput(enableFloatOutput)
            .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
            .setAudioProcessors(arrayOf(audioDelayProcessor, audioBoostProcessor))
            .build()

    override fun buildVideoRenderers(
        context: Context,
        extensionRendererMode: Int,
        codecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        eventHandler: Handler,
        eventListener: VideoRendererEventListener,
        allowedJoiningTimeMs: Long,
        out: ArrayList<Renderer>,
    ) {
        val observer = videoObserver
        super.buildVideoRenderers(
            context,
            extensionRendererMode,
            codecSelector,
            enableDecoderFallback,
            eventHandler,
            if (observer == null) eventListener else ObservedVideoListener(eventListener, observer),
            allowedJoiningTimeMs,
            out,
        )
        // Add FfmpegVideoRenderer as ultimate fallback (after all MediaCodec
        // renderers). Used when hardware + software MediaCodec decoders both
        // fail (e.g. 10-bit HEVC on devices without 10-bit MediaCodec support).
        // Added at the END so HDR/DV hardware path stays primary.
        // Constructor: (allowedJoiningTimeMs, handler, eventListener, maxDroppedFramesToNotify)
        try {
            out.add(FfmpegVideoRenderer(allowedJoiningTimeMs, eventHandler, eventListener, 0))
            Log.i("DreamRenderersFactory", "Loaded FfmpegVideoRenderer as fallback.")
        } catch (e: Exception) {
            Log.w("DreamRenderersFactory", "FfmpegVideoRenderer unavailable, falling back to MediaCodec only.", e)
        }
    }

    override fun buildAudioRenderers(
        context: Context,
        extensionRendererMode: Int,
        codecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        audioSink: AudioSink,
        eventHandler: Handler,
        eventListener: AudioRendererEventListener,
        out: ArrayList<Renderer>,
    ) {
        super.buildAudioRenderers(
            context,
            extensionRendererMode,
            codecSelector,
            enableDecoderFallback,
            audioSink,
            eventHandler,
            eventListener,
            out,
        )
        try {
            out.add(FfmpegAudioRenderer(eventHandler, eventListener, audioSink))
            Log.i("DreamRenderersFactory", "Loaded FfmpegAudioRenderer.")
        } catch (e: Exception) {
            Log.w("DreamRenderersFactory", "FfmpegAudioRenderer unavailable, falling back to MediaCodec only.", e)
        }
    }

    /// Forwards every video-renderer event to Media3's own listener and to our
    /// observer. Kotlin's interface delegation keeps the default methods of
    /// [VideoRendererEventListener] intact.
    private class ObservedVideoListener(
        private val delegate: VideoRendererEventListener,
        private val observer: VideoRendererEventListener,
    ) : VideoRendererEventListener by delegate {
        override fun onVideoDecoderInitialized(
            codecName: String,
            initializationDurationMs: Long,
            initializationLatencyMs: Long,
        ) {
            delegate.onVideoDecoderInitialized(codecName, initializationDurationMs, initializationLatencyMs)
            observer.onVideoDecoderInitialized(codecName, initializationDurationMs, initializationLatencyMs)
        }

        // Media3 1.10.1 signature: onRenderedFirstFrame(Object output, long renderTimeMs).
        override fun onRenderedFirstFrame(output: Any, renderTimeMs: Long) {
            delegate.onRenderedFirstFrame(output, renderTimeMs)
            observer.onRenderedFirstFrame(output, renderTimeMs)
        }

        override fun onVideoInputFormatChanged(
            format: androidx.media3.common.Format,
            decoderReuseEvaluation: androidx.media3.exoplayer.DecoderReuseEvaluation?,
        ) {
            delegate.onVideoInputFormatChanged(format, decoderReuseEvaluation)
            observer.onVideoInputFormatChanged(format, decoderReuseEvaluation)
        }
    }
}
