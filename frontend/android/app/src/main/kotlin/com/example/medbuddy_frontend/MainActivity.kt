package com.example.medbuddy_frontend

import android.content.Intent
import android.content.pm.ActivityInfo
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 클래스명: MainActivity
// 역할: Flutter 화면과 Android 알림 설정 및 처방전 촬영 회전 정책 사이의 연결을 제공한다.
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
    }

    // 함수명: enableSensorOrientationForPrescriptionCamera
    // 역할: 처방전 촬영 중에만 세로와 가로 센서 회전을 모두 허용한다.
    private fun enableSensorOrientationForPrescriptionCamera() {
        if (orientationBeforePrescriptionCamera == null) {
            orientationBeforePrescriptionCamera = requestedOrientation
        }
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
    }

    // 함수명: restorePortraitAfterPrescriptionCamera
    // 역할: 촬영 화면을 닫을 때 저장된 세로 방향 정책을 복원한다.
    private fun restorePortraitAfterPrescriptionCamera() {
        requestedOrientation = orientationBeforePrescriptionCamera
            ?: ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
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
