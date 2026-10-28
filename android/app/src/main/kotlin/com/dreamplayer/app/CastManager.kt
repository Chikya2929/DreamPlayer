package com.dreamplayer.app

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadOptions
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.CastState
import com.google.android.gms.cast.framework.CastStateListener
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import com.google.android.gms.common.api.ResultCallback
import com.google.android.gms.common.images.WebImage
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/**
 * Google Cast session control.
 *
 * The Cast SDK owns the route picker, the session and the remote media
 * client; this class is the thin bridge to Flutter, so the player can ask
 * "what is the receiver doing?" and tell it what to play.
 *
 * The **Default Media Receiver** (`CC1AD845`) is used, so a sideloaded build
 * can cast without a Cast Console app.
 *
 * The receiver decodes the media itself, so anything the native engines can
 * play is not automatically castable: the receiver has to be able to *fetch*
 * the URL. A `file://` path or a `127.0.0.1` loopback URL means nothing to a
 * device in the next room, so Dart decides what is offered (see
 * `lib/services/cast_manager.dart`).
 *
 * The Cast SDK 22.x moved most of its API around; the shapes used here are
 * the v22 ones:
 * - `CastContext.getSharedInstance(context, executor)` returns a Task.
 * - `MediaMetadata` is constructed directly (there is no Builder any more).
 * - `MediaLoadOptions.Builder.setPlayPosition` (not `setCurrentTime`).
 * - `RemoteMediaClient.load(...)` returns a `PendingResult`, so the reply
 *   arrives through `setResultCallback` — failures are a non-success status.
 */
class CastManager(private val context: Context) {

    companion object {
        const val METHOD_CHANNEL = "dreamplayer/cast"
        const val EVENT_CHANNEL = "dreamplayer/cast_events"

        /** The Default Media Receiver — no Cast Console registration needed. */
        const val RECEIVER_APP_ID = "CC1AD845"

        private const val TAG = "DreamCast"
    }

    private val executor: Executor = Executors.newSingleThreadExecutor()
    private var castContext: CastContext? = null
    private var eventSink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())

    private var available = false
    private var connected = false
    private var deviceName: String? = null
    private var positionMs = 0L
    private var playing = false
    private var mediaLoaded = false

    private val positionPoll = object : Runnable {
        override fun run() {
            val client = remoteClient()
            if (client != null) {
                try {
                    val status = client.mediaStatus
                    if (status != null) {
                        positionMs = status.streamPosition
                        playing = status.playerState == MediaStatus.PLAYER_STATE_PLAYING
                    }
                } catch (e: Throwable) {
                    Log.w(TAG, "media status read failed: ${e.message}")
                }
            }
            emitState()
            handler.postDelayed(this, 1000L)
        }
    }

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarting(session: CastSession) {}

        override fun onSessionStarted(session: CastSession, sessionId: String) {
            connected = true
            deviceName = session.castDevice?.friendlyName
            mediaLoaded = false
            emitState()
            handler.removeCallbacks(positionPoll)
            handler.post(positionPoll)
        }

        override fun onSessionStartFailed(session: CastSession, error: Int) {
            connected = false
            emitState()
        }

        override fun onSessionEnding(session: CastSession) {}

        override fun onSessionEnded(session: CastSession, error: Int) {
            connected = false
            deviceName = null
            mediaLoaded = false
            positionMs = 0
            playing = false
            handler.removeCallbacks(positionPoll)
            emitState()
        }

        override fun onSessionResuming(session: CastSession, sessionId: String) {}

        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            connected = true
            deviceName = session.castDevice?.friendlyName
            emitState()
        }

        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            connected = false
            emitState()
        }

        override fun onSessionSuspended(session: CastSession, reason: Int) {
            connected = false
            emitState()
        }
    }

    fun configure(methodChannel: MethodChannel, eventChannel: EventChannel) {
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                emitState()
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        methodChannel.setMethodCallHandler { call, result -> handle(call, result) }
        try {
            // The SDK reads the receiver app id from CastOptionsProvider
            // through the manifest; the task resolves once Play services has
            // answered, and fails when it is missing.
            CastContext.getSharedInstance(context, executor).addOnCompleteListener { task ->
                if (!task.isSuccessful || task.result == null) {
                    Log.w(TAG, "Cast unavailable: ${task.exception?.message}")
                    available = false
                    emitState()
                    return@addOnCompleteListener
                }
                val ctx = task.result ?: return@addOnCompleteListener
                castContext = ctx
                ctx.addCastStateListener(CastStateListener { newState ->
                    connected = newState == CastState.CONNECTED
                    if (!connected) {
                        deviceName = null
                        mediaLoaded = false
                        positionMs = 0
                        playing = false
                    }
                    emitState()
                })
                ctx.sessionManager.addSessionManagerListener(sessionListener, CastSession::class.java)
                available = true
                emitState()
            }
        } catch (e: Throwable) {
            // Google Play services missing or too old — Cast is simply not
            // available; the player hides the button.
            Log.w(TAG, "Cast unavailable: ${e.message}")
            available = false
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getState" -> result.success(stateMap())
            "cast" -> cast(call, result)
            "stop" -> {
                val client = remoteClient()
                try {
                    client?.stop()
                } catch (e: Throwable) {
                    Log.w(TAG, "remote stop failed: ${e.message}")
                }
                try {
                    castContext?.sessionManager?.endCurrentSession(true)
                } catch (e: Throwable) {
                    Log.w(TAG, "ending session failed: ${e.message}")
                }
                result.success(true)
            }
            "play" -> {
                val client = remoteClient()
                if (client == null) {
                    result.error("no_device", "No cast device is connected", null)
                } else {
                    client.play()
                    result.success(true)
                }
            }
            "pause" -> {
                val client = remoteClient()
                if (client == null) {
                    result.error("no_device", "No cast device is connected", null)
                } else {
                    client.pause()
                    result.success(true)
                }
            }
            "seek" -> {
                val client = remoteClient()
                val target = (call.argument<Number>("positionMs") ?: 0).toLong()
                if (client == null) {
                    result.error("no_device", "No cast device is connected", null)
                } else {
                    client.seek(
                        MediaSeekOptions.Builder()
                            .setPosition(target)
                            .setResumeState(MediaSeekOptions.RESUME_STATE_UNCHANGED)
                            .build(),
                    )
                    result.success(true)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun cast(call: MethodCall, reply: MethodChannel.Result) {
        val client = remoteClient()
        if (client == null) {
            reply.error("no_device", "No cast device is connected", null)
            return
        }
        val url = call.argument<String>("url")
        if (url.isNullOrBlank()) {
            reply.error("bad_url", "No media URL", null)
            return
        }
        val title = call.argument<String>("title") ?: "DreamPlayer"
        val startAt = (call.argument<Number>("positionMs") ?: 0).toLong()
        val contentType = call.argument<String>("contentType")
        val imageUrl = call.argument<String>("imageUrl")
        val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MOVIE)
        metadata.putString(MediaMetadata.KEY_TITLE, title)
        if (!imageUrl.isNullOrBlank()) {
            try {
                metadata.addImage(WebImage(Uri.parse(imageUrl)))
            } catch (e: Throwable) {
                Log.w(TAG, "poster ignored: ${e.message}")
            }
        }
        val builder = MediaInfo.Builder(url).setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
        if (!contentType.isNullOrBlank()) {
            builder.setContentType(contentType)
        }
        builder.setMetadata(metadata)
        val options = MediaLoadOptions.Builder()
            .setAutoplay(true)
            .setPlayPosition(startAt)
            .build()
        try {
            client.load(builder.build(), options).setResultCallback(ResultCallback { loadResult ->
                val status = loadResult.status
                if (status.isSuccess) {
                    mediaLoaded = true
                    positionMs = startAt
                    emitState()
                    reply.success(true)
                } else {
                    val message = status.statusMessage ?: "The receiver refused the media"
                    Log.w(TAG, "remote load failed: $message")
                    reply.error("load_failed", message, null)
                }
            })
        } catch (e: Throwable) {
            reply.error("load_failed", e.message ?: "The receiver refused the media", null)
        }
    }

    private fun remoteClient(): RemoteMediaClient? {
        val manager = castContext?.sessionManager ?: return null
        return try {
            manager.currentCastSession?.remoteMediaClient
        } catch (e: Throwable) {
            null
        }
    }

    private fun stateMap(): Map<String, Any?> {
        return mapOf(
            "available" to available,
            "connected" to connected,
            "deviceName" to deviceName,
            "positionMs" to positionMs,
            "playing" to playing,
            "mediaLoaded" to mediaLoaded,
        )
    }

    private fun emitState() {
        val sink = eventSink ?: return
        try {
            sink.success(stateMap())
        } catch (e: Throwable) {
            Log.w(TAG, "event emit failed: ${e.message}")
        }
    }
}
