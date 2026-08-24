package com.example.medbuddy_frontend

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 클래스명: MainActivity
// 역할: Flutter 화면과 Android 시스템 설정 화면 사이의 최소 연결을 제공한다.
class MainActivity : FlutterActivity() {
    private val settingsChannel = "com.medbuddy.app/settings"

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
