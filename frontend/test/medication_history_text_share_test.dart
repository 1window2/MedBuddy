// 파일명: medication_history_text_share_test.dart
// 역할: 외부 공유 본문의 날짜·상태·개인정보 최소화와 빈 기록 표시를 검증한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_history_entity.dart';
import 'package:medbuddy_frontend/entities/medication_history_export.dart';

import 'medication_history_fixtures.dart';

// 함수이름: main
// 함수역할:
// - 한글·영어 외부 공유에서 빈 기록과 복용 상태별 표현·개인정보 제외를 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 두 언어의 공유 본문 테스트를 등록한다.
void main() {
  for (final english in [false, true]) {
    // 함수이름: test callback
    // 함수역할:
    // - 기록 없는 스냅샷은 한영 빈 기록 안내만 공유하고 저장 약 이름·CSV 흔적·BOM을 내보내지 않는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 없음; 기대값과 다르면 테스트가 실패한다.
    test(
      'empty text share is readable and excludes stored medicines ($english)',
      () {
        final snapshot = MedicationHistorySnapshot.fromJson(
          historyTestBody(items: []),
        );
        final text = medicationHistoryShareText(snapshot, isEnglish: english);
        expect(
          text,
          contains(english ? 'No medication records' : '표시할 복약 기록이 없습니다'),
        );
        expect(text, isNot(contains('테스트 주간약')));
        expect(text, isNot(contains('테스트 필요시약')));
        expect(text, isNot(contains('"')));
        expect(text, isNot(contains('0건')));
        expect(text, isNot(contains('\uFEFF')));
      },
    );

    // 함수이름: test callback
    // 함수역할:
    // - 여러 상태와 반복 필요시 기록을 날짜·시간대 순서로 공유하고 한국 시각·사유·불확실성 안내를 보존하되 계정·작업 ID·리비전은 제외하는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 없음; 기대값과 다르면 테스트가 실패한다.
    test(
      'text share retains every status and repeated PRN event ($english)',
      () {
        final snapshot = MedicationHistorySnapshot.fromJson(
          historyTestBody(
            items: [
              historyTestEntry(date: '2026-10-17', status: 'taken')
                ..['actual_taken_at'] = '2026-10-16T23:30:00Z'
                ..['patient_hash'] = 'private-scope',
              historyTestEntry(
                date: '2026-10-17',
                slot: 'lunch',
                status: 'skipped',
              )..['reason'] = '외출\n중',
              historyTestEntry(date: '2026-10-17', slot: 'evening'),
              historyTestEntry(
                id: 2,
                date: '2026-10-16',
                name: '필요시 시험약',
                mode: 'as_needed',
                slot: 'as_needed:10000000-0000-4000-8000-000000000001',
                status: 'taken',
              )..['actual_taken_at'] = '2026-10-16T01:00:00Z',
              historyTestEntry(
                id: 2,
                date: '2026-10-16',
                name: '필요시 시험약',
                mode: 'as_needed',
                slot: 'as_needed:10000000-0000-4000-8000-000000000002',
                status: 'taken',
              ),
            ],
          ),
        );
        final text = medicationHistoryShareText(snapshot, isEnglish: english);
        expect(text, contains('2026-10-17 08:30'));
        expect(text, contains('2026-10-16 10:00'));
        expect(text, contains('외출 중'));
        expect(
          text,
          contains(
            english ? 'Taken time was not entered' : '복용 시각은 입력하지 않았습니다',
          ),
        );
        expect(text, contains(english ? 'Taken 3' : '복용함 3건'));
        expect(text, contains(english ? 'Skipped 1' : '건너뜀 1건'));
        expect(text, contains(english ? 'Unrecorded 1' : '미기록 1건'));
        expect('필요시 시험약'.allMatches(text), hasLength(2));
        expect(text, isNot(contains('10000000-')));
        expect(text, isNot(contains('revision')));
        expect(text, isNot(contains('기록 버전')));
        expect(text, isNot(contains('private-scope')));
        // 두 언어 모두 자가 기록이 실제 복용의 증명이 아님을 함께 알린다.
        expect(
          text,
          contains(
            english ? 'not proof of ingestion' : '실제 복용을 증명하지 않습니다',
          ),
        );
        expect(
          text,
          contains(
            english
                ? 'Unrecorded does not mean not taken'
                : '미기록은 미복용을 뜻하지 않습니다',
          ),
        );
        expect(
          text.indexOf('\n2026-10-16\n'),
          lessThan(text.indexOf('\n2026-10-17\n')),
        );
        expect(
          text.indexOf(english ? '- Morning' : '- 아침'),
          lessThan(text.indexOf(english ? '- Lunch' : '- 점심')),
        );
      },
    );
  }
}
