// File Name: medbuddy_view_model_analysis_test.dart
// Role: Verifies prescription analysis state handling in MedBuddyViewModel.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/check_medication_detail_control.dart';
import 'package:medbuddy_frontend/controls/check_prescription_change_control.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/controls/input_prescription_control.dart';
import 'package:medbuddy_frontend/entities/analyzed_medication_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_change_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';

// Class Name: _FakeInputPrescription
// Role: Prescription-input stub with fixed schedules and recognition counters.
// Responsibilities:
// - Expose the raw OCR medication count used by correction notices.
// - Expose the number of OCR rows successfully parsed into schedules.
// - Expose the number of OCR rows omitted from analysis.
// Attributes:
// - rawCount (int): Number of medication rows before OCR filtering.
// - parsedCount (int): Number of OCR medication rows successfully parsed.
// - skippedCount (int): OCR rows excluded from the recognized schedule result.
class _FakeInputPrescription extends InputPrescription {
  final List<MedicationSchedule> schedules;
  final int rawCount;
  final int parsedCount;
  final int skippedCount;

  // Function Name: _FakeInputPrescription
  // Description:
  // - Store recognized schedules and raw, parsed, and skipped row counts.
  // Parameters:
  // - schedules (List<MedicationSchedule>): Recognized or current dose schedules for the scenario.
  // - rawCount (int): Number of medication rows before OCR filtering.
  // - parsedCount (int): Number of OCR medication rows successfully parsed.
  // - skippedCount (int): OCR rows excluded from the recognized schedule result.
  // Returns:
  // - A prescription-input fixture with the supplied OCR outcome.
  _FakeInputPrescription(
    this.schedules, {
    this.rawCount = 0,
    this.parsedCount = 0,
    this.skippedCount = 0,
  });

  // Function Name: lastRawMedicationCount
  // Description:
  // - Expose the raw OCR medication count used by correction notices.
  // Parameters:
  // - None.
  // Returns:
  // - The configured raw row count.
  @override
  int get lastRawMedicationCount => rawCount;

  // Function Name: lastParsedMedicationCount
  // Description:
  // - Expose the number of OCR rows successfully parsed into schedules.
  // Parameters:
  // - None.
  // Returns:
  // - The configured parsed row count.
  @override
  int get lastParsedMedicationCount => parsedCount;

  // Function Name: lastSkippedMedicationCount
  // Description:
  // - Expose the number of OCR rows omitted from analysis.
  // Parameters:
  // - None.
  // Returns:
  // - The configured skipped row count.
  @override
  int get lastSkippedMedicationCount => skippedCount;

  // Function Name: requestPrescriptionImageFromGallery
  // Description:
  // - Signal image selection and return fixed recognized schedules without opening a gallery.
  // Parameters:
  // - onImageSelected (PrescriptionImageSelectedCallback?): Callback announcing that an image has been
  //   selected.
  // Returns:
  // - The configured schedule list after the optional selection callback.
  @override
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    onImageSelected?.call();
    return schedules;
  }
}

// Class Name: _FakeCheckMedicationDetail
// Role: Medication-detail stub with a designated unresolvable drug name.
// Responsibilities:
// - Return no match for missing-tablet and construct details for all other recognized names.
class _FakeCheckMedicationDetail extends CheckMedicationDetail {
  // Function Name: requestMedicationDetail
  // Description:
  // - Return no match for missing-tablet and construct details for all other recognized names.
  // Parameters:
  // - medicationSchedule (MedicationSchedule): Recognized or reviewed dose schedule for the medication.
  // Returns:
  // - Null for the designated missing drug; otherwise matching medication details.
  @override
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule medicationSchedule,
  ) async {
    if (medicationSchedule.medicationName == 'missing-tablet') {
      return null;
    }
    return MedicationDetail(
      itemName: medicationSchedule.medicationName,
      efficacy: 'effect',
      usageMethod: 'usage',
      warning: 'warning',
    );
  }
}

// 클래스명: _CapturingCheckMedicationDetail
// 역할: OCR 수정 약명이 실제 상세조회 요청에 전달되는지 기록한다.
// 주요 책임:
// - 상세조회에 전달된 수정 일정을 기록하고 해당 약명의 상세정보를 제공한다.
class _CapturingCheckMedicationDetail extends CheckMedicationDetail {
  MedicationSchedule? requestedSchedule;

  // 함수이름: requestMedicationDetail
  // 함수역할:
  // - 상세조회에 전달된 수정 일정을 기록하고 해당 약명의 상세정보를 제공한다.
  // 매개변수:
  // - medicationSchedule (MedicationSchedule): 인식 또는 검토한 약의 복약 일정.
  // 반환값:
  // - 요청한 약명과 고정 효능·복용법·주의 정보.
  @override
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule medicationSchedule,
  ) async {
    requestedSchedule = medicationSchedule;
    return MedicationDetail(
      itemName: medicationSchedule.medicationName,
      efficacy: 'effect',
      usageMethod: 'usage',
      warning: 'warning',
    );
  }
}

// Class Name: _DeferredInputPrescription
// Role: Prescription-input stub whose OCR result is released explicitly by the test.
// Responsibilities:
// - Signal image selection immediately but defer recognized schedules until the test completes OCR.
class _DeferredInputPrescription extends InputPrescription {
  final Completer<List<MedicationSchedule>?> completer =
      Completer<List<MedicationSchedule>?>();

  // Function Name: requestPrescriptionImageFromGallery
  // Description:
  // - Signal image selection immediately but defer recognized schedules until the test completes OCR.
  // Parameters:
  // - onImageSelected (PrescriptionImageSelectedCallback?): Callback announcing that an image has been
  //   selected.
  // Returns:
  // - The pending recognition completer Future.
  @override
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
  }) {
    onImageSelected?.call();
    return completer.future;
  }
}

// Class Name: _DeferredCheckMedicationDetail
// Role: Medication-detail stub with controllable response timing for stale-result tests.
// Responsibilities:
// - Hold the detail response until the test releases its completion barrier.
class _DeferredCheckMedicationDetail extends CheckMedicationDetail {
  final Completer<MedicationDetail?> completer = Completer<MedicationDetail?>();

  // Function Name: requestMedicationDetail
  // Description:
  // - Hold the detail response until the test releases its completion barrier.
  // Parameters:
  // - medicationSchedule (MedicationSchedule): Recognized or reviewed dose schedule for the medication.
  //   Accepted but not consumed by this fixture.
  // Returns:
  // - The pending medication-detail Future.
  @override
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule medicationSchedule,
  ) {
    return completer.future;
  }
}

// Class Name: _DeferredCheckSavedMedication
// Role: Holds the first save open so overlapping save attempts can be tested.
// Responsibilities:
// - Count save attempts while keeping the first result pending to expose overlapping requests.
// Attributes:
// - requestCount (int): Number of intercepted control requests.
class _DeferredCheckSavedMedication extends CheckSavedMedication {
  final Completer<MedicationSaveResult> completer =
      Completer<MedicationSaveResult>();
  int requestCount = 0;

  // Function Name: saveMedicationDetail
  // Description:
  // - Count save attempts while keeping the first result pending to expose overlapping requests.
  // Parameters:
  // - medicationDetail (MedicationDetail): Resolved medication details requested for saving. Accepted
  //   but not consumed by this fixture.
  // - medicationSchedule (MedicationSchedule?): Recognized or reviewed dose schedule for the medication.
  //   Accepted but not consumed by this fixture.
  // Returns:
  // - The controlled medication-save Future.
  @override
  Future<MedicationSaveResult> saveMedicationDetail(
    MedicationDetail medicationDetail, {
    MedicationSchedule? medicationSchedule,
  }) {
    requestCount += 1;
    return completer.future;
  }
}

// Class Name: _RetryableCheckMedicationDetail
// Role: Medication-detail stub that allows recovery after an initial no-match result.
// Responsibilities:
// - Count detail lookups, return no match once, and resolve the same drug on retry.
// Attributes:
// - requestCount (int): Number of intercepted control requests.
class _RetryableCheckMedicationDetail extends CheckMedicationDetail {
  int requestCount = 0;

  // Function Name: requestMedicationDetail
  // Description:
  // - Count detail lookups, return no match once, and resolve the same drug on retry.
  // Parameters:
  // - medicationSchedule (MedicationSchedule): Recognized or reviewed dose schedule for the medication.
  // Returns:
  // - Null on the first call; medication details on subsequent calls.
  @override
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule medicationSchedule,
  ) async {
    requestCount += 1;
    if (requestCount == 1) {
      return null;
    }
    return MedicationDetail(
      itemName: medicationSchedule.medicationName,
      efficacy: 'effect',
      usageMethod: 'usage',
      warning: 'warning',
    );
  }
}

// 클래스명: _SelectiveCheckMedicationDetail
// 역할: 약명별 상세조회 성공 여부와 재조회 대상을 기록한다.
// 주요 책임:
// - 조회한 약명을 기록하고 허용된 약명에만 상세정보를 제공한다.
// 속성:
// - matchedMedicationNames (Set<String>): 상세조회 대역이 성공 결과를 제공할 약명 집합.
class _SelectiveCheckMedicationDetail extends CheckMedicationDetail {
  final Set<String> matchedMedicationNames;
  final List<String> requestedMedicationNames = [];

  // 함수이름: _SelectiveCheckMedicationDetail
  // 함수역할:
  // - 상세조회에 성공할 약명 집합을 보관한다.
  // 매개변수:
  // - matchedMedicationNames (Set<String>): 상세조회 대역이 성공 결과를 제공할 약명 집합.
  // 반환값:
  // - 약명별 성공과 재조회 기록을 제공하는 대역.
  _SelectiveCheckMedicationDetail(this.matchedMedicationNames);

  // 함수이름: requestMedicationDetail
  // 함수역할:
  // - 조회한 약명을 기록하고 허용된 약명에만 상세정보를 제공한다.
  // 매개변수:
  // - medicationSchedule (MedicationSchedule): 인식 또는 검토한 약의 복약 일정.
  // 반환값:
  // - 허용 약명의 상세정보 또는 미일치 시 null.
  @override
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule medicationSchedule,
  ) async {
    requestedMedicationNames.add(medicationSchedule.medicationName);
    if (!matchedMedicationNames.contains(medicationSchedule.medicationName)) {
      return null;
    }
    return MedicationDetail(
      itemName: medicationSchedule.medicationName,
      efficacy: 'effect',
      usageMethod: 'usage',
      warning: 'warning',
    );
  }
}

// 클래스명: _ConcurrencyTrackingCheckMedicationDetail
// 역할: 약품 상세조회가 동시에 시작되는 최대 개수와 배치 전환 시점을 기록한다.
// 주요 책임:
// - 동시 상세조회 수와 최대값을 기록하고 첫 배치 해제까지 모든 응답을 대기시킨다.
// 속성:
// - activeRequestCount (int): 시작했지만 아직 해제·완료되지 않은 요청 수.
// - maximumActiveRequestCount (int): 동시에 활성화된 요청 수의 최대값.
// - startedRequestCount (int): 배치 해제 전후 시작한 상세조회 누계.
class _ConcurrencyTrackingCheckMedicationDetail extends CheckMedicationDetail {
  final Completer<void> firstBatchRelease = Completer<void>();
  int activeRequestCount = 0;
  int maximumActiveRequestCount = 0;
  int startedRequestCount = 0;

  // 함수이름: requestMedicationDetail
  // 함수역할:
  // - 동시 상세조회 수와 최대값을 기록하고 첫 배치 해제까지 모든 응답을 대기시킨다.
  // 매개변수:
  // - medicationSchedule (MedicationSchedule): 인식 또는 검토한 약의 복약 일정.
  // 반환값:
  // - 배치 해제 후 요청 약명의 상세정보.
  @override
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule medicationSchedule,
  ) async {
    startedRequestCount += 1;
    activeRequestCount += 1;
    if (activeRequestCount > maximumActiveRequestCount) {
      maximumActiveRequestCount = activeRequestCount;
    }

    await firstBatchRelease.future;
    activeRequestCount -= 1;
    return MedicationDetail(
      itemName: medicationSchedule.medicationName,
      efficacy: 'effect',
      usageMethod: 'usage',
      warning: 'warning',
    );
  }
}

// 클래스명: _FakeCheckPrescriptionChange
// 역할: 처방 변경 조회 횟수와 신규 약 한 건의 비교 결과를 제공하는 대역.
// 주요 책임:
// - 처방 변경 조회 횟수를 기록하고 이전 처방 대비 약 한 건 추가 결과를 제공한다.
// 속성:
// - requestCount (int): 가로챈 제어기 요청 횟수.
class _FakeCheckPrescriptionChange extends CheckPrescriptionChange {
  int requestCount = 0;

  // 함수이름: requestPrescriptionChange
  // 함수역할:
  // - 처방 변경 조회 횟수를 기록하고 이전 처방 대비 약 한 건 추가 결과를 제공한다.
  // 매개변수:
  // - medications (List<AnalyzedMedication>): 가짜 제어기에 제공하는 약 관련 입력 목록. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 이전 처방 존재와 추가 건수 1을 가진 비교 결과.
  @override
  Future<PrescriptionChangeRadar> requestPrescriptionChange(
    List<AnalyzedMedication> medications,
  ) async {
    requestCount += 1;
    return const PrescriptionChangeRadar(
      hasPreviousPrescription: true,
      summary: PrescriptionChangeSummary(addedCount: 1),
    );
  }
}

// 함수이름: main
// 함수역할:
// - 처방 분석 상태, 부분 재시도, 오래된 응답과 중복 저장 차단 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - 갤러리 OCR 결과에 서버의 약명 수정 안내를 노출하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'requestPrescriptionImageFromGallery exposes OCR correction notice',
    () async {
      final viewModel = MedBuddyViewModel(
        inputPrescription: _FakeInputPrescription(
          const [
            MedicationSchedule(
              medicationName: '프루코프정',
              rawMedicationName: '포루코프정',
              nameConfidence: 0.92,
              nameCorrectionSource: 'local_catalog_ocr_vowel_variant',
            ),
          ],
          rawCount: 2,
          parsedCount: 1,
          skippedCount: 1,
        ),
      );
      addTearDown(viewModel.dispose);

      await viewModel.requestPrescriptionImageFromGallery();

      expect(
        viewModel.prescriptionFlowState,
        PrescriptionFlowState.previewReady,
      );
      expect(viewModel.lastPrescriptionRawMedicationCount, 2);
      expect(viewModel.lastPrescriptionParsedMedicationCount, 1);
      expect(viewModel.lastPrescriptionSkippedMedicationCount, 1);
      expect(viewModel.correctedPrescriptionMedicationCount, 1);
      expect(viewModel.prescriptionRecognitionNotice, contains('약명 보정'));
      expect(viewModel.prescriptionRecognitionNotice, contains('OCR 항목 제외'));
      expect(viewModel.statusMessage, contains('인식 내역'));
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 상세조회에 실패한 약을 버리지 않고 재검토 상태로 보존한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('상세조회에 실패한 약을 버리지 않고 재검토 상태로 보존한다', () async {
    final changeControl = _FakeCheckPrescriptionChange();
    final viewModel = MedBuddyViewModel(
      inputPrescription: _FakeInputPrescription(const [
        MedicationSchedule(medicationName: 'found-tablet'),
        MedicationSchedule(medicationName: 'missing-tablet'),
      ]),
      checkMedicationDetail: _FakeCheckMedicationDetail(),
      checkPrescriptionChange: changeControl,
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();
    await viewModel.requestPrescriptionAnalysis();

    expect(
      viewModel.prescriptionFlowState,
      PrescriptionFlowState.medicationReviewRequired,
    );
    expect(viewModel.analyzedMedicationList, hasLength(1));
    expect(viewModel.verifiedMedicationScheduleIndexes, {0});
    expect(viewModel.unverifiedMedicationScheduleIndexes, {1});
    expect(viewModel.statusMessage, contains('1개 약 정보'));
    expect(viewModel.canRetryPrescriptionAnalysis, isTrue);

    final continued = viewModel.continueWithVerifiedMedicationAnalysis();

    expect(continued, isTrue);
    expect(
      viewModel.prescriptionFlowState,
      PrescriptionFlowState.analysisSucceeded,
    );
    expect(changeControl.requestCount, 0);
    expect(viewModel.prescriptionChangeRadar, isNull);
    expect(viewModel.isPrescriptionChangeLoading, isFalse);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 처방 약 상세정보를 최대 여섯 건씩 병렬 조회한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('처방 약 상세정보를 최대 여섯 건씩 병렬 조회한다', () async {
    final detailControl = _ConcurrencyTrackingCheckMedicationDetail();
    final schedules = List<MedicationSchedule>.generate(
      7,
      // 함수이름: List<MedicationSchedule>.generate 콜백
      // 함수역할:
      // - 동시 상세조회 요청을 구분할 수 있도록 순번별 약명 일정을 만든다.
      // 매개변수:
      // - index (int): 0부터 시작하는 행 또는 생성 대역의 순번.
      // 반환값:
      // - 순번이 약명에 포함된 MedicationSchedule.
      (index) => MedicationSchedule(medicationName: 'medicine-$index'),
    );
    final viewModel = MedBuddyViewModel(
      inputPrescription: _FakeInputPrescription(schedules),
      checkMedicationDetail: detailControl,
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();
    final pendingAnalysis = viewModel.requestPrescriptionAnalysis();
    await Future<void>.delayed(Duration.zero);

    expect(detailControl.startedRequestCount, 6);
    expect(detailControl.maximumActiveRequestCount, 6);

    detailControl.firstBatchRelease.complete();
    await pendingAnalysis;

    expect(detailControl.startedRequestCount, 7);
    expect(
      viewModel.prescriptionFlowState,
      PrescriptionFlowState.analysisSucceeded,
    );
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 사용자가 수정한 OCR 결과로 약품 상세정보를 조회한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('사용자가 수정한 OCR 결과로 약품 상세정보를 조회한다', () async {
    final detailControl = _CapturingCheckMedicationDetail();
    final viewModel = MedBuddyViewModel(
      inputPrescription: _FakeInputPrescription(const [
        MedicationSchedule(
          medicationName: '에니코프캡슐',
          dosage: '1정',
          intakeTime: '1일 3회',
          medicationTime: 4,
          nameCorrectionSource: 'unverified',
        ),
      ]),
      checkMedicationDetail: detailControl,
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();
    viewModel.updateRecognizedMedicationSchedule(
      0,
      const MedicationSchedule(
        medicationName: '애니코프캡슐',
        dosage: '0.5정',
        intakeTime: '1일 2회',
        medicationTime: 5,
      ),
    );

    final correctedSchedule = viewModel.recognizedMedicationScheduleList.first;
    expect(correctedSchedule.medicationName, '애니코프캡슐');
    expect(correctedSchedule.rawMedicationName, '에니코프캡슐');
    expect(correctedSchedule.nameCorrectionSource, 'user_edit');
    expect(correctedSchedule.nameConfidence, 1.0);

    await viewModel.requestPrescriptionAnalysis();

    expect(detailControl.requestedSchedule?.medicationName, '애니코프캡슐');
    expect(detailControl.requestedSchedule?.dosage, '0.5정');
    expect(detailControl.requestedSchedule?.intakeTime, '1일 2회');
    expect(detailControl.requestedSchedule?.medicationTime, 5);
    expect(viewModel.analyzedMedicationList.single.displayName, '애니코프캡슐');
    expect(
      viewModel.prescriptionFlowState,
      PrescriptionFlowState.analysisSucceeded,
    );
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 처방 분석 완료 후 이전 처방과의 변경 비교 결과를 조회하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('requestPrescriptionAnalysis loads prescription change radar', () async {
    final changeControl = _FakeCheckPrescriptionChange();
    final viewModel = MedBuddyViewModel(
      inputPrescription: _FakeInputPrescription(const [
        MedicationSchedule(medicationName: 'found-tablet'),
      ]),
      checkMedicationDetail: _FakeCheckMedicationDetail(),
      checkPrescriptionChange: changeControl,
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();
    await viewModel.requestPrescriptionAnalysis();
    viewModel.showMedicationAnalysisResult();
    await Future<void>.delayed(Duration.zero);

    expect(changeControl.requestCount, 1);
    expect(viewModel.prescriptionChangeRadar, isNotNull);
    expect(viewModel.prescriptionChangeRadar!.summary.addedCount, 1);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 약 상세 분석 실패는 처방 OCR을 반복하지 않고 다시 조회할 수 있는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'medication analysis can retry without repeating prescription OCR',
    () async {
      final detailControl = _RetryableCheckMedicationDetail();
      final viewModel = MedBuddyViewModel(
        inputPrescription: _FakeInputPrescription(const [
          MedicationSchedule(medicationName: 'retry-tablet'),
        ]),
        checkMedicationDetail: detailControl,
      );
      addTearDown(viewModel.dispose);

      await viewModel.requestPrescriptionImageFromGallery();
      await viewModel.requestPrescriptionAnalysis();

      expect(
        viewModel.prescriptionFlowState,
        PrescriptionFlowState.medicationReviewRequired,
      );
      expect(viewModel.canRetryPrescriptionAnalysis, isTrue);
      expect(viewModel.recognizedMedicationScheduleList, hasLength(1));

      await viewModel.requestPrescriptionAnalysis();

      expect(
        viewModel.prescriptionFlowState,
        PrescriptionFlowState.analysisSucceeded,
      );
      expect(viewModel.canRetryPrescriptionAnalysis, isFalse);
      expect(viewModel.analyzedMedicationList, hasLength(1));
      expect(detailControl.requestCount, 2);
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 확인된 약은 유지하고 수정한 미확인 약만 다시 조회한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('확인된 약은 유지하고 수정한 미확인 약만 다시 조회한다', () async {
    final detailControl = _SelectiveCheckMedicationDetail({'found-tablet'});
    final viewModel = MedBuddyViewModel(
      inputPrescription: _FakeInputPrescription(const [
        MedicationSchedule(medicationName: 'found-tablet'),
        MedicationSchedule(medicationName: 'wrong-tablet'),
      ]),
      checkMedicationDetail: detailControl,
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();
    await viewModel.requestPrescriptionAnalysis();
    expect(detailControl.requestedMedicationNames, [
      'found-tablet',
      'wrong-tablet',
    ]);
    expect(
      viewModel.prescriptionFlowState,
      PrescriptionFlowState.medicationReviewRequired,
    );

    detailControl.matchedMedicationNames.add('corrected-tablet');
    viewModel.updateRecognizedMedicationSchedule(
      1,
      const MedicationSchedule(medicationName: 'corrected-tablet'),
    );
    await viewModel.requestPrescriptionAnalysis();

    expect(detailControl.requestedMedicationNames, [
      'found-tablet',
      'wrong-tablet',
      'corrected-tablet',
    ]);
    expect(
      viewModel.prescriptionFlowState,
      PrescriptionFlowState.analysisSucceeded,
    );
    // 함수이름: map 콜백
    // 함수역할:
    // - 목록 검증에 사용할 최종 표시 약명를 추출한다.
    // 매개변수:
    // - item (AnalyzedMedication): 약 관련 필드를 추출할 목록 요소.
    // 반환값:
    // - 요소의 displayName 값.
    expect(viewModel.analyzedMedicationList.map((item) => item.displayName), [
      'found-tablet',
      'corrected-tablet',
    ]);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: OCR 누락 약을 직접 추가해 분석 대상에 포함한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('OCR 누락 약을 직접 추가해 분석 대상에 포함한다', () async {
    final detailControl = _SelectiveCheckMedicationDetail({
      'recognized-tablet',
      'manual-tablet',
    });
    final viewModel = MedBuddyViewModel(
      inputPrescription: _FakeInputPrescription(const [
        MedicationSchedule(medicationName: 'recognized-tablet'),
      ]),
      checkMedicationDetail: detailControl,
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();
    viewModel.addRecognizedMedicationSchedule(
      const MedicationSchedule(
        medicationName: 'manual-tablet',
        dosage: '1정',
        intakeTime: '2회',
        medicationTime: 3,
        scheduleSlotKeys: ['morning', 'evening'],
      ),
    );

    expect(viewModel.recognizedMedicationScheduleList, hasLength(2));
    expect(
      viewModel.recognizedMedicationScheduleList.last.nameCorrectionSource,
      'manual_add',
    );
    await viewModel.requestPrescriptionAnalysis();

    expect(
      viewModel.prescriptionFlowState,
      PrescriptionFlowState.analysisSucceeded,
    );
    expect(viewModel.analyzedMedicationList, hasLength(2));
    expect(detailControl.requestedMedicationNames, [
      'recognized-tablet',
      'manual-tablet',
    ]);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 처방 인식 자체의 실패에는 약 상세 분석 전용 재시도를 노출하지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'prescription recognition failure does not expose analysis retry',
    () async {
      final viewModel = MedBuddyViewModel(
        inputPrescription: _FakeInputPrescription(const []),
      );
      addTearDown(viewModel.dispose);

      await viewModel.requestPrescriptionImageFromGallery();

      expect(
        viewModel.prescriptionFlowState,
        PrescriptionFlowState.analysisFailed,
      );
      expect(viewModel.canRetryPrescriptionAnalysis, isFalse);
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 인식 상태를 지운 뒤 도착한 이전 OCR 결과를 무시하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('clearing recognition ignores a late OCR result', () async {
    final prescriptionControl = _DeferredInputPrescription();
    final viewModel = MedBuddyViewModel(inputPrescription: prescriptionControl);
    addTearDown(viewModel.dispose);

    final pendingRequest = viewModel.requestPrescriptionImageFromGallery();
    await Future<void>.delayed(Duration.zero);
    expect(
      viewModel.prescriptionFlowState,
      PrescriptionFlowState.recognizingPrescription,
    );

    viewModel.clearAnalysisResult();
    prescriptionControl.completer.complete(const [
      MedicationSchedule(medicationName: 'late-tablet'),
    ]);
    await pendingRequest;

    expect(viewModel.prescriptionFlowState, PrescriptionFlowState.idle);
    expect(viewModel.recognizedMedicationScheduleList, isEmpty);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 분석 상태를 지운 뒤 도착한 이전 약 상세 결과를 무시하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('clearing analysis ignores a late medication detail result', () async {
    final detailControl = _DeferredCheckMedicationDetail();
    final viewModel = MedBuddyViewModel(
      inputPrescription: _FakeInputPrescription(const [
        MedicationSchedule(medicationName: 'late-tablet'),
      ]),
      checkMedicationDetail: detailControl,
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();
    final pendingRequest = viewModel.requestPrescriptionAnalysis();
    await Future<void>.delayed(Duration.zero);
    expect(
      viewModel.prescriptionFlowState,
      PrescriptionFlowState.analyzingMedication,
    );

    viewModel.clearAnalysisResult();
    detailControl.completer.complete(
      const MedicationDetail(
        itemName: 'late-tablet',
        efficacy: 'effect',
        usageMethod: 'usage',
        warning: 'warning',
      ),
    );
    await pendingRequest;

    expect(viewModel.prescriptionFlowState, PrescriptionFlowState.idle);
    expect(viewModel.analyzedMedicationList, isEmpty);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: overlapping per-card medication saves are rejected.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('overlapping per-card medication saves are rejected', () async {
    final saveControl = _DeferredCheckSavedMedication();
    final viewModel = MedBuddyViewModel(checkSavedMedication: saveControl);
    addTearDown(viewModel.dispose);
    const firstMedication = AnalyzedMedication(
      schedule: MedicationSchedule(medicationName: 'first-tablet'),
      detail: MedicationDetail(
        itemName: 'first-tablet',
        efficacy: 'effect',
        usageMethod: 'usage',
        warning: 'warning',
      ),
    );
    const secondMedication = AnalyzedMedication(
      schedule: MedicationSchedule(medicationName: 'second-tablet'),
      detail: MedicationDetail(
        itemName: 'second-tablet',
        efficacy: 'effect',
        usageMethod: 'usage',
        warning: 'warning',
      ),
    );

    final firstSave = viewModel.requestMedicationSave(firstMedication, 0);
    await Future<void>.delayed(Duration.zero);
    final secondResult = await viewModel.requestMedicationSave(
      secondMedication,
      1,
    );

    expect(secondResult, isFalse);
    expect(saveControl.requestCount, 1);
    expect(viewModel.savingMedicationIndex, 0);

    final bulkResult = await viewModel.requestAllAnalyzedMedicationSave();
    expect(bulkResult, isFalse);
    expect(saveControl.requestCount, 1);
    expect(viewModel.isAllMedicationSaving, isFalse);
    expect(viewModel.statusMessage, '다른 복약 정보를 저장하고 있습니다.');

    saveControl.completer.complete(
      const MedicationSaveResult(
        status: MedicationSaveStatus.failed,
        message: 'simulated failure',
      ),
    );
    await firstSave;
  });
}
