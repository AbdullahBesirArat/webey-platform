import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: load key.properties from android/ folder if it exists.
val keyPropsFile = rootProject.file("key.properties")
val keyProps = Properties()
if (keyPropsFile.exists()) {
    FileInputStream(keyPropsFile).use { keyProps.load(it) }
}

android {
    namespace = "tr.com.webey.webey_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        if (keyPropsFile.exists()) {
            create("release") {
                keyAlias      = keyProps["keyAlias"]      as String
                keyPassword   = keyProps["keyPassword"]   as String
                storeFile     = file(keyProps["storeFile"] as String)
                storePassword = keyProps["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "tr.com.webey.beauty"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "Webey Beauty"
    }

    flavorDimensions += "app"
    productFlavors {
        create("customer") {
            dimension = "app"
            applicationId = "tr.com.webey.beauty"
            manifestPlaceholders["appLabel"] = "Webey Beauty"
        }
        create("business") {
            dimension = "app"
            applicationId = "tr.com.webey.business"
            manifestPlaceholders["appLabel"] = "Webey Business"
        }
    }

    buildTypes {
        release {
            // Release signing: use key.properties when present; otherwise fall back
            // to the debug keystore so the APK can be installed on test devices.
            // For Play Store submission, create android/key.properties and a proper keystore.
            signingConfig = if (keyPropsFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.14.0"))
    implementation("com.google.firebase:firebase-messaging")
}
