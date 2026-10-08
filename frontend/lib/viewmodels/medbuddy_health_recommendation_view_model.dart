// File Name: medbuddy_health_recommendation_view_model.dart
// Role: Owns recommendation presentation state independently of other features.

import 'package:flutter/foundation.dart';

import '../controls/check_health_recommendation_control.dart';
import '../entities/health_recommendation_entity.dart';
import '../entities/user_setting_entity.dart';

// Class Name: MedBuddyHealthRecommendationViewModel
// Role: Patient-scoped recommendation presentation state.
// Responsibilities:
// - Delegate requests to the existing control and accept only the latest result.
// - Keep status messages isolated and ignore completions after disposal.
// Attributes:
// - _control: Borrowed control; its owner remains responsible for disposal.
class MedBuddyHealthRecommendationViewModel extends ChangeNotifier {
  final CheckHealthRecommendation _control;
  bool _disposed = false;
  int _requestId = 0;
  bool _loading = false;
  bool _empty = false;
  HealthRecommendation? _recommendation;
  String _statusMessage = '';

  // Function Name: MedBuddyHealthRecommendationViewModel
  // Description: Binds a borrowed patient-scoped control.
  // Parameters: control: Existing recommendation use-case control.
  // Returns: An initially idle feature model.
  MedBuddyHealthRecommendationViewModel(CheckHealthRecommendation control)
    : _control = control;

  // Function Name: isLoading
  // Description: Exposes whether the latest request is pending.
  // Parameters: None.
  // Returns: Latest request loading state.
  bool get isLoading => _loading;

  // Function Name: hasNoActiveMedications
  // Description: Distinguishes confirmed empty medication data from a failure.
  // Parameters: None.
  // Returns: Whether the latest request confirmed no active medication.
  bool get hasNoActiveMedications => _empty;

  // Function Name: recommendation
  // Description: Exposes only the latest successful request result.
  // Parameters: None.
  // Returns: Recommendation, or null before success.
  HealthRecommendation? get recommendation => _recommendation;

  // Function Name: statusMessage
  // Description: Exposes a feature-local message in the request language.
  // Parameters: None.
  // Returns: Current recommendation status message.
  String get statusMessage => _statusMessage;

  // Function Name: fetch
  // Description: Replaces presentation state only when this request is still current.
  // Parameters: language: Language captured for both the request and its messages.
  // Returns: Completion without propagating expected API failures to the UI.
  Future<void> fetch({required String language}) async {
    if (_disposed) return;
    final requestId = ++_requestId;
    final english = isEnglishLanguage(language);
    _loading = true;
    _empty = false;
    _recommendation = null;
    _statusMessage = english
        ? 'Loading health recommendations.'
        : '건강 관리 추천을 불러오는 중입니다.';
    notifyListeners();
    // A listener may dispose the owner or start a newer request synchronously.
    if (!_isCurrent(requestId)) return;
    try {
      final result = await _control.requestHealthRecommendation(
        language: language,
      );
      if (!_isCurrent(requestId)) return;
      _recommendation = result;
      _statusMessage = english
          ? 'Health recommendations loaded.'
          : '건강 관리 추천을 불러왔습니다.';
    } on NoActiveMedicationsError {
      if (!_isCurrent(requestId)) return;
      _empty = true;
      _statusMessage = english
          ? 'You have no active medications.'
          : '현재 복용 중인 약이 없어요.';
    } catch (_) {
      if (!_isCurrent(requestId)) return;
      _statusMessage = english
          ? 'Could not load health recommendations.'
          : '건강 관리 추천을 불러오지 못했습니다.';
    } finally {
      if (_isCurrent(requestId)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  // Function Name: _isCurrent
  // Description: Rejects superseded requests and disposed owners.
  // Parameters: requestId: Generation captured by the request.
  // Returns: Whether the request may still publish state.
  bool _isCurrent(int requestId) => !_disposed && requestId == _requestId;

  // Function Name: dispose
  // Description: Invalidates pending completions without closing the borrowed control.
  // Parameters: None.
  // Returns: None.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
