// 파일명: MainActivity.kt
// 역할: Flutter의 요청을 Android 알림 설정과 처방전 카메라 방향 제어로 연결한다.

package com.example.medbuddy_frontend

import android.content.Intent
import android.content.pm.ActivityInfo
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Class Name: MainActivity
// Role: Adapts Flutter method-channel requests to Android settings and camera orientation.
// Responsibilities: Register native handlers and restore the orientation saved before camera use.
// Attributes: settingsChannel/prescriptionCameraChannel identify handlers; orientationBeforePrescriptionCamera preserves the prior policy.
class MainActivity : FlutterActivity() {
    private val settingsChannel = "com.medbuddy.app/settings"
    private val prescriptionCameraChannel = "com.medbuddy.app/prescription-camera"
    private val dataExportChannel = "com.medbuddy/data_export"
    private var orientationBeforePrescriptionCamera: Int? = null

    // Function Name: configureFlutterEngine
    // Description: Registers settings and camera-orientation handlers after the standard Flutter engine setup.
    // Parameters: flutterEngine - engine whose messenger receives the app's method-channel calls.
    // Returns: Unit; supported calls complete through their MethodChannel result callbacks.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 함수명: settingsChannel.setMethodCallHandler 콜백
        // 역할: 알림 설정 열기 요청을 처리하고 다른 메서드는 미지원으로 응답한다.
        // 매개변수: call - Flutter 호출 정보; result - 성공 또는 미지원 응답 통로.
        // 반환값: Unit; 설정 화면을 연 뒤 result.success(null)로 완료를 알린다.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, settingsChannel)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "openNotificationSettings" -> {
                            openNotificationSettings()
                            result.success(null)
                        }
                        "supportsExactReminderSettings" ->
                            result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                        "openExactReminderSettings" -> {
                            openExactReminderSettings()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("settings_unavailable", "Could not open notification settings.", null)
                }
            }
        // Function Name: prescriptionCameraChannel.setMethodCallHandler callback
        // Description: Dispatches camera rotation enable/restore requests and rejects unsupported methods.
        // Parameters: call - Flutter method request; result - channel response callback.
        // Returns: Unit; supported requests respond with success after updating orientation.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, prescriptionCameraChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableSensorOrientation" -> {
                        enableSensorOrientationForPrescriptionCamera()
                        result.success(null)
                    }
                    "restorePortrait" -> {
                        restorePortraitAfterPrescriptionCamera()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // 함수역할: 사용자 확인을 거친 복약 기록 글을 Android 공유 창에 전달하고, 이전 버전이 남긴 내보내기 캐시를 지운다.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, dataExportChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "clearExports") {
                    val root = File(cacheDir, "medication_exports")
                    if (!root.exists() || root.deleteRecursively()) {
                        result.success(null)
                    } else {
                        result.error("cleanup_failed", "Could not clear export cache.", null)
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "shareText") {
                    val content = call.argument<String>("content")
                    val subject = call.argument<String>("subject")
                    if (content.isNullOrBlank() || content.length > 100_000 ||
                        subject == null || subject.length > 100) {
                        result.error("invalid_export", "Invalid text export.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        // 파일 첨부 없이 메시지 본문으로 전달하며 받는 앱은 사용자가 선택한다.
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, content)
                            putExtra(Intent.EXTRA_SUBJECT, subject)
                        }
                        startActivity(Intent.createChooser(intent, null))
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("share_unavailable", "Could not open the share sheet.", null)
                    }
                    return@setMethodCallHandler
                }
                result.notImplemented()
            }
    }

    // Function Name: enableSensorOrientationForPrescriptionCamera
    // Description: Saves the previous orientation once and permits portrait/landscape sensor rotation during capture.
    // Parameters: None; uses this activity's current orientation policy.
    // Returns: Unit; updates requestedOrientation without changing the captured image.
    private fun enableSensorOrientationForPrescriptionCamera() {
        if (orientationBeforePrescriptionCamera == null) {
            orientationBeforePrescriptionCamera = requestedOrientation
        }
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
    }

    // Function Name: restorePortraitAfterPrescriptionCamera
    // Description: Restores the saved policy after capture, defaulting to portrait when no saved value exists.
    // Parameters: None; consumes the orientation saved before camera use.
    // Returns: Unit; clears the saved value after restoring requestedOrientation.
    private fun restorePortraitAfterPrescriptionCamera() {
        requestedOrientation = orientationBeforePrescriptionCamera
            ?: ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        orientationBeforePrescriptionCamera = null
    }

    // 함수명: openNotificationSettings
    // 역할: 현재 MedBuddy 앱의 Android 알림 설정 화면을 연다.
    // 매개변수: 없음; 현재 앱의 패키지 이름을 사용한다.
    // 반환값: 없음; 알림 설정을 열지 못하면 앱 상세 설정 화면으로 연결한다.
    private fun openNotificationSettings() {
        // 함수명: notificationIntent.apply 콜백
        // 역할: 알림 설정에서 표시할 앱의 패키지 이름을 Intent에 추가한다.
        // 매개변수: Intent 수신 객체; 명시적인 인자는 없다.
        // 반환값: Unit; 수신 객체의 설정값을 변경한다.
        val notificationIntent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        }
        // 함수명: fallbackIntent.apply 콜백
        // 역할: 앱 상세 설정으로 이동할 때 사용할 패키지 URI를 지정한다.
        // 매개변수: Intent 수신 객체; 명시적인 인자는 없다.
        // 반환값: Unit; 수신 객체의 data를 설정한다.
        val fallbackIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        }
        // 함수명: runCatching 콜백
        // 역할: 알림 설정 화면 열기를 시도하며 발생한 예외는 runCatching이 보관한다.
        // 매개변수: 없음; 위에서 구성한 notificationIntent를 사용한다.
        // 반환값: Unit; 실패 시 예외가 runCatching의 실패 결과로 변환된다.
        runCatching { startActivity(notificationIntent) }
            // 함수명: getOrElse 콜백
            // 역할: 알림 설정 열기에 실패하면 앱 상세 설정을 대신 연다.
            // 매개변수: 앞선 실패 원인인 Throwable; 본문에서는 사용하지 않는다.
            // 반환값: Unit; 대체 화면도 열 수 없으면 해당 예외는 호출자에게 전달된다.
            .getOrElse { startActivity(fallbackIntent) }
    }

    // 이미 허용된 권한도 변경할 수 있도록 권한 요청 대신 설정 화면을 직접 연다.
    private fun openExactReminderSettings() {
        check(Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }
}
