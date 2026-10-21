# R8 keep rules for the release build.
#
# The Flutter Gradle plugin turns minification on for every release build
# (`FlutterPlugin.kt` sets `releaseBuildType.isMinifyEnabled = true`), so R8
# always runs. Without a rules file of its own the app has no say in what R8
# keeps, and it stripped classes that the YouTube extractor reaches only
# reflectively.
#
# --- Rhino ---
#
# `newpipeextractor_dart` pulls in `org.mozilla:rhino`, which NewPipe Extractor
# uses to run YouTube's player JavaScript when a stream URL arrives as a
# `signatureCipher` and the signature has to be deobfuscated. The path is:
#
#   YoutubeStreamExtractor -> YoutubeJavaScriptPlayerManager -> JavaScript -> Rhino
#
# `FathomYtMusic.audioUri` calls `VideoExtractor.getStream`, which goes through
# `YoutubeStreamExtractor`, so this is reachable at runtime for any video whose
# stream URL carries a cipher. Rhino must NOT be excluded from the build: doing
# so replaces a build-time warning with a `NoClassDefFoundError` on a subset of
# tracks, which would surface as an unexplained resolve failure.
#
# Rhino's `JavaToJSONConverters` reflects over JavaBeans to turn arbitrary Java
# objects into JSON, and that path names `java.beans.*`. Those classes are not
# on Android at all, and the reflective bean path is never taken by NewPipe's
# use of Rhino, which only ever evaluates a script and calls a function. R8
# cannot prove that unreachability, so the references are accepted here rather
# than kept.
#
# `javax.script.ScriptEngineFactory` is the JSR-223 registration interface,
# referenced only by Rhino's `RhinoScriptEngineFactory` so the engine can be
# discovered through the standard service loader. Fathom never uses the script
# engine SPI, and the class is likewise absent on Android.
-dontwarn java.beans.BeanDescriptor
-dontwarn java.beans.BeanInfo
-dontwarn java.beans.IntrospectionException
-dontwarn java.beans.Introspector
-dontwarn java.beans.PropertyDescriptor
-dontwarn javax.script.ScriptEngineFactory
