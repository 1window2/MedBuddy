package com.example.medbuddy_frontend

import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import es.antonborri.home_widget.HomeWidgetBackgroundWorker

// 파일명: DoseWidgetRefreshScheduler.kt
// 역할: 실패한 위젯 작업이 다음 클릭까지 막지 않도록 백그라운드 갱신을 예약한다.
// 클래스명: DoseWidgetRefreshScheduler
// 주요 책임: 기존 위젯 실행 계약을 유지하며 실패·취소 뒤의 요청을 복구한다.
// 속성: WORK_NAME - 플러그인이 사용하는 고유 작업 대기열 이름.
internal object DoseWidgetRefreshScheduler {
    // home_widget 0.10의 작업 이름과 입력 키를 유지해 기존 실패 대기열도 복구한다.
    private const val WORK_NAME = "home_widget_background"

    // 함수이름: request
    // 함수역할: 네트워크 없이도 기기 내 복용 기록을 먼저 처리할 갱신 요청을 만든다.
    // 매개변수: 없음. 반환값: home_widget의 Dart 콜백을 실행할 작업.
    fun request(): OneTimeWorkRequest = OneTimeWorkRequestBuilder<HomeWidgetBackgroundWorker>()
        .setInputData(Data.Builder().putString("uri_data", "medbuddy-widget://refresh").build())
        .build()

    // 함수이름: enqueue
    // 함수역할: 진행 중인 작업은 이어가되 실패·취소된 작업의 상태는 새 요청에 전파하지 않는다.
    // 매개변수: manager 작업 관리자, name 대기열 이름, work 갱신 작업.
    // 반환값: 예약 완료를 확인할 작업. 시험에서는 별도 대기열과 기록 없는 작업을 사용한다.
    fun enqueue(
        manager: WorkManager,
        name: String = WORK_NAME,
        work: OneTimeWorkRequest = request(),
    ) = manager.enqueueUniqueWork(name, ExistingWorkPolicy.APPEND_OR_REPLACE, work)
}
