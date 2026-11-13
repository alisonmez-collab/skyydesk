# The library calls these by name from native code.
-keep class ffi.FFI { *; }
-keep class com.skyydesk.embed.Native { *; }
-keep class com.elpo.skyydesk.CaptureService { *; }
-keep class com.elpo.skyydesk.RdClipboardManager { *; }
-keep class org.rustls.platformverifier.** { *; }
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }
