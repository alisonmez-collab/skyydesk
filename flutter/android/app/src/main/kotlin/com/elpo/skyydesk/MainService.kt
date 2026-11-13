package com.elpo.skyydesk

import ffi.FFI

/**
 * The SkyyDesk app's capture service: CaptureService, reporting to the Flutter screen.
 */

import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity

class MainService : CaptureService() {

    override val notificationIcon: Int
        get() = R.mipmap.ic_stat_logo

    override val notificationColor: Int
        get() = ContextCompat.getColor(this, R.color.primary)

    override fun notificationIntent(): Intent {
        return Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            putExtra("type", type)
        }
    }

    override fun startServer() {
        // keep the config dir same with flutter
        val prefs = applicationContext.getSharedPreferences(KEY_SHARED_PREFERENCES, FlutterActivity.MODE_PRIVATE)
        val configPath = prefs.getString(KEY_APP_DIR_CONFIG_PATH, "") ?: ""
        FFI.startServer(configPath, "")
    }

    override fun onStateChanged(name: String, value: Boolean) {
        MainActivity.flutterMethodChannel?.invokeMethod(
            "on_state_changed",
            mapOf("name" to name, "value" to value.toString())
        )
    }

    override fun onCaptureChanged(started: Boolean) {
        MainActivity.rdClipboardManager?.setCaptureStarted(started)
    }

    override fun onError(title: String, text: String) {
        MainActivity.flutterMethodChannel?.invokeMethod("msgbox", mapOf(
            "type" to "custom-nook-nocancel-hasclose-error",
            "title" to title,
            "text" to text))
    }

    override fun onServiceDestroy() {
        stopService(Intent(this, FloatingWindowService::class.java))
    }
}
