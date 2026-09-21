package com.example.medbuddy_frontend

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import android.widget.Toast
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.SimpleTimeZone

// Native receiver only journals opaque taps and renders. Dose ownership
// and idempotency are validated atomically in the encrypted Dart store.
class DoseWidgetProvider : HomeWidgetProvider() {
    // 함수이름: onReceive
    // 함수역할: 조회는 즉시 전환하고 복용·취소 요청은 토큰 검증 후 백그라운드 처리한다.
    // 매개변수: context 위젯 실행 환경, intent 버튼 요청. 반환값: 없음.
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) {
            super.onReceive(context, intent)
            return
        }
        val data = HomeWidgetPlugin.getData(context)
        val kind = intent.data?.host ?: return
        if (kind == "page") {
            synchronized(lock) {
                val state = json(data.getString(STATE, "{}"))
                val id = intent.data?.getQueryParameter("widget")?.toIntOrNull() ?: return
                val slot = intent.data?.getQueryParameter("slot") ?: return
                val key = intent.data?.getQueryParameter("context") ?: return
                val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(
                    ComponentName(context, DoseWidgetProvider::class.java))
                if (id !in ids || key != state.optString("navigation_key") ||
                    System.currentTimeMillis() >= state.optLong("expires") ||
                    pages(state).none { it.optString("slot") == slot } ||
                    queue(data).length() > 0) return
                data.edit().putString(pageKey(id), JSONObject()
                    .put("context", key).put("slot", slot).toString()).commit()
            }
            renderAll(context)
            return
        }
        if (kind != "refresh") {
            if (kind != "take" && kind != "cancel") return
            val token = intent.data?.getQueryParameter("token") ?: return
            synchronized(lock) {
                val state = json(data.getString(STATE, "{}"))
                val page = (pages(state) + state).firstOrNull {
                    it.optString("token") == token && it.optString("action") == kind
                }
                if (page == null || token.isEmpty() ||
                    System.currentTimeMillis() >= state.optLong("expires")) return
                val queue = queue(data)
                if (queue.length() != 0) return
                queue.put(JSONObject().put("action", kind).put("token", token)
                    .put("widget", intent.data?.getQueryParameter("widget")?.toIntOrNull()))
                val edit = data.edit().putString(JOURNAL, queue.toString())
                // 취소 후에는 같은 시간대를 유지하여 다시 복용 기록할 수 있게 한다.
                if (kind == "cancel") {
                    val id = intent.data?.getQueryParameter("widget")?.toIntOrNull() ?: -1
                    edit.putString(pageKey(id), JSONObject()
                        .put("context", state.optString("navigation_key"))
                        .put("slot", page.optString("slot")).toString())
                }
                if (!edit.commit()) {
                    Toast.makeText(context, "기록을 저장하지 못했습니다", Toast.LENGTH_SHORT).show()
                    return
                }
            }
        }
        renderAll(context)
        wake(context, data)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        wake(context, HomeWidgetPlugin.getData(context))
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        renderAll(context)
    }

    // 함수이름: onDeleted
    // 함수역할: 제거한 위젯의 조회 위치만 정리한다. 복약 기록에는 영향을 주지 않는다.
    // 매개변수: context 실행 환경, ids 제거된 위젯 번호. 반환값: 없음.
    override fun onDeleted(context: Context, ids: IntArray) {
        val edit = HomeWidgetPlugin.getData(context).edit()
        for (id in ids) edit.remove(pageKey(id))
        edit.apply()
        super.onDeleted(context, ids)
    }

    // 함수이름: onUpdate
    // 함수역할: 처리한 요청을 정리하고 다음 일정과 저장 상태를 모든 위젯에 반영한다.
    // 매개변수: context 실행 환경, manager 위젯 관리자, ids 대상 위젯, data 저장 상태.
    // 반환값: 없음. 이전 되돌리기 화면은 새로고침하여 교체한다.
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, data: SharedPreferences) {
        val state = json(data.getString(STATE, "{}"))
        val pending = synchronized(lock) {
            val handled = state.optJSONArray("handled") ?: JSONArray()
            val tokens = (0 until handled.length()).map { handled.optString(it) }.toSet()
            val remaining = JSONArray()
            val old = queue(data)
            val edit = data.edit()
            for (i in 0 until old.length()) {
                val item = old.optJSONObject(i) ?: continue
                if (!tokens.contains(item.optString("token"))) {
                    remaining.put(item)
                } else if (item.optString("action") == "take") {
                    // 복용 완료 시에만 다음 일정으로 이동하고 취소한 시간대는 유지한다.
                    edit.remove(pageKey(item.optInt("widget", -1)))
                }
            }
            edit.putString(JOURNAL, remaining.toString()).commit()
            remaining.length() > 0
        }
        val english = state.optString("language") == "en"
        fun tr(ko: String, en: String) = if (english) en else ko
        val known = state.has("date")
        // 이전 버전의 되돌리기 화면은 다음 일정으로 새로고침한다.
        val expired = System.currentTimeMillis() >= state.optLong("expires", 0L) ||
            state.optString("action") == "undo"
        val pages = if (known && !expired) pages(state) else emptyList()
        for (id in ids) {
            val selection = json(data.getString(pageKey(id), "{}"))
            val selected = if (selection.optString("context") == state.optString("navigation_key"))
                pages.indexOfFirst { it.optString("slot") == selection.optString("slot") } else -1
            val next = pages.indexOfFirst { it.optString("slot") == state.optString("slot") }
            val index = if (selected >= 0) selected else if (next >= 0) next else pages.lastIndex
            val page = pages.getOrNull(index) ?: state
            val cancelling = known && !expired && page.optString("action") == "cancel"
            val open = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java,
                Uri.Builder().scheme("medbuddy-widget").authority("schedule")
                    .appendQueryParameter("slot", page.optString("slot")).build())
            val views = RemoteViews(context.packageName, R.layout.dose_home_widget)
            // 작은 위젯이나 큰 글씨에서도 제목·버튼이 약 목록에 밀려 잘리지 않게 한다.
            val heightOption = if (context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE)
                AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT
            val height = manager.getAppWidgetOptions(id).getInt(heightOption, 300)
            val largeText = context.resources.configuration.fontScale > 1.15f
            val compact = height < 340 || largeText
            views.setInt(R.id.widget_heading, "setMaxLines", if (compact) 1 else 2)
            val detailLines = if (height < 300 || (largeText && (height < 340 || page.optBoolean("overdue")))) 1 else if (compact) 2 else 3
            views.setInt(R.id.widget_details, "setMaxLines", detailLines)
            views.setInt(R.id.widget_warning, "setMaxLines", if (compact) 1 else 2)
            views.setInt(R.id.widget_status, "setMaxLines", if (compact) 1 else 2)
            views.setOnClickPendingIntent(R.id.widget_content, open)
            views.setOnClickPendingIntent(R.id.widget_refresh, action(context, "refresh", ""))
            views.setContentDescription(R.id.widget_refresh, tr("새로고침", "Refresh"))
            views.setTextViewText(R.id.widget_title, state.optString("title", tr("나의 복약 일정", "My medication")))
            // 갱신이 지연돼도 날짜는 앱의 복약 기준 시간대로 오늘을 표시한다.
            val dateFormat = SimpleDateFormat(if (english) "M/d (EEE)" else "M월 d일 (EEE)",
                if (english) Locale.ENGLISH else Locale.KOREAN)
            dateFormat.timeZone = SimpleTimeZone(state.optInt("utc_offset_minutes", 540) * 60000, "dose")
            views.setTextViewText(R.id.widget_date, if (!expired && state.has("date_label"))
                state.optString("date_label") else dateFormat.format(Date()))
            views.setTextViewText(R.id.widget_heading, when {
                !known -> tr("MedBuddy를 열어주세요", "Open MedBuddy")
                expired -> tr("일정을 새로고침해주세요", "Refresh your schedule")
                else -> page.optString("heading")
            })
            views.setTextViewText(R.id.widget_details, if (known && !expired) page.optString("details") else "")
            views.setTextViewText(R.id.widget_count, if (known) "${state.optInt("done")}/${state.optInt("total")}" else "")
            views.setProgressBar(R.id.widget_progress, state.optInt("total", 1).coerceAtLeast(1), state.optInt("done"), false)
            views.setTextViewText(R.id.widget_status, when {
                pending -> tr("기기에 저장 중", "Saving on device")
                !known -> tr("로그인 후 본인 일정을 표시합니다", "Sign in to view your own doses")
                expired -> tr("지난 일정은 기록하지 않아요", "Old schedules cannot be recorded")
                else -> state.optString("status")
            })
            views.setTextViewText(R.id.widget_warning, tr("놓친 약은 처방·복약지도를 확인하세요", "Check guidance for missed doses"))
            views.setViewVisibility(R.id.widget_warning, if (page.optBoolean("overdue") && !expired) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.widget_pager, if (pages.size > 1) View.VISIBLE else View.GONE)
            val dots = intArrayOf(R.id.widget_dot_0, R.id.widget_dot_1, R.id.widget_dot_2, R.id.widget_dot_3)
            for (position in dots.indices) {
                views.setViewVisibility(dots[position], if (position < pages.size) View.VISIBLE else View.GONE)
                val target = pages.getOrNull(position) ?: continue
                views.setImageViewResource(dots[position], if (position == index)
                    R.drawable.dose_widget_dot_active else R.drawable.dose_widget_dot)
                val description = "${target.optString("label")}, ${position + 1}/${pages.size}" +
                    if (position == index) tr(", 선택됨", ", selected") else ""
                views.setContentDescription(dots[position], description)
                views.setBoolean(dots[position], "setEnabled", !pending)
                views.setOnClickPendingIntent(dots[position], pageAction(context, id,
                    target.optString("slot"), state.optString("navigation_key")))
            }
            for ((button, targetIndex) in listOf(R.id.widget_previous to index - 1, R.id.widget_next to index + 1)) {
                val target = pages.getOrNull(targetIndex)
                views.setViewVisibility(button, if (target != null) View.VISIBLE else View.INVISIBLE)
                views.setBoolean(button, "setEnabled", !pending && target != null)
                views.setContentDescription(button, if (button == R.id.widget_previous)
                    tr("이전 복약 일정", "Previous medication slot") else tr("다음 복약 일정", "Next medication slot"))
                if (target != null) views.setOnClickPendingIntent(button, pageAction(context, id,
                    target.optString("slot"), state.optString("navigation_key")))
            }
            views.setTextViewText(R.id.widget_take, when {
                pending -> tr("저장 중", "Saving")
                !known -> tr("앱 열기", "Open app")
                expired -> tr("새로고침", "Refresh")
                else -> page.optString("button", tr("일정 열기", "Open schedule"))
            })
            views.setInt(R.id.widget_take, "setBackgroundResource", if (cancelling)
                R.drawable.dose_widget_cancel_button else R.drawable.dose_widget_button)
            views.setTextColor(R.id.widget_take, Color.parseColor(if (cancelling) "#007E5E" else "#FFFFFF"))
            views.setContentDescription(R.id.widget_take, when {
                pending -> tr("저장 중", "Saving")
                cancelling -> "${page.optString("label")} " + tr("복용 기록 취소", "undo dose record")
                known && !expired && page.optString("action") == "take" ->
                    "${page.optString("label")} " + tr("복용했어요", "mark as taken")
                else -> null
            })
            views.setBoolean(R.id.widget_take, "setEnabled", !pending)
            views.setOnClickPendingIntent(R.id.widget_take, when {
                !known -> open
                expired -> action(context, "refresh", "")
                page.optString("action") in listOf("take", "cancel") ->
                    action(context, page.optString("action"), page.optString("token"), id)
                else -> open
            })
            manager.updateAppWidget(id, views)
        }
        // Recover a killed callback and refresh the day without a polling loop.
        if ((pending || expired) && System.currentTimeMillis() - data.getLong(LAST_WAKE, 0L) > 5000) wake(context, data)
    }

    companion object {
        private const val ACTION = "com.medbuddy.app.DOSE_WIDGET_ACTION"
        private const val STATE = "dose_widget_state"
        private const val JOURNAL = "dose_widget_actions"
        private const val LAST_WAKE = "dose_widget_last_wake"
        private val lock = Any()
        private fun pageKey(id: Int) = "dose_widget_page_$id"
        // 함수이름: pages / 함수역할: 표시 가능한 시간대 페이지를 읽는다.
        // 매개변수: state 위젯 상태. 반환값: 시간대 순서의 표시 데이터.
        private fun pages(state: JSONObject): List<JSONObject> {
            val items = state.optJSONArray("pages") ?: return emptyList()
            return (0 until items.length()).mapNotNull { items.optJSONObject(it) }
        }
        private fun json(value: String?) = runCatching { JSONObject(value ?: "{}") }.getOrDefault(JSONObject())
        private fun queue(data: SharedPreferences) = runCatching { JSONArray(data.getString(JOURNAL, "[]")) }.getOrDefault(JSONArray())
        private fun action(context: Context, kind: String, token: String, widget: Int = -1): PendingIntent {
            val intent = Intent(context, DoseWidgetProvider::class.java).apply {
                action = ACTION
                data = Uri.Builder().scheme("medbuddy-widget").authority(kind).appendQueryParameter("token", token)
                    .appendQueryParameter("widget", widget.toString()).build()
                addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
            }
            return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        // 함수이름: pageAction
        // 함수역할: 복약을 기록하지 않는 조회 전환 요청을 위젯별로 만든다.
        // 매개변수: context 실행 환경, id 위젯 번호, slot 대상 시간대, key 계정·날짜 구분용 토큰.
        // 반환값: 홈 화면에서 즉시 처리하는 페이지 선택 요청.
        private fun pageAction(context: Context, id: Int, slot: String, key: String): PendingIntent {
            val intent = Intent(context, DoseWidgetProvider::class.java).apply {
                action = ACTION
                data = Uri.Builder().scheme("medbuddy-widget").authority("page")
                    .appendQueryParameter("widget", id.toString()).appendQueryParameter("slot", slot)
                    .appendQueryParameter("context", key).build()
            }
            return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        private fun wake(context: Context, data: SharedPreferences) {
            data.edit().putLong(LAST_WAKE, System.currentTimeMillis()).apply()
            HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("medbuddy-widget://refresh")).send()
        }
        private fun renderAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, DoseWidgetProvider::class.java))
            DoseWidgetProvider().onUpdate(context, manager, ids, HomeWidgetPlugin.getData(context))
        }
    }
}
