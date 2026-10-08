// 파일명: caregiver_notification_monitor_factory_test.dart
// 역할: 보호자 알림을 표시하기 직전의 사용자 설정 확인(알림 허용, 민감정보 표시)을 검증한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/composition/caregiver_notification_monitor_factory.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 함수이름: main
// 함수역할: 알림 허용 여부와 내용 표시 방식의 네 조합을 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  for (final enabled in [true, false]) {
    for (final showDetails in [true, false]) {
      // 함수이름: 설정 조합 테스트
      // 함수역할: 보호자 알림을 꺼 두면 표시하지 않고, 켜 두면 저장된 내용 표시 방식을 그대로 넘겨 한 번만
      //   표시하는지 검증한다. 매개변수: 없음. 반환값: 검증 완료.
      test(
        'caregiver alert: notifications ${enabled ? 'on' : 'off'}, '
        'details ${showDetails ? 'shown' : 'hidden'}',
        () async {
          var settingReads = 0;
          final shownWithDetails = <bool>[];

          final delivered = await deliverCaregiverAlert(
            loadSetting: () async {
              settingReads++;
              return UserSetting(
                caregiverNotificationsEnabled: enabled,
                notificationDetailMode: showDetails ? 'full' : 'type_only',
              );
            },
            notify: (showSensitiveDetails) async {
              shownWithDetails.add(showSensitiveDetails);
            },
          );

          expect(settingReads, 1);
          expect(delivered, enabled);
          expect(shownWithDetails, enabled ? [showDetails] : isEmpty);
        },
      );
    }
  }

  // 함수이름: 설정 조회 실패 테스트
  // 함수역할: 설정을 읽지 못하면 내용 표시 방식을 알 수 없으므로 알림을 표시하지 않고 오류를 호출자에게
  //   넘기는지 검증한다. 매개변수: 없음. 반환값: 검증 완료.
  test('caregiver alert is not shown when the setting cannot be read', () async {
    var shown = 0;

    await expectLater(
      deliverCaregiverAlert(
        loadSetting: () async => throw StateError('settings unavailable'),
        notify: (_) async => shown++,
      ),
      throwsStateError,
    );

    expect(shown, 0);
  });
}
