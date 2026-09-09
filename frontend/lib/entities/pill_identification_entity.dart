// File Name: pill_identification_entity.dart
// Role: Validates pill-identification features, ranked candidates, and spatial multi-pill observations.
import 'medication_image_url_entity.dart';

// Class Name: PillVisualFeatures
// Role: Holds observed shape, colors, imprints, score lines, and image-quality evidence.
// Responsibilities:
// - Preserve both-side consistency and quality issues used to explain identification candidates.
// Attributes:
// - shape (String): Observed or cataloged pill shape.
// - colors (List<String>): Observed or cataloged pill colors.
// - frontImprint (String): Observed front-side imprint.
// - backImprint (String): Observed back-side imprint.
// - frontLine (String): Observed front-side score line.
// - backLine (String): Observed back-side score line.
// - quality (String): Image-quality judgment for identification.
// - qualityIssues (List<String>): Detected image-quality issues.
// - samePill (bool): Judgment that front and back images depict the same pill.
// - sideConsistencyConfidence (double): Front/back consistency confidence from zero to one.
class PillVisualFeatures {
  final String shape;
  final List<String> colors;
  final String frontImprint;
  final String backImprint;
  final String frontLine;
  final String backLine;
  final String quality;
  final List<String> qualityIssues;
  final bool samePill;
  final double sideConsistencyConfidence;

  // Function Name: PillVisualFeatures
  // Description: Captures observed pill appearance, image-quality findings, and the same-pill consistency assessment for both sides.
  // Parameters:
  // - shape (String): Observed or cataloged pill shape.
  // - colors (List<String>): Observed or cataloged pill colors.
  // - frontImprint (String): Observed front-side imprint.
  // - backImprint (String): Observed back-side imprint.
  // - frontLine (String): Observed front-side score line.
  // - backLine (String): Observed back-side score line.
  // - quality (String): Image-quality judgment for identification.
  // - qualityIssues (List<String>): Detected image-quality issues.
  // - samePill (bool): Judgment that front and back images depict the same pill.
  // - sideConsistencyConfidence (double): Front/back consistency confidence from zero to one.
  // Returns:
  // - PillVisualFeatures: the initialized instance.
  const PillVisualFeatures({
    this.shape = 'unknown',
    this.colors = const [],
    this.frontImprint = '',
    this.backImprint = '',
    this.frontLine = 'unknown',
    this.backLine = 'unknown',
    this.quality = 'usable',
    this.qualityIssues = const [],
    this.samePill = true,
    this.sideConsistencyConfidence = 1.0,
  });

  // Function Name: PillVisualFeatures.fromJson
  // Description: Reads visual-feature lists and text while requiring a boolean same-pill judgment and a finite consistency score within zero to one.
  // Parameters:
  // - json (Map<String, dynamic>): Backend response or stored JSON object for this model.
  // Returns:
  // - PillVisualFeatures: the decoded record after field validation and default handling.
  factory PillVisualFeatures.fromJson(Map<String, dynamic> json) {
    return PillVisualFeatures(
      shape: _readString(json['shape'], fallback: 'unknown'),
      colors: _readStrings(json['colors']),
      frontImprint: _readString(json['front_imprint']),
      backImprint: _readString(json['back_imprint']),
      frontLine: _readString(json['front_line'], fallback: 'unknown'),
      backLine: _readString(json['back_line'], fallback: 'unknown'),
      quality: _readString(json['quality'], fallback: 'usable'),
      qualityIssues: _readStrings(json['quality_issues']),
      samePill: _readRequiredBool(json['same_pill'], 'same_pill'),
      sideConsistencyConfidence: _readRequiredScore(
        json['side_consistency_confidence'],
        'side_consistency_confidence',
      ),
    );
  }
}

// Class Name: PillIdentificationCandidate
// Role: Represents one public-catalog candidate and the evidence for its match.
// Responsibilities:
// - Preserve drug identifiers, manufacturer, trusted image URL, appearance, score, and matched attributes for user review.
// Attributes:
// - itemSeq (String): Public-catalog medication item identifier.
// - itemName (String): Medication name used for display and persistence.
// - manufacturer (String): Manufacturer name from the public catalog.
// - imageUrl (String): Remote image URL associated with medication details or a candidate.
// - shape (String): Observed or cataloged pill shape.
// - colors (List<String>): Observed or cataloged pill colors.
// - printFront (String): Catalog candidate imprint on the back or front side.
// - printBack (String): Catalog candidate imprint on the back or front side.
// - matchScore (double): Pill candidate match score.
// - matchedAttributes (List<String>): Visual attributes supporting the candidate match.
class PillIdentificationCandidate {
  final String itemSeq;
  final String itemName;
  final String manufacturer;
  final String imageUrl;
  final String shape;
  final List<String> colors;
  final String printFront;
  final String printBack;
  final double matchScore;
  final List<String> matchedAttributes;

  // Function Name: PillIdentificationCandidate
  // Description: Captures a candidate's catalog identity, appearance, matching evidence, and score for the mandatory review screen.
  // Parameters:
  // - itemSeq (String): Public-catalog medication item identifier.
  // - itemName (String): Medication name used for display and persistence.
  // - manufacturer (String): Manufacturer name from the public catalog.
  // - imageUrl (String): Remote image URL associated with medication details or a candidate.
  // - shape (String): Observed or cataloged pill shape.
  // - colors (List<String>): Observed or cataloged pill colors.
  // - printFront (String): Catalog candidate imprint on the back or front side.
  // - printBack (String): Catalog candidate imprint on the back or front side.
  // - matchScore (double): Pill candidate match score.
  // - matchedAttributes (List<String>): Visual attributes supporting the candidate match.
  // Returns:
  // - PillIdentificationCandidate: the initialized instance.
  const PillIdentificationCandidate({
    required this.itemSeq,
    required this.itemName,
    this.manufacturer = '',
    this.imageUrl = '',
    this.shape = '',
    this.colors = const [],
    this.printFront = '',
    this.printBack = '',
    this.matchScore = 0,
    this.matchedAttributes = const [],
  });

  // Function Name: PillIdentificationCandidate.fromJson
  // Description: Converts catalog candidate fields, filters its image URL through the trust policy, and normalizes list and score values.
  // Parameters:
  // - json (Map<String, dynamic>): Backend response or stored JSON object for this model.
  // Returns:
  // - PillIdentificationCandidate: the decoded record after field validation and default handling.
  factory PillIdentificationCandidate.fromJson(Map<String, dynamic> json) {
    return PillIdentificationCandidate(
      itemSeq: _readString(json['item_seq']),
      itemName: _readString(json['item_name']),
      manufacturer: _readString(json['entp_name']),
      imageUrl: safeMedicationImageUrl(json['image_url']),
      shape: _readString(json['shape']),
      colors: _readStrings(json['colors']),
      printFront: _readString(json['print_front']),
      printBack: _readString(json['print_back']),
      matchScore: _readScore(json['match_score']),
      matchedAttributes: _readStrings(json['matched_attributes']),
    );
  }
}

// Class Name: PillIdentificationResult
// Role: Holds validated single-pill candidates and the mandatory confirmation contract.
// Responsibilities:
// - Reject inconsistent success, confidence, candidate scores, and missing user-confirmation requirements.
// Attributes:
// - isConfident (bool): Server confidence judgment for the identification result.
// - requiresConfirmation (bool): Contract flag requiring user confirmation before saving.
// - observedFeatures (PillVisualFeatures): Pill appearance and quality observed in the photo.
// - candidates (List<PillIdentificationCandidate>): Candidates to inspect for a match.
class PillIdentificationResult {
  final bool isConfident;
  final bool requiresConfirmation;
  final PillVisualFeatures observedFeatures;
  final List<PillIdentificationCandidate> candidates;
  // 서버 상한 밖에도 동점 후보가 있어 추가 사진이 필요한지 나타낸다.
  final bool hasMoreCandidates;

  // Function Name: PillIdentificationResult
  // Description: Bundles observed features and candidate rankings with confidence and explicit user-confirmation requirements.
  // Parameters:
  // - isConfident (bool): Server confidence judgment for the identification result.
  // - requiresConfirmation (bool): Contract flag requiring user confirmation before saving.
  // - observedFeatures (PillVisualFeatures): Pill appearance and quality observed in the photo.
  // - candidates (List<PillIdentificationCandidate>): Candidates to inspect for a match.
  // Returns:
  // - PillIdentificationResult: the initialized instance.
  const PillIdentificationResult({
    required this.isConfident,
    required this.requiresConfirmation,
    required this.observedFeatures,
    required this.candidates,
    this.hasMoreCandidates = false,
  });

  // Function Name: PillIdentificationResult.fromJson
  // Description: Validates payload shapes, candidate identities and finite scores, mandatory confirmation, and consistency between success, confidence, and candidate presence.
  // Parameters:
  // - json (Map<String, dynamic>): Backend response or stored JSON object for this model.
  // Returns:
  // - PillIdentificationResult: the decoded record after field validation and default handling.
  factory PillIdentificationResult.fromJson(Map<String, dynamic> json) {
    final rawSuccess = json['success'];
    final rawMessage = json['message'];
    final rawConfidence = json['is_confident'];
    final rawRequiresConfirmation = json['requires_confirmation'];
    final rawFeatures = json['observed_features'];
    final rawCandidates = json['data'];
    final rawMoreCandidates = json['has_more_candidates'] ?? false;
    if (rawMoreCandidates is! bool) {
      throw const FormatException('has_more_candidates must be a boolean.');
    }
    if (rawSuccess is! bool) {
      throw const FormatException('success must be a boolean.');
    }
    if (rawMessage is! String || rawMessage.trim().isEmpty) {
      throw const FormatException('message must be a non-empty string.');
    }
    if (rawConfidence is! bool) {
      throw const FormatException('is_confident must be a boolean.');
    }
    if (rawRequiresConfirmation is! bool) {
      throw const FormatException('requires_confirmation must be a boolean.');
    }
    if (!rawRequiresConfirmation) {
      throw const FormatException(
        'requires_confirmation must preserve mandatory user confirmation.',
      );
    }
    if (rawFeatures is! Map) {
      throw const FormatException('observed_features must be an object.');
    }
    if (rawCandidates is! List) {
      throw const FormatException('data must be an array.');
    }

    final candidates = <PillIdentificationCandidate>[];
    for (final rawCandidate in rawCandidates) {
      if (rawCandidate is! Map) {
        throw const FormatException('Every candidate must be an object.');
      }
      final candidateJson = Map<String, dynamic>.from(rawCandidate);
      final itemSeq = candidateJson['item_seq'];
      final itemName = candidateJson['item_name'];
      final matchScore = candidateJson['match_score'];
      if (itemSeq is! String || itemSeq.trim().isEmpty) {
        throw const FormatException('Candidate item_seq is required.');
      }
      if (itemName is! String || itemName.trim().isEmpty) {
        throw const FormatException('Candidate item_name is required.');
      }
      if (matchScore is! num ||
          !matchScore.toDouble().isFinite ||
          matchScore < 0 ||
          matchScore > 1) {
        throw const FormatException('Candidate match_score is invalid.');
      }
      candidates.add(PillIdentificationCandidate.fromJson(candidateJson));
    }
    if (rawSuccess != candidates.isNotEmpty) {
      throw const FormatException(
        'success must match whether candidates are present.',
      );
    }
    if (!rawSuccess && rawConfidence) {
      throw const FormatException(
        'An empty result cannot be marked as confident.',
      );
    }

    return PillIdentificationResult(
      isConfident: rawConfidence,
      requiresConfirmation: rawRequiresConfirmation,
      observedFeatures: PillVisualFeatures.fromJson(
        Map<String, dynamic>.from(rawFeatures),
      ),
      candidates: List<PillIdentificationCandidate>.unmodifiable(candidates),
      hasMoreCandidates: rawMoreCandidates,
    );
  }
}

// Class Name: PillBoundingBox
// Role: Represents a pill rectangle in normalized image coordinates.
// Responsibilities:
// - Require finite unit-range coordinates, positive dimensions, and containment within the image when decoding.
// Attributes:
// - left (double): Normalized horizontal start coordinate from the image left edge.
// - top (double): Normalized y coordinate measured from the image top.
// - width (double): Region width in normalized zero-to-one coordinates.
// - height (double): Region height in normalized zero-to-one coordinates.
class PillBoundingBox {
  final double left;
  final double top;
  final double width;
  final double height;

  // Function Name: PillBoundingBox
  // Description: Captures a pill rectangle's normalized origin and size for image overlays.
  // Parameters:
  // - left (double): Normalized horizontal start coordinate from the image left edge.
  // - top (double): Normalized y coordinate measured from the image top.
  // - width (double): Region width in normalized zero-to-one coordinates.
  // - height (double): Region height in normalized zero-to-one coordinates.
  // Returns:
  // - PillBoundingBox: the initialized instance.
  const PillBoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  // Function Name: PillBoundingBox.fromJson
  // Description: Requires finite zero-to-one coordinates, positive width and height, and a rectangle fully contained within the image.
  // Parameters:
  // - json (Map<String, dynamic>): Backend response or stored JSON object for this model.
  // Returns:
  // - PillBoundingBox: the decoded record after field validation and default handling.
  factory PillBoundingBox.fromJson(Map<String, dynamic> json) {
    final left = _readRequiredScore(json['left'], 'left');
    final top = _readRequiredScore(json['top'], 'top');
    final width = _readRequiredScore(json['width'], 'width');
    final height = _readRequiredScore(json['height'], 'height');
    if (width <= 0 || height <= 0 || left + width > 1 || top + height > 1) {
      throw const FormatException('bounding_box must stay inside the image.');
    }
    return PillBoundingBox(left: left, top: top, width: width, height: height);
  }
}

// Class Name: MultiplePillObservation
// Role: Associates one numbered pill region with its independent identification result.
// Responsibilities:
// - Keep spatial location and candidate evidence together while preserving observation order.
// Attributes:
// - index (int): Position in the original input or observation sequence.
// - boundingBox (PillBoundingBox): Normalized image rectangle occupied by the pill.
// - identification (PillIdentificationResult): Pill-candidate identification result for the image region.
class MultiplePillObservation {
  final int index;
  final PillBoundingBox boundingBox;
  final PillIdentificationResult identification;

  // Function Name: MultiplePillObservation
  // Description: Binds an observation index and image rectangle to the corresponding single-pill candidate result.
  // Parameters:
  // - index (int): Position in the original input or observation sequence.
  // - boundingBox (PillBoundingBox): Normalized image rectangle occupied by the pill.
  // - identification (PillIdentificationResult): Pill-candidate identification result for the image region.
  // Returns:
  // - MultiplePillObservation: the initialized instance.
  const MultiplePillObservation({
    required this.index,
    required this.boundingBox,
    required this.identification,
  });
}

// Class Name: MultiplePillIdentificationResult
// Role: Holds the validated sequence of pill observations from a single photo.
// Responsibilities:
// - Require one to ten contiguous observations, valid boxes and candidates, and mandatory user confirmation.
// Attributes:
// - observations (List<MultiplePillObservation>): Ordered pill observations separated from the input photo.
// - requiresConfirmation (bool): Contract flag requiring user confirmation before saving.
class MultiplePillIdentificationResult {
  final List<MultiplePillObservation> observations;
  final bool requiresConfirmation;

  // Function Name: MultiplePillIdentificationResult
  // Description: Captures the observation sequence and confirmation flag for reviewing multiple pills in one photo.
  // Parameters:
  // - observations (List<MultiplePillObservation>): Ordered pill observations separated from the input photo.
  // - requiresConfirmation (bool): Contract flag requiring user confirmation before saving.
  // Returns:
  // - MultiplePillIdentificationResult: the initialized instance.
  const MultiplePillIdentificationResult({
    required this.observations,
    required this.requiresConfirmation,
  });

  // Function Name: MultiplePillIdentificationResult.fromJson
  // Description: Requires success and mandatory confirmation, validates one to ten contiguously indexed observations, and decodes each bounding box and identification result.
  // Parameters:
  // - json (Map<String, dynamic>): Backend response or stored JSON object for this model.
  // Returns:
  // - MultiplePillIdentificationResult: the decoded record after field validation and default handling.
  factory MultiplePillIdentificationResult.fromJson(Map<String, dynamic> json) {
    if (json['success'] is! bool || json['success'] != true) {
      throw const FormatException('success must be true.');
    }
    if (json['requires_confirmation'] != true) {
      throw const FormatException('Confirmation must remain mandatory.');
    }
    final rawObservations = json['observations'];
    if (rawObservations is! List ||
        rawObservations.isEmpty ||
        rawObservations.length > 10) {
      throw const FormatException('observations must contain 1 to 10 pills.');
    }
    final observations = <MultiplePillObservation>[];
    for (var position = 0; position < rawObservations.length; position += 1) {
      final raw = rawObservations[position];
      if (raw is! Map) {
        throw const FormatException('Every observation must be an object.');
      }
      final observation = Map<String, dynamic>.from(raw);
      final index = observation['index'];
      final rawBox = observation['bounding_box'];
      final rawIdentification = observation['identification'];
      if (index is! int || index != position + 1) {
        throw const FormatException('Observation indexes must be contiguous.');
      }
      if (rawBox is! Map || rawIdentification is! Map) {
        throw const FormatException('Observation payload is incomplete.');
      }
      observations.add(
        MultiplePillObservation(
          index: index,
          boundingBox: PillBoundingBox.fromJson(
            Map<String, dynamic>.from(rawBox),
          ),
          identification: PillIdentificationResult.fromJson(
            Map<String, dynamic>.from(rawIdentification),
          ),
        ),
      );
    }
    return MultiplePillIdentificationResult(
      observations: List<MultiplePillObservation>.unmodifiable(observations),
      requiresConfirmation: true,
    );
  }
}

// Function Name: _readRequiredBool
// Description: Requires an actual boolean for a named response field and throws FormatException for any other type.
// Parameters:
// - value (dynamic): Raw response field to decode into the documented return type.
// - fieldName (String): Backend field name being read or validated.
// Returns:
// - bool: Requires an actual boolean for a named response field and throws FormatException for any other type.
bool _readRequiredBool(dynamic value, String fieldName) {
  if (value is! bool) {
    throw FormatException('$fieldName must be a boolean.');
  }
  return value;
}

// Function Name: _readRequiredScore
// Description: Requires a numeric, finite score within zero to one and identifies the invalid response field in FormatException.
// Parameters:
// - value (dynamic): Raw response field to decode into the documented return type.
// - fieldName (String): Backend field name being read or validated.
// Returns:
// - double: Requires a numeric, finite score within zero to one and identifies the invalid response field in FormatException.
double _readRequiredScore(dynamic value, String fieldName) {
  if (value is! num) {
    throw FormatException('$fieldName must be a number.');
  }
  final score = value.toDouble();
  if (!score.isFinite || score < 0 || score > 1) {
    throw FormatException('$fieldName must be between 0 and 1.');
  }
  return score;
}

// Function Name: _readString
// Description: Uses trimmed text when nonempty and otherwise preserves the caller-supplied fallback.
// Parameters:
// - value (dynamic): Raw response field to decode into the documented return type.
// - fallback (String): Fallback for absent or unparseable input.
// Returns:
// - String: trimmed nonblank text, or the supplied fallback.
String _readString(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

// Function Name: _readStrings
// Description: Converts list entries to trimmed nonempty strings and uses an empty list for nonlist input.
// Parameters:
// - value (dynamic): Raw response field to decode into the documented return type.
// Returns:
// - List<String>: trimmed, nonempty list entries; an empty list for nonlist input.
List<String> _readStrings(dynamic value) {
  if (value is! List) {
    return const [];
  }
  return List<String>.unmodifiable(
    value
        .map(
          /* Function Name: map callback
         * Description: Converts an optional identification-list entry into trimmed text.
         * Parameters:
         * - item (dynamic): Current response or collection entry being transformed or checked.
         * Returns:
         * - Trimmed text, or an empty string for null.
         */
          (item) => item?.toString().trim() ?? '',
        )
        .where(
          /* Function Name: where callback
         * Description: Removes blank strings from the parsed identification list.
         * Parameters:
         * - item (String): Current response or collection entry being transformed or checked.
         * Returns:
         * - Whether the entry contains text.
         */
          (item) => item.isNotEmpty,
        ),
  );
}

// Function Name: _readScore
// Description: Parses a candidate score, replaces nonfinite values with zero, and clamps finite values to the zero-to-one range.
// Parameters:
// - value (dynamic): Raw response field to decode into the documented return type.
// Returns:
// - double: Parses a candidate score, replaces nonfinite values with zero, and clamps finite values to the zero-to-one range.
double _readScore(dynamic value) {
  final score = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0.0;
  if (!score.isFinite) {
    return 0.0;
  }
  return score.clamp(0.0, 1.0).toDouble();
}
