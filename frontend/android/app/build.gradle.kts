plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// 로컬 인증 비활성화 환경에서는 Firebase 설정 파일 없이도 디버그 빌드를 허용한다.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val releaseKeystorePath = System.getenv("MEDBUDDY_KEYSTORE_PATH")
val releaseKeystorePassword = System.getenv("MEDBUDDY_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("MEDBUDDY_KEY_ALIAS")
val releaseKeyPassword = System.getenv("MEDBUDDY_KEY_PASSWORD")
val releaseSigningValues = listOf(
    releaseKeystorePath,
    releaseKeystorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
)
val hasReleaseSigning = releaseSigningValues.all { !it.isNullOrBlank() }
val requireReleaseSigning =
    System.getenv("MEDBUDDY_REQUIRE_RELEASE_SIGNING")?.toBooleanStrictOrNull() == true

if (requireReleaseSigning && !hasReleaseSigning) {
    throw GradleException("MedBuddy release signing environment is incomplete.")
}

android {
    namespace = "com.example.medbuddy_frontend"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.medbuddy.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // 처방전 한글 OCR에 필요한 온디바이스 ML Kit 모델을 릴리스 앱에 포함한다.
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
}
