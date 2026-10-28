package com.dreamplayer.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadOptions
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import androidx.mediarouter.app.MediaRouteChooserDialogFragment
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Google Cast session bridge to Flutter, per the CAF session-management
 * model (developers.google.com/cast/docs/android_sender/integrate): the
 * SDK owns the picker, the session and the [RemoteMediaClient]; this class
 * reports session changes and takes the "cast the current video" command.
 *
 * The DEFAULT Media Receiver (`CC1AD845`) is used, so a sideloaded build
 * can cast without a Cast Console app registration.
 *
 * The receiver fetches and decodes the media itself, so it can only play a
 * URL it can reach. Dart decides whether a source is castable
 * (`lib/services/cast_manager.dart`); anything else keeps playing locally.
 */
class CastManager(private val context: Context) {

    companion object {
        const val METHOD_CHANNEL = "dreamplayer/cast"
        const val EVENT_CHANNEL = "dreamplayer/cast_events"

        /** The Default Media Receiver — no Cast Console registration needed. */
        const val RECEIVER_APP_ID = "CC1AD845"

        private const val TAG = "DreamCast"
    }

    private val handler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var connected = false
    private var deviceName: String? = null

    private fun castContext(): CastContext? {
        return try {
            CastContext.getSharedInstance(context)
        } catch (e: Throwable) {
            Log.w(TAG, "CastContext unavailable: ${e.message}")
            null
        }
    }

    /** Registers the channels and (once) the session listeners. */
    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler { call, result -> onMethod(call, result) }
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
                emitState()
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })
        // CastContext must be touched in the app process for Google Play
        // services' CastMediaRouteProvider to bind OUR app's receiver criteria
        // (default CC1AD845) to its mDNS discovery. Without this the picker
        // opens but reports zero routes (verified on-device 2026-10-28).
        try {
            CastContext.getSharedInstance(context)
        } catch (t: Throwable) {
            Log.w(TAG, "castContext init deferred: ${t.message}")
        }
        try {
            castContext()?.sessionManager
                ?.addSessionManagerListener(sessionListener, CastSession::class.java)
        } catch (e: Throwable) {
            Log.w(TAG, "listener add failed: ${e.message}")
        }
    }

    private fun onMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openPicker" -> {
                // The unified "Send to TV" sheet reaches the Google picker
                // programmatically: the dialog fragment opens against the
                // CastContext's merged selector without needing a visible
                // MediaRouteButton in the tree. Requires an AppCompat
                // FragmentActivity (MainActivity is FlutterFragmentActivity)
                // and the mediaRouteTheme style (a missing one crashed in
                // calculateContrast on this device).
                val activity = context as? FragmentActivity
                val contextCast = castContext()
                if (activity == null || contextCast == null) {
                    result.success(mapOf("ok" to false, "error" to "no_activity"))
                    return
                }
                try {
                    val selector = contextCast.mergedSelector
                    if (selector == null) {
                        result.success(mapOf("ok" to false, "error" to "no_selector"))
                        return
                    }
                    val fragment = MediaRouteChooserDialogFragment()
                    fragment.routeSelector = selector
                    fragment.show(activity.supportFragmentManager, "dreamcast")
                    result.success(mapOf("ok" to true))
                } catch (e: Throwable) {
                    Log.w(TAG, "openPicker failed: ${e.message}")
                    result.success(mapOf("ok" to false, "error" to e.message))
                }
            }
            "getState" -> result.success(
                mapOf(
                    "available" to (castContext() != null),
                    "connected" to connected,
                    "deviceName" to deviceName,
                ),
            )
            "loadCurrent" -> {
                val url = call.argument<String>("url")
                val mime = call.argument<String>("mimeType") ?: "video/mp4"
                val title = call.argument<String>("title") ?: ""
                val positionMs = (call.argument<Int>("positionMs") ?: 0).toLong()
                if (!connected) {
                    result.success(mapOf("ok" to false, "error" to "no_session"))
                    return
                }
                val session = castContext()?.sessionManager?.currentCastSession
                val client = session?.remoteMediaClient
                if (url == null || client == null) {
                    result.success(mapOf("ok" to false, "error" to "no_client"))
                    return
                }
                try {
                    val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MOVIE)
                    if (title.isNotEmpty()) metadata.putString(MediaMetadata.KEY_TITLE, title)
                    val info = MediaInfo.Builder(url)
                        .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
                        .setContentType(mime)
                        .setMetadata(metadata)
                        .build()
                    val options = MediaLoadOptions.Builder()
                        .setAutoplay(true)
                        .setPlayPosition(positionMs.coerceAtLeast(0L))
                        .build()
                    client.load(info, options).setResultCallback { loadResult ->
                        Log.i(TAG, "load result: ${loadResult.status}")
                    }
                    result.success(mapOf("ok" to true))
                } catch (e: Throwable) {
                    Log.w(TAG, "load failed: ${e.message}")
                    result.success(mapOf("ok" to false, "error" to e.message))
                }
            }
            "stop" -> {
                try {
                    castContext()?.sessionManager?.endCurrentSession(true)
                } catch (e: Throwable) {
                    Log.w(TAG, "end session failed: ${e.message}")
                }
                result.success(mapOf("ok" to true))
            }
            else -> result.notImplemented()
        }
    }

    private fun emitState() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post { emitState() }
            return
        }
        sink?.success(
            mapOf(
                "event" to if (connected) "sessionStarted" else "sessionEnded",
                "connected" to connected,
                "deviceName" to deviceName,
            ),
        )
    }

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarting(session: CastSession) {}
        override fun onSessionStartFailed(session: CastSession, error: Int) {
            connected = false
            deviceName = null
            emitState()
        }

        override fun onSessionStarted(session: CastSession, sessionId: String) {
            onSessionLive(session)
        }

        override fun onSessionEnding(session: CastSession) {}
        override fun onSessionEnded(session: CastSession, error: Int) {
            onSessionGone()
        }

        override fun onSessionResuming(session: CastSession, sessionId: String) {}
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            onSessionLive(session)
        }

        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            onSessionGone()
        }

        override fun onSessionSuspended(session: CastSession, reason: Int) {
            onSessionGone()
        }
    }

    private fun onSessionLive(session: CastSession) {
        connected = true
        deviceName = session.castDevice?.friendlyName
        Log.i(TAG, "session live on ${deviceName ?: "?"}")
        emitState()
    }

    private fun onSessionGone() {
        connected = false
        deviceName = null
        Log.i(TAG, "session gone")
        emitState()
    }
}
