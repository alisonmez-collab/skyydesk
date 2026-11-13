package com.elpo.skyydesk

// Shared by the SkyyDesk app and the embedding package: nothing here knows about Flutter.

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioRecord
import android.media.AudioRecord.READ_BLOCKING
import android.media.MediaCodecInfo
import android.media.MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
import android.media.MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar
import android.media.MediaCodecList
import android.os.Build
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.annotation.RequiresApi
import ffi.FFI
import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.util.*

// intent action, extra
const val ACT_REQUEST_MEDIA_PROJECTION = "REQUEST_MEDIA_PROJECTION"
const val ACT_INIT_MEDIA_PROJECTION_AND_SERVICE = "INIT_MEDIA_PROJECTION_AND_SERVICE"
const val ACT_LOGIN_REQ_NOTIFY = "LOGIN_REQ_NOTIFY"
const val ACT_STOP_SERVICE = "STOP_SERVICE"
const val EXT_INIT_FROM_BOOT = "EXT_INIT_FROM_BOOT"
const val EXT_MEDIA_PROJECTION_RES_INTENT = "MEDIA_PROJECTION_RES_INTENT"
const val EXT_LOGIN_REQ_NOTIFY = "LOGIN_REQ_NOTIFY"
// Which CaptureService the permission activity starts once the user consents.
const val EXT_SERVICE_CLASS = "SERVICE_CLASS"

// Activity requestCode
const val REQ_REQUEST_MEDIA_PROJECTION = 201

// Activity responseCode
const val RES_FAILED = -100

@SuppressLint("ConstantLocale")
val LOCAL_NAME = Locale.getDefault().toString()
val SCREEN_INFO = Info(0, 0, 1, 200)

data class Info(
    var width: Int, var height: Int, var scale: Int, var dpi: Int
)

fun isSupportVoiceCall(): Boolean {
    // https://developer.android.com/reference/android/media/MediaRecorder.AudioSource#VOICE_COMMUNICATION
    return Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
}

class AudioReader(val bufSize: Int, private val maxFrames: Int) {
    private var currentPos = 0
    private val bufferPool: Array<ByteBuffer>

    init {
        if (maxFrames < 0 || maxFrames > 32) {
            throw Exception("Out of bounds")
        }
        if (bufSize <= 0) {
            throw Exception("Wrong bufSize")
        }
        bufferPool = Array(maxFrames) {
            ByteBuffer.allocateDirect(bufSize)
        }
    }

    private fun next() {
        currentPos++
        if (currentPos >= maxFrames) {
            currentPos = 0
        }
    }

    @RequiresApi(Build.VERSION_CODES.M)
    fun readSync(audioRecord: AudioRecord): ByteBuffer? {
        val buffer = bufferPool[currentPos]
        val res = audioRecord.read(buffer, bufSize, READ_BLOCKING)
        return if (res > 0) {
            next()
            buffer
        } else {
            null
        }
    }
}


fun getScreenSize(windowManager: WindowManager) : Pair<Int, Int>{
    var w = 0
    var h = 0
    @Suppress("DEPRECATION")
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val m = windowManager.maximumWindowMetrics
        w = m.bounds.width()
        h = m.bounds.height()
    } else {
        val dm = DisplayMetrics()
        windowManager.defaultDisplay.getRealMetrics(dm)
        w = dm.widthPixels
        h = dm.heightPixels
    }
    return Pair(w, h)
}

 fun translate(input: String): String {
    Log.d("common", "translate:$LOCAL_NAME")
    return FFI.translateLocale(LOCAL_NAME, input)
}

/** Tells the core which hardware video encoders this device has. */
fun setCodecInfo(context: Context) {
    val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
    val codecs = codecList.codecInfos
    val codecArray = JSONArray()

    val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    val wh = getScreenSize(windowManager)
    var w = wh.first
    var h = wh.second
    val align = 64
    w = (w + align - 1) / align * align
    h = (h + align - 1) / align * align
    codecs.forEach { codec ->
        val codecObject = JSONObject()
        codecObject.put("name", codec.name)
        codecObject.put("is_encoder", codec.isEncoder)
        var hw: Boolean? = null;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            hw = codec.isHardwareAccelerated
        } else {
            // https://chromium.googlesource.com/external/webrtc/+/HEAD/sdk/android/src/java/org/webrtc/MediaCodecUtils.java#29
            // https://chromium.googlesource.com/external/webrtc/+/master/sdk/android/api/org/webrtc/HardwareVideoEncoderFactory.java#229
            if (listOf("OMX.google.", "OMX.SEC.", "c2.android").any { codec.name.startsWith(it, true) }) {
                hw = false
            } else if (listOf("c2.qti", "OMX.qcom.video", "OMX.Exynos", "OMX.hisi", "OMX.MTK", "OMX.Intel", "OMX.Nvidia").any { codec.name.startsWith(it, true) }) {
                hw = true
            }
        }
        if (hw != true) {
            return@forEach
        }
        codecObject.put("hw", hw)
        var mime_type = ""
        codec.supportedTypes.forEach { type ->
            if (listOf("video/avc", "video/hevc").contains(type)) { // "video/x-vnd.on2.vp8", "video/x-vnd.on2.vp9", "video/av01"
                mime_type = type;
            }
        }
        if (mime_type.isNotEmpty()) {
            codecObject.put("mime_type", mime_type)
            val caps = codec.getCapabilitiesForType(mime_type)
            if (codec.isEncoder) {
                // Encoder's max_height and max_width are interchangeable
                if (!caps.videoCapabilities.isSizeSupported(w,h) && !caps.videoCapabilities.isSizeSupported(h,w)) {
                    return@forEach
                }
            }
            codecObject.put("min_width", caps.videoCapabilities.supportedWidths.lower)
            codecObject.put("max_width", caps.videoCapabilities.supportedWidths.upper)
            codecObject.put("min_height", caps.videoCapabilities.supportedHeights.lower)
            codecObject.put("max_height", caps.videoCapabilities.supportedHeights.upper)
            val surface = caps.colorFormats.contains(COLOR_FormatSurface);
            codecObject.put("surface", surface)
            val nv12 = caps.colorFormats.contains(COLOR_FormatYUV420SemiPlanar)
            codecObject.put("nv12", nv12)
            if (!(nv12 || surface)) {
                return@forEach
            }
            codecObject.put("min_bitrate", caps.videoCapabilities.bitrateRange.lower / 1000)
            codecObject.put("max_bitrate", caps.videoCapabilities.bitrateRange.upper / 1000)
            if (!codec.isEncoder) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    codecObject.put("low_latency", caps.isFeatureSupported(MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency))
                }
            }
            if (!codec.isEncoder) {
                return@forEach
            }
            codecArray.put(codecObject)
        }
    }
    val result = JSONObject()
    result.put("version", Build.VERSION.SDK_INT)
    result.put("w", w)
    result.put("h", h)
    result.put("codecs", codecArray)
    FFI.setCodecInfo(result.toString())
}
