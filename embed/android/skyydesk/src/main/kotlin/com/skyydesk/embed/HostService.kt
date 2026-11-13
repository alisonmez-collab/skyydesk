package com.skyydesk.embed

import android.content.Intent
import android.util.Log
import com.elpo.skyydesk.CaptureService

/**
 * The capture service of an application that embeds SkyyDesk. Started by [SkyyDesk.start] once
 * the user allows screen capture; the core runs inside it.
 */
class HostService : CaptureService() {

    companion object {
        @Volatile
        internal var current: HostService? = null
            private set
    }

    // Applications can replace both with resources of the same name.
    override val notificationIcon: Int
        get() = R.drawable.skyydesk_notification

    override val notificationColor: Int
        get() = getColor(R.color.skyydesk_notification)

    override fun notificationIntent(): Intent {
        return packageManager.getLaunchIntentForPackage(packageName) ?: Intent()
    }

    override fun onCreate() {
        current = this
        super.onCreate()
    }

    override fun startServer() {
        val res = Native.start(SkyyDesk.allowPassword)
        if (res != 0) {
            Log.e("SkyyDesk", "start failed: $res")
        }
    }

    override fun onStateChanged(name: String, value: Boolean) {
        when (name) {
            "media" -> SkyyDesk.post { onScreenChanged(value) }
            "input" -> SkyyDesk.post { onInputChanged(value) }
        }
    }

    override fun onCaptureChanged(started: Boolean) {
        SkyyDesk.clipboard?.setCaptureStarted(started)
    }

    override fun onError(title: String, text: String) {
        SkyyDesk.post { onError(text) }
    }

    override fun onDestroy() {
        super.onDestroy()
        current = null
    }
}
