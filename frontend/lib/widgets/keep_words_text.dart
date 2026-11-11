// File Name: keep_words_text.dart
// Role: Wraps Korean text between words instead of between syllables, so large text does not leave one syllable on a line ("관리해 / 요").
import 'package:flutter/widgets.dart';

const _wordJoiner = '⁠';
const _noBreakSpace = ' ';

// Function Name: _isHangul
// Description: Reports whether a code point is a Hangul syllable or jamo.
// Parameters:
// - rune (int): Unicode code point.
// Returns:
// - Whether the code point is Hangul.
bool _isHangul(int rune) =>
    (rune >= 0xAC00 && rune <= 0xD7A3) ||
    (rune >= 0x1100 && rune <= 0x11FF) ||
    (rune >= 0x3130 && rune <= 0x318F);

// Function Name: _isSpace
// Description: Reports whether a code point is a space or line break, where a line may still wrap.
// Parameters:
// - rune (int): Unicode code point.
// Returns:
// - Whether the code point separates words.
bool _isSpace(int rune) =>
    rune == 0x20 || rune == 0x0A || rune == 0x09 || rune == 0x3000;

// Function Name: keepKoreanWords
// Description: Joins the characters of each word that contains Hangul so a line breaks only at spaces, and keeps a range written as "A ~ B" on one line. A word longer than the line is still broken by the text engine.
// Parameters:
// - text (String): Display text.
// Returns:
// - The text with invisible word joiners; use it for painting only, never for comparison or storage.
String keepKoreanWords(String text) {
  if (text.isEmpty) return text;
  final buffer = StringBuffer();
  final runes = text.runes.toList();
  for (var index = 0; index < runes.length; index++) {
    final rune = runes[index];
    // 범위 표시의 물결표 양옆 공백은 줄바꿈하지 않는 공백으로 바꾼다.
    final besideTilde =
        rune == 0x20 &&
        ((index > 0 && runes[index - 1] == 0x7E) ||
            (index + 1 < runes.length && runes[index + 1] == 0x7E));
    buffer.write(besideTilde ? _noBreakSpace : String.fromCharCode(rune));
    if (index + 1 == runes.length) continue;
    final next = runes[index + 1];
    if (!_isSpace(rune) &&
        !_isSpace(next) &&
        (_isHangul(rune) || _isHangul(next))) {
      buffer.write(_wordJoiner);
    }
  }
  return buffer.toString();
}

// Class Name: KeepWordsText
// Role: Render text with Korean word-preserving line breaks and the original accessibility label.
// Responsibilities: Apply keepKoreanWords without exposing inserted joiners to screen readers.
// Attributes: data (String): original text; style/strutStyle/textAlign/maxLines/overflow/softWrap: standard optional text layout settings.
class KeepWordsText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;

  // Function Name: KeepWordsText
  // Description: Stores the text and the usual Text layout options.
  // Parameters:
  // - data (String): Original display text.
  // - style, strutStyle, textAlign, maxLines, overflow, softWrap: Same meaning as on Text.
  // - key (Key?): widget identity.
  // Returns: A configured KeepWordsText.
  const KeepWordsText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
  });

  // Function Name: build
  // Description: Builds a rich Text whose painted text is joined by word and whose semantics label is the original.
  // Parameters:
  // - context (BuildContext): Widget tree location.
  // Returns: The text widget.
  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(text: keepKoreanWords(data), semanticsLabel: data),
    style: style,
    strutStyle: strutStyle,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    softWrap: softWrap,
  );
}
