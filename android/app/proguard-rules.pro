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
# Rhino is kept whole, not narrowed to the classes NewPipe names directly.
# R8's reachability analysis cannot follow Rhino's own dispatch: `Context`
# loads its VM bridge (`org.mozilla.javascript.VMBridge_jdk18`) and its code
# generator (`org.mozilla.javascript.optimizer.Codegen`) by name, and the
# interpreter/optimizer split hands work to classes no static call edge names.
# A narrowed build proved this the hard way: release mapping reduced
# `org.mozilla.javascript.Context` to `<clinit>` plus one field, and
# `YoutubeSignatureUtils` ended up with a `throw null` where
# `Context.compileString` belongs, so every signatureCipher stream would have
# failed to resolve at runtime while debug builds worked. Keeping the package
# costs about a megabyte and removes the whole failure mode.
-keep class org.mozilla.javascript.** { *; }
-keep class org.mozilla.classfile.** { *; }

# Keeping the whole runtime brings in two Java SE surfaces Android lacks, both
# on paths Fathom never takes:
#
# * `java.beans.*` — `JavaToJSONConverters` reflects over JavaBeans to turn
#   arbitrary Java objects into JSON. NewPipe only evaluates a script and calls
#   a function.
# * `javax.script.*` — the JSR-223 engine (`org.mozilla.javascript.engine`).
# * `jdk.dynalink.*` — the `invokedynamic` bootstrap in `optimizer.Bootstrapper`.
#   Android's ART has no `java.lang.invoke` call-site support for it; `Codegen`
#   and the interpreter, which NewPipe does use, do not need it.
#
# R8 cannot prove those branches unreachable once the package is kept, so the
# references are accepted instead of kept. `-dontwarn` does not keep the classes
# and does not change which path runs; it only lets the build finish.
-dontwarn java.beans.**
-dontwarn javax.script.**
-dontwarn jdk.dynalink.**
