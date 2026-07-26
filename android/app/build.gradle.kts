import java.io.File
import java.io.FileInputStream
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

val keystoreProperties =
    Properties().apply {
        val propertiesFile = rootProject.file("key.properties")
        if (propertiesFile.exists()) {
            load(FileInputStream(propertiesFile))
        }
    }

val releaseSigningRequested =
    gradle.startParameter.taskNames.any {
        it.contains("release", ignoreCase = true) || it.contains("bundle", ignoreCase = true)
    }

fun releaseSigningValue(propertyName: String, envName: String): String? =
    (keystoreProperties[propertyName] as String?)?.takeIf { it.isNotBlank() }
        ?: System.getenv(envName)?.takeIf { it.isNotBlank() }

fun requiredReleaseSigningValue(propertyName: String, envName: String): String {
    val value = releaseSigningValue(propertyName, envName)
    if (value.isNullOrBlank() && releaseSigningRequested) {
        throw GradleException(
            "Missing Android release signing value '$propertyName'. " +
                "Create android/key.properties or set $envName before building release."
        )
    }
    return value.orEmpty()
}

fun releaseStoreFile(): File? {
    val path = releaseSigningValue("storeFile", "ANDROID_KEYSTORE_PATH")
    if (path.isNullOrBlank()) {
        if (releaseSigningRequested) {
            throw GradleException(
                "Missing Android release signing storeFile. " +
                    "Create android/key.properties or set ANDROID_KEYSTORE_PATH before building release."
            )
        }
        return null
    }

    val candidate = File(path)
    return if (candidate.isAbsolute) candidate else rootProject.file(path)
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.company.manfathak"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
    isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.company.manfathak"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStoreFile()
            storePassword = requiredReleaseSigningValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
            keyAlias = requiredReleaseSigningValue("keyAlias", "ANDROID_KEY_ALIAS")
            keyPassword = requiredReleaseSigningValue("keyPassword", "ANDROID_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
