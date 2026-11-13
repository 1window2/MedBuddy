package com.example.medbuddy_frontend

import android.appwidget.AppWidgetManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews

// File Name: DoseWidgetLayout.kt
// Role: Fits the same widget state and actions to the launcher's allocated height.
// Class Name: DoseWidgetLayout
// Responsibilities: Select responsive layouts while preserving 48dp primary action targets.
// Attributes: ROW_LIMIT (Int) separates the single-row and stacked layouts in dp.
object DoseWidgetLayout {
    // Function Name: responsive
    // Description: Uses size-keyed layouts on Android 12+ and orientation-specific layouts on older versions.
    // Parameters: context (Context), base/row (RemoteViews), options (Bundle), known/overdue/hasPager (Boolean).
    // Returns: RemoteViews; heights below ROW_LIMIT use the single-row layout with state and dose action.
    fun responsive(context: Context, base: RemoteViews, row: RemoteViews, options: Bundle,
        known: Boolean, overdue: Boolean, hasPager: Boolean): RemoteViews {
        // Function Name: pick
        // Description: Chooses the single-row or stacked layout for one launcher height.
        // Parameters: height (Int) is the available height in dp; other state is captured from responsive.
        // Returns: A resized RemoteViews clone without altering the supplied base views.
        fun pick(height: Int) = if (height < ROW_LIMIT) row(context, row, height, known, overdue)
            else sized(context, base, height, known, overdue, hasPager)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return RemoteViews(listOf(48, 60, ROW_LIMIT, 180, 230, 300, 340, 420).associate { height ->
                SizeF(250f, height.toFloat()) to pick(height)
            })
        }
        val landscape = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 240)
        val portrait = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 240)
        return RemoteViews(pick(landscape), pick(portrait))
    }

    // 1칸 높이 런처(세로 약 109dp, 가로 약 51dp)는 제목 줄과 48dp 버튼을 위아래로 둘 수 없다.
    const val ROW_LIMIT = 110

    // Function Name: row
    // Description: Fits state and action text inside one row, reducing line count for short or large-font layouts.
    // Parameters: context (Context), base (RemoteViews), height (Int, dp), known/overdue (Boolean).
    // Returns: A resized RemoteViews clone; the original view remains unchanged.
    fun row(context: Context, base: RemoteViews, height: Int, known: Boolean, overdue: Boolean): RemoteViews {
        val views = base.clone()
        val scale = context.resources.configuration.fontScale
        val large = scale > 1.15f
        val veryLarge = scale > 1.6f
        views.setTextViewTextSize(R.id.widget_tiny_heading, TypedValue.COMPLEX_UNIT_SP,
            if (veryLarge) 9f else if (large) 12f else 14f)
        views.setTextViewTextSize(R.id.widget_tiny_status, TypedValue.COMPLEX_UNIT_SP,
            if (veryLarge) 7f else if (large) 10f else 11f)
        views.setTextViewTextSize(R.id.widget_take, TypedValue.COMPLEX_UNIT_SP,
            if (veryLarge) 8f else if (large) 12f else 15f)
        // 가로 화면 1칸(약 51dp)은 큰 글씨에서 안내 두 줄과 저장 상태가 함께 들어가지 않는다.
        warning(views, scale, known && overdue, if (veryLarge || (large && height < 60)) 1 else 2)
        return views
    }

    // Function Name: sized
    // Description: Reduces padding and optional detail at short heights while retaining state and primary actions.
    // Parameters: context (Context), base (RemoteViews), height (Int, dp), known/overdue/hasPager (Boolean).
    // Returns: A resized RemoteViews clone. Minimal layouts move time-slot and save state into the heading.
    @Suppress("DEPRECATION")
    fun sized(context: Context, base: RemoteViews, height: Int,
        known: Boolean, overdue: Boolean, hasPager: Boolean): RemoteViews {
        val views = base.clone()
        val scale = context.resources.configuration.fontScale
        val large = scale > 1.15f
        val veryLarge = scale > 1.6f
        val tiny = height < 180
        val minimal = height < 230
        // 세로 화면 4 x 2(약 234dp)는 기존 짧은 배치보다 몇 dp 낮아 여백과 제목 글씨만 더 줄인다.
        val snug = !minimal && height < 240
        val short = height < 300 || (height < 340 && large)
        val compact = height < 340 || large
        val verticalPadding = if (tiny || snug) 2 else if (short) 4 else 16
        val horizontalPadding = if (short) 12 else 16
        val density = context.resources.displayMetrics.density
        views.setViewPadding(R.id.widget_root,
            (horizontalPadding * density).toInt(), (verticalPadding * density).toInt(),
            (horizontalPadding * density).toInt(), (verticalPadding * density).toInt())
        views.setTextViewTextSize(R.id.widget_heading, TypedValue.COMPLEX_UNIT_SP,
            if (minimal || (snug && veryLarge)) 14f else if (snug) 16f else if (short) 18f else 21f)
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
        if (tiny) {
            // 제목·날짜 자리에 시간대와 저장 상태를 두고 본문·시간대 전환·진행 막대를 숨겨 복용 버튼을 지킨다.
            views.setTextViewTextSize(R.id.widget_tiny_heading, TypedValue.COMPLEX_UNIT_SP, if (veryLarge) 10f else 14f)
            views.setTextViewTextSize(R.id.widget_tiny_status, TypedValue.COMPLEX_UNIT_SP, if (veryLarge) 8f else 11f)
            for (id in listOf(R.id.widget_title, R.id.widget_date))
                views.setViewVisibility(id, if (known) View.GONE else View.VISIBLE)
            for (id in listOf(R.id.widget_tiny_heading, R.id.widget_tiny_status))
                views.setViewVisibility(id, if (known) View.VISIBLE else View.GONE)
            for (id in listOf(R.id.widget_content, R.id.widget_pager, R.id.widget_progress, R.id.widget_status))
                views.setViewVisibility(id, View.GONE)
            warning(views, scale, known && overdue, if (veryLarge) 1 else 2)
        }
        return views
    }

    // Function Name: warning
    // Description: Places missed-dose guidance beside the time slot when the main body is hidden.
    // Parameters: views (RemoteViews), scale (Float), shown (Boolean), lines (Int) control visibility and fit.
    // Returns: Unit. Updates the supplied view and permits ellipsis when available width is insufficient.
    private fun warning(views: RemoteViews, scale: Float, shown: Boolean, lines: Int) {
        views.setTextViewTextSize(R.id.widget_tiny_warning, TypedValue.COMPLEX_UNIT_SP,
            if (scale > 1.6f) 7f else if (scale > 1.15f) 9f else 11f)
        // 줄이 넘치면 제목 줄이 48dp를 넘어 복용 버튼을 밀어내므로 호출한 배치가 줄 수를 정한다.
        views.setInt(R.id.widget_tiny_warning, "setMaxLines", lines)
        views.setViewVisibility(R.id.widget_tiny_warning, if (shown) View.VISIBLE else View.GONE)
    }
}
