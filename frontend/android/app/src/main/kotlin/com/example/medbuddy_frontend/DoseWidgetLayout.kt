package com.example.medbuddy_frontend

import android.appwidget.AppWidgetManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews

// 파일명: DoseWidgetLayout.kt
// 역할: 런처가 배정한 높이에 따라 동일한 위젯 정보와 버튼을 배치한다.
// 클래스명: DoseWidgetLayout
// 주요 책임: 최소 크기에서도 48dp 조작 영역을 유지하고 크기별 표시 밀도를 선택한다.
object DoseWidgetLayout {
    // 함수이름: responsive
    // 함수역할: Android 12 이상은 높이별 배치를 제공하고 이전 버전은 회전별 크기를 사용한다.
    // 매개변수: context 실행 환경, base 내용과 클릭 동작, options 런처 크기,
    //           known 로그인 여부, overdue 놓친 일정 여부, hasPager 시간대 전환 여부.
    // 반환값: 런처가 실제 크기에 맞춰 선택할 RemoteViews.
    fun responsive(context: Context, base: RemoteViews, options: Bundle,
        known: Boolean, overdue: Boolean, hasPager: Boolean): RemoteViews {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return RemoteViews(listOf(180, 240, 300, 340, 420).associate { height ->
                SizeF(250f, height.toFloat()) to sized(context, base, height, known, overdue, hasPager)
            })
        }
        val landscape = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 240)
        val portrait = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 240)
        return RemoteViews(
            sized(context, base, landscape, known, overdue, hasPager),
            sized(context, base, portrait, known, overdue, hasPager),
        )
    }

    // 함수이름: sized
    // 함수역할: 짧은 위젯은 여백과 상세 줄 수를 줄이고 진행 숫자·저장 상태·버튼을 유지한다.
    // 매개변수: context 글자 배율과 밀도, base 원본 표시, height 높이(dp),
    //           known 로그인 여부, overdue 안내 표시 여부, hasPager 시간대 전환 여부.
    // 반환값: 원본을 변경하지 않은 크기별 표시 복사본.
    @Suppress("DEPRECATION")
    fun sized(context: Context, base: RemoteViews, height: Int,
        known: Boolean, overdue: Boolean, hasPager: Boolean): RemoteViews {
        val views = base.clone()
        val scale = context.resources.configuration.fontScale
        val large = scale > 1.15f
        val veryLarge = scale > 1.6f
        val minimal = height < 240
        val short = height < 300 || (height < 340 && large)
        val compact = height < 340 || large
        val verticalPadding = if (short) 4 else 16
        val horizontalPadding = if (short) 12 else 16
        val density = context.resources.displayMetrics.density
        views.setViewPadding(R.id.widget_root,
            (horizontalPadding * density).toInt(), (verticalPadding * density).toInt(),
            (horizontalPadding * density).toInt(), (verticalPadding * density).toInt())
        views.setTextViewTextSize(R.id.widget_heading, TypedValue.COMPLEX_UNIT_SP,
            if (minimal) 14f else if (short) 18f else 21f)
        views.setTextViewTextSize(R.id.widget_details, TypedValue.COMPLEX_UNIT_SP, if (minimal) 11f else 14f)
        views.setTextViewTextSize(R.id.widget_status, TypedValue.COMPLEX_UNIT_SP,
            if (minimal && veryLarge) 8f else if (minimal) 10f else 11f)
        views.setTextViewTextSize(R.id.widget_compact_heading, TypedValue.COMPLEX_UNIT_SP, if (veryLarge) 10f else 14f)
        for (id in listOf(R.id.widget_title, R.id.widget_date)) {
            views.setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_SP,
                if (minimal && veryLarge) 8f else if (short && veryLarge) 10f else 14f)
        }
        views.setInt(R.id.widget_heading, "setMaxLines", if (compact) 1 else 2)
        val detailLines = if (minimal || (short && veryLarge) || (known && (short || (large && (height < 340 || overdue))))) 1 else if (compact) 2 else 3
        views.setInt(R.id.widget_details, "setMaxLines", detailLines)
        views.setInt(R.id.widget_warning, "setMaxLines", if (compact) 1 else 2)
        views.setInt(R.id.widget_status, "setMaxLines", if (compact) 1 else 2)
        // 숫자 진행률은 그대로 남기고 작은 높이에서만 중복 막대의 공간을 돌려준다.
        views.setViewVisibility(R.id.widget_progress, if (known && !short) View.VISIBLE else View.GONE)
        val summaryOnly = (minimal && known) || (height < 360 && known && hasPager && veryLarge)
        views.setViewVisibility(R.id.widget_details,
            if (summaryOnly || (short && known && hasPager && large)) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.widget_warning, if (overdue && !summaryOnly) View.VISIBLE else View.GONE)
        // 런처의 가로 화면 기준 최소 높이에서도 화살표·저장 상태·복용 버튼은 유지한다.
        views.setViewVisibility(R.id.widget_content, if (minimal && hasPager) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.widget_compact_heading, if (minimal && hasPager) View.VISIBLE else View.GONE)
        return views
    }
}
