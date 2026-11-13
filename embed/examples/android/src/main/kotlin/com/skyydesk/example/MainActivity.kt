package com.skyydesk.example

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.skyydesk.embed.SkyyDesk

/**
 * Shows this device's SkyyDesk ID, makes it reachable, and asks before letting anyone in.
 * Started with an enroll key (adb shell am start ... --es key sdk_...), the device also puts
 * itself in the key owner's address book.
 */
class MainActivity : Activity(), SkyyDesk.Listener {

    private lateinit var status: TextView
    private lateinit var input: Button
    // The last event worth reading. A redraw from another event (the capture stopping right after
    // a connection closes) must not wipe it.
    private var note = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pad = (16 * resources.displayMetrics.density).toInt()
        val key = EditText(this).apply {
            hint = "Enroll key (optional)"
            setText(intent.getStringExtra("key") ?: "")
        }
        status = TextView(this).apply { textSize = 18f }
        input = Button(this).apply { setOnClickListener { SkyyDesk.openInputSettings(this@MainActivity) } }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad, pad, pad)
            addView(status)
            addView(key)
            addView(Button(context).apply {
                text = "Allow connections"
                setOnClickListener {
                    if (key.text.isNotBlank()) SkyyDesk.setEnrollKey(key.text.toString().trim())
                    SkyyDesk.start(this@MainActivity, allowPassword = false)
                }
            })
            addView(Button(context).apply {
                text = "Stop"
                setOnClickListener { SkyyDesk.stop(this@MainActivity) }
            })
            addView(input)
            // Android 15 draws apps under the status and navigation bars; without this the ID
            // and the enroll key field sat behind them.
            ViewCompat.setOnApplyWindowInsetsListener(this) { v, insets ->
                val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
                v.setPadding(pad + bars.left, pad + bars.top, pad + bars.right, pad + bars.bottom)
                insets
            }
        })
        SkyyDesk.listener = this
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        refresh()
    }

    override fun onDestroy() {
        if (SkyyDesk.listener === this) SkyyDesk.listener = null
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    private fun refresh(newNote: String? = null) {
        if (newNote != null) note = newNote
        status.text = "SkyyDesk ID ${SkyyDesk.myId}\n" +
            (if (SkyyDesk.isSharing) "Screen is being shared" else "Not sharing") +
            (if (note.isEmpty()) "" else "\n$note")
        input.text = if (SkyyDesk.isInputEnabled) "Remote touch is on" else "Turn on remote touch"
    }

    override fun onIncoming(connection: SkyyDesk.Connection) {
        refresh()
        if (connection.authorized || isFinishing || isDestroyed) return
        AlertDialog.Builder(this)
            .setTitle("${connection.name} (${connection.peerId})")
            .setMessage("wants to connect to this device. Allow?")
            .setPositiveButton("Allow") { _, _ -> SkyyDesk.accept(connection.id) }
            .setNegativeButton("Deny") { _, _ -> SkyyDesk.close(connection.id) }
            .setCancelable(false)
            .show()
    }

    override fun onClosed(connectionId: Int) = refresh("Connection $connectionId closed")

    override fun onEnrolled(ok: Boolean, error: String?) =
        refresh(if (ok) "Added to the address book" else "Enroll failed: $error")

    override fun onScreenChanged(ready: Boolean) = refresh()

    override fun onInputChanged(enabled: Boolean) = refresh()

    override fun onError(message: String) = refresh(message)
}
