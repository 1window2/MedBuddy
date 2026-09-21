package com.example.medbuddy_frontend

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
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

// Native receiver only journals opaque taps and renders. Dose ownership
// and idempotency are validated atomically in the encrypted Dart store.
class DoseWidgetProvider : HomeWidgetProvider() {
    // 함수이름: onReceive
    // 함수역할: 복용/새로고침 요청만 받아 저장하고 백그라운드 처리를 시작한다.
    // 매개변수: context 위젯 실행 환경, intent 버튼 요청. 반환값: 없음.
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) {
            super.onReceive(context, intent)
            return
        }
        val data = HomeWidgetPlugin.getData(context)
        val kind = intent.data?.host ?: return
        if (kind != "refresh") {
            if (kind != "take") return
            val token = intent.data?.getQueryParameter("token") ?: return
            synchronized(lock) {
                val state = json(data.getString(STATE, "{}"))
                if (token != state.optString("token") || kind != state.optString("action") ||
                    System.currentTimeMillis() >= state.optLong("expires")) return
                val queue = queue(data)
                if (queue.length() != 0) return
                queue.put(JSONObject().put("action", kind).put("token", token))
                if (!data.edit().putString(JOURNAL, queue.toString()).commit()) {
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
            for (i in 0 until old.length()) {
                val item = old.optJSONObject(i) ?: continue
                if (!tokens.contains(item.optString("token"))) remaining.put(item)
            }
            data.edit().putString(JOURNAL, remaining.toString()).commit()
            remaining.length() > 0
        }
        val english = state.optString("language") == "en"
        fun tr(ko: String, en: String) = if (english) en else ko
        val known = state.has("date")
        // 이전 버전의 되돌리기 화면은 다음 일정으로 새로고침한다.
        val expired = System.currentTimeMillis() >= state.optLong("expires", 0L) ||
            state.optString("action") == "undo"
        val open = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java,
            Uri.Builder().scheme("medbuddy-widget").authority("schedule")
                .appendQueryParameter("slot", state.optString("slot")).build())
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.dose_home_widget)
            views.setOnClickPendingIntent(R.id.widget_content, open)
            views.setOnClickPendingIntent(R.id.widget_refresh, action(context, "refresh", ""))
            views.setContentDescription(R.id.widget_refresh, tr("새로고침", "Refresh"))
            views.setTextViewText(R.id.widget_title, state.optString("title", tr("나의 복약 일정", "My medication")))
            views.setTextViewText(R.id.widget_heading, when {
                !known -> tr("MedBuddy를 열어주세요", "Open MedBuddy")
                expired -> tr("일정을 새로고침해주세요", "Refresh your schedule")
                else -> state.optString("heading")
            })
            views.setTextViewText(R.id.widget_details, if (known && !expired) state.optString("details") else "")
            views.setTextViewText(R.id.widget_count, if (known) "${state.optInt("done")}/${state.optInt("total")}" else "")
            views.setProgressBar(R.id.widget_progress, state.optInt("total", 1).coerceAtLeast(1), state.optInt("done"), false)
            views.setTextViewText(R.id.widget_status, when {
                pending -> tr("기기에 저장 중", "Saving on device")
                !known -> tr("로그인 후 본인 일정을 표시합니다", "Sign in to view your own doses")
                expired -> tr("지난 일정은 기록하지 않아요", "Old schedules cannot be recorded")
                else -> state.optString("status")
            })
            views.setTextViewText(R.id.widget_warning, tr("놓친 약은 처방·복약지도를 확인하세요", "Check guidance for missed doses"))
            views.setViewVisibility(R.id.widget_warning, if (state.optBoolean("overdue") && !expired) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.widget_take, when {
                pending -> tr("저장 중", "Saving")
                !known -> tr("앱 열기", "Open app")
                expired -> tr("새로고침", "Refresh")
                else -> state.optString("button", tr("일정 열기", "Open schedule"))
            })
            views.setBoolean(R.id.widget_take, "setEnabled", !pending)
            views.setOnClickPendingIntent(R.id.widget_take, when {
                !known -> open
                expired -> action(context, "refresh", "")
                state.optString("action") == "take" -> action(context, "take", state.optString("token"))
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
        private fun json(value: String?) = runCatching { JSONObject(value ?: "{}") }.getOrDefault(JSONObject())
        private fun queue(data: SharedPreferences) = runCatching { JSONArray(data.getString(JOURNAL, "[]")) }.getOrDefault(JSONArray())
        private fun action(context: Context, kind: String, token: String): PendingIntent {
            val intent = Intent(context, DoseWidgetProvider::class.java).apply {
                action = ACTION
                data = Uri.Builder().scheme("medbuddy-widget").authority(kind).appendQueryParameter("token", token).build()
                addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
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
