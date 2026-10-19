package com.example.medbuddy_frontend

import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

// 파일명: MedicationExportProviderTest.kt
// 역할: 복약 CSV 내보내기의 Android 파일 접근 범위를 실제 기기에서 검사한다.
@RunWith(AndroidJUnit4::class)
class MedicationExportProviderTest {
    // 함수역할: 제공자는 외부에 공개되지 않으며 공유 시 개별 URI 권한만 허용하는지 확인한다.
    @Test fun providerRequiresExplicitUriGrant() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val provider = context.packageManager.resolveContentProvider(
            "${context.packageName}.medication_exports", PackageManager.GET_META_DATA,
        ) ?: error("Missing export provider")
        assertFalse(provider.exported)
        assertTrue(provider.grantUriPermissions)
    }

    // 함수역할: 내보내기 전용 경로는 URI를 만들고, 일반 앱 캐시 경로는 거부하는지 확인한다.
    @Test fun onlyDedicatedExportCacheCanBeShared() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.cacheDir, "medication_exports/test-${UUID.randomUUID()}")
        check(directory.mkdirs())
        val export = File(directory, "test.csv")
        val privateFile = File(context.cacheDir, "private-${UUID.randomUUID()}.txt")
        try {
            export.writeText("date,status\n2026-10-17,taken\n")
            privateFile.writeText("private")
            val uri = FileProvider.getUriForFile(
                context, "${context.packageName}.medication_exports", export,
            )
            assertTrue(uri.toString().startsWith("content://"))
            try {
                FileProvider.getUriForFile(
                    context, "${context.packageName}.medication_exports", privateFile,
                )
                fail("Unrelated app cache must not be shared")
            } catch (_: IllegalArgumentException) {
                // 내보내기 디렉터리 밖의 파일을 거부하는 정상 경로.
            }
        } finally {
            privateFile.delete()
            directory.deleteRecursively()
        }
    }
}
