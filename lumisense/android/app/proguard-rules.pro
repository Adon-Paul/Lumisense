# ─── Flutter ──────────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# ─── ML Kit text recognition ─────────────────────────────────────────────────
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ─── TensorFlow Lite ─────────────────────────────────────────────────────────
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**
-keep class org.tensorflow.lite.gpu.** { *; }
-dontwarn org.tensorflow.lite.gpu.**

# ─── Ultralytics YOLO plugin ─────────────────────────────────────────────────
-keep class com.ultralytics.** { *; }
-dontwarn com.ultralytics.**

# ─── SnakeYAML (via ultralytics_yolo) ────────────────────────────────────────
# References java.beans APIs unavailable on Android — unused at runtime.
-dontwarn java.beans.BeanInfo
-dontwarn java.beans.FeatureDescriptor
-dontwarn java.beans.IntrospectionException
-dontwarn java.beans.Introspector
-dontwarn java.beans.PropertyDescriptor

# ─── Geolocator ──────────────────────────────────────────────────────────────
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# ─── Flutter Secure Storage ──────────────────────────────────────────────────
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# ─── Speech to Text ──────────────────────────────────────────────────────────
-keep class com.csdcorp.speech_to_text.** { *; }
-dontwarn com.csdcorp.speech_to_text.**

# ─── Permission Handler ──────────────────────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**
