// File Name: build.gradle.kts
// Role: Configures the Android application, release signing and bundled OCR dependencies.

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

// Flutter의 `--target-platform` 값을 ABI 이름으로 바꾼다. 속성이 없거나 알 수 없는 값이
// 섞여 있으면 null이며, 이때는 Flutter 플러그인의 기본 ABI 구성을 그대로 둔다.
val flutterTargetAbis: List<String>? =
    (project.findProperty("target-platform") as String?)
        ?.split(",")
        ?.map {
            when (it.trim()) {
                "android-arm" -> "armeabi-v7a"
                "android-arm64" -> "arm64-v8a"
                "android-x64" -> "x86_64"
                else -> ""
            }
        }
        ?.takeIf { abis -> abis.isNotEmpty() && abis.none { it.isEmpty() } }
val splitPerAbi = (project.findProperty("split-per-abi") as String?)?.toBoolean() == true

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
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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

    // `--target-platform`은 Flutter 엔진과 앱 코드만 줄이고 플러그인의 네이티브 라이브러리는
    // 모든 기본 ABI로 남긴다. 엔진이 없는 ABI 폴더가 APK에 남지 않도록 같은 목록으로 제한한다.
    // Flutter 플러그인은 버전에 따라 빌드 유형 또는 기본 구성에 필터를 쓰므로 두 곳을 모두 바꾼다.
    if (flutterTargetAbis != null && !splitPerAbi) {
        defaultConfig.ndk {
            abiFilters.clear()
            abiFilters.addAll(flutterTargetAbis)
        }
        buildTypes.configureEach {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(flutterTargetAbis)
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("com.google.guava:guava:33.5.0-android")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // 위젯의 실패 복구 예약에 사용하며 기존 위젯·백그라운드 플러그인 버전과 맞춘다.
    implementation("androidx.work:work-runtime-ktx:2.11.2")

    // 처방전 한글 OCR에 필요한 온디바이스 ML Kit 모델을 릴리스 앱에 포함한다.
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
}
