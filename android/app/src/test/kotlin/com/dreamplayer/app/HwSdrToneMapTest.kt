package com.dreamplayer.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Unit tests for the hardware SDR tone-mapping decision (issue #55).
///
/// The setting asks the video codec to output standard SDR
/// (`KEY_COLOR_TRANSFER_REQUEST = COLOR_TRANSFER_SDR_VIDEO`) instead of the
/// source's HDR/Dolby-Vision signal, so the system's display colour modes
/// apply again. The request is only worth sending when
///  * the user asked for it,
///  * the device has the key (API 31+), and
///  * the track really is HDR or Dolby Vision.
///
/// The last one is the subtle part: a Dolby Vision MKV without the `Colour`
/// element carries NO colour info at all (Media3's MatroskaExtractor never
/// reads the HEVC VUI), so a colour-info-only check would silently skip
/// exactly the files the feature is for.
class HwSdrToneMapTest {

    private fun request(
        enabled: Boolean = true,
        sdkInt: Int = 31,
        mimeType: String? = "video/hevc",
        codecs: String? = "hev1.2.4.L153.B0",
        colorTransfer: Int? = 6,
    ) = HwSdrToneMap.shouldRequest(
        enabled = enabled,
        sdkInt = sdkInt,
        mimeType = mimeType,
        codecs = codecs,
        colorTransfer = colorTransfer,
    )

    @Test
    fun `disabled setting never requests`() {
        assertFalse(request(enabled = false))
    }

    @Test
    fun `old Android has no transfer request key`() {
        // KEY_COLOR_TRANSFER_REQUEST was added in API 31.
        assertFalse(request(sdkInt = 30))
        assertTrue(request(sdkInt = 31))
    }

    @Test
    fun `hdr10 and hlg are requested`() {
        assertTrue(request(colorTransfer = 6))
        assertTrue(request(colorTransfer = 7))
    }

    @Test
    fun `sdr content is left alone`() {
        assertFalse(request(colorTransfer = 2))
        assertFalse(request(colorTransfer = null))
    }

    @Test
    fun `dolby vision without colour info is still requested`() {
        // The Colour-element-less DV MKV: no colorInfo at all.
        assertTrue(
            request(
                mimeType = "video/dolby-vision",
                codecs = "dvhe.08.06",
                colorTransfer = null,
            ),
        )
        assertTrue(
            request(
                mimeType = "video/hevc",
                codecs = "dvav.09.06",
                colorTransfer = null,
            ),
        )
    }

    @Test
    fun `audio tracks are never touched`() {
        assertFalse(request(mimeType = "audio/mp4a-latm", colorTransfer = null))
    }
}
