package com.example.medbuddy_frontend

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import java.util.concurrent.TimeUnit

// 파일명: DoseWidgetRefreshSchedulerTest.kt
// 역할: 기존 실패·취소 뒤에도 새 위젯 요청이 실행되는지 Android 작업 관리자에서 확인한다.
// 실제 복약 기록과 위젯 대기열은 건드리지 않고 시험 전용 작업만 사용한다.
// 클래스명: DoseWidgetRefreshSchedulerTest
// 주요 책임: 콜백 입력, 실패 복구와 정상 대기열 순서를 검증한다. 별도 보관 속성은 없다.
@RunWith(AndroidJUnit4::class)
class DoseWidgetRefreshSchedulerTest {
    // 함수이름: refreshRequestKeepsPluginContractAndAllowsOfflineStorage
    // 함수역할: 플러그인 콜백 입력과 네트워크 없는 로컬 저장 경로를 검증한다.
    // 매개변수: 없음. 반환값: 없음, 위젯 실행 계약이 바뀌면 실패한다.
    @Test fun refreshRequestKeepsPluginContractAndAllowsOfflineStorage() {
        val request = DoseWidgetRefreshScheduler.request()
        assertTrue(request.tags.contains("es.antonborri.home_widget.HomeWidgetBackgroundWorker"))
        assertEquals("medbuddy-widget://refresh", request.workSpec.input.getString("uri_data"))
        assertEquals(Constraints.NONE, request.workSpec.constraints)
    }

    // 함수이름: failedChainDoesNotRejectTheNextRefresh
    // 함수역할: 기존 APPEND 방식의 실패 전파를 재현한 뒤 새 예약 방식이 복구하는지 확인한다.
    // 매개변수: 없음. 반환값: 없음, 새 요청이 실행되지 않으면 실패한다.
    @Test fun failedChainDoesNotRejectTheNextRefresh() = withQueue { manager, name ->
        val failed = OneTimeWorkRequestBuilder<WidgetFailureProbe>().build()
        manager.enqueueUniqueWork(name, ExistingWorkPolicy.APPEND, failed).result.get(10, TimeUnit.SECONDS)
        awaitState(manager, failed.id, WorkInfo.State.FAILED)
        val inherited = OneTimeWorkRequestBuilder<WidgetSuccessProbe>().build()
        manager.enqueueUniqueWork(name, ExistingWorkPolicy.APPEND, inherited).result.get(10, TimeUnit.SECONDS)
        awaitState(manager, inherited.id, WorkInfo.State.FAILED)
        val recovered = OneTimeWorkRequestBuilder<WidgetSuccessProbe>().build()
        DoseWidgetRefreshScheduler.enqueue(manager, name, recovered).result.get(10, TimeUnit.SECONDS)
        awaitState(manager, recovered.id, WorkInfo.State.SUCCEEDED)
    }

    // 함수이름: cancelledChainDoesNotRejectTheNextRefresh
    // 함수역할: 취소된 작업 뒤의 클릭도 실패 때와 같이 독립적으로 처리되는지 확인한다.
    // 매개변수: 없음. 반환값: 없음, 새 요청이 취소 상태를 물려받으면 실패한다.
    @Test fun cancelledChainDoesNotRejectTheNextRefresh() = withQueue { manager, name ->
        val cancelled = OneTimeWorkRequestBuilder<WidgetSuccessProbe>()
            .setInitialDelay(1, TimeUnit.DAYS).build()
        manager.enqueueUniqueWork(name, ExistingWorkPolicy.APPEND, cancelled).result.get(10, TimeUnit.SECONDS)
        manager.cancelUniqueWork(name).result.get(10, TimeUnit.SECONDS)
        awaitState(manager, cancelled.id, WorkInfo.State.CANCELLED)
        val recovered = OneTimeWorkRequestBuilder<WidgetSuccessProbe>().build()
        DoseWidgetRefreshScheduler.enqueue(manager, name, recovered).result.get(10, TimeUnit.SECONDS)
        awaitState(manager, recovered.id, WorkInfo.State.SUCCEEDED)
    }

    // 함수이름: pendingWorkIsNotCancelledByAnotherRefresh
    // 함수역할: 복구 정책이 진행 가능한 기존 작업을 취소하거나 순서를 건너뛰지 않게 한다.
    // 매개변수: 없음. 반환값: 없음, 선행 작업이 대체되면 실패한다.
    @Test fun pendingWorkIsNotCancelledByAnotherRefresh() = withQueue { manager, name ->
        val first = OneTimeWorkRequestBuilder<WidgetSuccessProbe>()
            .setInitialDelay(1, TimeUnit.DAYS).build()
        DoseWidgetRefreshScheduler.enqueue(manager, name, first).result.get(10, TimeUnit.SECONDS)
        val next = OneTimeWorkRequestBuilder<WidgetSuccessProbe>().build()
        DoseWidgetRefreshScheduler.enqueue(manager, name, next).result.get(10, TimeUnit.SECONDS)
        awaitState(manager, first.id, WorkInfo.State.ENQUEUED)
        awaitState(manager, next.id, WorkInfo.State.BLOCKED)
    }

    // 함수이름: withQueue
    // 함수역할: 각 시험에 독립된 대기열을 만들고 종료 시 해당 시험 작업만 취소한다.
    // 매개변수: check 검증 동작. 반환값: 없음.
    private fun withQueue(check: (WorkManager, String) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val manager = WorkManager.getInstance(context)
        val name = "medbuddy.widget.test.${UUID.randomUUID()}"
        try { check(manager, name) }
        finally { manager.cancelUniqueWork(name).result.get(10, TimeUnit.SECONDS) }
    }

    // 함수이름: awaitState
    // 함수역할: Android 비동기 작업의 실제 결과를 제한 시간 안에 확인한다.
    // 매개변수: manager 작업 관리자, id 작업 번호, expected 기대 상태. 반환값: 없음.
    private fun awaitState(manager: WorkManager, id: UUID, expected: WorkInfo.State) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20)
        do {
            val state = manager.getWorkInfoById(id).get(5, TimeUnit.SECONDS)?.state
            if (state == expected) return
            assertFalse("Unexpected terminal state: $state; expected $expected", state?.isFinished == true)
            Thread.sleep(50)
        } while (System.nanoTime() < deadline)
        assertEquals(expected, manager.getWorkInfoById(id).get(5, TimeUnit.SECONDS)?.state)
    }
}

// 클래스명: WidgetFailureProbe
// 역할: 실패 전파를 재현한다. 파일, 네트워크, 복약 데이터와 별도 보관 속성은 사용하지 않는다.
// 생성자: context 실행 환경과 parameters 작업 설정을 Android Worker에 전달한다.
class WidgetFailureProbe(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    // 함수이름: doWork / 함수역할: 시험용 실패를 반환한다. 매개변수: 없음. 반환값: 실패 상태.
    override fun doWork(): Result = Result.failure()
}

// 클래스명: WidgetSuccessProbe
// 역할: 복구된 작업의 실행 여부를 확인한다. 복약 데이터와 별도 보관 속성은 사용하지 않는다.
// 생성자: context 실행 환경과 parameters 작업 설정을 Android Worker에 전달한다.
class WidgetSuccessProbe(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    // 함수이름: doWork / 함수역할: 실행 완료를 반환한다. 매개변수: 없음. 반환값: 성공 상태.
    override fun doWork(): Result = Result.success()
}
