import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:medbuddy_frontend/services/camera_lifecycle_coordinator.dart';

void main() {
  test('serializes permission pause and resume camera transitions', () async {
    final coordinator = CameraLifecycleCoordinator();
    final firstStarted = Completer<void>();
    final allowFirstToFinish = Completer<void>();
    final events = <String>[];

    final initialOpen = coordinator.schedule(() async {
      events.add('initial-open-start');
      firstStarted.complete();
      await allowFirstToFinish.future;
      events.add('initial-open-end');
    });
    await firstStarted.future;

    final permissionPause = coordinator.schedule(() async {
      events.add('permission-pause-release');
    });
    final permissionResume = coordinator.schedule(() async {
      events.add('permission-resume-open');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, ['initial-open-start']);

    allowFirstToFinish.complete();
    await Future.wait([initialOpen, permissionPause, permissionResume]);

    expect(events, [
      'initial-open-start',
      'initial-open-end',
      'permission-pause-release',
      'permission-resume-open',
    ]);
  });

  test('a failed transition does not block the next transition', () async {
    final coordinator = CameraLifecycleCoordinator();
    final events = <String>[];

    await expectLater(
      coordinator.schedule(() async {
        events.add('failed');
        throw StateError('camera failed');
      }),
      throwsStateError,
    );
    await coordinator.schedule(() async {
      events.add('recovered');
    });

    expect(events, ['failed', 'recovered']);
  });
}
