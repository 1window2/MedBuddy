import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medbuddy_frontend/boundaries/medication_photo_source_sheet.dart';

void main() {
  for (final cancelFirst in [false, true]) {
    testWidgets(
      'source double tap preserves entry route (cancel=$cancelFirst)',
      (tester) async {
        final selections = <ImageSource?>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: TextButton(
                    child: const Text('open entry'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => Scaffold(
                          body: TextButton(
                            child: const Text('select photo'),
                            onPressed: () async {
                              selections.add(
                                await showMedicationPhotoSourceOptions(
                                  context: context,
                                  language: 'en',
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('open entry'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('select photo'));
        await tester.pumpAndSettle();
        final row = find.ancestor(
          of: find.text('Take Photo'),
          matching: find.byType(InkWell),
        );
        final select = tester.widget<InkWell>(row).onTap!;
        if (cancelFirst) {
          await tester.binding.handlePopRoute();
          await tester.pump();
        } else {
          select();
        }
        select();
        await tester.pumpAndSettle();
        expect(find.text('select photo'), findsOneWidget);
        expect(selections, [cancelFirst ? null : ImageSource.camera]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
