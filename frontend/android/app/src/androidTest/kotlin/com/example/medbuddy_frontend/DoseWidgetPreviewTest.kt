package com.example.medbuddy_frontend

import android.graphics.BitmapFactory
import android.graphics.Color
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

// 파일명: DoseWidgetPreviewTest.kt
// 역할: 실제 Android 위젯 리소스로 두 크기의 비어 있지 않은 미리보기가 만들어지는지 확인한다.
@RunWith(AndroidJUnit4::class)
class DoseWidgetPreviewTest {
    @Test fun rendersBothSizesInBothLanguagesWithoutBindingWidgets() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            for (language in listOf("ko", "en")) {
                val images = DoseWidgetPreview.render(instrumentation.targetContext, language)
                assertEquals(setOf("compact", "expanded"), images.keys)
                for ((size, bytes) in images) {
                    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    assertEquals(720, bitmap.width)
                    assertEquals(if (size == "compact") 160 else 600, bitmap.height)
                    var greenPixels = 0
                    var darkPixels = 0
                    for (x in 0 until bitmap.width step 3) for (y in 0 until bitmap.height step 3) {
                        val pixel = bitmap.getPixel(x, y)
                        if (Color.alpha(pixel) < 200) continue
                        if (Color.green(pixel) > Color.red(pixel) + 40 && Color.green(pixel) > Color.blue(pixel) + 20) greenPixels++
                        if (Color.red(pixel) < 100 && Color.green(pixel) < 100 && Color.blue(pixel) < 100) darkPixels++
                    }
                    assertTrue("$language/$size must contain the medication button", greenPixels > 300)
                    assertTrue("$language/$size must contain text", darkPixels > 30)
                    bitmap.recycle()
                }
            }
        }
    }
}
