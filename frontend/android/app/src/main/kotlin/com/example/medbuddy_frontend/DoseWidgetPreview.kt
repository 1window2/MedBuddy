package com.example.medbuddy_frontend

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.ContextThemeWrapper
import android.view.View
import android.widget.FrameLayout
import android.widget.RemoteViews
import java.io.ByteArrayOutputStream
import kotlin.math.roundToInt

// 파일명: DoseWidgetPreview.kt
// 역할: 기존 위젯 레이아웃을 개인정보와 클릭 동작 없이 메모리 이미지로 만든다.
object DoseWidgetPreview {
    // 함수역할: 같은 폭의 4 x 1·4 x 3 예시를 실제 Android 레이아웃으로 그린다.
    // 매개변수: context는 리소스, language는 앱 표시 언어. 반환값: 크기별 PNG 바이트.
    fun render(context: Context, language: String): Map<String, ByteArray> {
        val config = Configuration(context.resources.configuration).apply { densityDpi = 320 }
        val themed = ContextThemeWrapper(context.createConfigurationContext(config),
            android.R.style.Theme_Material_Light_NoActionBar)
        return mapOf(
            "compact" to image(themed, language == "en", false),
            "expanded" to image(themed, language == "en", true),
        )
    }

    // 함수역할: 예시 텍스트만 채운 원래 위젯을 렌더링하고 사용한 비트맵을 해제한다.
    // 매개변수: context는 고정 밀도 환경, english는 언어, expanded는 시작 크기. 반환값: PNG.
    private fun image(context: Context, english: Boolean, expanded: Boolean): ByteArray {
        fun tr(ko: String, en: String) = if (english) en else ko
        val height = if (expanded) 300 else 80
        val base = RemoteViews(context.packageName,
            if (expanded) R.layout.dose_home_widget else R.layout.dose_home_widget_row)
        base.setTextViewText(R.id.widget_take, tr("복용했어요", "Taken"))
        base.setViewVisibility(R.id.widget_previous, View.INVISIBLE)
        base.setBoolean(R.id.widget_previous, "setEnabled", false)
        base.setViewVisibility(R.id.widget_next, View.VISIBLE)
        base.setBoolean(R.id.widget_next, "setEnabled", true)
        if (expanded) {
            base.setTextViewText(R.id.widget_title, tr("나의 복약 일정", "My medication"))
            base.setTextViewText(R.id.widget_date, "20XX.XX.XX")
            base.setTextViewText(R.id.widget_heading, tr("아침 --:--", "Morning --:--"))
            base.setTextViewText(R.id.widget_details, tr("아침약 · 미복용", "Morning medication · Not taken"))
            base.setTextViewText(R.id.widget_status, tr("미복용", "Not taken"))
            base.setTextViewText(R.id.widget_count, "0/3")
            base.setViewVisibility(R.id.widget_count, View.VISIBLE)
            base.setViewVisibility(R.id.widget_refresh, View.VISIBLE)
            base.setProgressBar(R.id.widget_progress, 3, 0, false)
            base.setImageViewResource(R.id.widget_dot_0, R.drawable.dose_widget_dot_active)
            base.setViewVisibility(R.id.widget_dot_3, View.GONE)
        } else {
            base.setTextViewText(R.id.widget_tiny_heading, tr("아침 --:--", "Morning --:--"))
            base.setTextViewText(R.id.widget_tiny_status, tr("미복용", "Not taken"))
        }
        val views = if (expanded) DoseWidgetLayout.sized(context, base, height, true, false, true)
            else DoseWidgetLayout.row(context, base, height, true, false)
        val root = views.apply(context, FrameLayout(context))
        val density = context.resources.displayMetrics.density
        val widthPx = (360 * density).roundToInt()
        val heightPx = (height * density).roundToInt()
        root.measure(View.MeasureSpec.makeMeasureSpec(widthPx, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(heightPx, View.MeasureSpec.EXACTLY))
        root.layout(0, 0, widthPx, heightPx)
        root.jumpDrawablesToCurrentState()
        val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        try {
            root.draw(Canvas(bitmap))
            return ByteArrayOutputStream().use {
                check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
                it.toByteArray()
            }
        } finally { bitmap.recycle() }
    }
}
