package com.dreamplayer.app

import android.content.Context
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider

/**
 * The Cast options the Google Cast SDK reads at startup.
 *
 * The SDK looks this class up through the manifest entry
 * `com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME` — the
 * app id is the **Default Media Receiver** (`CC1AD845`), which needs no Cast
 * Console registration. A custom receiver would need a registered app id and
 * a hosted receiver page, which a sideloaded build has no way to publish.
 */
class CastOptionsProvider : OptionsProvider {

    override fun getCastOptions(context: Context): CastOptions {
        return CastOptions.Builder()
            .setReceiverApplicationId(CastManager.RECEIVER_APP_ID)
            .setStopReceiverApplicationWhenEndingSession(true)
            .build()
    }

    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? {
        return null
    }
}
