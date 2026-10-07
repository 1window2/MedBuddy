package com.example.medbuddy_frontend

import android.content.Context
import android.content.res.Configuration
import android.view.ContextThemeWrapper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.RemoteViews
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.roundToInt

// 파일명: DoseWidgetLayoutTest.kt
// 역할: 실제 Android 글꼴 측정으로 최소 높이와 큰 글씨에서 위젯 잘림을 확인한다.
// 클래스명: DoseWidgetLayoutTest
// 주요 책임: 런처 크기 계약, 상태별 텍스트 영역과 조작 버튼의 크기를 검증한다.
@RunWith(AndroidJUnit4::class)
class DoseWidgetLayoutTest {
    // 함수이름: providerKeepsTargetWithinResizeBounds
    // 함수역할: 기본 높이와 회전별 최소 높이를 분리해 4 x 3 요청이 무시되는 회귀를 막는다.
    // 매개변수: 없음. 반환값: 없음, 잘못된 크기 선언에서 실패한다.
    @Test fun providerKeepsTargetWithinResizeBounds() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        context.resources.getXml(R.xml.dose_home_widget_info).use { parser ->
            while (parser.next() != org.xmlpull.v1.XmlPullParser.START_TAG) { }
            val values = context.obtainStyledAttributes(parser, intArrayOf(
                android.R.attr.minHeight, android.R.attr.minResizeHeight,
                android.R.attr.targetCellWidth, android.R.attr.targetCellHeight,
            ))
            try {
                val height = (240 * context.resources.displayMetrics.density).roundToInt()
                assertEquals(height, values.getDimensionPixelSize(0, -1))
                assertEquals((180 * context.resources.displayMetrics.density).roundToInt(), values.getDimensionPixelSize(1, -1))
                assertEquals(4, values.getInt(2, -1))
                assertEquals(3, values.getInt(3, -1))
            } finally { values.recycle() }
        }
    }

    // 함수이름: resizedContentFitsWithoutShrinkingActionTargets
    // 함수역할: 크기·글자 배율·로그인 상태별 배치를 실측하며 계정이나 기록은 변경하지 않는다.
    // 매개변수: 없음. 반환값: 없음, 잘린 내용 또는 축소된 핵심 버튼에서 실패한다.
    @Test fun resizedContentFitsWithoutShrinkingActionTargets() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val failures = mutableListOf<String>()
        instrumentation.runOnMainSync {
            for (height in listOf(180, 240, 300, 340, 420)) for (width in listOf(250, 360)) {
                for (scale in listOf(1f, 1.3f, 2f)) for (state in listOf("patient", "caregiver", "signed-out")) for (overdue in listOf(false, true)) {
                    val config = Configuration(instrumentation.targetContext.resources.configuration)
                    config.fontScale = scale
                    val context = ContextThemeWrapper(instrumentation.targetContext.createConfigurationContext(config),
                        android.R.style.Theme_Material_Light_NoActionBar)
                    val known = state != "signed-out"
                    val views = DoseWidgetLayout.sized(context, sampleViews(context, state), height, known, known && overdue, known)
                    val root = views.apply(context, FrameLayout(context))
                    assertEquals(scale, root.resources.configuration.fontScale, 0.01f)
                    val density = context.resources.displayMetrics.density
                    root.measure(View.MeasureSpec.makeMeasureSpec((width * density).roundToInt(), View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec((height * density).roundToInt(), View.MeasureSpec.EXACTLY))
                    root.layout(0, 0, root.measuredWidth, root.measuredHeight)
                    val label = "$state ${width}x$height font=$scale overdue=$overdue"
                    try {
                        assertVisibleContentFits(root, label)
                        for (id in listOf(R.id.widget_dot_0, R.id.widget_dot_1, R.id.widget_dot_2, R.id.widget_dot_3)) {
                            val dot = root.findViewById<View>(id)
                            if (!isVisible(dot)) continue
                            assertTrue("$label dot $id clipped", dot.height >= (16 * density).toInt() && dot.width >= (16 * density).toInt())
                        }
                        for (id in listOf(R.id.widget_take, R.id.widget_previous, R.id.widget_next,
                            R.id.widget_refresh, R.id.widget_patient_previous, R.id.widget_patient_next)) {
                            val button = root.findViewById<View>(id)
                            if (!isVisible(button)) continue
                            assertTrue("$label button $id height", button.height >= (48 * density).toInt())
                            assertTrue("$label button $id width", button.width >= (48 * density).toInt())
                        }
                    } catch (failure: AssertionError) { failures.add("${failure.message}\n${describe(root)}") }
                }
            }
        }
        assertTrue(failures.joinToString("\n\n"), failures.isEmpty())
    }

    // 함수이름: isVisible
    // 함수역할: 숨겨진 부모 안의 버튼을 조작 영역 검사에서 제외한다.
    // 매개변수: view 검사 대상. 반환값: 부모까지 모두 표시 상태인지 여부.
    private fun isVisible(view: View): Boolean = view.visibility == View.VISIBLE &&
        ((view.parent as? View)?.let { isVisible(it) } ?: true)

    // 함수이름: sampleViews
    // 함수역할: 네트워크 요청과 복용 기록이 없는 표시 전용 시험 상태를 만든다.
    // 매개변수: context 리소스 환경, state 상태 이름. 반환값: 대표 내용과 표시 여부.
    private fun sampleViews(context: Context, state: String): RemoteViews {
        val known = state != "signed-out"
        return RemoteViews(context.packageName, R.layout.dose_home_widget).apply {
            setTextViewText(R.id.widget_title, if (state == "caregiver") "환자 테스트 이름" else "나의 복약 일정")
            setTextViewText(R.id.widget_date, "9월 23일 (수)")
            setTextViewText(R.id.widget_heading, if (known) "아침 · 미복용" else "로그인이 필요해요")
            setTextViewText(R.id.widget_compact_heading, "아침 08:00")
            setTextViewText(R.id.widget_details, if (known) "08:00 · 이름이 긴 아침약 외 2개" else "로그인하면 복약 일정을 볼 수 있어요.")
            setTextViewText(R.id.widget_warning, "놓친 약은 처방·복약지도를 확인하세요")
            setTextViewText(R.id.widget_status, "2/5 · 서버 전송 대기 중")
            setTextViewText(R.id.widget_count, "2/5")
            setTextViewText(R.id.widget_take, if (state == "caregiver") "일정 보기" else if (known) "복용했어요" else "로그인하기")
            for (id in listOf(R.id.widget_pager, R.id.widget_status, R.id.widget_refresh))
                setViewVisibility(id, if (known) View.VISIBLE else View.GONE)
            setViewVisibility(R.id.widget_count, if (state == "patient") View.VISIBLE else View.GONE)
            for (id in listOf(R.id.widget_patient_previous, R.id.widget_patient_next))
                setViewVisibility(id, if (state == "caregiver") View.VISIBLE else View.GONE)
        }
    }

    // 함수이름: assertVisibleContentFits
    // 함수역할: 보이는 자식의 부모 경계와 실제 텍스트 줄 높이를 재귀적으로 검사한다.
    // 매개변수: view 측정한 뷰, label 실패 사례 설명. 반환값: 없음, 잘리면 실패한다.
    private fun assertVisibleContentFits(view: View, label: String) {
        if (view.visibility != View.VISIBLE) return
        if (view is TextView && view.text.isNotEmpty()) {
            val lines = view.layout
            if (lines != null) assertTrue("$label text ${view.resources.getResourceEntryName(view.id)}: ${lines.height} > ${view.height}",
                lines.height <= view.height - view.compoundPaddingTop - view.compoundPaddingBottom + 1)
        }
        if (view is ViewGroup) for (index in 0 until view.childCount) {
            val child = view.getChildAt(index)
            if (child.visibility != View.VISIBLE) continue
            assertTrue("$label child ${child.id} outside height ${view.height}: ${child.top}..${child.bottom}",
                child.top >= 0 && child.bottom <= view.height)
            assertTrue("$label child ${child.id} outside width ${view.width}", child.left >= 0 && child.right <= view.width)
            assertVisibleContentFits(child, label)
        }
    }

    // 함수이름: describe
    // 함수역할: 실패한 배치의 실제 치수를 표시하여 잘린 뷰를 추적한다.
    // 매개변수: view 측정한 뷰. 반환값: 보이는 뷰의 높이와 텍스트 치수.
    private fun describe(view: View): String {
        if (view.visibility != View.VISIBLE) return ""
        val name = if (view.id == View.NO_ID) view.javaClass.simpleName else view.resources.getResourceEntryName(view.id)
        val line = "$name ${view.width}x${view.height}" + if (view is TextView) " text=${view.layout?.height}" else ""
        return line + if (view is ViewGroup) (0 until view.childCount).joinToString("\n", "\n") { describe(view.getChildAt(it)) } else ""
    }
}
