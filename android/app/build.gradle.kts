import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Signing credentials ────────────────────────────────────────────────────────
// CI: injected as environment variables (KEY_STORE_PASSWORD etc.)
// Local: read from android/key.properties (git-ignored)
val keyPropsFile = rootProject.file("key.properties")

val storeFilePath: String = when {
    System.getenv("KEY_STORE_PASSWORD") != null -> System.getenv("KEY_STORE_PATH") ?: ""
    keyPropsFile.exists() -> {
        val p = Properties().also { it.load(keyPropsFile.reader()) }
        rootProject.file(p.getProperty("storeFile")).absolutePath
    }
    else -> ""
}

val storePass: String = when {
    System.getenv("KEY_STORE_PASSWORD") != null -> System.getenv("KEY_STORE_PASSWORD") ?: ""
    keyPropsFile.exists() -> Properties().also { it.load(keyPropsFile.reader()) }.getProperty("storePassword")
    else -> ""
}

val keyPass: String = when {
    System.getenv("KEY_STORE_PASSWORD") != null -> System.getenv("KEY_PASSWORD") ?: ""
    keyPropsFile.exists() -> Properties().also { it.load(keyPropsFile.reader()) }.getProperty("keyPassword")
    else -> ""
}

val keyAliasName: String = when {
    System.getenv("KEY_STORE_PASSWORD") != null -> System.getenv("KEY_ALIAS") ?: ""
    keyPropsFile.exists() -> Properties().also { it.load(keyPropsFile.reader()) }.getProperty("keyAlias")
    else -> ""
}

android {
    namespace = "com.sympathyforthedevil.singularity_collapse"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (storeFilePath.isNotEmpty()) {
            create("release") {
                storeFile     = file(storeFilePath)
                storePassword = storePass
                keyPassword   = keyPass
                keyAlias      = keyAliasName
            }
        }
    }

    defaultConfig {
        applicationId = "com.sympathyforthedevil.singularity_collapse"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode  = flutter.versionCode
        versionName  = flutter.versionName
    }

    buildTypes {
        release {
            // Uses release signing when keystore secrets are set; falls back to
            // debug signing for unsigned test builds (still installable).
            signingConfig = if (storeFilePath.isNotEmpty())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
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
