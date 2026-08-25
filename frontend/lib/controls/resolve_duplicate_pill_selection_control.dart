import '../entities/identified_pill_save_request_entity.dart';
import '../entities/pill_identification_entity.dart';

// 파일명: resolve_duplicate_pill_selection_control.dart
// 역할: 다중 낱알 식별에서 같은 품목과 같은 복약 일정을 안전하게 구분한다.

// 클래스명: DuplicatePillSelectionGroup
// 역할: 여러 사진에서 같은 품목으로 선택된 후보의 개수를 표현한다.
class DuplicatePillSelectionGroup {
  final String itemSeq;
  final String itemName;
  final int count;

  const DuplicatePillSelectionGroup({
    required this.itemSeq,
    required this.itemName,
    required this.count,
  });
}

// 클래스명: ResolveDuplicatePillSelectionControl
// 역할: 같은 품목 사진을 찾고, 사용자가 허용한 경우 같은 일정만 하나로 묶는다.
class ResolveDuplicatePillSelectionControl {
  const ResolveDuplicatePillSelectionControl();

  // 함수명: countEquivalentCandidates
  // 역할: 품목번호 또는 정규화한 약명이 같은 선택 후보의 개수를 반환한다.
  int countEquivalentCandidates(
    Iterable<PillIdentificationCandidate> candidates,
    PillIdentificationCandidate target,
  ) {
    final targetKey = _candidateKey(target);
    return candidates
        .where((candidate) => _candidateKey(candidate) == targetKey)
        .length;
  }

  // 함수명: uniqueCandidates
  // 역할: 품목번호가 없는 후보도 약명 기준으로 구분하며 같은 품목만 하나로 묶는다.
  List<PillIdentificationCandidate> uniqueCandidates(
    Iterable<PillIdentificationCandidate> candidates,
  ) {
    final uniqueCandidates = <String, PillIdentificationCandidate>{};
    for (final candidate in candidates) {
      uniqueCandidates.putIfAbsent(_candidateKey(candidate), () => candidate);
    }
    return uniqueCandidates.values.toList(growable: false);
  }

  // 함수명: findDuplicateGroups
  // 역할: 두 장 이상의 사진에서 같은 품목으로 선택된 후보를 찾는다.
  List<DuplicatePillSelectionGroup> findDuplicateGroups(
    Iterable<PillIdentificationCandidate> candidates,
  ) {
    final groupedCandidates = <String, List<PillIdentificationCandidate>>{};
    for (final candidate in candidates) {
      final key = _candidateKey(candidate);
      groupedCandidates.putIfAbsent(key, () => []).add(candidate);
    }
    return [
      for (final entry in groupedCandidates.entries)
        if (entry.value.length > 1)
          DuplicatePillSelectionGroup(
            itemSeq: entry.value.first.itemSeq,
            itemName: entry.value.first.itemName,
            count: entry.value.length,
          ),
    ];
  }

  // 함수명: mergeEquivalentRequests
  // 역할:
  // - 품목과 사용자가 검토한 복약 일정이 모두 같은 요청만 하나로 묶는다.
  // - 복용량, 기간, 시작일 또는 시간대가 다르면 같은 약도 별도로 유지한다.
  List<IdentifiedPillSaveRequest> mergeEquivalentRequests(
    Iterable<IdentifiedPillSaveRequest> requests,
  ) {
    final uniqueRequests = <String, IdentifiedPillSaveRequest>{};
    for (final request in requests) {
      uniqueRequests.putIfAbsent(_requestKey(request), () => request);
    }
    return uniqueRequests.values.toList(growable: false);
  }

  String _requestKey(IdentifiedPillSaveRequest request) {
    final schedule = request.medicationSchedule;
    final date = schedule.prescriptionDate;
    final dateKey = date == null
        ? ''
        : '${date.year.toString().padLeft(4, '0')}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}';
    final slotKeys = [...schedule.slotKeys]..sort();
    return [
      _candidateKey(request.candidate),
      _normalize(schedule.medicationName),
      dateKey,
      _normalize(schedule.dosage),
      schedule.dailyFrequencyCount.toString(),
      schedule.medicationTime.toString(),
      slotKeys.join(','),
    ].join('|');
  }

  String _candidateKey(PillIdentificationCandidate candidate) {
    final itemSeq = candidate.itemSeq.trim();
    return itemSeq.isNotEmpty ? itemSeq : _normalize(candidate.itemName);
  }

  String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
  }
}
