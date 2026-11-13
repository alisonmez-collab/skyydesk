package com.skyydesk.embed

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import com.elpo.skyydesk.ACT_REQUEST_MEDIA_PROJECTION
import com.elpo.skyydesk.ACT_STOP_SERVICE
import com.elpo.skyydesk.CaptureService
import com.elpo.skyydesk.EXT_SERVICE_CLASS
import com.elpo.skyydesk.InputService
import com.elpo.skyydesk.PermissionRequestTransparentActivity
import com.elpo.skyydesk.RdClipboardManager
import com.elpo.skyydesk.setCodecInfo
import ffi.FFI
import org.json.JSONObject
import kotlin.concurrent.thread

/**
 * SkyyDesk inside your Android application: SkyyDesk users can connect to this device, and
 * your application decides who gets in.
 *
 * ```
 * SkyyDesk.init(this)
 * SkyyDesk.listener = object : SkyyDesk.Listener {
 *     override fun onIncoming(connection: SkyyDesk.Connection) {
 *         if (!connection.authorized) askTheUser(connection)   // then accept() or close()
 *     }
 * }
 * SkyyDesk.start(activity, allowPassword = false)
 * ```
 *
 * The screen is shared through Android's screen-capture permission, which the user grants
 * when [start] is called. Touch and keys from the other side need the SkyyDesk input
 * accessibility service, which only the user can switch on: see [openInputSettings].
 */
object SkyyDesk {
    private const val TAG = "SkyyDesk"

    // Event kinds, the same numbers as SKYYDESK_EVENT_* in skyydesk.h.
    private const val EVENT_INCOMING = 1
    private const val EVENT_INCOMING_CLOSED = 2
    private const val EVENT_ENROLLED = 3

    /** A connection to this device, as the library reports it. */
    data class Connection(
        /** Pass to [accept] or [close]. */
        val id: Int,
        /** SkyyDesk ID of the device connecting. */
        val peerId: String,
        /** Name of the person or device connecting. */
        val name: String,
        /** False while the connection waits for [accept]. */
        val authorized: Boolean,
        val isFileTransfer: Boolean,
        /** Everything the library sent, for fields this class does not name. */
        val json: String,
    )

    /** Called on the main thread. */
    interface Listener {
        /** A connection arrived. If it is not [Connection.authorized], it waits for [accept] or [close]. */
        fun onIncoming(connection: Connection)

        /** A connection ended. */
        fun onClosed(connectionId: Int) {}

        /** The enroll key was tried: the device is in the key owner's address book, or why not. */
        fun onEnrolled(ok: Boolean, error: String?) {}

        /** Screen capture permission was granted or lost. */
        fun onScreenChanged(ready: Boolean) {}

        /** The input accessibility service was switched on or off. */
        fun onInputChanged(enabled: Boolean) {}

        /** Something the user should hear about failed, e.g. switching a voice call. */
        fun onError(message: String) {}
    }

    /**
     * Set it in your Activity's onCreate and clear it in onDestroy. A connection still waiting
     * for [accept] or [close] is reported again to the next listener, so a request that arrived
     * while no screen was showing is not lost.
     */
    @Volatile
    var listener: Listener? = null
        set(value) {
            field = value
            if (value != null) {
                val waiting = synchronized(pending) { pending.values.toList() }
                waiting.forEach { c -> post { onIncoming(c) } }
            }
        }

    // Connections waiting for accept or close, by id.
    private val pending = LinkedHashMap<Int, Connection>()

    private val main = Handler(Looper.getMainLooper())
    private var initialized = false
    internal var allowPassword = false
        private set
    internal var clipboard: RdClipboardManager? = null
        private set

    /**
     * Loads the library. Call once, before anything else here; Application.onCreate is a good
     * place. Settings and the device's SkyyDesk ID are kept in the application's files folder.
     * Returns 0, or -1 if the library could not start.
     */
    @Synchronized
    fun init(context: Context): Int {
        if (initialized) return 0
        val app = context.applicationContext
        FFI.onAppStart(app)
        val res = Native.init(app.filesDir.absolutePath, deviceName(app))
        if (res != 0) return res
        RdClipboardManager(app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).also {
            clipboard = it
            FFI.setClipboardManager(it)
        }
        InputService.stateListener = { enabled -> listener?.onInputChanged(enabled) }
        thread {
            try {
                setCodecInfo(app)
            } catch (e: Exception) {
                Log.e(TAG, "codec info: ${e.message}", e)
            }
        }
        initialized = true
        return 0
    }

    /**
     * Makes this device reachable. Android first asks the user to allow screen capture; once
     * they do, the capture service starts and the device appears online. With
     * [allowPassword] false, every connection waits for [accept]; otherwise the password also
     * lets it in.
     *
     * Throws IllegalStateException without a [listener]: a connection nobody can see or approve
     * must not be possible.
     */
    fun start(activity: Activity, allowPassword: Boolean) {
        check(initialized) { "SkyyDesk.init has not been called" }
        checkNotNull(listener) { "set SkyyDesk.listener before start" }
        this.allowPassword = allowPassword
        activity.startActivity(Intent(activity, PermissionRequestTransparentActivity::class.java).apply {
            action = ACT_REQUEST_MEDIA_PROJECTION
            putExtra(EXT_SERVICE_CLASS, HostService::class.java.name)
        })
    }

    /** Stops sharing the screen and takes the device offline until the next [start]. */
    fun stop(context: Context) {
        if (!initialized) return
        Native.stop()
        synchronized(pending) { pending.clear() }
        if (HostService.current == null) return
        context.startService(Intent(context, HostService::class.java).setAction(ACT_STOP_SERVICE))
    }

    /** Lets a waiting connection in. */
    fun accept(connectionId: Int) {
        synchronized(pending) { pending.remove(connectionId) }
        HostService.current?.cancelNotification(connectionId)
        if (HostService.current?.startCapture() != true) {
            // The connection opens anyway; without capture the other side sees no picture.
            Log.w(TAG, "screen capture did not start for connection $connectionId")
            post { onError("Screen capture is not running; call start again and allow screen recording.") }
        }
        Native.accept(connectionId)
    }

    /** Refuses a waiting connection or ends an open one. */
    fun close(connectionId: Int) {
        synchronized(pending) { pending.remove(connectionId) }
        HostService.current?.cancelNotification(connectionId)
        Native.close(connectionId)
    }

    /** This device's SkyyDesk ID. */
    val myId: String
        get() = Native.myId()

    /** The one-time password, if passwords are allowed. */
    val oneTimePassword: String
        get() = Native.oneTimePassword()

    fun newOneTimePassword() = Native.newOneTimePassword()

    /** Sets the permanent password; an empty string removes it. Returns 0, or -1. */
    fun setPermanentPassword(value: String): Int = Native.setPermanentPassword(value)

    /**
     * The enroll key from the SkyyDesk panel (Settings > Enroll keys): the device puts itself in
     * the key owner's address book. Kept, so it is needed once. Returns 0, or -1.
     */
    fun setEnrollKey(key: String): Int = Native.setOption("enroll-key", key)

    /**
     * The same settings as the SkyyDesk client's, e.g. `enable-keyboard`, `enable-clipboard`,
     * `enable-file-transfer`, `enable-audio`. Server and account settings are not changed here:
     * setOption returns -1 for them.
     */
    fun getOption(key: String): String = Native.getOption(key)

    fun setOption(key: String, value: String): Int = Native.setOption(key, value)

    /** Whether screen capture is running for a connection. */
    val isSharing: Boolean
        get() = CaptureService.isStart

    /** Whether touch and keys from the other side reach this device. */
    val isInputEnabled: Boolean
        get() = InputService.isOpen

    /** Opens Android's accessibility settings, where the user switches SkyyDesk input on. */
    fun openInputSettings(context: Context) {
        context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    internal fun post(action: Listener.() -> Unit) {
        main.post { listener?.action() }
    }

    internal fun onEvent(kind: Int, payload: String) {
        when (kind) {
            EVENT_INCOMING -> {
                val o = JSONObject(payload)
                val connection = Connection(
                    id = o.getInt("id"),
                    peerId = o.optString("peer_id"),
                    name = o.optString("name"),
                    authorized = o.optBoolean("authorized"),
                    isFileTransfer = o.optBoolean("is_file_transfer"),
                    json = payload,
                )
                synchronized(pending) {
                    if (connection.authorized) pending.remove(connection.id) else pending[connection.id] = connection
                }
                post { onIncoming(connection) }
            }
            EVENT_INCOMING_CLOSED -> payload.toIntOrNull()?.let { id ->
                synchronized(pending) { pending.remove(id) }
                HostService.current?.cancelNotification(id)
                post { onClosed(id) }
            }
            EVENT_ENROLLED -> {
                val o = JSONObject(payload)
                val ok = o.optBoolean("ok")
                val error = if (ok) null else o.optString("error")
                post { onEnrolled(ok, error) }
            }
            else -> Log.w(TAG, "unknown event $kind")
        }
    }

    private fun deviceName(context: Context): String {
        val name = Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
        return if (name.isNullOrBlank()) Build.MODEL else name
    }
}
