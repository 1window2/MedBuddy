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

// Class Name: PillSavePlan
// Role: Map each photographed pill selection to the request that will store it.
// Responsibilities: Preserve source order even when equivalent reviewed schedules are merged.
// Attributes: uniqueRequests (List<IdentifiedPillSaveRequest>): ordered requests; sourceToRequestIndex (List<int>): request index for each source.
class PillSavePlan {
  final List<IdentifiedPillSaveRequest> uniqueRequests;
  final List<int> sourceToRequestIndex;

  // Function Name: PillSavePlan
  // Description: Retain outgoing requests and their source-to-request mapping.
  // Parameters: uniqueRequests (List<IdentifiedPillSaveRequest>): requests; sourceToRequestIndex (List<int>): source mapping.
  // Returns: PillSavePlan: supplied plan without additional validation.
  const PillSavePlan({
    required this.uniqueRequests,
    required this.sourceToRequestIndex,
  });

  // Function Name: mergedCount
  // Description: Count sources eliminated by request merging.
  // Parameters: None.
  // Returns: int: source count minus outgoing request count.
  int get mergedCount => sourceToRequestIndex.length - uniqueRequests.length;
}

// Class Name: PillSaveSummary
// Role: Represent request outcomes and corresponding photo-selection outcomes.
// Responsibilities: Keep missing-result failures and merged-source statuses explicit.
// Attributes: requestStatuses/perSourceStatus (List<MedicationSaveStatus>): request/source outcomes; savedCount/duplicateCount/failedCount (int): request totals.
class PillSaveSummary {
  final List<MedicationSaveStatus> requestStatuses;
  final List<MedicationSaveStatus> perSourceStatus;
  final int savedCount;
  final int duplicateCount;
  final int failedCount;

  // Function Name: PillSaveSummary
  // Description: Bundle request and source outcomes with precomputed status totals.
  // Parameters: requestStatuses/perSourceStatus (List<MedicationSaveStatus>): ordered statuses; savedCount/duplicateCount/failedCount (int): request counts.
  // Returns: PillSaveSummary: supplied result summary.
  const PillSaveSummary({
    required this.requestStatuses,
    required this.perSourceStatus,
    required this.savedCount,
    required this.duplicateCount,
    required this.failedCount,
  });

  // Function Name: isSourceStored
  // Description: Check whether a source was saved or already existed; reject out-of-range indices.
  // Parameters: sourceIndex (int): original selection position.
  // Returns: bool: true for saved or duplicate, false for failed or invalid positions.
  bool isSourceStored(int sourceIndex) {
    return sourceIndex >= 0 &&
        sourceIndex < perSourceStatus.length &&
        perSourceStatus[sourceIndex] != MedicationSaveStatus.failed;
  }
}

// Class Name: ResolveDuplicatePillSelectionControl
// Role: Merge equivalent pill selections only when requested.
// Responsibilities: Compare item identity and reviewed schedules, then map request outcomes back to every source.
// Attributes: No instance state; comparison helpers derive normalized identity and schedule keys.
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

  // Function Name: buildPillSavePlan
  // Description: Build an ordered save plan, merging identical item-and-schedule keys only when enabled.
  // Parameters: requests (Iterable<IdentifiedPillSaveRequest>): source order; mergeEquivalent (bool): permit deduplication.
  // Returns: PillSavePlan: unmodifiable outgoing requests and source indices.
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

  // Function Name: summarizePillSaveResults
  // Description: Expand request results to source statuses; treat missing results or invalid mappings as failed and ignore excess results.
  // Parameters: plan (PillSavePlan): outgoing requests and source map; results (List<MedicationSaveResult>): request-order outcomes.
  // Returns: PillSaveSummary: immutable statuses and request-level saved/duplicate/failed totals.
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

  // Function Name: _requestKey
  // Description: Combine candidate identity with normalized name, date, dosage, frequency, duration and sorted slots.
  // Parameters: request (IdentifiedPillSaveRequest): reviewed selection.
  // Returns: String: equality key for item-and-schedule deduplication.
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
