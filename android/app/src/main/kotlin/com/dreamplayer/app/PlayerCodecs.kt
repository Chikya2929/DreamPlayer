package com.dreamplayer.app

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.HttpDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import okhttp3.OkHttpClient
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager

/// Shared codec/decoder selection for the in-app playback surface (the hybrid
/// platform view) and the audio-passthrough path:
///  * FLAC always goes through the FFmpeg renderer (platform MediaCodec FLAC
///    buffers are too small for 24-bit multi-channel frames on some devices);
///  * the Dolby E-AC3 component is skipped on devices where the codec2
///    resource manager churns it (endless audio-renderer re-init, no AudioTrack);
///  * audio passthrough (TV): when enabled AND HDMI is detected, return empty
///    decoder lists for the compressed surround formats so AudioTrack
///    bitstreams them to the TV / soundbar / AVR;
///  * Dolby Vision falls back to HEVC when no DV decoder exists (P7/P8 base
///    layers are HDR10 HEVC).
@UnstableApi
object PlayerCodecs {

    /// Whether audio passthrough is active: user toggle ON in Settings AND an
    /// HDMI output (TV / soundbar / AVR) is currently connected.
    fun passthroughEnabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE,
        )
        if (!prefs.getBoolean("flutter.dreamplayer.audioPassthrough", false)) {
            return false
        }
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val hdmi = devices.any { d ->
            d.type == AudioDeviceInfo.TYPE_HDMI ||
                (Build.VERSION.SDK_INT >= 31 && d.type == AudioDeviceInfo.TYPE_HDMI_ARC) ||
                (Build.VERSION.SDK_INT >= 31 && d.type == AudioDeviceInfo.TYPE_HDMI_EARC)
        }
        android.util.Log.i("PlayerCodecs", "Audio passthrough: setting=ON, hdmi=$hdmi")
        return hdmi
    }

    fun isPassthroughFormat(mimeType: String?): Boolean = when (mimeType) {
        MimeTypes.AUDIO_AC3, MimeTypes.AUDIO_E_AC3, MimeTypes.AUDIO_E_AC3_JOC,
        MimeTypes.AUDIO_DTS, MimeTypes.AUDIO_DTS_HD, MimeTypes.AUDIO_TRUEHD -> true
        else -> false
    }

    /// OkHttp HTTP data source factory. When [allowSelfSigned] is set the
    /// client trusts any certificate (per-server opt-in for self-signed WebDAV
    /// servers); otherwise the system trust store is used.
    fun httpDataSourceFactory(allowSelfSigned: Boolean): HttpDataSource.Factory {
        if (!allowSelfSigned) {
            return OkHttpDataSource.Factory(OkHttpClient())
        }
        val trustAll = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) = Unit
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) = Unit
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        }
        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, arrayOf(trustAll), SecureRandom())
        val client = OkHttpClient.Builder()
            .sslSocketFactory(sslContext.socketFactory, trustAll)
            .hostnameVerifier { _, _ -> true }
            .build()
        return OkHttpDataSource.Factory(client)
    }

    fun decoderMode(context: Context): String {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE,
        )
        return prefs.getString("flutter.dreamplayer.decoderMode", null) ?: "auto"
    }

    private fun isSoftwareVideoDecoder(name: String): Boolean {
        val n = name.lowercase()
        return n.contains("google") || n.contains("ffmpeg") || n.startsWith("c2.android.")
    }

    /// Forces a Dolby Vision track onto the HEVC hardware decoder using the
    /// DV base layer (i.e. it plays as HDR10 instead of Dolby Vision).
    ///
    /// Set by the player view when the device's DV decoder produced no frames
    /// for a DV file — the Fire TV Stick's failure mode with DV profile 8
    /// remuxes (blank picture, audio plays, no error).
    ///
    /// The base-layer path is Media3's own: the HEVC decoder is configured with
    /// `video/hevc` (the codec's own mime type, see `MediaCodecVideoRenderer
    /// .getMediaFormat`), so it decodes the HEVC base layer of the DV stream.
    /// The base layer of a P4/P8 file IS HDR10 HEVC, and the container's CSD
    /// for an MKV DV track is the HEVC configuration record (MatroskaExtractor
    /// keeps the `hvcC` data and only swaps the mime type + codecs string), so
    /// the decoder gets exactly what it needs.
    @Volatile
    var forceHevcBaseLayer: Boolean = false

    /// Remembered Dolby Vision base-layer fallbacks.
    ///
    /// Keyed by the track's codecs string (e.g. `dvhe.08.06`), so a device
    /// that cannot render ONE Dolby Vision profile keeps using the HEVC base
    /// layer for that profile only — every other DV profile still gets the
    /// device's real DV decoder.
    ///
    /// This lives in its OWN SharedPreferences file on purpose: Flutter's
    /// `shared_preferences` plugin owns `FlutterSharedPreferences`, and the app
    /// must not write unknown keys into it.
    private const val DV_FALLBACK_PREFS = "dreamplayer_dv"

    /// Whether [codecs] has to be played through the HEVC base layer on this
    /// device (remembered from an earlier black-picture retry).
    fun dvFallbackEnabled(context: Context, codecs: String?): Boolean {
        if (codecs.isNullOrEmpty()) return false
        return context.getSharedPreferences(DV_FALLBACK_PREFS, Context.MODE_PRIVATE)
            .getBoolean(codecs, false)
    }

    /// Remembers (or forgets) that [codecs] has to be played through the HEVC
    /// base layer on this device.
    fun setDvFallback(context: Context, codecs: String?, enabled: Boolean) {
        if (codecs.isNullOrEmpty()) return
        context.getSharedPreferences(DV_FALLBACK_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(codecs, enabled)
            .apply()
    }

    /// Builds the decoder selector.
    ///
    /// [videoFormatProvider] returns the currently selected video track's
    /// format (null when unknown). The selector needs it because Media3 asks
    /// for decoders by MIME type only — the profile/level/resolution that
    /// decides whether a DV decoder can actually decode the file is only known
    /// from the format.
    fun mediaCodecSelector(
        context: Context,
        videoFormatProvider: () -> Format? = { null },
    ): MediaCodecSelector {
        return MediaCodecSelector { mimeType, requiresSecureDecoder, requiresTunnelingDecoder ->
            // Read prefs LIVE on every query so a mode toggle takes effect on
            // the next `open()` without recreating the whole player view. Same
            // for passthrough (HDMI may be plugged/unplugged between files).
            val modeLive = decoderMode(context)
            val passthroughLive = passthroughEnabled(context)
            val isVideo = mimeType?.startsWith("video/") == true
            fun filterByMode(list: List<MediaCodecInfo>): List<MediaCodecInfo> = when (modeLive) {
                "hw" -> list.filterNot { isSoftwareVideoDecoder(it.name) }
                "sw" -> list.filter { isSoftwareVideoDecoder(it.name) }
                // FFmpeg video: empty for video so Media3 uses the FfmpegVideoRenderer
                // extension; audio decoders stay normal (MediaCodec for best quality).
                "ffmpeg_video" -> if (isVideo) emptyList() else list
                else -> list
            }
            when {
                mimeType == MimeTypes.AUDIO_FLAC -> emptyList()
                // Passthrough: return empty for compressed surround formats so
                // DefaultAudioSink routes them to AudioTrack passthrough mode.
                // Checked BEFORE the FFmpeg-audio branch on purpose: on a TV
                // this must stay a raw bitstream, not get decoded to PCM.
                passthroughLive && isPassthroughFormat(mimeType) -> emptyList()
                mimeType == MimeTypes.AUDIO_E_AC3 || mimeType == MimeTypes.AUDIO_E_AC3_JOC ->
                    MediaCodecSelector.DEFAULT.getDecoderInfos(
                        mimeType,
                        requiresSecureDecoder,
                        requiresTunnelingDecoder,
                    ).filterNot { it.name.contains("dolby", ignoreCase = true) }
                // Dolby Vision: pick a decoder that can actually decode THIS
                // track, preferring the device's DV decoder (true Dolby Vision)
                // and falling back to the HEVC base layer when it cannot.
                //
                // Media3 takes the FIRST decoder the selector returns and never
                // re-checks it: the "soft match" list it builds (DV decoders +
                // the alternative-mime HEVC decoders) is only re-sorted for the
                // track-selection check, not for codec creation. So a DV
                // decoder that cannot handle the file's profile/level yields a
                // BLANK picture with the audio playing and no error at all —
                // exactly the Fire TV Stick's symptom with DV profile 8
                // remuxes. The base layer of a P4/P8 file IS HDR10 HEVC, so it
                // is a working fallback whenever the DV decoder is unusable.
                mimeType == MimeTypes.VIDEO_DOLBY_VISION -> {
                    val format = videoFormatProvider()
                    val codecs = format?.codecs
                    val dv = filterByMode(
                        MediaCodecSelector.DEFAULT.getDecoderInfos(
                            mimeType,
                            requiresSecureDecoder,
                            requiresTunnelingDecoder,
                        ),
                    )
                    // The device's DV decoder rendered nothing for this profile
                    // before (or the profile is known to be broken here): play
                    // the base layer straight away. Media3 configures the
                    // decoder with ITS OWN mime type, so the HEVC decoder is
                    // set up as `video/hevc` and decodes the base layer.
                    val forced = forceHevcBaseLayer || dvFallbackEnabled(context, codecs)
                    if (forced) {
                        // The base layer of a DV profile is H.264 / H.265 / AV1
                        // depending on the profile (P4/P8 → HEVC, P9 → H.264,
                        // P10 → AV1). Ask Media3 which one this track needs.
                        val baseLayerMime = format?.let {
                            androidx.media3.exoplayer.mediacodec.MediaCodecUtil
                                .getAlternativeCodecMimeType(it)
                        } ?: MimeTypes.VIDEO_H265
                        val baseLayer = filterByMode(
                            MediaCodecSelector.DEFAULT.getDecoderInfos(
                                baseLayerMime,
                                requiresSecureDecoder,
                                requiresTunnelingDecoder,
                            ),
                        )
                        android.util.Log.i(
                            "PlayerCodecs",
                            "Dolby Vision: $baseLayerMime base layer forced for $codecs",
                        )
                        baseLayer
                    } else if (dv.isEmpty()) {
                        // No Dolby Vision decoder at all: the base layer is the
                        // only way to get a picture.
                        filterByMode(
                            MediaCodecSelector.DEFAULT.getDecoderInfos(
                                MimeTypes.VIDEO_H265,
                                requiresSecureDecoder,
                                requiresTunnelingDecoder,
                            ),
                        )
                    } else if (format != null &&
                        dv.none { it.isFormatFunctionallySupported(context, format) }
                    ) {
                        // Not a single DV decoder can decode this profile, but
                        // the base layer can: return an EMPTY list for the DV
                        // mime type so Media3's soft match picks the base-layer
                        // decoder instead of the unusable DV one.
                        //
                        // The FUNCTIONAL check is used on purpose (the same one
                        // Media3 sorts decoders by): the strict check also
                        // rejects decoders that merely under-report their
                        // capabilities, and losing true Dolby Vision on a
                        // device that can do it is worse than a late fallback.
                        val hevc = filterByMode(
                            MediaCodecSelector.DEFAULT.getDecoderInfos(
                                MimeTypes.VIDEO_H265,
                                requiresSecureDecoder,
                                requiresTunnelingDecoder,
                            ),
                        )
                        if (hevc.isNotEmpty()) {
                            android.util.Log.w(
                                "PlayerCodecs",
                                "Dolby Vision: no DV decoder supports $codecs " +
                                    "- using the HEVC base layer",
                            )
                            emptyList()
                        } else {
                            dv
                        }
                    } else {
                        // True Dolby Vision stays primary.
                        dv
                    }
                }
                isVideo -> filterByMode(
                    MediaCodecSelector.DEFAULT.getDecoderInfos(
                        mimeType,
                        requiresSecureDecoder,
                        requiresTunnelingDecoder,
                    ),
                )
                else -> MediaCodecSelector.DEFAULT.getDecoderInfos(
                    mimeType,
                    requiresSecureDecoder,
                    requiresTunnelingDecoder,
                )
            }
        }
    }
}