# WebRTC invokes Java from native JNI; these entry points are not visible to R8.
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
