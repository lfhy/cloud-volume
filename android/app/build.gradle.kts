import java.io.File

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    // Kotlin is applied explicitly (version pinned in settings.gradle.kts) so the
    // build also works on Flutter releases whose gradle plugin does not auto-apply it.
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// CI supplies all four values together; an incomplete signing setup must not ship a debug-signed APK.
val releaseSigningVariables = listOf(
    "ANDROID_KEYSTORE_FILE",
    "ANDROID_KEYSTORE_PASSWORD",
    "ANDROID_KEY_ALIAS",
    "ANDROID_KEY_PASSWORD",
)
val releaseSigningValues = releaseSigningVariables.associateWith {
    providers.environmentVariable(it).orNull
}
val releaseSigningRequested = releaseSigningValues.values.any { it != null }
val releaseKeystoreFile = if (releaseSigningRequested) {
    val missing = releaseSigningValues.filterValues { it.isNullOrBlank() }.keys
    require(missing.isEmpty()) {
        "Incomplete Android release signing environment: missing or empty ${missing.joinToString()}"
    }
    File(requireNotNull(releaseSigningValues["ANDROID_KEYSTORE_FILE"])).also {
        require(it.isAbsolute && it.isFile) {
            "ANDROID_KEYSTORE_FILE must point to an existing absolute file"
        }
    }
} else {
    null
}

android {
    namespace = "com.cloud.volume"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.cloud.volume"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeystoreFile != null) {
            create("releaseFromEnvironment") {
                storeFile = releaseKeystoreFile
                storePassword = releaseSigningValues["ANDROID_KEYSTORE_PASSWORD"]
                keyAlias = releaseSigningValues["ANDROID_KEY_ALIAS"]
                keyPassword = releaseSigningValues["ANDROID_KEY_PASSWORD"]
            }
        }
    }

    buildTypes {
        release {
            // Local release runs without CI signing values retain Flutter's debug-key fallback.
            signingConfig = signingConfigs.getByName(
                if (releaseKeystoreFile != null) "releaseFromEnvironment" else "debug"
            )
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
