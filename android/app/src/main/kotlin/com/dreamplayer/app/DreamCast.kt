package com.dreamplayer.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.UUID
import java.util.concurrent.Executors
import androidx.core.app.ServiceCompat
import org.json.JSONObject

/**
 * Dart-facing switch for the receiver service: `enable` / `disable` plus a
 * `getPort` used by the sender-side tests. The channel is
 * `dreamplayer/dreamcast`.
 */
class DreamCast(private val context: Context) {

    companion object {
        const val CHANNEL = "dreamplayer/dreamcast"
    }

    fun configure(channel: io.flutter.plugin.common.MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    val intent = Intent(context, DreamCastReceiverService::class.java)
                    androidx.core.content.ContextCompat.startForegroundService(context, intent)
                    result.success(true)
                }
                "disable" -> {
                    context.stopService(
                        Intent(context, DreamCastReceiverService::class.java),
                    )
                    result.success(true)
                }
                "isReceiverSupported" ->
                    result.success(MainActivity.isTvBox(context))
                else -> result.notImplemented()
            }
        }
    }
}

/** An incoming HTTP request parsed into the request line and the body. */

/**
 * "Play on TV" receiver for the Fire TV Stick (and any device running
 * DreamPlayer). The stick is NOT a Chromecast and NOT a DLNA renderer, so the
 * only sender that can reach it is DreamPlayer itself: this service answers a
 * UDP broadcast discovery and accepts a small HTTP POST that launches the
 * video through the app's normal "Open with" pipeline (the same VIEW intent
 * path MainActivity already resolves).
 *
 * Sender side: [discoverDreamCast] in MulticastLockManager (broadcast
 * DREAMCAST_DISCOVER on DISCOVERY_PORT) + `dream_cast_client.dart` HTTP POSTs.
 *
 * The deviceIdentifier bound to the token prevents another app on the LAN
 * from driving the TV without first seeing the discovery reply.
 */
class DreamCastReceiverService : Service() {

    companion object {
        const val DISCOVERY_PORT = 51717
        const val PORT_PREF = "flutter.dreamplayer.dreamcastPort"
        private const val TAG = "DreamCastRx"
        private const val NOTIFICATION_ID = 5122
        private const val CHANNEL_ID = "dreamplayer_dreamcast"
    }

    private val executor = Executors.newCachedThreadPool()
    private var udpSocket: DatagramSocket? = null
    private var serverSocket: ServerSocket? = null
    private var httpPort: Int = 0
    private val token: String = UUID.randomUUID().toString().replace("-", "")

    @Volatile private var stopped = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        // Same free-port allocation the MPV loopback proxy uses: keep a port
        // across restarts so the sender can reconnect without re-discovery.
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val saved = prefs.getInt(PORT_PREF, 0)
        httpPort = if (saved in 50000..59999) saved else freePort(50000, 59999)
        if (saved != httpPort) prefs.edit().putInt(PORT_PREF, httpPort).apply()
        startForegroundWithNotice()
        startUdpResponder()
        startHttpServer()
        Log.i(TAG, "receiver up: udp=$DISCOVERY_PORT http=$httpPort token=$token")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int =
        START_STICKY

    override fun onDestroy() {
        stopped = true
        try {
            udpSocket?.close()
        } catch (_: Exception) {}
        try {
            serverSocket?.close()
        } catch (_: Exception) {}
        Log.i(TAG, "receiver stopped")
        super.onDestroy()
    }

    private fun freePort(from: Int, to: Int): Int {
        for (port in from..to) {
            try {
                ServerSocket(port).use { return port }
            } catch (_: Exception) {}
        }
        return ServerSocket(0).use { it.localPort }
    }

    private fun startForegroundWithNotice() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "TV receiver",
                    NotificationManager.IMPORTANCE_MIN,
                ).apply { setSound(null, null) },
            )
        }
        val notification: Notification = androidx.core.app.NotificationCompat.Builder(
            this,
            CHANNEL_ID,
        )
            .setSmallIcon(R.drawable.ic_stat_play)
            .setContentTitle("DreamPlayer is ready to receive")
            .setContentText("Phones can play videos on this TV")
            .setOngoing(true)
            .setSilent(true)
            .build()
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification,
            if (Build.VERSION.SDK_INT >= 34)
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            else 0,
        )
    }

    private fun startUdpResponder() {
        val thread = Thread {
            try {
                val socket = DatagramSocket(null)
                socket.reuseAddress = true
                socket.bind(InetSocketAddress(DISCOVERY_PORT))
                socket.soTimeout = 0
                udpSocket = socket
                Log.i(TAG, "discovery responder listening on $DISCOVERY_PORT")
                while (!stopped) {
                    try {
                        val buffer = ByteArray(512)
                        val packet = DatagramPacket(buffer, buffer.size)
                        socket.receive(packet)
                        val message =
                            String(packet.data, packet.offset, packet.length, Charsets.UTF_8).trim()
                        if (!message.startsWith("DREAMCAST_DISCOVER")) continue
                        val reply =
                            ("DREAMCAST_HERE\n$name\n$httpPort\n$token").toByteArray(Charsets.UTF_8)
                        socket.send(DatagramPacket(reply, reply.size, packet.address, packet.port))
                    } catch (_: Exception) {
                        if (!stopped) Log.w(TAG, "udp loop error")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "discovery responder failed: $e")
            }
        }.also {
            it.isDaemon = true
            it.start()
        }
    }

    private fun startHttpServer() {
        val thread = Thread {
            try {
                val server = ServerSocket()
                server.reuseAddress = true
                server.bind(InetSocketAddress(httpPort))
                serverSocket = server
                while (!stopped) {
                    val client = try {
                        server.accept()
                    } catch (_: Exception) {
                        break
                    }
                    executor.execute { handleClient(client) }
                }
            } catch (e: Exception) {
                Log.e(TAG, "http server failed: $e")
            }
        }.also {
            it.isDaemon = true
            it.start()
        }
    }

    private fun handleClient(socket: Socket) {
        try {
            socket.soTimeout = 5000
            val reader: InputStream = socket.getInputStream()
            val request = readHttpRequest(reader) ?: return
            val firstLine = request.firstLine
            val method = firstLine.substringBefore(' ').uppercase()
            val path = firstLine.substringAfter(' ').substringBefore(' ')
            val body = request.body
            Log.i(TAG, "http $method $path (${body.size}b)")
            val out: OutputStream = socket.getOutputStream()
            when {
                method == "GET" && path.startsWith("/ping") -> {
                    json(out, """{"name":"$name","port":$httpPort,"token":"$token"}""")
                }
                method == "POST" && path.startsWith("/play") && path.endsWith(token) -> {
                    val json = JSONObject(String(body, Charsets.UTF_8))
                    play(json)
                    json(out, """{"ok":true}""")
                }
                else -> json(out, 404, """{"error":"not_found"}""")
            }
        } catch (e: Exception) {
            Log.w(TAG, "client error: $e")
        } finally {
            try {
                socket.close()
            } catch (_: Exception) {}
        }
    }

    private fun readHttpRequest(input: InputStream): HttpRequest? {
        val header = StringBuilder()
        var bodyLength = 0
        while (header.length < 65536) {
            val ch = input.read()
            if (ch == -1) return null
            header.append(ch.toChar())
            if (header.endsWith("\r\n\r\n")) break
        }
        val lines = header.toString().split("\r\n")
        for (line in lines.drop(1)) {
            val match = line.uppercase().startsWith("CONTENT-LENGTH")
            if (match) bodyLength = line.substringAfter(':').trim().toIntOrNull() ?: 0
        }
        val body = ByteArray(bodyLength)
        var read = 0
        while (read < bodyLength) {
            val n = input.read(body, read, bodyLength - read)
            if (n == -1) break
            read += n
        }
        return HttpRequest(lines.firstOrNull() ?: "", body)
    }

    private class HttpRequest(val firstLine: String, val body: ByteArray)

    private fun json(out: OutputStream, body: String) = json(out, 200, body)

    private fun json(out: OutputStream, status: Int, body: String) {
        val reason = if (status == 200) "OK" else "ERROR"
        out.write(
            ("HTTP/1.1 $status $reason\r\n" +
                "Content-Type: application/json\r\n" +
                "Content-Length: ${body.toByteArray().size}\r\n" +
                "Connection: close\r\n\r\n$body").toByteArray(Charsets.UTF_8),
        )
        out.flush()
    }

    private val name: String
        get() = "${Build.MODEL} · ${Build.PRODUCT}".replace('\n', ' ')

    /** Launches the video through the normal VIEW-intent pipeline. */
    private fun play(json: JSONObject) {
        val uri = json.optString("uri", "")
        val path = json.optString("path", "")
        val title = json.optString("title", "Video")
        val target = uri.ifBlank { path }
        if (target.isBlank()) {
            Log.w(TAG, "play request with no target")
            return
        }
        val parsed = try {
            android.net.Uri.parse(target)
        } catch (_: Exception) {
            Log.w(TAG, "unparseable play uri")
            return
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(parsed, "video/*")
            setPackage(packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("dp_title", title)
        }
        // The Fire TV receiver may be showing the launcher (app backgrounded);
        // this both resumes the task and delivers onNewIntent → Dart open.
        startActivity(intent)
        Log.i(TAG, "launched $title")
    }
}
