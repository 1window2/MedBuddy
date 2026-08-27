package com.example.medbuddy_frontend

import android.content.pm.ActivityInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 클래스명: MainActivity
// 역할: 처방전 촬영 화면에서만 센서 회전을 허용하고 종료 시 기존 방향을 복원한다.
class MainActivity : FlutterActivity() {
    private val prescriptionCameraChannel = "com.medbuddy.app/prescription-camera"
    private var orientationBeforePrescriptionCamera: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}
