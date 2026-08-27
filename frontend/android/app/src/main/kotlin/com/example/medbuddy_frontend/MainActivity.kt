package com.example.medbuddy_frontend

import android.content.Intent
import android.content.pm.ActivityInfo
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 클래스명: MainActivity
// 역할: Flutter 화면과 Android 시스템 설정 화면 사이의 최소 연결을 제공한다.
class MainActivity : FlutterActivity() {
    private val settingsChannel = "com.medbuddy.app/settings"
    private val prescriptionCameraChannel = "com.medbuddy.app/prescription-camera"
    private var orientationBeforePrescriptionCamera: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, settingsChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "openNotificationSettings") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                openNotificationSettings()
                result.success(null)
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, prescriptionCameraChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableSensorRotation" -> {
                        enablePrescriptionCameraRotation()
                        result.success(null)
                    }
                    "restoreOrientation" -> {
                        restoreOrientationAfterPrescriptionCamera()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // 함수명: enablePrescriptionCameraRotation
    // 역할: 처방전 촬영 중에는 시스템 회전 잠금과 관계없이 센서 방향을 따른다.
    private fun enablePrescriptionCameraRotation() {
        if (orientationBeforePrescriptionCamera == null) {
            orientationBeforePrescriptionCamera = requestedOrientation
        }
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
    }

    // 함수명: restoreOrientationAfterPrescriptionCamera
    // 역할: 처방전 촬영 화면을 닫을 때 이전 앱 방향 정책을 복원한다.
    private fun restoreOrientationAfterPrescriptionCamera() {
        requestedOrientation = orientationBeforePrescriptionCamera
            ?: ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        orientationBeforePrescriptionCamera = null
    }

    // 함수명: openNotificationSettings
    // 역할: 현재 MedBuddy 앱의 Android 알림 설정 화면을 연다.
    private fun openNotificationSettings() {
        val notificationIntent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        }
        val fallbackIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        }
        runCatching { startActivity(notificationIntent) }
            .getOrElse { startActivity(fallbackIntent) }
    }
}
