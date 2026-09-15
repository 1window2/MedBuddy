// 파일명: check_caregiver_home_control.dart
// 역할: 환자 일정 표시를 선택한 사용자에게 연결 환자의 오늘 복약 현황을 제공한다.
import 'package:flutter/foundation.dart';

import '../entities/caregiver_monitoring_snapshot_entity.dart';
import '../entities/patient_caregiver_link_entity.dart';
import 'check_caregiver_medication_control.dart';

// 클래스명: CheckCaregiverHome
// 역할: 기존 조회 Control을 재사용하고 계정·연동 범위 밖의 응답을 버린다.
// 속성: userHash는 소유 계정, links는 보호자 역할의 활성 연동, snapshots는 오늘 현황이다.
class CheckCaregiverHome extends ChangeNotifier {
  final String userHash;
  final CheckCaregiverMedication _control;
  final bool _ownsControl;
  List<PatientCaregiverLink> _links = const [];
  Map<int, CaregiverMonitoringSnapshot> _snapshots = const {};
  bool isLoading = false;
  bool hasError = false;
  bool _disposed = false;
  int _generation = 0;
  DateTime? updatedAt;

  // 함수역할: 계정과 기존 환자 조회 기능을 연결한다. 주입 Control은 호출자가 소유한다.
  CheckCaregiverHome({
    required this.userHash,
    CheckCaregiverMedication? control,
  }) : _control = control ?? CheckCaregiverMedication(caregiverHash: userHash),
       _ownsControl = control == null;

  List<PatientCaregiverLink> get links => List.unmodifiable(_links);
  CaregiverMonitoringSnapshot? snapshotFor(int? linkId) => _snapshots[linkId];

  // 함수역할: 활성 보호자 연동만 유지하고 해제되거나 바뀐 관계의 진행 중 응답을 무효화한다.
  // 매개변수: 최신 연동 목록. 반환값: 없음.
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
    if (!setEquals(oldKeys, nextKeys)) {
      _generation++;
      _snapshots = {};
      updatedAt = null;
    }
    _links = next;
    notifyListeners();
  }

  // 함수역할: 홈의 명시적 환자 일정 선택에 따라 허용된 환자의 현황을 조회한다.
  // 반환값: 갱신 완료. 실패와 일정 0개는 구분하며 중복 요청은 합친다.
  Future<void> refresh() async {
    if (_disposed || isLoading || _links.isEmpty) return;
    final generation = _generation;
    isLoading = true;
    notifyListeners();
    try {
      hasError = false;
      final received = await _control.requestMonitoringSnapshot();
      if (_disposed || generation != _generation) return;
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
      updatedAt = DateTime.now();
    } catch (_) {
      if (_disposed || generation != _generation) return;
      hasError = true;
      _snapshots = {};
      updatedAt = null;
    } finally {
      isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  // 함수역할: 화면/계정 수명이 끝나면 응답과 소유한 연결을 정리한다.
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    if (_ownsControl) _control.dispose();
    super.dispose();
  }
}
