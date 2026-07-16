class PillVisualFeatures {
  final String shape;
  final List<String> colors;
  final String frontImprint;
  final String backImprint;
  final String frontLine;
  final String backLine;
  final String quality;
  final List<String> qualityIssues;

  const PillVisualFeatures({
    this.shape = 'unknown',
    this.colors = const [],
    this.frontImprint = '',
    this.backImprint = '',
    this.frontLine = 'unknown',
    this.backLine = 'unknown',
    this.quality = 'usable',
    this.qualityIssues = const [],
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
  final bool success;
  final String message;
  final bool isConfident;
  final bool requiresConfirmation;
  final PillVisualFeatures observedFeatures;
  final List<PillIdentificationCandidate> candidates;

  const PillIdentificationResult({
    required this.success,
    required this.message,
    required this.isConfident,
    required this.requiresConfirmation,
    required this.observedFeatures,
    required this.candidates,
  });

  factory PillIdentificationResult.fromJson(Map<String, dynamic> json) {
    final rawFeatures = json['observed_features'];
    final rawCandidates = json['data'];
    return PillIdentificationResult(
      success: json['success'] == true,
      message: _readString(json['message']),
      isConfident: json['is_confident'] == true,
      // Product confirmation is a client-side safety invariant, not a
      // server-controlled display preference.
      requiresConfirmation: true,
      observedFeatures: rawFeatures is Map
          ? PillVisualFeatures.fromJson(
              Map<String, dynamic>.from(rawFeatures),
            )
          : const PillVisualFeatures(),
      candidates: rawCandidates is List
          ? rawCandidates
              .whereType<Map>()
              .map(
                (item) => PillIdentificationCandidate.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where(
                (candidate) =>
                    candidate.itemSeq.isNotEmpty &&
                    candidate.itemName.isNotEmpty,
              )
              .toList(growable: false)
          : const [],
    );
  }
}

String _readString(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

List<String> _readStrings(dynamic value) {
  if (value is! List) {
    return const [];
  }
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

double _readScore(dynamic value) {
  final score = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0.0;
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
