// 파일명: dose_home_widget_background.dart
// 역할: 홈 위젯 서비스에 서버 조회 Control을 연결하고 위젯의 백그라운드 진입점을 제공한다.

import 'package:flutter/widgets.dart';

import '../controls/check_caregiver_medication_control.dart';
import '../controls/check_schedule_control.dart';
import '../services/dose_home_widget_service.dart';
import '../services/dose_sync_service.dart';

// 함수이름: installDoseHomeWidgetReaders
// 함수역할: 위젯 서비스가 Control을 직접 만들지 않도록 오늘 일정과 연동 환자 일정을 읽는 함수를 넣는다.
//   앱 시작, 위젯 진입점, 백그라운드 작업 진입점에서 한 번씩 호출하며 여러 번 호출해도 결과는 같다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음.
void installDoseHomeWidgetReaders() {
  DoseHomeWidget.readScheduleWindow = (owner, client) {
    return CheckSchedule(
      patientHash: owner,
      client: client,
    ).requestOfflineScheduleWindow(
      expectedStartDay: doseScheduleDay(DateTime.now()),
    );
  };
  DoseHomeWidget.readTodaySchedules = (owner, client) {
    return CheckSchedule(
      patientHash: owner,
      client: client,
    ).requestTodayMedicationSchedule();
  };
  DoseHomeWidget.readPatientSnapshots = (owner, client) {
    return CheckCaregiverMedication(
      caregiverHash: owner,
      client: client,
    ).requestScheduleSnapshot();
  };
}

// Function Name: doseHomeWidgetCallback
// Description: Handle background widget refresh requests after binding initialization; keep this top-level entry point stable because the platform persists its handle.
// Parameters: uri (Uri?): only medbuddy-widget://refresh is accepted.
// Returns: Future<void>: completes after refresh, or immediately for unrelated requests.
@pragma('vm:entry-point')
Future<void> doseHomeWidgetCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (uri?.scheme != 'medbuddy-widget' || uri?.host != 'refresh') return;
  installDoseHomeWidgetReaders();
  await DoseHomeWidget.refreshInBackground(requestedByWidget: true);
  await DoseHomeWidget.retryWhileStale();
}
