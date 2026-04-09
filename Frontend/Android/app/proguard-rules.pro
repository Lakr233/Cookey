# Lazysodium
-keep class com.goterl.lazysodium.** { *; }
-keep class com.sun.jna.** { *; }
-dontwarn com.sun.jna.**

# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class wiki.qaq.cookey.**$$serializer { *; }
-keepclassmembers class wiki.qaq.cookey.** { *** Companion; }
-keepclasseswithmembers class wiki.qaq.cookey.** { kotlinx.serialization.KSerializer serializer(...); }
