// 파일명: ingredient_overlap_entity.dart
// 역할: 등록 결과의 약과 복약 목록·같은 결과 화면의 다른 약이 같은 주성분을 가졌는지 표현하고 안내 문구를 만든다.

import 'json_value_reader.dart';
import 'prescription_flow_entity.dart';

// Class Name: IngredientOverlapSource
// Role: Tells where the other medicine of an overlap is.
// Responsibilities: Separate saved medicines from medicines on the same result screen.
// Attributes: saved: in the medication list; batch: on the same result screen.
enum IngredientOverlapSource { saved, batch }

// Class Name: IngredientOverlap
// Role: One shared main ingredient between a result row and another medicine.
// Responsibilities: Decode the server entry and keep the other medicine's number, name, place and same-product flag.
// Attributes:
// - ingredientCode, ingredientName (String): Shared ingredient from the approval catalog; the name may be empty.
// - withItemSeq, withItemName (String): Product number and name of the other medicine.
// - source (IngredientOverlapSource): Medication list or same result screen.
// - sameProduct (bool): The other medicine is the same product number already in the list.
class IngredientOverlap {
  final String ingredientCode;
  final String ingredientName;
  final String withItemSeq;
  final String withItemName;
  final IngredientOverlapSource source;
  final bool sameProduct;

  // Function Name: IngredientOverlap
  // Description: Keeps one overlap entry.
  // Parameters: ingredientCode/ingredientName: shared ingredient; withItemSeq/withItemName: other medicine; source: its place; sameProduct: same product flag.
  // Returns: IngredientOverlap.
  const IngredientOverlap({
    this.ingredientCode = '',
    this.ingredientName = '',
    required this.withItemSeq,
    required this.withItemName,
    required this.source,
    this.sameProduct = false,
  });

  // Function Name: IngredientOverlap.tryParse
  // Description: Decodes one server overlap entry; an entry without a partner, with an unknown source or a nameless partner is dropped.
  // Parameters: value (dynamic): one element of `overlaps`.
  // Returns: IngredientOverlap?, null for unusable entries.
  static IngredientOverlap? tryParse(dynamic value) {
    if (value is! Map) return null;
    final partner = value['with'];
    if (partner is! Map) return null;
    final source = switch (readJsonText(partner['source'])) {
      'saved' => IngredientOverlapSource.saved,
      'batch' => IngredientOverlapSource.batch,
      _ => null,
    };
    final withItemSeq = readJsonText(partner['item_seq']);
    if (source == null || withItemSeq.isEmpty) return null;
    return IngredientOverlap(
      ingredientCode: readJsonText(value['ingredient_code']),
      ingredientName: readJsonText(value['ingredient_name']),
      withItemSeq: withItemSeq,
      withItemName: readJsonText(partner['item_name']),
      source: source,
      sameProduct: partner['same_product'] == true,
    );
  }

  // Function Name: copyWithName
  // Description: Replaces the other medicine's name, for batch partners shown under their result-row name.
  // Parameters: name (String): replacement name.
  // Returns: A copy with the new name.
  IngredientOverlap copyWithName(String name) => IngredientOverlap(
    ingredientCode: ingredientCode,
    ingredientName: ingredientName,
    withItemSeq: withItemSeq,
    withItemName: name,
    source: source,
    sameProduct: sameProduct,
  );
}

// Function Name: filterIngredientOverlapsForSource
// Description:
// - For a prescription, drops entries of the same result screen (the prescriber combined them) and the same product
//   already in the list (refills repeat products); pill-photo and manual results keep every entry.
// Parameters: overlaps (List<IngredientOverlap>): server entries of one row; source (MedicationResultSource): result screen source.
// Returns: An unmodifiable filtered list.
List<IngredientOverlap> filterIngredientOverlapsForSource(
  List<IngredientOverlap> overlaps,
  MedicationResultSource source,
) {
  if (source != MedicationResultSource.prescription) {
    return List.unmodifiable(overlaps);
  }
  return List.unmodifiable(
    overlaps.where(
      // 함수이름: where 콜백
      // 함수역할: 처방전에서는 복약 목록의 다른 품목과 겹친 항목만 남긴다.
      // 매개변수: overlap (IngredientOverlap): 판정할 항목.
      // 반환값: 남길 항목이면 true.
      (overlap) =>
          overlap.source == IngredientOverlapSource.saved &&
          !overlap.sameProduct,
    ),
  );
}

// Function Name: ingredientOverlapNoticeText
// Description:
// - Builds the notice of one result row: the same product already in the list first, then other products in the
//   medication list, then other products on the same result screen, and one closing question when an ingredient is shared.
// - Names are quoted and never followed by a particle that depends on their last sound; two names are listed and the
//   rest are counted. No text is produced without an overlap.
// Parameters: overlaps (List<IngredientOverlap>): filtered entries of one row; isEnglish (bool): language.
// Returns: The notice, or an empty string when there is nothing to say.
String ingredientOverlapNoticeText(
  List<IngredientOverlap> overlaps, {
  required bool isEnglish,
}) {
  final sameNames = _distinctNames(overlaps.where((o) => o.sameProduct));
  final saved = overlaps
      .where((o) => !o.sameProduct && o.source == IngredientOverlapSource.saved)
      .toList(growable: false);
  final batch = overlaps
      .where((o) => !o.sameProduct && o.source == IngredientOverlapSource.batch)
      .toList(growable: false);

  final sentences = <String>[
    if (sameNames.isNotEmpty)
      isEnglish
          ? 'Your medication list already has the same medicine (${_quotedList(sameNames, isEnglish)}). '
                'Check that you are not registering it twice.'
          : '이미 복약 목록에 같은 약(${_quotedList(sameNames, isEnglish)})이 있어요. '
                '같은 약을 두 번 등록하는지 확인해 주세요.',
    if (saved.isNotEmpty)
      _sharedIngredientSentence(
        saved,
        isEnglish: isEnglish,
        place: isEnglish ? 'in your medication list' : '복약 목록의',
      ),
    if (batch.isNotEmpty)
      _sharedIngredientSentence(
        batch,
        isEnglish: isEnglish,
        place: isEnglish ? 'in this result list' : '이 결과 목록의',
      ),
    if (saved.isNotEmpty || batch.isNotEmpty)
      isEnglish
          ? 'Ask a pharmacist or doctor whether you can take them together.'
          : '함께 드셔도 되는지 약사나 의사에게 물어보세요.',
  ];
  return sentences.join(' ');
}

// Function Name: _sharedIngredientSentence
// Description: States that the listed products contain the same ingredients.
// Parameters: overlaps: entries of one place; isEnglish: language; place: "복약 목록의" or its English phrase.
// Returns: One sentence.
String _sharedIngredientSentence(
  List<IngredientOverlap> overlaps, {
  required bool isEnglish,
  required String place,
}) {
  final productNames = _distinctNames(overlaps);
  final ingredientNames = [
    for (final name in {
      for (final overlap in overlaps)
        if (overlap.ingredientName.trim().isNotEmpty)
          overlap.ingredientName.trim(),
    })
      name,
  ];
  final names = _quotedList(productNames, isEnglish);
  if (isEnglish) {
    final noun = ingredientNames.length > 1
        ? 'the same ingredients'
        : 'the same ingredient';
    final ingredients = ingredientNames.isEmpty
        ? ''
        : ' (${ingredientNames.join(', ')})';
    final verb = productNames.length == 1 ? 'contains' : 'contain';
    return '$names $place also $verb $noun$ingredients.';
  }
  final ingredients = ingredientNames.isEmpty
      ? ''
      : '(${ingredientNames.join(', ')})';
  return '$place $names에도 같은 성분$ingredients이 들어 있어요.';
}

// Function Name: _distinctNames
// Description: Lists other medicines once each, by product number, in entry order.
// Parameters: overlaps (Iterable<IngredientOverlap>): entries.
// Returns: Display names; a missing name falls back to the product number.
List<String> _distinctNames(Iterable<IngredientOverlap> overlaps) {
  final names = <String, String>{};
  for (final overlap in overlaps) {
    final name = overlap.withItemName.trim();
    names.putIfAbsent(
      overlap.withItemSeq,
      () => name.isEmpty ? overlap.withItemSeq : name,
    );
  }
  return names.values.toList(growable: false);
}

// Function Name: _quotedList
// Description: Quotes up to two names and counts the rest ("‘A’, ‘B’ 외 N개" / "‘A’, ‘B’ and N more").
// Parameters: names (List<String>): at least one name; isEnglish (bool): language.
// Returns: The joined list.
String _quotedList(List<String> names, bool isEnglish) {
  final quoted = names.take(2).map((name) => '‘$name’').toList();
  final rest = names.length - quoted.length;
  if (isEnglish) {
    if (rest > 0) return '${quoted.join(', ')} and $rest more';
    return quoted.join(' and ');
  }
  final joined = quoted.join(', ');
  return rest > 0 ? '$joined 외 $rest개' : joined;
}
