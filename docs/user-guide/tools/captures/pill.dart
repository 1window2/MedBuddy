// File Name: pill.dart
// Role: Append source-widget pill captures with explicitly synthetic candidates.
// Class Name: _GuidePills
// Role: Supply a reference photo and synthetic partial-identification observations.
// Responsibilities: Read local imagery and align fixture boxes to that imagery.
// Attributes: No additional state; inherits the isolated identification fixture.
class _GuidePills extends _PartlyEmptyIdentifyPill {
  // Function Name: requestPillImage
  // Description: Read a local reference without opening a camera or gallery.
  // Parameters: source is ignored by this fixture.
  // Returns: Future<Uint8List?> with photo bytes; file errors fail the test.
  @override
  Future<Uint8List?> requestPillImage(ImageSource source) async =>
      File('$workspace/work/partial-pill-reference-1.jpg').readAsBytesSync();
  // Function Name: requestMultiplePillIdentification
  // Description: Preserve fixture candidates and align synthetic bounding boxes.
  // Parameters: image is passed to the inherited mock identification operation.
  // Returns: Future<MultiplePillIdentificationResult> requiring confirmation.
  @override
  Future<MultiplePillIdentificationResult> requestMultiplePillIdentification({required Uint8List image}) async {
    final result = await super.requestMultiplePillIdentification(image: image);
    return MultiplePillIdentificationResult(requiresConfirmation: true, observations: [
      for (var i = 0; i < result.observations.length; i++) MultiplePillObservation(
        index: i + 1, boundingBox: PillBoundingBox(left: i == 0 ? .22 : .59, top: .30, width: .22, height: .36),
        identification: result.observations[i].identification),
    ]);
  }
}

// Class Name: _GuidePaired
// Role: Supply front/back reference photos in selection order.
// Responsibilities: Replace image picking with local fixture reads.
// Attributes: selected (int) counts requested photos to select the next side.
class _GuidePaired extends _GuidePills {
  int selected = 0;
  // Function Name: requestPillImage
  // Description: Read the next supplied side without invoking a device picker.
  // Parameters: source is ignored by this fixture.
  // Returns: Future<Uint8List?> with photo bytes; file errors fail the test.
  @override
  Future<Uint8List?> requestPillImage(ImageSource source) async {
    final side = selected++ == 0 ? '앞면' : '뒷면';
    return File('$workspace/work/pill-front-back-1116/MedBuddy_Pill_Test/01_타이레놀정500밀리그람_$side.png').readAsBytesSync();
  }
}

// Function Name: main
// Description: Register upload, partial selection, review and paired-photo captures.
// Parameters: None.
// Returns: void; configures fonts and two isolated tests without real saves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(captureFonts);
  // Function Name: guide pill initial and partial states
  // Description: Check the five-second notice and partial-selection review action.
  // Parameters: tester drives the product widget with synthetic candidates.
  // Returns: Future<void>; captures PNGs and fails if notice/action assertions differ.
  testWidgets('guide pill initial and partial states', (tester) async {
    captureViewport(tester);
    final control = _GuidePills();
    await tester.pumpWidget(MaterialApp(theme: captureTheme(), debugShowCheckedModeBanner: false,
      home: PillIdentificationUI(userSetting: const UserSetting(), control: control,
        captureMode: PillCaptureMode.singlePhoto, onReviewRequested: (_) => true)));
    await captureScreen(tester, 'pill-upload-notice');
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const Key('pill-ai-disclosure')), findsNothing);
    await captureScreen(tester, 'pill-upload-placeholder');
    await _tapVisible(tester, find.byKey(const Key('identify-multiple-pills-from-one-photo-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    await captureScreen(tester, 'pill-partial-unselected');
    await _tapVisible(tester, find.text('첫 번째 알약'));
    await tester.pumpAndSettle();
    expect(_confirmButtonLabel(tester), '선택한 알약 1개 검토 후 저장');
    await captureScreen(tester, 'pill-partial-selected');
    await _tapVisible(tester, find.byKey(const Key('confirm-pill-candidate-button')));
    await tester.pumpAndSettle();
    await captureScreen(tester, 'pill-partial-review');
    await tester.tap(find.byKey(const Key('schedule-review-edit-0')));
    await tester.pumpAndSettle();
    await captureScreen(tester, 'pill-partial-edit');
    await tester.pumpWidget(const SizedBox.shrink());
    control.dispose();
  });
  // Function Name: guide individual photo placeholders
  // Description: Capture empty, paired and added photo groups using local images.
  // Parameters: tester drives the product widget with a fake image picker.
  // Returns: Future<void>; writes PNGs without opening a real device gallery.
  testWidgets('guide individual photo placeholders', (tester) async {
    captureViewport(tester);
    final control = _GuidePaired();
    await tester.pumpWidget(MaterialApp(theme: captureTheme(), debugShowCheckedModeBanner: false,
      home: PillIdentificationUI(userSetting: const UserSetting(), control: control,
        captureMode: PillCaptureMode.individualPhotos, onReviewRequested: (_) => true)));
    await tester.pump(const Duration(seconds: 5));
    await captureScreen(tester, 'pill-individual-empty');
    await _addPillPhoto(tester, 0);
    await _tapVisible(tester, find.byKey(const Key('pill-back-image-slot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    await captureScreen(tester, 'pill-individual-paired');
    await _tapVisible(tester, find.byKey(const Key('add-pill-photo-set-button')));
    await tester.pumpAndSettle();
    await captureScreen(tester, 'pill-individual-added');
    await tester.pumpWidget(const SizedBox.shrink());
    control.dispose();
  });
}
