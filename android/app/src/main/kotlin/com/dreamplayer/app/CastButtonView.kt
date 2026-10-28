package com.dreamplayer.app

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.mediarouter.app.MediaRouteButton
import androidx.mediarouter.media.MediaRouteSelector
import androidx.mediarouter.media.MediaRouter
import com.google.android.gms.cast.framework.CastButtonFactory
import com.google.android.gms.cast.framework.CastContext
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * The Cast button (the route picker) in a platform view.
 *
 * The Cast SDK 22.x no longer ships its own button widget: the button is
 * AndroidX's `MediaRouteButton`, and the SDK wires the Cast route selector
 * into it through `CastButtonFactory`. The button is the route picker —
 * tapping it lists the Cast devices on the network and starts a session when
 * one is chosen.
 *
 * It stays hidden while no route is available, so the player chrome does not
 * grow an inert icon on a device with nothing to cast to.
 */
class CastButtonViewFactory(
    private val context: Context,
    messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return CastButtonView(context)
    }
}

class CastButtonView(context: Context) : PlatformView {

    private val button: MediaRouteButton = MediaRouteButton(context)

    private val container: FrameLayout = FrameLayout(context)

    private val routeCallback = object : MediaRouter.Callback() {
        override fun onRouteAdded(router: MediaRouter, route: MediaRouter.RouteInfo) {
            updateVisibility(router)
        }

        override fun onRouteRemoved(router: MediaRouter, route: MediaRouter.RouteInfo) {
            updateVisibility(router)
        }

        override fun onProviderAdded(router: MediaRouter, provider: MediaRouter.ProviderInfo) {
            updateVisibility(router)
        }

        override fun onProviderRemoved(router: MediaRouter, provider: MediaRouter.ProviderInfo) {
            updateVisibility(router)
        }
    }

    /** The router the route callback was registered on. */
    private var router: MediaRouter? = null

    /**
     * The button is only useful when there is something to pick, so it stays
     * hidden until a Cast route shows up on the network.
     */
    private fun updateVisibility(router: MediaRouter) {
        val routes = try {
            router.routes
        } catch (_: Throwable) {
            null
        }
        button.visibility = if (routes != null && routes.isNotEmpty()) {
            View.VISIBLE
        } else {
            View.GONE
        }
    }

    init {
        try {
            // Let the SDK install its route selector and dialog factory.
            CastButtonFactory.setUpMediaRouteButton(context, button)
        } catch (_: Throwable) {
        }
        button.layoutParams = ViewGroup.LayoutParams(dp(40), dp(40))
        try {
            // The stock indicator follows the light theme and disappears on
            // the player's black chrome, so it is replaced with a white one.
            button.setRemoteIndicatorDrawable(
                androidx.core.content.ContextCompat.getDrawable(context, R.drawable.ic_cast_white),
            )
        } catch (_: Throwable) {
        }
        container.addView(button)
        try {
            // The Cast SDK's merged selector is what carries the video
            // categories, so the availability callback fires for Cast routes.
            val castContext: CastContext = CastContext.getSharedInstance(context)
            val selector = castContext.mergedSelector
            if (selector != null) {
                val mediaRouter: MediaRouter = MediaRouter.getInstance(context)
                router = mediaRouter
                mediaRouter.addCallback(selector, routeCallback)
                updateVisibility(mediaRouter)
            }
        } catch (_: Throwable) {
        }
    }

    override fun getView(): View {
        return container
    }

    override fun dispose() {
        try {
            router?.removeCallback(routeCallback)
        } catch (_: Throwable) {
        }
    }

    private fun dp(value: Int): Int {
        return (value * container.resources.displayMetrics.density).toInt()
    }
}
