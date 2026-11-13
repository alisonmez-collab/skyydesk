package com.skyydesk.embed

// The library's functions (src/skyydesk_capi.rs, module `android`). Public members of an
// internal object keep their JVM names, which the library looks up.
internal object Native {
    init {
        System.loadLibrary("skyydesk")
    }

    @JvmStatic external fun init(appDir: String, deviceName: String): Int
    @JvmStatic external fun start(allowPassword: Boolean): Int
    @JvmStatic external fun myId(): String
    @JvmStatic external fun oneTimePassword(): String
    @JvmStatic external fun newOneTimePassword()
    @JvmStatic external fun setPermanentPassword(value: String): Int
    @JvmStatic external fun getOption(key: String): String
    @JvmStatic external fun setOption(key: String, value: String): Int
    @JvmStatic external fun accept(connection: Int)
    @JvmStatic external fun close(connection: Int)
    @JvmStatic external fun stop()

    /** Called by the library on its own threads. */
    @JvmStatic
    fun onEvent(kind: Int, payload: String) {
        SkyyDesk.onEvent(kind, payload)
    }
}
