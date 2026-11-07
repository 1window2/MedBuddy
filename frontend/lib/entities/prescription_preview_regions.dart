// File Name: prescription_preview_regions.dart
// Role: Chooses the OCR regions drawn on the prescription preview: every sensitive masking region, and the recognised text that matches an analysed medication name.
import 'medication_schedule_entity.dart';
import 'recognized_text_region_entity.dart';

const double _medicationRegionSimilarityThreshold = 0.75;
final RegExp _medicationFormPattern = RegExp(
  r'(건조시럽|캡슐|시럽|과립|연고|크림|패치|주사|흡입|점안|좌약|필름|'
  r'로션|스프레이|현탁액|정제|정|액|산|겔)',
  caseSensitive: false,
);

// Function Name: resolvePrescriptionPreviewRegions
// Description: Preserves sensitive masking regions, adds medication-matched OCR regions, removes duplicate category/box entries, and sorts the preview top-to-bottom then left-to-right.
// Parameters:
// - localRegions (List<RecognizedTextRegion>): Local OCR text and sensitive masking regions.
// - medicationSchedules (List<MedicationSchedule>): Medication schedules used for lookup, comparison, or reminders.
// Returns:
// - List<RecognizedTextRegion>: Preserves sensitive masking regions, adds medication-matched OCR regions, removes duplicate category/box entries, and sorts the preview top-to-bottom then left-to-right.
List<RecognizedTextRegion> resolvePrescriptionPreviewRegions({
  required List<RecognizedTextRegion> localRegions,
  required List<MedicationSchedule> medicationSchedules,
}) {
  final sensitiveRegions = localRegions.where(
    /* Function Name: where callback
   * Description: Selects OCR regions marked sensitive for image redaction.
   * Parameters:
   * - region (RecognizedTextRegion): OCR region being selected or reclassified.
   * Returns:
   * - Whether the region contains sensitive content.
   */
    (region) => region.isSensitive,
  );
  final medicationRegions = _classifyLocalMedicationRegions(
    localRegions,
    medicationSchedules,
  );
  final uniqueRegions = <RecognizedTextRegion>[];
  final seenRegionKeys = <String>{};

  for (final region in [...sensitiveRegions, ...medicationRegions]) {
    final regionKey =
        '${region.category}:${region.box2d.map(/* 함수이름: map 콜백
         * 함수역할: 민감 영역 좌표를 반올림해 정수 경계값으로 맞춘다.
         * 매개변수:
         * - value (double): 반올림할 OCR 좌표
         * 반환값:
         * - 반올림된 좌표값.
         */ (value) => value.round()).join(',')}';
    if (seenRegionKeys.add(regionKey)) {
      uniqueRegions.add(region);
    }
  }
  uniqueRegions.sort(/* 함수이름: sort 콜백
   * 함수역할: 민감 영역을 위쪽 좌표 우선, 같은 높이에서는 왼쪽 좌표 우선으로 정렬한다.
   * 매개변수:
   * - left (RecognizedTextRegion): 정렬 비교의 첫 번째 OCR 영역
   * - right (RecognizedTextRegion): 정렬 비교의 두 번째 OCR 영역
   * 반환값:
   * - 위·왼쪽 순서를 나타내는 음수·0·양수 비교값.
   */ (left, right) {
    final topComparison = left.box2d[0].compareTo(right.box2d[0]);
    return topComparison != 0
        ? topComparison
        : left.box2d[1].compareTo(right.box2d[1]);
  });
  return List.unmodifiable(uniqueRegions);
}

// Function Name: _classifyLocalMedicationRegions
// Description: Retain medication regions and reclassify matching generic OCR text; require at least one normalized medication name of three characters.
// Parameters: localRegions (List<RecognizedTextRegion>): local OCR regions; medicationSchedules (List<MedicationSchedule>): analyzed medication names.
// Returns: List<RecognizedTextRegion>: selected medication regions, empty when no usable names exist.
List<RecognizedTextRegion> _classifyLocalMedicationRegions(
  List<RecognizedTextRegion> localRegions,
  List<MedicationSchedule> medicationSchedules,
) {
  final medicationNames = <String>{
    for (final schedule in medicationSchedules)
      ...[
        _normalizeRegionText(schedule.medicationName),
        _normalizeRegionText(schedule.rawMedicationName),
      ].where(
        /* 함수이름: where 콜백
       * 함수역할: 짧은 문자열의 오탐을 줄이기 위해 세 글자 이상인 약 이름만 유지한다.
       * 매개변수:
       * - name (String): 표시·일치 여부를 검사할 약 이름
       * 반환값:
       * - 약 이름 길이가 3 이상이면 true.
       */
        (name) => name.length >= 3,
      ),
  };
  if (medicationNames.isEmpty) {
    return const [];
  }

  return localRegions
      .where(/* 함수이름: where 콜백
       * 함수역할: 명시적 약 영역과 약 이름에 대응하는 충분히 긴 일반 인식 영역만 선택한다.
       * 매개변수:
       * - region (RecognizedTextRegion): 선택 또는 재분류할 OCR 인식 영역
       * 반환값:
       * - 약 이름 영역으로 사용할 수 있으면 true.
       */ (region) {
        if (region.isMedication) {
          return true;
        }
        if (region.category != 'recognized_text') {
          return false;
        }
        final regionText = _normalizeRegionText(region.text);
        if (regionText.length < 3) {
          return false;
        }
        return medicationNames.any(
          // 함수이름: any 콜백
          // 함수역할: 정규화된 인식 텍스트가 후보 약 이름과 일치하는지 검사한다.
          // 매개변수:
          // - name (String): 표시·일치 여부를 검사할 약 이름
          // 반환값:
          // - 해당 약 이름과 대응하면 true.
          (name) => _isMedicationRegionMatch(regionText, name),
        );
      })
      .map(
        // 함수이름: map 콜백
        // 함수역할: 기존 약 영역은 유지하고 일치한 일반 인식 영역은 약 이름 범주로 다시 표시한다.
        // 매개변수:
        // - region (RecognizedTextRegion): 선택 또는 재분류할 OCR 인식 영역
        // 반환값:
        // - 약 이름 범주가 부여된 인식 영역.
        (region) => region.isMedication
            ? region
            : RecognizedTextRegion(
                category: 'medication_name',
                text: region.text,
                box2d: region.box2d,
              ),
      )
      .toList(growable: false);
}

// Function Name: _isMedicationRegionMatch
// Description: Accept containment matches, otherwise require sufficiently long dosage-form text and thresholded edit similarity.
// Parameters: regionText/medicationName (String): normalized OCR text and medication name.
// Returns: bool: whether the region can represent that medication.
bool _isMedicationRegionMatch(String regionText, String medicationName) {
  if (regionText.contains(medicationName) ||
      medicationName.contains(regionText)) {
    return true;
  }
  if (regionText.length < 4 ||
      medicationName.length < 4 ||
      !_medicationFormPattern.hasMatch(regionText)) {
    return false;
  }
  return _bestWindowSimilarity(regionText, medicationName) >=
      _medicationRegionSimilarityThreshold;
}

// Function Name: _bestWindowSimilarity
// Description: Find the best normalized edit similarity against the whole longer string or nearby-length windows; stop at an exact match.
// Parameters: left/right (String): normalized texts of at least four characters.
// Returns: double: best similarity in [0, 1].
double _bestWindowSimilarity(String left, String right) {
  final shorter = left.length <= right.length ? left : right;
  final longer = left.length <= right.length ? right : left;
  var bestScore = _editSimilarity(shorter, longer);
  final minimumWindowLength = (shorter.length - 2).clamp(4, shorter.length);
  final maximumWindowLength = (shorter.length + 2).clamp(
    minimumWindowLength,
    longer.length,
  );

  for (
    var windowLength = minimumWindowLength;
    windowLength <= maximumWindowLength;
    windowLength++
  ) {
    for (var start = 0; start + windowLength <= longer.length; start++) {
      final window = longer.substring(start, start + windowLength);
      final score = _editSimilarity(shorter, window);
      if (score > bestScore) {
        bestScore = score;
      }
      if (bestScore >= 1) {
        return 1;
      }
    }
  }
  return bestScore;
}

// Function Name: _editSimilarity
// Description: Normalize Levenshtein distance by the longer text length.
// Parameters: left/right (String): comparison strings.
// Returns: double: similarity in [0, 1], with two empty strings equal to 1.
double _editSimilarity(String left, String right) {
  final longestLength = left.length > right.length
      ? left.length
      : right.length;
  if (longestLength == 0) {
    return 1;
  }
  return 1 - (_levenshteinDistance(left, right) / longestLength);
}

// Function Name: _levenshteinDistance
// Description: Compute insertion, deletion and substitution distance with two rolling rows.
// Parameters: left/right (String): comparison strings.
// Returns: int: minimum unit-cost edit count.
int _levenshteinDistance(String left, String right) {
  if (left == right) {
    return 0;
  }
  if (left.isEmpty) {
    return right.length;
  }
  if (right.isEmpty) {
    return left.length;
  }

  var previousRow = List<int>.generate(
    right.length + 1,
    /* 함수이름: callback 콜백
   * 함수역할: 편집 거리 계산의 초기 행을 문자 위치별 삽입 비용으로 채운다.
   * 매개변수:
   * - index (int): 현재 목록 항목의 0부터 시작하는 위치
   * 반환값:
   * - 초기 위치와 같은 삽입 비용.
   */
    (index) => index,
  );
  for (var leftIndex = 1; leftIndex <= left.length; leftIndex++) {
    final currentRow = List<int>.filled(right.length + 1, 0);
    currentRow[0] = leftIndex;
    for (var rightIndex = 1; rightIndex <= right.length; rightIndex++) {
      final substitutionCost = left[leftIndex - 1] == right[rightIndex - 1]
          ? 0
          : 1;
      final insertion = currentRow[rightIndex - 1] + 1;
      final deletion = previousRow[rightIndex] + 1;
      final substitution = previousRow[rightIndex - 1] + substitutionCost;
      currentRow[rightIndex] = [insertion, deletion, substitution].reduce(
        /* 함수이름: reduce 콜백
       * 함수역할: 편집 거리 후보 비용에서 더 작은 값을 유지한다.
       * 매개변수:
       * - minimum (int): 지금까지 선택한 최소 편집 비용
       * - value (int): 비교할 편집 거리 비용
       * 반환값:
       * - 두 후보 중 작은 비용.
       */
        (minimum, value) => value < minimum ? value : minimum,
      );
    }
    previousRow = currentRow;
  }
  return previousRow.last;
}

// Function Name: _normalizeRegionText
// Description: Lowercase OCR text and retain only ASCII letters, digits and Korean syllables.
// Parameters: value (String): OCR region or medication name.
// Returns: String: normalized matching text.
String _normalizeRegionText(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^0-9a-z가-힣]'), '');
}
