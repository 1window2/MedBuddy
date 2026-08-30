package com.example.medbuddy_frontend

import android.content.pm.ActivityInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 클래스명: MainActivity
// 역할: 앱과 처방전 촬영 화면을 세로 방향으로 고정한다.
class MainActivity : FlutterActivity() {
    private val prescriptionCameraChannel = "com.medbuddy.app/prescription-camera"
    private var orientationBeforePrescriptionCamera: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, prescriptionCameraChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "lockPortrait" -> {
                        lockPortraitForPrescriptionCamera()
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

    // 함수명: lockPortraitForPrescriptionCamera
    // 역할: 처방전 촬영 중에도 앱의 세로 방향 정책을 유지한다.
    private fun lockPortraitForPrescriptionCamera() {
        if (orientationBeforePrescriptionCamera == null) {
            orientationBeforePrescriptionCamera = requestedOrientation
        }
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    }

    // 함수명: restorePortraitAfterPrescriptionCamera
    // 역할: 촬영 화면을 닫을 때 저장된 세로 방향 정책을 복원한다.
    private fun restorePortraitAfterPrescriptionCamera() {
        requestedOrientation = orientationBeforePrescriptionCamera
            ?: ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        orientationBeforePrescriptionCamera = null
    }
}
