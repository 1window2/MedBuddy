// File Name: saved_medication_save_flow_test.dart
// Role: Regression coverage for saving identified pills and manual entries, device photo
//   storage and orphan photo cleanup in the saved-medication view model.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_medication_detail_control.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/identified_pill_save_request_entity.dart';
import 'package:medbuddy_frontend/entities/manual_medication_entry_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_match_review_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/pill_identification_entity.dart';
import 'package:medbuddy_frontend/services/manual_medication_image_store.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_saved_medication_view_model.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Function Name: _offlineClient
// Description:
// - Builds an HTTP client that answers every request with status 500 so no fake reaches a server.
// Parameters:
// - None.
// Returns:
// - A mock client for controls whose requests the fakes override.
http.Client _offlineClient() =>
    MockClient((_) async => http.Response('{}', 500));

// Class Name: _RecordingSavedControl
// Role: Saved-medication control fake that records save requests and serves a scripted list.
// Responsibilities:
// - Keep every saved detail and schedule in call order.
// - Assign increasing saved IDs, or fail or throw for chosen medication names.
// - Count list requests and return the configured list.
// - Confirm deletions except for the IDs a test marks as rejected.
// Attributes:
// - savedDetails (List<MedicationDetail>): Details passed to the save request, in order.
// - savedSchedules (List<MedicationSchedule?>): Schedules passed with each save request.
// - failingNames (Set<String>): Names whose save reports a failed result.
// - throwingNames (Set<String>): Names whose save throws.
// - listedMedications (List<MedicationDetail>): List returned by the list request.
// - listRequests (int): Number of list requests received.
// - rejectedDeleteIds (Set<int>): Saved IDs whose deletion the fake server rejects.
class _RecordingSavedControl extends CheckSavedMedication {
  final savedDetails = <MedicationDetail>[];
  final savedSchedules = <MedicationSchedule?>[];
  final failingNames = <String>{};
  final throwingNames = <String>{};
  List<MedicationDetail> listedMedications = const [];
  int listRequests = 0;
  final rejectedDeleteIds = <int>{};
  int _nextId = 41;

  // Function Name: _RecordingSavedControl
  // Description:
  // - Binds the fake to an offline client so an unexpected real request cannot leave the test.
  // Parameters:
  // - None.
  // Returns:
  // - _RecordingSavedControl: the initialized instance.
  _RecordingSavedControl()
    : super(baseUrl: 'http://medbuddy.test', client: _offlineClient());

  // Function Name: saveMedicationDetail
  // Description:
  // - Records the request and answers with a new saved ID, a failed result or an exception
  //   according to the configured names.
  // Parameters:
  // - medicationDetail (MedicationDetail): Detail the view model resolved for saving.
  // - medicationSchedule (MedicationSchedule?): Schedule sent with the detail.
  // Returns:
  // - The scripted save result.
  @override
  Future<MedicationSaveResult> saveMedicationDetail(
    MedicationDetail medicationDetail, {
    MedicationSchedule? medicationSchedule,
  }) async {
    if (throwingNames.contains(medicationDetail.itemName)) {
      throw StateError('save crashed');
    }
    savedDetails.add(medicationDetail);
    savedSchedules.add(medicationSchedule);
    if (failingNames.contains(medicationDetail.itemName)) {
      return const MedicationSaveResult(
        status: MedicationSaveStatus.failed,
        message: 'rejected',
      );
    }
    return MedicationSaveResult(
      status: MedicationSaveStatus.saved,
      message: 'saved',
      savedMedicationId: _nextId++,
    );
  }

  // Function Name: requestSavedMedicationInfo
  // Description:
  // - Counts the list request and returns a copy of the configured list.
  // Parameters:
  // - None.
  // Returns:
  // - The configured saved medications.
  @override
  Future<List<MedicationDetail>> requestSavedMedicationInfo() async {
    listRequests += 1;
    return List<MedicationDetail>.of(listedMedications);
  }

  // Function Name: requestDelete
  // Description:
  // - Confirms the deletion unless the test marked the ID as rejected.
  // Parameters:
  // - savedMedicationId (int): Saved medication to delete.
  // Returns:
  // - Whether the fake server deleted the medication.
  @override
  Future<bool> requestDelete(int savedMedicationId) async =>
      !rejectedDeleteIds.contains(savedMedicationId);
}

// Class Name: _ScriptedDetailControl
// Role: Catalog lookup fake whose answer each test scripts.
// Responsibilities:
// - Record the looked-up schedules and delegate the answer to the test's callback.
// Attributes:
// - onRequest (Future<MedicationDetail?> Function(MedicationSchedule)): Scripted lookup answer.
// - requestedNames (List<String>): Medication names looked up, in order.
class _ScriptedDetailControl extends CheckMedicationDetail {
  Future<MedicationDetail?> Function(MedicationSchedule schedule) onRequest;
  final requestedNames = <String>[];

  // Function Name: _ScriptedDetailControl
  // Description:
  // - Stores the scripted answer and binds the fake to an offline client.
  // Parameters:
  // - onRequest: Callback producing the lookup result or throwing the lookup failure.
  // Returns:
  // - _ScriptedDetailControl: the initialized instance.
  _ScriptedDetailControl(this.onRequest) : super(client: _offlineClient());

  // Function Name: requestMedicationDetail
  // Description:
  // - Records the looked-up name and returns the scripted answer.
  // Parameters:
  // - medicationSchedule (MedicationSchedule): Schedule whose medication name is looked up.
  // Returns:
  // - The scripted detail, null, or the scripted failure.
  @override
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule medicationSchedule,
  ) {
    requestedNames.add(medicationSchedule.medicationName);
    return onRequest(medicationSchedule);
  }
}

// Class Name: _FakeImageStore
// Role: Device photo store fake that records calls instead of touching app storage.
// Responsibilities:
// - Record saved photos and report a stored path for them afterwards.
// - Fail photo saving on request and record the orphan cleanup scope.
// Attributes:
// - savedSources (Map<int, String>): Source path saved for each medication ID.
// - failSave (bool): Whether saving a photo throws.
// - orphanScopes (List<Set<int>>): Active ID sets passed to orphan cleanup.
// - deletedIds (List<int>): Medication IDs whose photo deletion was requested.
class _FakeImageStore extends ManualMedicationImageStore {
  final savedSources = <int, String>{};
  bool failSave = false;
  final orphanScopes = <Set<int>>[];
  final deletedIds = <int>[];

  // Function Name: saveImage
  // Description:
  // - Records the source path for the medication, or throws when saving is set to fail.
  // Parameters:
  // - patientHash (String): Account scope of the photo; not used by this fake.
  // - medicationId (int): Saved medication that owns the photo.
  // - sourcePath (String): Picked photo copy to store.
  // Returns:
  // - The path the fake reports for the stored photo.
  @override
  Future<String> saveImage({
    required String patientHash,
    required int medicationId,
    required String sourcePath,
  }) async {
    if (failSave) {
      throw const FileSystemException('disk full');
    }
    savedSources[medicationId] = sourcePath;
    return '/stored/$medicationId.jpg';
  }

  // Function Name: findImagePath
  // Description:
  // - Reports the stored path for medications whose photo was saved.
  // Parameters:
  // - patientHash (String): Account scope of the photo; not used by this fake.
  // - medicationId (int): Saved medication to look up.
  // Returns:
  // - The stored path, or an empty string when no photo was saved.
  @override
  Future<String> findImagePath({
    required String patientHash,
    required int medicationId,
  }) async {
    return savedSources.containsKey(medicationId)
        ? '/stored/$medicationId.jpg'
        : '';
  }

  // Function Name: removeOrphanImages
  // Description:
  // - Records the set of saved medication IDs that are still active.
  // Parameters:
  // - patientHash (String): Account scope of the photos; not used by this fake.
  // - activeMedicationIds (Set<int>): IDs whose photos must be kept.
  // Returns:
  // - Future<void>; completes when the scope is recorded.
  @override
  Future<void> removeOrphanImages({
    required String patientHash,
    required Set<int> activeMedicationIds,
  }) async {
    orphanScopes.add(Set<int>.of(activeMedicationIds));
  }

  // Function Name: deleteImage
  // Description:
  // - Records the medication whose photo deletion was requested.
  // Parameters:
  // - patientHash (String): Account scope of the photo; not used by this fake.
  // - medicationId (int): Saved medication whose photo is removed.
  // Returns:
  // - Future<void>; completes when the request is recorded.
  @override
  Future<void> deleteImage({
    required String patientHash,
    required int medicationId,
  }) async {
    deletedIds.add(medicationId);
  }
}

// Class Name: _TemporaryPathProvider
// Role: Test path provider that reports a chosen directory as the app temporary directory.
// Responsibilities:
// - Replace the platform channel so the temporary directory is a folder the test controls.
// Attributes:
// - temporaryPath (String): Directory reported as the temporary directory.
class _TemporaryPathProvider extends PathProviderPlatform {
  final String temporaryPath;

  // Function Name: _TemporaryPathProvider
  // Description:
  // - Keeps the directory to report as the app temporary directory.
  // Parameters:
  // - temporaryPath (String): Directory to report.
  // Returns:
  // - _TemporaryPathProvider: the initialized instance.
  _TemporaryPathProvider(this.temporaryPath);

  // Function Name: getTemporaryPath
  // Description:
  // - Reports the configured temporary directory.
  // Parameters:
  // - None.
  // Returns:
  // - The configured directory path.
  @override
  Future<String?> getTemporaryPath() async => temporaryPath;
}

// Class Name: _Harness
// Role: Bundles the saved-medication view model with its fakes and refresh counters.
// Responsibilities:
// - Build the view model without the application facade so each save path is observed directly.
// Attributes:
// - saved (_RecordingSavedControl): Save and list fake.
// - lookup (_ScriptedDetailControl): Catalog lookup fake.
// - images (_FakeImageStore): Device photo store fake.
// - scheduleRefreshes (int): Number of schedule refreshes requested after saving.
// - reminderSyncs (int): Number of reminder synchronizations requested after saving.
// - model (MedBuddySavedMedicationViewModel): View model under test.
class _Harness {
  final saved = _RecordingSavedControl();
  final images = _FakeImageStore();
  final _ScriptedDetailControl lookup;
  int scheduleRefreshes = 0;
  int reminderSyncs = 0;
  late final MedBuddySavedMedicationViewModel model;

  // Function Name: _Harness
  // Description:
  // - Wires the fakes and counting callbacks into a view model for patient "patient-a".
  // Parameters:
  // - onLookup: Scripted catalog lookup answer.
  // Returns:
  // - _Harness: the initialized instance.
  _Harness(Future<MedicationDetail?> Function(MedicationSchedule) onLookup)
    : lookup = _ScriptedDetailControl(onLookup) {
    model = MedBuddySavedMedicationViewModel(
      checkSavedMedication: saved,
      checkMedicationDetail: lookup,
      manualMedicationImageStore: images,
      patientHash: 'patient-a',
      readEnglishSetting: () => false,
      fetchTodayMedicationSchedule: () async => scheduleRefreshes += 1,
      synchronizeReminders: () async => reminderSyncs += 1,
      onChanged: (_) {},
    );
  }
}

const _chosenCandidate = PillIdentificationCandidate(
  itemSeq: '200000001',
  itemName: '타이레놀정500밀리그람',
  imageUrl: 'https://nedrug.mfds.go.kr/chosen.jpg',
);

const _chosenSchedule = MedicationSchedule(
  medicationName: '타이레놀정500밀리그람',
  dosage: '1정',
  intakeTime: '3회',
  medicationTime: 5,
  scheduleSlotKeys: ['morning', 'lunch', 'evening'],
);

// Function Name: _catalogDetail
// Description:
// - Builds a catalog detail whose text fields are marked with the item code they belong to.
// Parameters:
// - itemSeq (String): Catalog item code of the product.
// - imageUrl (String): Optional trusted catalog image of the product.
// Returns:
// - A detail whose efficacy, usage and warning name the product.
MedicationDetail _catalogDetail(String itemSeq, {String imageUrl = ''}) =>
    MedicationDetail(
      itemSeq: itemSeq,
      itemName: 'catalog name $itemSeq',
      efficacy: 'efficacy of $itemSeq',
      usageMethod: 'usage of $itemSeq',
      warning: 'warning of $itemSeq',
      imageUrl: imageUrl,
    );

// Function Name: main
// Description:
// - Registers the save-flow cases for identified pills, manual entries, device photos and
//   orphan photo cleanup.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('identified pill', () {
    // Function Name: test callback
    // Description:
    // - Expected behavior: when the name lookup answers with another product, its text and
    //   image are not stored under the item code the patient confirmed.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the assertions pass.
    test('a lookup that returns another product is not saved under the '
        'chosen item code', () async {
      final harness = _Harness(
        (_) async => _catalogDetail(
          '299999999',
          imageUrl: 'https://nedrug.mfds.go.kr/other.jpg',
        ),
      );
      addTearDown(harness.model.dispose);

      final result = await harness.model.saveIdentifiedPill(
        _chosenCandidate,
        _chosenSchedule,
      );

      expect(result.status, MedicationSaveStatus.saved);
      final saved = harness.saved.savedDetails.single;
      expect(saved.itemSeq, '200000001');
      expect(saved.itemName, '타이레놀정500밀리그람');
      expect(saved.efficacy, isEmpty);
      expect(saved.usageMethod, isEmpty);
      expect(saved.warning, isEmpty);
      expect(saved.imageUrl, 'https://nedrug.mfds.go.kr/chosen.jpg');
      expect(
        harness.saved.savedSchedules.single?.imageUrl,
        'https://nedrug.mfds.go.kr/chosen.jpg',
      );
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: an ambiguous name lookup is resolved with the candidate that has
    //   the confirmed item code, so its usage and warning text are saved.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the assertions pass.
    test('an ambiguous lookup is resolved by the chosen item code', () async {
      final harness = _Harness(
        (_) async => throw MedicationMatchReview([
          _catalogDetail('299999999'),
          _catalogDetail('200000001'),
        ]),
      );
      addTearDown(harness.model.dispose);

      await harness.model.saveIdentifiedPill(_chosenCandidate, _chosenSchedule);

      final saved = harness.saved.savedDetails.single;
      expect(saved.itemSeq, '200000001');
      expect(saved.itemName, '타이레놀정500밀리그람');
      expect(saved.efficacy, 'efficacy of 200000001');
      expect(saved.usageMethod, 'usage of 200000001');
      expect(saved.warning, 'warning of 200000001');
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: an ambiguous lookup without the confirmed item code saves the
    //   candidate's own fields and none of the other products' text.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the assertions pass.
    test('an ambiguous lookup without the chosen item code keeps the '
        'candidate fields', () async {
      final harness = _Harness(
        (_) async => throw MedicationMatchReview([
          _catalogDetail('299999999'),
          _catalogDetail('288888888'),
        ]),
      );
      addTearDown(harness.model.dispose);

      await harness.model.saveIdentifiedPill(_chosenCandidate, _chosenSchedule);

      final saved = harness.saved.savedDetails.single;
      expect(saved.itemSeq, '200000001');
      expect(saved.efficacy, isEmpty);
      expect(saved.warning, isEmpty);
      expect(saved.imageUrl, 'https://nedrug.mfds.go.kr/chosen.jpg');
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: a lookup of the confirmed product adds its catalog text and image
    //   while the schedule values the patient reviewed are kept.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the assertions pass.
    test('a lookup of the chosen product adds its catalog text', () async {
      final harness = _Harness(
        (_) async => _catalogDetail(
          '200000001',
          imageUrl: 'https://nedrug.mfds.go.kr/catalog.jpg',
        ).copyWith(itemSeq: ' 200000001 '),
      );
      addTearDown(harness.model.dispose);

      await harness.model.saveIdentifiedPill(_chosenCandidate, _chosenSchedule);

      final saved = harness.saved.savedDetails.single;
      expect(saved.itemSeq, '200000001');
      expect(saved.itemName, '타이레놀정500밀리그람');
      expect(saved.efficacy, 'efficacy of 200000001');
      expect(saved.warning, 'warning of 200000001');
      expect(saved.imageUrl, 'https://nedrug.mfds.go.kr/catalog.jpg');
      expect(saved.dosagePerTime, '1정');
      expect(saved.dailyFrequency, '3회');
      expect(harness.saved.listRequests, 1);
      expect(harness.scheduleRefreshes, 1);
      expect(harness.reminderSyncs, 1);
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: a failed or busy lookup does not block saving the confirmed
    //   candidate with the reviewed schedule.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the assertions pass.
    test('a failed or busy lookup still saves the confirmed candidate', () async {
      for (final failure in <Object>[
        StateError('lookup failed'),
        MedicationLookupBusy(const Duration(seconds: 5)),
      ]) {
        final harness = _Harness((_) async => throw failure);
        addTearDown(harness.model.dispose);

        final result = await harness.model.saveIdentifiedPill(
          _chosenCandidate,
          _chosenSchedule,
        );

        expect(result.isCompleted, isTrue);
        final saved = harness.saved.savedDetails.single;
        expect(saved.itemSeq, '200000001');
        expect(saved.itemName, '타이레놀정500밀리그람');
        expect(saved.imageUrl, 'https://nedrug.mfds.go.kr/chosen.jpg');
      }
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: a batch keeps the request order, isolates a rejected and a crashed
    //   save, and refreshes the list, schedule and reminders once at the end.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the assertions pass.
    test('a batch keeps its order, isolates failures and refreshes once', () async {
      final harness = _Harness((_) async => null);
      addTearDown(harness.model.dispose);
      harness.saved.failingNames.add('rejected pill');
      harness.saved.throwingNames.add('crashing pill');
      IdentifiedPillSaveRequest request(String itemSeq, String name) =>
          IdentifiedPillSaveRequest(
            candidate: PillIdentificationCandidate(
              itemSeq: itemSeq,
              itemName: name,
            ),
            medicationSchedule: MedicationSchedule(medicationName: name),
          );

      final results = await harness.model.saveIdentifiedPills([
        request('1', 'first pill'),
        request('2', 'rejected pill'),
        request('3', 'crashing pill'),
        request('4', 'last pill'),
      ]);

      expect(results.map((result) => result.status), [
        MedicationSaveStatus.saved,
        MedicationSaveStatus.failed,
        MedicationSaveStatus.failed,
        MedicationSaveStatus.saved,
      ]);
      expect(harness.lookup.requestedNames, [
        'first pill',
        'rejected pill',
        'crashing pill',
        'last pill',
      ]);
      expect(harness.saved.listRequests, 1);
      expect(harness.scheduleRefreshes, 1);
      expect(harness.reminderSyncs, 1);
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: a batch in which every save fails does not refresh anything.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the assertions pass.
    test('a batch without a completed save does not refresh', () async {
      final harness = _Harness((_) async => null);
      addTearDown(harness.model.dispose);
      harness.saved.failingNames.add('rejected pill');

      final results = await harness.model.saveIdentifiedPills([
        IdentifiedPillSaveRequest(
          candidate: const PillIdentificationCandidate(
            itemSeq: '2',
            itemName: 'rejected pill',
          ),
          medicationSchedule: const MedicationSchedule(
            medicationName: 'rejected pill',
          ),
        ),
      ]);

      expect(results.single.status, MedicationSaveStatus.failed);
      expect(harness.saved.listRequests, 0);
      expect(harness.scheduleRefreshes, 0);
    });
  });

  group('manual entry', () {
    final entry = ManualMedicationEntry(
      medicationName: ' 직접 입력약 ',
      dosageAmount: '1',
      dosageUnit: '정',
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 10, 3),
      scheduleSlotKeys: const ['morning', 'evening'],
      localImagePath: '/picked/photo.jpg',
    );

    // Function Name: test callback
    // Description:
    // - Expected behavior: a manual entry is saved with the entered name and schedule even
    //   when the name lookup fails or is ambiguous, and the picked photo is stored for the
    //   saved ID.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the assertions pass.
    test('a failed or ambiguous lookup still saves the entered medication '
        'and its photo', () async {
      for (final failure in <Object>[
        StateError('lookup failed'),
        MedicationMatchReview([_catalogDetail('299999999')]),
      ]) {
        final harness = _Harness((_) async => throw failure);
        addTearDown(harness.model.dispose);

        final result = await harness.model.saveManualMedication(entry);

        expect(result.status, MedicationSaveStatus.saved);
        final saved = harness.saved.savedDetails.single;
        expect(saved.itemName, '직접 입력약');
        expect(saved.efficacy, isEmpty);
        final schedule = harness.saved.savedSchedules.single!;
        expect(schedule.nameCorrectionSource, 'manual_entry');
        expect(schedule.scheduleSlotKeys, ['morning', 'evening']);
        expect(schedule.medicationTime, 3);
        expect(harness.images.savedSources, {
          result.savedMedicationId: '/picked/photo.jpg',
        });
      }
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: a rejected save stores no photo and refreshes nothing.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the assertions pass.
    test('a rejected save stores no photo and does not refresh', () async {
      final harness = _Harness((_) async => null);
      addTearDown(harness.model.dispose);
      harness.saved.failingNames.add('직접 입력약');

      final result = await harness.model.saveManualMedication(entry);

      expect(result.status, MedicationSaveStatus.failed);
      expect(harness.images.savedSources, isEmpty);
      expect(harness.saved.listRequests, 0);
      expect(harness.scheduleRefreshes, 0);
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: a photo that cannot be stored does not undo the saved medication.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the assertions pass.
    test('a photo that cannot be stored does not fail the save', () async {
      final harness = _Harness((_) async => null);
      addTearDown(harness.model.dispose);
      harness.images.failSave = true;

      final result = await harness.model.saveManualMedication(entry);

      expect(result.status, MedicationSaveStatus.saved);
      expect(harness.saved.listRequests, 1);
    });
  });

  group('picked photo copy', () {
    late Directory sandbox;
    late Directory temporaryDirectory;
    late PathProviderPlatform originalProvider;

    // Function Name: setUp callback
    // Description:
    // - Creates an app temporary directory the test controls and reports it through the
    //   path provider.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the directory exists and the provider is replaced.
    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('medbuddy-save-flow-');
      temporaryDirectory = await Directory('${sandbox.path}/cache').create();
      originalProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TemporaryPathProvider(
        temporaryDirectory.path,
      );
    });

    // Function Name: tearDown callback
    // Description:
    // - Restores the path provider and removes the directories of the case.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the sandbox is removed.
    tearDown(() async {
      PathProviderPlatform.instance = originalProvider;
      await sandbox.delete(recursive: true);
    });

    // Function Name: saveWithPhoto
    // Description:
    // - Saves one medication with the given picked photo path through the view model.
    // Parameters:
    // - harness (_Harness): View model and fakes of the case.
    // - photoPath (String): Path of the picked photo copy.
    // Returns:
    // - The save result.
    Future<MedicationSaveResult> saveWithPhoto(
      _Harness harness,
      String photoPath,
    ) => harness.model.saveMedicationInfo(
      const MedicationDetail(
        itemName: '사진 있는 약',
        efficacy: '',
        usageMethod: '',
        warning: '',
      ),
      localImagePath: photoPath,
    );

    // Function Name: test callback
    // Description:
    // - Expected behavior: the picked copy in the app temporary directory is deleted once the
    //   photo has been stored for the saved medication.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the assertions pass.
    test('the picked copy is deleted after the photo is stored', () async {
      final harness = _Harness((_) async => null);
      addTearDown(harness.model.dispose);
      final picked = File('${temporaryDirectory.path}/picked.jpg');
      await picked.writeAsBytes([1, 2, 3]);

      final result = await saveWithPhoto(harness, picked.path);

      expect(harness.images.savedSources, {
        result.savedMedicationId: picked.path,
      });
      expect(await picked.exists(), isFalse);
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: the picked copy is kept when storing the photo fails, and a file
    //   outside the app temporary directory is never deleted.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the assertions pass.
    test('the picked copy is kept when storing fails or it is not an app '
        'temporary file', () async {
      final failing = _Harness((_) async => null);
      addTearDown(failing.model.dispose);
      failing.images.failSave = true;
      final picked = File('${temporaryDirectory.path}/picked.jpg');
      await picked.writeAsBytes([1, 2, 3]);

      await saveWithPhoto(failing, picked.path);

      expect(await picked.exists(), isTrue);

      final harness = _Harness((_) async => null);
      addTearDown(harness.model.dispose);
      final gallery = File('${sandbox.path}/gallery.jpg');
      await gallery.writeAsBytes([1, 2, 3]);

      await saveWithPhoto(harness, gallery.path);

      expect(harness.images.savedSources.values, [gallery.path]);
      expect(await gallery.exists(), isTrue);
    });
  });

  group('device photos of the saved list', () {
    // Function Name: test callback
    // Description:
    // - Expected behavior: a list load attaches the stored photo paths and limits orphan
    //   cleanup to photos of medications that are no longer in the list.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the assertions pass.
    test('a list load attaches stored photos and cleans orphans by the '
        'listed IDs', () async {
      final harness = _Harness((_) async => null);
      addTearDown(harness.model.dispose);
      harness.images.savedSources[7] = '/picked/seven.jpg';
      harness.saved.listedMedications = const [
        MedicationDetail(
          id: 7,
          itemName: 'with photo',
          efficacy: '',
          usageMethod: '',
          warning: '',
        ),
        MedicationDetail(
          id: 8,
          itemName: 'without photo',
          efficacy: '',
          usageMethod: '',
          warning: '',
        ),
      ];

      await harness.model.fetchSavedMedicationInfo();
      await pumpEventQueue();

      expect(
        harness.model.medications.map((item) => item.localImagePath),
        ['/stored/7.jpg', ''],
      );
      expect(harness.images.orphanScopes, [
        {7, 8},
      ]);
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: deleting a saved medication removes its device photo and keeps the
    //   photo of a medication whose deletion the server rejected.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the assertions pass.
    test('deleting a medication removes only its own device photo', () async {
      final harness = _Harness((_) async => null);
      addTearDown(harness.model.dispose);
      harness.saved.rejectedDeleteIds.add(8);

      final result = await harness.model.requestDeleteSavedMedications([
        7,
        8,
      ]);
      await pumpEventQueue();

      expect(result.successCount, 1);
      expect(result.failureCount, 1);
      expect(harness.images.deletedIds, [7]);
    });
  });
}
