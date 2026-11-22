# Optional desktop JVM classes referenced by smbj / mbassador / BouncyCastle not used on Android
-dontwarn javax.el.**
-dontwarn org.ietf.jgss.**
-dontwarn org.bouncycastle.**

# Keep SMBJ & MBassador reflective handlers used at runtime for SMB2/SMB3
-keep class com.hierynomus.** { *; }
-keep class net.engio.mbassy.** { *; }

-keep class org.drinkless.tdlib.** { *; }
-dontwarn org.drinkless.tdlib.**
