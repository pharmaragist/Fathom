plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "pharmaracist.fathom"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // NewPipe Extractor targets Java 8+ APIs (java.time, java.util.stream)
        // that the platform only has from API 26 up, and Fathom supports older
        // devices. Desugaring supplies them; the extractor's Gradle wiring
        // expects both this flag and the desugar_jdk_libs dependency.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "pharmaracist.fathom"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // From pubspec.yaml. `flutter build apk --split-per-abi` adds 1000 * the
        // ABI's version automatically, so split APKs do not share a version code.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // NDK abiFilters left to Flutter/AGP defaults to avoid conflicts with
        // Flutter's split ABI configuration. Use `flutter build apk --split-per-abi`
        // for per-ABI splits.
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // No `proguardFiles` call here on purpose. The Flutter Gradle
            // plugin already enables minification for every release build and
            // adds `proguard-android-optimize.txt`, its own
            // `flutter_proguard_rules.pro`, and — by convention — this module's
            // `android/app/proguard-rules.pro` whenever that file exists.
            // Naming the files again here would add the default rules twice.
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Required by NewPipe Extractor's use of java.time and java.util.stream;
    // see isCoreLibraryDesugaringEnabled above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
