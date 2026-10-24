import java.util.Properties
import java.util.Base64
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase
    id("com.google.gms.google-services")
}

// Kalici imza anahtari. android/key.properties dosyasindan okunur.
// Bu anahtar DEGISMEDIGI surece guncellemeler mevcut uygulamanin uzerine
// kurulur ve kullanicinin verileri (resimler, notlar, PIN) silinmez.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.melek.stargaleri"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    buildFeatures { buildConfig = true }
    defaultConfig {
        val postgresPrimary = (project.findProperty("dart-defines") as String?)?.split(',')?.any {
            runCatching { String(Base64.getDecoder().decode(it)) == "NEURAL_POSTGRES_PRIMARY=true" }.getOrDefault(false)
        } ?: false
        buildConfigField("boolean", "POSTGRES_PRIMARY", postgresPrimary.toString())
        applicationId = "com.melek.stargaleri"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        // pubspec.yaml'daki "version:" alanindan okunur. Sabit deger yazilirsa
        // her derleme ayni surum numarasini alir ve yuklu uygulama guncellenemez.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        // Match third-party JNI libraries to Flutter's requested targets too.
        // Otherwise an ARM64-only build may still contain other WebRTC ABIs.
        val requestedTargets = (project.findProperty("target-platform") as String?)
            ?: "android-arm,android-arm64,android-x64"
        val requestedAbis = requestedTargets.split(',').mapNotNull {
            when (it.trim()) {
                "android-arm" -> "armeabi-v7a"
                "android-arm64" -> "arm64-v8a"
                "android-x64" -> "x86_64"
                else -> null
            }
        }
        ndk {
            abiFilters.clear()
            abiFilters.addAll(requestedAbis)
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?

            // Tum imza semalari acik: bazi cihazlarin kurulum ekrani
            // eksik semali APK'yi "paket gecersiz" diye reddediyor.
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.15.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.firebase:firebase-firestore")
    implementation("androidx.media3:media3-transformer:1.8.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.multidex:multidex:2.0.1")
}
