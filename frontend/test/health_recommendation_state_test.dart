// File Name: health_recommendation_state_test.dart
// Role: Regression coverage for isolated, latest-request-only recommendation state.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/check_health_recommendation_control.dart';
import 'package:medbuddy_frontend/entities/health_recommendation_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_feature_updates.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_health_recommendation_view_model.dart';

// Class Name: _PendingRecommendations
// Role: Holds responses until tests explicitly complete them.
// Responsibilities: Make overlapping requests deterministic without real networking.
// Attributes: requests: Ordered pending responses.
class _PendingRecommendations extends CheckHealthRecommendation {
  final requests = <Completer<HealthRecommendation>>[];

  // Function Name: requestHealthRecommendation
  // Description: Creates a manually controlled response.
  // Parameters: language: Requested recommendation language.
  // Returns: Pending recommendation future.
  @override
  Future<HealthRecommendation> requestHealthRecommendation({
    String language = 'ko',
  }) {
    final response = Completer<HealthRecommendation>();
    requests.add(response);
    return response.future;
  }
}

const _result = HealthRecommendation(
  dietRecommendation: 'Latest diet',
  exerciseRecommendation: 'Latest exercise',
  cautionItems: ['Latest caution'],
  medicationNames: ['Test medication'],
);

// Function Name: main
// Description: Registers lifecycle, race, and feature-isolation regressions.
// Parameters: None.
// Returns: None.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Function Name: language test
  // Description: Preserves English locale variants for feature-local feedback.
  // Parameters: None.
  // Returns: Test completion.
  test('language variants keep their request-local feedback', () async {
    final control = _PendingRecommendations();
    final feature = MedBuddyHealthRecommendationViewModel(control);
    addTearDown(feature.dispose);
    addTearDown(control.dispose);
    final request = feature.fetch(language: ' EN-us ');
    expect(feature.statusMessage, 'Loading health recommendations.');
    control.requests.single.completeError(StateError('unavailable'));
    await request;
    expect(feature.statusMessage, 'Could not load health recommendations.');
    expect(feature.hasNoActiveMedications, isFalse);
  });

  // Function Name: latest result test
  // Description: Ignores an older success after a newer confirmed-empty result.
  // Parameters: None.
  // Returns: Test completion.
  test('older success cannot replace the newest empty state', () async {
    final control = _PendingRecommendations();
    final model = MedBuddyViewModel(checkHealthRecommendation: control);
    addTearDown(model.dispose);
    final originalStatus = model.statusMessage;
    final oldRequest = model.fetchHealthRecommendation();
    final newRequest = model.fetchHealthRecommendation();
    control.requests[1].completeError(NoActiveMedicationsError());
    await newRequest;
    final revision = model
        .updatesFor(MedBuddyFeature.healthRecommendation)
        .revision;
    control.requests[0].complete(_result);
    await oldRequest;
    expect(model.healthRecommendation, isNull);
    expect(model.hasNoActiveHealthMedications, isTrue);
    expect(model.statusMessage, originalStatus);
    expect(
      model.updatesFor(MedBuddyFeature.healthRecommendation).revision,
      revision,
    );
    expect(model.updatesFor(MedBuddyFeature.prescription).revision, 0);
  });

  // Function Name: stale failure test
  // Description: An old failure cannot clear a newer request's loading flag or message.
  // Parameters: None.
  // Returns: Test completion.
  test('stale failure leaves newer loading state intact', () async {
    final control = _PendingRecommendations();
    final model = MedBuddyViewModel(checkHealthRecommendation: control);
    addTearDown(model.dispose);
    final oldRequest = model.fetchHealthRecommendation();
    final newRequest = model.fetchHealthRecommendation();
    control.requests[0].completeError(StateError('old failure'));
    await oldRequest;
    expect(model.isHealthRecommendationLoading, isTrue);
    expect(model.healthRecommendationStatusMessage, '건강 관리 추천을 불러오는 중입니다.');
    control.requests[1].complete(_result);
    await newRequest;
    expect(model.isHealthRecommendationLoading, isFalse);
    expect(model.healthRecommendation, same(_result));
    expect(model.hasNoActiveHealthMedications, isFalse);
  });

  // Function Name: disposal test
  // Description: Pending completion cannot mutate or notify a disposed feature owner.
  // Parameters: None.
  // Returns: Test completion.
  test('disposed owner ignores pending results and new requests', () async {
    final control = _PendingRecommendations();
    final model = MedBuddyViewModel(checkHealthRecommendation: control);
    final request = model.fetchHealthRecommendation();
    model.dispose();
    control.requests.single.complete(_result);
    await request;
    await model.fetchHealthRecommendation();
    expect(model.healthRecommendation, isNull);
    expect(control.requests, hasLength(1));
    model.dispose();
  });
}
