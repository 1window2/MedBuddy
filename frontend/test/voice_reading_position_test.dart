import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/voice_reading_position.dart';

void main() {
  const detail = MedicationDetail(
    itemName: '테스트',
    efficacy: '효능 설명',
    usageMethod: '0.5 단위입니다. 같은 문장. 같은 문장.',
    warning: '',
  );
  for (final language in ['ko', 'en']) {
    test('기존 $language 안내문의 본문에만 위치를 연결한다', () {
      final guide = detail.voiceGuideTextForLanguage(language);
      final map = VoiceReadingMap(guide, detail, language);
      expect(map.at(-1, -1).sentence, isNull);
      expect(map.at(0, 1).sentence, isNull);
      final name = guide.indexOf(detail.itemName);
      expect(map.at(name, name + 1).section, VoiceSection.name);
      final decimal = guide.indexOf('0.5');
      expect(map.at(decimal, decimal + 3).sentence, '0.5 단위입니다.');
      final index = guide.lastIndexOf('같은');
      expect(map.at(index, index + 2), (
        section: VoiceSection.usage,
        sentence: '같은 문장.',
        offset: detail.usageMethod.lastIndexOf('같은'),
      ));
    });
  }
  test('서버가 일부 문장만 주면 해당 위치만 연결하고 임의 요약은 강조하지 않는다', () {
    final source = detail.copyWith(warning: '첫 문장. 두 번째 문장.');
    const guide = '주의사항: 두 번째 문장.';
    expect(
      VoiceReadingMap(guide, source, 'ko').at(6, 7).offset,
      source.warning.indexOf('두 번째'),
    );
    expect(VoiceReadingMap('서버 요약.', source, 'ko').at(0, 2).sentence, isNull);
  });
}
