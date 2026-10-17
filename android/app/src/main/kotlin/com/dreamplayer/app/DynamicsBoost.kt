package com.dreamplayer.app

import android.media.audiofx.DynamicsProcessing
import android.os.Build
import android.util.Log

/// Volume boost as a real compressor + limiter, instead of a fixed makeup gain.
///
/// #41, and the reason this file exists.
///
/// The previous implementation asked `LoudnessEnhancer` for up to 1500 mB of
/// makeup gain. Android's own documentation for that class says "signals
/// amplified outside of the sample range supported by the platform are
/// compressed" — it is a FIXED compressor the app cannot tune, with no limiter
/// stage, and its behaviour varies by vendor. A real Android audio player
/// (Lissen, PR #494) measured it clipping audibly from about 6 dB of boost on a
/// device where 15 dB is not remotely subtle.
///
/// The reported symptom was "background music plays, but the vocals/dialogue
/// become inaudible or disappear entirely". That is the signature of
/// over-compression, not of a level or a downmix problem: makeup gain lifts
/// everything, the loudest material (music, bass, LFE) hits the ceiling first,
/// and the compressor pulls gain back by as much as the loudest band demands —
/// applied to the WHOLE mix. Dialogue sits mid-level in the centre channel, so
/// it is dragged down along with everything else, while the distorted music
/// survives and reads as "louder".
///
/// `DynamicsProcessing` is the supported alternative: an explicit chain of
/// inputGain -> PreEQ -> MBC -> PostEQ -> Limiter, with every parameter
/// settable at runtime. The Limiter stage is documented as "commonly used to
/// protect the signal from overloading and distortion", which is exactly the
/// missing stage. Peaks get limited instead of clipped, so a high boost gets
/// *denser* rather than harsher.
///
/// Tuning below is Lissen's device-verified set, which stayed clean at 20 dB on
/// a phone that clipped at 6 dB with `LoudnessEnhancer`.
///
/// API shape notes, because the real one is not the obvious one:
/// * There is NO `(priority, audioSession)` constructor. A `Config` is required.
/// * The chain is PER CHANNEL, not a single shared descriptor. Everything is
///   reached through `Config.get*ByChannelIndex(...)`, mutated, and pushed back
///   with the matching `set*AllChannelsTo(...)`.
/// * `Stage.setInUse(...)` does not exist — "in use" is a Builder flag, while
///   `setEnabled(...)` is the per-stage runtime switch.
object DynamicsBoost {

    private const val TAG = "DynamicsBoost"

    /// Compressor: anything above -20 dBFS is squeezed 2:1 so the make-up gain
    /// downstream has somewhere to go before the ceiling.
    private const val COMP_THRESHOLD_DB = -20f

    /**
     * Band counts tried for the two (disabled) EQ stages, most-lenient first.
     *
     * Non-zero is tried before zero because several vendor HALs answer
     * bandCount = 0 with BAD_VALUE even when the stage is not in use, which
     * fails the whole DynamicsProcessing construction and drops the app onto
     * the LoudnessEnhancer fallback (issue #41). Zero stays in the list so a
     * stricter platform that insists on it still works.
     */
    private val BAND_COUNTS = intArrayOf(1, 0)
    private const val COMP_RATIO = 2f
    private const val COMP_ATTACK_MS = 10f
    private const val COMP_RELEASE_MS = 200f

    /// Limiter, last in chain. -1 dBFS leaves a hair of headroom so the hardest
    /// transient still does not wrap.
    private const val LIMIT_THRESHOLD_DB = -1f
    private const val LIMIT_RATIO = 10f
    private const val LIMIT_ATTACK_MS = 1f
    private const val LIMIT_RELEASE_MS = 60f

    /// API 28+. Below that we fall back to `LoudnessEnhancer` — see [supported].
    /// Note the app's minSdk is 24, so this guard is load-bearing and NOT dead
    /// code: dropping it would crash on Android 7/8 devices, the same trap
    /// already recorded for `SurfaceControl.Transaction.setDataSpace` and
    /// `setDesiredHdrHeadroom`.
    val supported: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P

    /// Attach a boost of [boostDb] dB to [sessionId], or return null so the
    /// caller can fall back to `LoudnessEnhancer`.
    ///
    /// [channelCount] is the track's real channel count. `Config`'s channel
    /// count has to match the AudioTrack or the effect fails to initialise,
    /// and a failed `AudioEffect` is easy to miss — so [isLive] probes it.
    ///
    /// The probe is `getId()`, which throws `IllegalStateException` when the
    /// effect is not initialised. NOT `getStatus()`: that method is absent from
    /// the android-37 stub, the same gap AGENTS.md records for
    /// `HdrCapabilities.isHdrSupported`, so referencing it would not compile.
    fun attach(sessionId: Int, boostDb: Float, channelCount: Int): DynamicsProcessing? {
        if (!supported) return null
        if (boostDb <= 0.01f) return null
        // Try the real layout first, then the two common fallbacks. A mono or
        // odd layout is more likely to reject 2 or 6 than the other way round.
        val channelCandidates = buildList {
            if (channelCount > 0) add(channelCount)
            add(2)
            add(6)
        }.distinct()
        // Band-count ladder, issue #41. Some vendor HALs reject bandCount = 0
        // with BAD_VALUE even for a stage that is not in use, surfacing as
        // "IllegalArgumentException: AudioEffect: bad parameter value" from the
        // DynamicsProcessing constructor. On a OnePlus Pad 2 that rejected both
        // ch=6 and ch=2, so EVERY attempt failed and the app silently fell
        // back to LoudnessEnhancer -- the exact component removed in 0.5.2
        // because it crushes dialogue out of the mix. Reporting that fallback
        // is what identified it.
        //
        // A non-zero band count on a disabled stage is harmless: the stage stays
        // off via inUse, it simply allocates no working bands. So try the safe
        // non-zero counts first and keep the original zeroes as a last resort.
        for (bands in BAND_COUNTS) {
            for (channels in channelCandidates) {
                val effect = build(sessionId, boostDb, channels, bands) ?: continue
                if (isLive(effect)) {
                    Log.i(
                        TAG,
                        "attached boost=${boostDb}dB ch=$channels bands=$bands session=$sessionId"
                    )
                    return effect
                }
                Log.w(TAG, "effect not initialised for ch=$channels bands=$bands")
                try {
                    effect.release()
                } catch (_: Exception) {
                }
            }
        }
        Log.w(
            TAG,
            "could not attach DynamicsProcessing for boost=${boostDb}dB " +
                "after trying channels=$channelCandidates bands=$BAND_COUNTS; " +
                "caller will fall back"
        )
        return null
    }

    /** True when the effect really attached; a dead AudioEffect is not usable. */
    private fun isLive(effect: DynamicsProcessing): Boolean = try {
        effect.id >= 0
    } catch (_: IllegalStateException) {
        false
    } catch (_: Exception) {
        false
    }

    private fun build(
        sessionId: Int,
        boostDb: Float,
        channels: Int,
        bands: Int,
    ): DynamicsProcessing? {
        return try {
            // variant, channel count, usePreEq/preEqBands, useMbc/mbcBands,
            // usePostEq/postEqBands, useLimiter.
            //
            // `bands` is applied to BOTH EQ stages even though they are disabled.
            // That looks redundant but is deliberate: passing 0 is what some
            // HALs reject outright, and it is the whole reason the effect never
            // attached. See attach().
            val config = DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_TIME_RESOLUTION,
                channels,
                false, bands,
                true, 1,
                false, bands,
                true,
            ).build()

            val band = config.getMbcBandByChannelIndex(0, 0)
            band.setEnabled(true)
            band.setThreshold(COMP_THRESHOLD_DB)
            band.setRatio(COMP_RATIO)
            band.setAttackTime(COMP_ATTACK_MS)
            band.setReleaseTime(COMP_RELEASE_MS)
            // The user's boost IS the make-up gain here. It is deliberately not
            // the net loudness change: material above COMP_THRESHOLD_DB is
            // compressed first, so the result is quieter than the dB figure
            // suggests. That is the whole point — dense, not harsh.
            band.setPostGain(boostDb)
            config.setMbcBandAllChannelsTo(0, band)

            config.getMbcByChannelIndex(0).apply { setEnabled(true) }
                .also { config.setMbcAllChannelsTo(it) }

            val limiter = config.getLimiterByChannelIndex(0)
            limiter.setEnabled(true)
            limiter.setThreshold(LIMIT_THRESHOLD_DB)
            limiter.setRatio(LIMIT_RATIO)
            limiter.setAttackTime(LIMIT_ATTACK_MS)
            limiter.setReleaseTime(LIMIT_RELEASE_MS)
            limiter.setPostGain(0f)
            config.setLimiterAllChannelsTo(limiter)

            // Gain lives on the compressor's make-up stage, so the chain input
            // stays at unity: one gain stage, in one place.
            config.setInputGainAllChannelsTo(0f)

            DynamicsProcessing(0, sessionId, config).apply { setEnabled(true) }
        } catch (e: Exception) {
            Log.w(TAG, "build failed for ch=$channels", e)
            null
        } catch (e: LinkageError) {
            Log.w(TAG, "linkage failed for ch=$channels", e)
            null
        }
    }
}