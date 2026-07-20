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

  factory PillIdentificationCandidate.fromJson(Map<String, dynamic> json) {
    return PillIdentificationCandidate(
      itemSeq: _readString(json['item_seq']),
      itemName: _readString(json['item_name']),
      manufacturer: _readString(json['entp_name']),
      imageUrl: _safeNetworkUrl(json['image_url']),
      shape: _readString(json['shape']),
      colors: _readStrings(json['colors']),
      printFront: _readString(json['print_front']),
      printBack: _readString(json['print_back']),
      matchScore: _readScore(json['match_score']),
      matchedAttributes: _readStrings(json['matched_attributes']),
    );
  }
}

class PillIdentificationResult {
  final bool isConfident;
  final bool requiresConfirmation;
  final PillVisualFeatures observedFeatures;
  final List<PillIdentificationCandidate> candidates;

  const PillIdentificationResult({
    required this.isConfident,
    required this.requiresConfirmation,
    required this.observedFeatures,
    required this.candidates,
  });

  factory PillIdentificationResult.fromJson(Map<String, dynamic> json) {
    final rawSuccess = json['success'];
    final rawMessage = json['message'];
    final rawConfidence = json['is_confident'];
    final rawRequiresConfirmation = json['requires_confirmation'];
    final rawFeatures = json['observed_features'];
    final rawCandidates = json['data'];
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
    );
  }
}

bool _readRequiredBool(dynamic value, String fieldName) {
  if (value is! bool) {
    throw FormatException('$fieldName must be a boolean.');
  }
  return value;
}

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

String _readString(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

List<String> _readStrings(dynamic value) {
  if (value is! List) {
    return const [];
  }
  return List<String>.unmodifiable(
    value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty),
  );
}

double _readScore(dynamic value) {
  final score = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0.0;
  if (!score.isFinite) {
    return 0.0;
  }
  return score.clamp(0.0, 1.0).toDouble();
}

String _safeNetworkUrl(dynamic value) {
  final text = _readString(value);
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasAuthority) {
    return '';
  }
  return uri.scheme == 'http' || uri.scheme == 'https' ? text : '';
}
