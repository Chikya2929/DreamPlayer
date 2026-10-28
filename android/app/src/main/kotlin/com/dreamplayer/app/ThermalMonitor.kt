package com.dreamplayer.app

import android.content.Context
import android.os.Build
import android.os.PowerManager
import io.flutter.plugin.common.MethodChannel

/**
 * Reads the device's thermal headroom.
 *
 * `PowerManager.getThermalHeadroom(forecastSeconds)` returns a value from
 * 0 (about to throttle) to 1 (comfortable). It is the public Android API we
 * use to keep the GPU-heavy MPV features (Anime4K, frame interpolation) from
 * cooking the phone; the policy that turns the number into a quality tier
 * lives in Dart (`lib/utils/thermal_policy.dart`) so it can be unit-tested
 * without a device.
 *
 * `getThermalHeadroom` is API 30+. On older devices the channel answers -1,
 * which the Dart side reads as "no reading available" and leaves the quality
 * alone.
 */
class ThermalMonitor(private val context: Context) {

    companion object {
        const val CHANNEL = "dreamplayer/thermal"

        /** Forecast window handed to the platform, in seconds. */
        private const val FORECAST_SECONDS = 10
    }

    fun configure(channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getThermalHeadroom" -> result.success(readHeadroom())
                else -> result.notImplemented()
            }
        }
    }

    private fun readHeadroom(): Double {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return -1.0
        return try {
            val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (power == null) {
                -1.0
            } else {
                power.getThermalHeadroom(FORECAST_SECONDS).toDouble()
            }
        } catch (e: Throwable) {
            -1.0
        }
    }
}
