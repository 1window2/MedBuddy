// 실제 안내문의 UTF-16 위치를 상세 화면의 원문에 연결한다. 재생 문구는 변경하지 않는다.
import 'medication_detail_entity.dart';
import 'user_setting_entity.dart';

enum VoiceSection { name, usage, warning, other }

typedef VoicePosition = ({VoiceSection section, String? sentence, int offset});
typedef _Passage = ({int start, int end, VoicePosition position});

class VoiceReadingMap {
  static const _unmatched = (
    section: VoiceSection.other,
    sentence: null,
    offset: -1,
  );
  final List<_Passage> _passages = [];

  VoiceReadingMap(String guide, MedicationDetail detail, String language) {
    final english = isEnglishLanguage(language);
    final fields = {
      (english ? 'Medication' : '약 이름'): (VoiceSection.name, detail.itemName),
      (english ? 'How to take' : '복용 방법'): (
        VoiceSection.usage,
        detail.usageMethod,
      ),
      (english ? 'Warning' : '주의사항'): (VoiceSection.warning, detail.warning),
    };
    final labels = RegExp(
      '^(${fields.keys.map(RegExp.escape).join('|')}): ',
      multiLine: true,
    ).allMatches(guide).toList();
    for (var i = 0; i < labels.length; i++) {
      final label = labels[i];
      final (section, value) = fields[label.group(1)]!;
      final body = guide
          .substring(
            label.end,
            i + 1 < labels.length ? labels[i + 1].start : guide.length,
          )
          .trimRight();
      final source = value.trim();
      final origin = source.indexOf(body);
      if (body.isEmpty || origin < 0 || origin != source.lastIndexOf(body)) {
        continue;
      }
      // 소수점은 나누지 않고, 반복 문장도 원래 위치로 구분한다.
      var left = 0;
      for (final right in [
        ..._sentenceEnd.allMatches(body).map((m) => m.end),
        body.length,
      ]) {
        final raw = body.substring(left, right);
        final sentence = raw.trim();
        if (sentence.isNotEmpty) {
          final start = left + raw.indexOf(sentence);
          _passages.add((
            start: label.end + start,
            end: label.end + start + sentence.length,
            position: (
              section: section,
              sentence: sentence,
              offset: origin + start,
            ),
          ));
        }
        left = right;
      }
    }
  }

  static final _sentenceEnd = RegExp(r'[.!?。！？]+(?=\s|$)|\n+');

  VoicePosition at(int start, int end) {
    if (start >= 0 && end > start) {
      for (final p in _passages) {
        if (start < p.start) break;
        if (start < p.end) return p.position;
      }
    }
    return _unmatched;
  }
}
