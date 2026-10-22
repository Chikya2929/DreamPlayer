package com.dreamplayer.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The install half of the in-app updater for the sideload (GitHub Releases)
 * build. Play Core's in-app update API is deliberately not used: it only works
 * for Play-installed apps, and this app is distributed as an APK.
 *
 * Dart checks the release feed and downloads the APK into the cache; this class
 * only turns that file into a package-installer intent, which needs a
 * FileProvider URI and (API 26+) the "install unknown apps" grant.
 */
class AppUpdater(private val activity: Activity) {
    companion object {
        const val CHANNEL = "dreamplayer/updater"
        private const val DIR = "updates"
    }

    fun configure(channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "currentAbi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a")
                "canInstall" -> result.success(canInstall())
                "installApk" -> {
                    val fileName = call.argument<String>("fileName")
                    if (fileName.isNullOrBlank() || fileName.contains('/') || fileName.contains('\\')) {
                        result.error("bad_args", "fileName is required", null)
                        return@setMethodCallHandler
                    }
                    if (!canInstall()) {
                        // Not an error in the Dart sense: the caller opens the
                        // settings page and retries once the user returns.
                        result.error("permission_required", "Unknown sources is off", null)
                        return@setMethodCallHandler
                    }
                    try {
                        installApk(fileName)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("install_failed", e.message, null)
                    }
                }
                "openInstallPermissionSettings" -> {
                    openInstallPermissionSettings()
                    result.success(null)
                }
                "deleteApk" -> {
                    call.argument<String>("fileName")?.let { deleteApk(it) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            activity.packageManager.canRequestPackageInstalls()

    private fun installApk(fileName: String) {
        val file = File(File(activity.cacheDir, DIR), fileName)
        check(file.isFile) { "APK not found: ${file.name}" }
        val uri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(intent)
    }

    private fun openInstallPermissionSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}"),
            )
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${activity.packageName}"),
            )
        }
        activity.startActivity(intent)
    }

    private fun deleteApk(fileName: String) {
        runCatching { File(File(activity.cacheDir, DIR), fileName).delete() }
    }
}
