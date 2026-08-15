plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    id("com.google.firebase.firebase-perf")
}

val mapboxAccessToken = providers
    .environmentVariable("MAPBOX_ACCESS_TOKEN")
    .orNull
    ?.trim()
    .orEmpty()

if (mapboxAccessToken.isBlank()) {
    throw GradleException(
        "MAPBOX_ACCESS_TOKEN is required to build FluviAI Android.",
    )
}

if (!mapboxAccessToken.startsWith("pk.")) {
    throw GradleException(
        "MAPBOX_ACCESS_TOKEN must be a public token beginning with pk.",
    )
}
android {
    namespace = "com.example.fishtrack"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.fishtrack"

        minSdk = flutter.minSdkVersion

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        resValue("string", "mapbox_access_token", mapboxAccessToken)
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
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
