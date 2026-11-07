// 파일명: check_caregiver_home_control.dart
// 역할: 환자 일정 표시를 선택한 사용자에게 연결 환자의 오늘 복약 현황을 제공한다.
import 'package:flutter/foundation.dart';
import 'dart:convert';

import '../entities/caregiver_monitoring_snapshot_entity.dart';
import '../entities/dose_widget_state.dart';
import '../entities/patient_caregiver_link_entity.dart';
import 'check_caregiver_medication_control.dart';

// Class Name: CheckCaregiverHome
// Role: Maintains today's linked-patient progress for a caregiver's home screen.
// Responsibilities: Filter active caregiver links, discard stale or cross-day responses, and publish loading and failure state.
// Attributes: userHash identifies the owner; _links defines scope; _snapshots and _snapshotDay hold same-day results; _generation invalidates old requests.
class CheckCaregiverHome extends ChangeNotifier {
  final String userHash;
  final CheckCaregiverMedication _control;
  final bool _ownsControl;
  final DateTime Function() _clock;
  List<PatientCaregiverLink> _links = const [];
  Map<int, CaregiverMonitoringSnapshot> _snapshots = const {};
  bool _isLoading = false;
  // Function Name: isLoading
  // Description: Exposes the controller-owned progress flag without allowing external mutation.
  // Parameters: None.
  // Returns: Whether a home snapshot request is in progress.
  bool get isLoading => _isLoading;
  bool _hasError = false;
  // Function Name: hasError
  // Description: Distinguishes a failed home refresh from a successful empty result.
  // Parameters: None.
  // Returns: Whether the latest applicable refresh failed.
  bool get hasError => _hasError;
  bool _disposed = false;
  int _generation = 0;
  String? _snapshotDay;

  // Function Name: widgetCache
  // Description: Serializes only current links and withholds schedules after their snapshot day expires.
  // Parameters: None.
  // Returns: Widget cache containing the current day, failure flag, and linked patients; expired schedules are null.
  Map<String, dynamic> get widgetCache => {
    'date': doseWidgetDay(_clock()),
    'failed': _hasError,
    'patients': [
      for (final link in _links)
        {
          'link': link.toJson(),
          'schedules': _snapshotDay == doseWidgetDay(_clock())
              ? _snapshots[link.linkId]?.schedules
                    .map((s) => s.toJson())
                    .toList()
              : null,
        },
    ],
  };

  // Function Name: CheckCaregiverHome
  // Description: Binds the home state to an account, caregiver query control and clock.
  // Parameters: userHash: Owning account; control: Optional caller-owned query control; clock: Optional day-boundary clock, defaulting to DateTime.now.
  // Returns: A controller that disposes only a query control it creates.
  CheckCaregiverHome({
    required this.userHash,
    CheckCaregiverMedication? control,
    DateTime Function()? clock,
  }) : _control = control ?? CheckCaregiverMedication(caregiverHash: userHash),
       _ownsControl = control == null,
       _clock = clock ?? DateTime.now;

  // 함수이름: links
  // 함수역할: 홈 조회에 허용된 현재 보호자 연동을 외부 수정 불가 목록으로 제공한다.
  // 매개변수: 없음.
  // 반환값: 활성 연동 목록의 읽기 전용 복사본.
  List<PatientCaregiverLink> get links => List.unmodifiable(_links);
  // Function Name: snapshotFor
  // Description: Reads a patient's cached snapshot only while its recorded day is current.
  // Parameters: linkId: Optional link identifier.
  // Returns: The matching current-day snapshot, or null for missing or expired data.
  CaregiverMonitoringSnapshot? snapshotFor(int? linkId) =>
      _snapshotDay == doseWidgetDay(_clock()) ? _snapshots[linkId] : null;

  // 함수이름: updateLinks
  // 함수역할: 현재 계정의 유효한 보호자 연동만 유지한다. 연동 식별자가 바뀌면 진행 중 응답과 현황을 무효화한다.
  // 매개변수: links: 서버에서 받은 최신 연동 목록.
  // 반환값: 없음; 같은 목록이나 종료된 객체는 알리지 않고 나머지 변경은 구독자에게 알린다.
  void updateLinks(List<PatientCaregiverLink> links) {
    if (_disposed) return;
    final next = links
        .where(
          (link) =>
              link.linkStatus &&
              (link.linkId ?? 0) > 0 &&
              link.caregiverHash == userHash &&
              link.patientHash.isNotEmpty &&
              link.patientHash != userHash,
        )
        .toList();
    final oldKeys = _links
        .map((link) => (link.linkId, link.patientHash))
        .toSet();
    final nextKeys = next
        .map((link) => (link.linkId, link.patientHash))
        .toSet();
    if (jsonEncode(_links.map((l) => l.toJson()).toList()) ==
        jsonEncode(next.map((l) => l.toJson()).toList())) {
      return;
    }
    if (!setEquals(oldKeys, nextKeys)) {
      _generation++;
      _snapshots = {};
    }
    _links = next;
    notifyListeners();
  }

  // Function Name: refresh
  // Description: Loads linked-patient schedules, rejecting responses after disposal, scope changes or midnight.
  // Parameters: None.
  // Returns: A completion Future; busy, empty-scope and disposed calls return immediately, while applicable failures clear snapshots and set hasError.
  Future<void> refresh() async {
    if (_disposed || _isLoading || _links.isEmpty) return;
    final generation = _generation;
    final day = doseWidgetDay(_clock());
    _isLoading = true;
    notifyListeners();
    try {
      _hasError = false;
      // 홈 전용 일괄 조회는 알림이 꺼진 환자도 포함하고 약 상세는 제외한다.
      final received = await _control.requestScheduleSnapshot(links: _links);
      if (_disposed || generation != _generation) return;
      // 조회 중 자정이 지나면 받은 현황은 어제 것이므로 표시하지 않고 비운다.
      if (day != doseWidgetDay(_clock())) {
        _snapshots = {};
        _snapshotDay = null;
        return;
      }
      _snapshots = {
        for (final snapshot in received)
          if (snapshot.link.linkStatus &&
              snapshot.link.caregiverHash == userHash &&
              _links.any(
                (link) =>
                    link.linkId == snapshot.link.linkId &&
                    link.patientHash == snapshot.patientHash,
              ))
            snapshot.link.linkId!: snapshot,
      };
      _snapshotDay = day;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _hasError = true;
      _snapshots = {};
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  // 함수이름: dispose
  // 함수역할: 세대 번호를 바꿔 진행 중 응답을 무효화하고 직접 생성한 조회 객체만 해제한다.
  // 매개변수: 없음.
  // 반환값: 없음; 주입된 조회 객체의 수명은 호출자가 관리한다.
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    if (_ownsControl) _control.dispose();
    super.dispose();
  }
}
