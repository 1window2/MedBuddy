import '../entities/identified_pill_save_request_entity.dart';
import '../entities/pill_identification_entity.dart';

// 파일명: resolve_duplicate_pill_selection_control.dart
// 역할: 다중 낱알 식별에서 같은 품목과 같은 복약 일정을 안전하게 구분한다.

// 클래스명: DuplicatePillSelectionGroup
// 역할: 여러 사진에서 같은 품목으로 선택된 후보의 개수를 표현한다.
// 주요 책임:
// - 중복 확인 화면에 품목번호, 표시 약명과 사진 수를 함께 전달한다.
// 속성:
// - itemSeq (String): 공공데이터의 약 품목번호
// - itemName (String): 화면과 저장에 사용할 약 이름
// - count (int): 동일 품목으로 선택된 사진 수
class DuplicatePillSelectionGroup {
  final String itemSeq;
  final String itemName;
  final int count;

  // 함수이름: DuplicatePillSelectionGroup
  // 함수역할: 같은 품목으로 선택된 약의 품목번호·표시 이름·선택 사진 수를 중복 안내 자료로 묶는다.
  // 매개변수:
  // - itemSeq (String): 공공데이터의 약 품목번호
  // - itemName (String): 화면과 저장에 사용할 약 이름
  // - count (int): 동일 품목으로 선택된 사진 수
  // 반환값:
  // - DuplicatePillSelectionGroup: 초기화된 인스턴스.
  const DuplicatePillSelectionGroup({
    required this.itemSeq,
    required this.itemName,
    required this.count,
  });
}

// 클래스명: ResolveDuplicatePillSelectionControl
// 역할: 같은 품목 사진을 식별하고 사용자가 허용한 동일 일정 요청만 합친다.
// 주요 책임:
// - 품목번호가 없으면 정규화 약명을 사용하며 용량·기간·시작일·시간대가 다른 요청은 보존한다.
class ResolveDuplicatePillSelectionControl {
  // 함수이름: ResolveDuplicatePillSelectionControl
  // 함수역할: 알약 후보의 동일 품목 및 동일 복약 일정 비교에 사용할 무상태 Control을 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - ResolveDuplicatePillSelectionControl: 초기화된 인스턴스.
  const ResolveDuplicatePillSelectionControl();

  // 함수이름: countEquivalentCandidates
  // 함수역할: 품목번호 또는 정규화한 약명이 같은 선택 후보의 개수를 반환한다.
  // 매개변수:
  // - candidates (Iterable<PillIdentificationCandidate>): 일치 여부를 비교할 후보 목록
  // - target (PillIdentificationCandidate): 사용자가 선택하거나 동일성을 비교할 알약 후보
  // 반환값:
  // - int: 품목번호 또는 정규화한 약명이 같은 선택 후보의 개수를 반환한다.
  int countEquivalentCandidates(
    Iterable<PillIdentificationCandidate> candidates,
    PillIdentificationCandidate target,
  ) {
    final targetKey = _candidateKey(target);
    return candidates
        .where(/* 함수이름: where 콜백
         * 함수역할: 선택한 약과 정규화된 식별 키가 같은 중복 후보를 찾는다.
         * 매개변수:
         * - candidate (PillIdentificationCandidate): 사용자가 선택하거나 동일성을 비교할 알약 후보
         * 반환값:
         * - 후보 키가 선택 대상 키와 같으면 true.
         */(candidate) => _candidateKey(candidate) == targetKey)
        .length;
  }

  // 함수이름: uniqueCandidates
  // 함수역할: 품목번호가 없는 후보도 약명 기준으로 구분하며 같은 품목만 하나로 묶는다.
  // 매개변수:
  // - candidates (Iterable<PillIdentificationCandidate>): 일치 여부를 비교할 후보 목록
  // 반환값:
  // - List<PillIdentificationCandidate>: 품목번호가 없는 후보도 약명 기준으로 구분하며 같은 품목만 하나로 묶는다.
  List<PillIdentificationCandidate> uniqueCandidates(
    Iterable<PillIdentificationCandidate> candidates,
  ) {
    final uniqueCandidates = <String, PillIdentificationCandidate>{};
    for (final candidate in candidates) {
      uniqueCandidates.putIfAbsent(_candidateKey(candidate), /* 함수이름: putIfAbsent 콜백
       * 함수역할: 같은 키의 후보가 없을 때 현재 후보를 대표 항목으로 등록한다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 현재 약 식별 후보.
       */() => candidate);
    }
    return uniqueCandidates.values.toList(growable: false);
  }

  // 함수이름: findDuplicateGroups
  // 함수역할: 두 장 이상의 사진에서 같은 품목으로 선택된 후보를 찾는다.
  // 매개변수:
  // - candidates (Iterable<PillIdentificationCandidate>): 일치 여부를 비교할 후보 목록
  // 반환값:
  // - List<DuplicatePillSelectionGroup>: 두 장 이상의 사진에서 같은 품목으로 선택된 후보를 찾는다.
  List<DuplicatePillSelectionGroup> findDuplicateGroups(
    Iterable<PillIdentificationCandidate> candidates,
  ) {
    final groupedCandidates = <String, List<PillIdentificationCandidate>>{};
    for (final candidate in candidates) {
      final key = _candidateKey(candidate);
      groupedCandidates.putIfAbsent(key, /* 함수이름: putIfAbsent 콜백
       * 함수역할: 새 중복 그룹을 위한 선택 요청 목록을 만든다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 비어 있는 선택 요청 목록.
       */() => []).add(candidate);
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

  // 함수이름: mergeEquivalentRequests
  // 함수역할: 품목과 사용자가 검토한 복약 일정이 모두 같은 요청만 하나로 묶는다. 복용량, 기간, 시작일 또는 시간대가 다르면 같은 약도 별도로 유지한다.
  // 매개변수:
  // - requests (Iterable<IdentifiedPillSaveRequest>): 입력 순서를 보존할 알약 저장 요청 목록
  // 반환값:
  // - List<IdentifiedPillSaveRequest>: 품목과 사용자가 검토한 복약 일정이 모두 같은 요청만 하나로 묶는다. 복용량, 기간, 시작일 또는 시간대가 다르면 같은 약도 별도로 유지한다.
  List<IdentifiedPillSaveRequest> mergeEquivalentRequests(
    Iterable<IdentifiedPillSaveRequest> requests,
  ) {
    final uniqueRequests = <String, IdentifiedPillSaveRequest>{};
    for (final request in requests) {
      uniqueRequests.putIfAbsent(_requestKey(request), /* 함수이름: putIfAbsent 콜백
       * 함수역할: 아직 등록되지 않은 요청 키에 최초 선택 요청을 보존한다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 해당 키의 최초 저장 요청.
       */() => request);
    }
    return uniqueRequests.values.toList(growable: false);
  }

  // 함수이름: _requestKey
  // 함수역할: 품목·약명·시작일·복용량·횟수·기간·정렬된 시간대를 결합해 일정까지 같은 저장 요청의 중복 키를 만든다.
  // 매개변수:
  // - request (IdentifiedPillSaveRequest): 중복 키를 계산할 확정된 알약 저장 요청
  // 반환값:
  // - String: 품목·약명·시작일·복용량·횟수·기간·정렬된 시간대를 결합해 일정까지 같은 저장 요청의 중복 키를 만든다.
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

  // 함수이름: _candidateKey
  // 함수역할: 품목번호를 우선하고 없으면 공백과 대소문자를 정리한 약명을 후보의 동일성 키로 사용한다.
  // 매개변수:
  // - candidate (PillIdentificationCandidate): 사용자가 선택하거나 동일성을 비교할 알약 후보
  // 반환값:
  // - String: 품목번호를 우선하고 없으면 공백과 대소문자를 정리한 약명을 후보의 동일성 키로 사용한다.
  String _candidateKey(PillIdentificationCandidate candidate) {
    final itemSeq = candidate.itemSeq.trim();
    return itemSeq.isNotEmpty ? itemSeq : _normalize(candidate.itemName);
  }

  // 함수이름: _normalize
  // 함수역할: 약명과 일정 텍스트에서 모든 공백을 제거하고 소문자로 바꿔 중복 비교 기준을 통일한다.
  // 매개변수:
  // - value (String): 중복 약 식별 키에 포함할 원문
  // 반환값:
  // - String: 약명과 일정 텍스트에서 모든 공백을 제거하고 소문자로 바꿔 중복 비교 기준을 통일한다.
  String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
  }
}
