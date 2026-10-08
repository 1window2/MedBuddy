import '../entities/identified_pill_save_request_entity.dart';
import '../entities/json_value_reader.dart';
import '../entities/pill_identification_entity.dart';
import 'check_saved_medication_control.dart';

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

// 클래스명: PillSavePlan
// 역할: 사진별 저장 요청을 실제로 보낼 요청 목록과 사진→요청 대응으로 정리한다.
// 주요 책임:
// - 병합으로 요청 수가 줄어도 각 사진이 어느 요청의 결과를 따르는지 보존한다.
// 속성:
// - uniqueRequests (List<IdentifiedPillSaveRequest>): 저장 콜백에 보낼 요청 목록(입력 순서 유지)
// - sourceToRequestIndex (List<int>): 사진(입력 요청) 위치별로 대응하는 uniqueRequests 위치
class PillSavePlan {
  final List<IdentifiedPillSaveRequest> uniqueRequests;
  final List<int> sourceToRequestIndex;

  // 함수이름: PillSavePlan
  // 함수역할: 보낼 요청 목록과 사진별 대응 위치를 저장 계획으로 묶는다.
  // 매개변수:
  // - uniqueRequests (List<IdentifiedPillSaveRequest>): 저장 콜백에 보낼 요청 목록(입력 순서 유지)
  // - sourceToRequestIndex (List<int>): 사진(입력 요청) 위치별로 대응하는 uniqueRequests 위치
  // 반환값:
  // - PillSavePlan: 초기화된 인스턴스.
  const PillSavePlan({
    required this.uniqueRequests,
    required this.sourceToRequestIndex,
  });

  // 함수이름: mergedCount
  // 함수역할: 같은 일정으로 묶여 따로 보내지 않게 된 사진 수를 계산한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - int: 입력 요청 수에서 실제로 보낼 요청 수를 뺀 값.
  int get mergedCount => sourceToRequestIndex.length - uniqueRequests.length;
}

// 클래스명: PillSaveSummary
// 역할: 저장 결과를 사진별 상태와 요청 기준 건수로 정리한다.
// 주요 책임:
// - 결과가 없는 요청은 실패로 보아 저장되지 않은 약이 저장됨으로 표시되지 않게 한다.
// - 병합된 사진은 대응 요청의 결과를 그대로 따르게 한다.
// 속성:
// - requestStatuses (List<MedicationSaveStatus>): 보낸 요청 순서의 저장 상태
// - perSourceStatus (List<MedicationSaveStatus>): 사진(입력 요청) 순서의 저장 상태
// - savedCount (int): 새로 저장된 요청 수
// - duplicateCount (int): 이미 저장돼 있던 요청 수
// - failedCount (int): 저장하지 못한 요청 수
class PillSaveSummary {
  final List<MedicationSaveStatus> requestStatuses;
  final List<MedicationSaveStatus> perSourceStatus;
  final int savedCount;
  final int duplicateCount;
  final int failedCount;

  // 함수이름: PillSaveSummary
  // 함수역할: 요청별·사진별 저장 상태와 상태별 건수를 한 결과로 묶는다.
  // 매개변수:
  // - requestStatuses (List<MedicationSaveStatus>): 보낸 요청 순서의 저장 상태
  // - perSourceStatus (List<MedicationSaveStatus>): 사진(입력 요청) 순서의 저장 상태
  // - savedCount (int): 새로 저장된 요청 수
  // - duplicateCount (int): 이미 저장돼 있던 요청 수
  // - failedCount (int): 저장하지 못한 요청 수
  // 반환값:
  // - PillSaveSummary: 초기화된 인스턴스.
  const PillSaveSummary({
    required this.requestStatuses,
    required this.perSourceStatus,
    required this.savedCount,
    required this.duplicateCount,
    required this.failedCount,
  });

  // 함수이름: isSourceStored
  // 함수역할: 해당 사진의 약이 서버에 저장돼 있어 다시 보내면 안 되는지 판정한다.
  // 매개변수:
  // - sourceIndex (int): 저장 계획을 만들 때 넘긴 요청 목록에서의 사진 위치
  // 반환값:
  // - bool: 새로 저장됐거나 이미 저장돼 있으면 true, 실패했거나 범위를 벗어나면 false.
  bool isSourceStored(int sourceIndex) {
    return sourceIndex >= 0 &&
        sourceIndex < perSourceStatus.length &&
        perSourceStatus[sourceIndex] != MedicationSaveStatus.failed;
  }
}

// 클래스명: ResolveDuplicatePillSelectionControl
// 역할: 같은 품목 사진을 식별하고 사용자가 허용한 동일 일정 요청만 합친다.
// 주요 책임:
// - 품목번호가 없으면 정규화 약명을 사용하며 용량·기간·시작일·시간대가 다른 요청은 보존한다.
// - 저장할 요청 계획과 결과 요약을 만들어 사진별 저장 여부를 한 곳에서 판정한다.
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

  // 함수이름: buildPillSavePlan
  // 함수역할: 사진별 저장 요청에서 실제로 보낼 요청과 사진→요청 대응을 만든다. 병합을 선택했을 때만 품목과 검토 일정이 모두 같은 요청을 처음 요청 하나로 묶는다.
  // 매개변수:
  // - requests (Iterable<IdentifiedPillSaveRequest>): 사진 순서대로 정리한 저장 요청 목록
  // - mergeEquivalent (bool): 품목과 일정이 모두 같은 요청을 하나로 묶을지 여부
  // 반환값:
  // - PillSavePlan: 보낼 요청 목록과 사진 위치별 대응 요청 위치.
  PillSavePlan buildPillSavePlan(
    Iterable<IdentifiedPillSaveRequest> requests, {
    required bool mergeEquivalent,
  }) {
    final uniqueRequests = <IdentifiedPillSaveRequest>[];
    final sourceToRequestIndex = <int>[];
    final requestIndexByKey = <String, int>{};
    for (final request in requests) {
      if (!mergeEquivalent) {
        sourceToRequestIndex.add(uniqueRequests.length);
        uniqueRequests.add(request);
        continue;
      }
      final key = _requestKey(request);
      var requestIndex = requestIndexByKey[key];
      if (requestIndex == null) {
        requestIndex = uniqueRequests.length;
        requestIndexByKey[key] = requestIndex;
        uniqueRequests.add(request);
      }
      sourceToRequestIndex.add(requestIndex);
    }
    return PillSavePlan(
      uniqueRequests: List<IdentifiedPillSaveRequest>.unmodifiable(
        uniqueRequests,
      ),
      sourceToRequestIndex: List<int>.unmodifiable(sourceToRequestIndex),
    );
  }

  // 함수이름: summarizePillSaveResults
  // 함수역할: 요청 순서의 저장 결과를 사진별 상태와 상태별 건수로 바꾼다. 결과가 모자란 요청은 실패로 처리하고 요청 수를 넘는 결과는 무시한다.
  // 매개변수:
  // - plan (PillSavePlan): buildPillSavePlan이 만든 저장 계획
  // - results (List<MedicationSaveResult>): plan.uniqueRequests와 같은 순서의 저장 결과
  // 반환값:
  // - PillSaveSummary: 요청별·사진별 저장 상태와 저장·중복·실패 건수.
  PillSaveSummary summarizePillSaveResults(
    PillSavePlan plan,
    List<MedicationSaveResult> results,
  ) {
    final requestStatuses = <MedicationSaveStatus>[
      for (var index = 0; index < plan.uniqueRequests.length; index += 1)
        index < results.length
            ? results[index].status
            : MedicationSaveStatus.failed,
    ];
    var savedCount = 0;
    var duplicateCount = 0;
    var failedCount = 0;
    for (final status in requestStatuses) {
      switch (status) {
        case MedicationSaveStatus.saved:
          savedCount += 1;
        case MedicationSaveStatus.duplicate:
          duplicateCount += 1;
        case MedicationSaveStatus.failed:
          failedCount += 1;
      }
    }
    return PillSaveSummary(
      requestStatuses: List<MedicationSaveStatus>.unmodifiable(requestStatuses),
      perSourceStatus: List<MedicationSaveStatus>.unmodifiable([
        for (final requestIndex in plan.sourceToRequestIndex)
          requestIndex >= 0 && requestIndex < requestStatuses.length
              ? requestStatuses[requestIndex]
              : MedicationSaveStatus.failed,
      ]),
      savedCount: savedCount,
      duplicateCount: duplicateCount,
      failedCount: failedCount,
    );
  }

  // 함수이름: _requestKey
  // 함수역할: 품목·약명·시작일·복용량·횟수·기간·정렬된 시간대를 결합해 일정까지 같은 저장 요청의 중복 키를 만든다.
  // 매개변수:
  // - request (IdentifiedPillSaveRequest): 중복 키를 계산할 확정된 알약 저장 요청
  // 반환값:
  // - String: 품목·약명·시작일·복용량·횟수·기간·정렬된 시간대를 결합해 일정까지 같은 저장 요청의 중복 키를 만든다.
  String _requestKey(IdentifiedPillSaveRequest request) {
    final schedule = request.medicationSchedule;
    final dateKey = formatJsonDate(schedule.prescriptionDate) ?? '';
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
