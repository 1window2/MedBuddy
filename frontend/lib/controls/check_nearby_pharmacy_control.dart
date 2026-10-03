// File Name: check_nearby_pharmacy_control.dart
// Role: Selects pharmacy search policy without making hospitals a pharmacy subtype.

import '../entities/nearby_pharmacy_entity.dart';
import '../services/api_config.dart';
import 'check_nearby_care_control.dart';

// Class Name: CheckNearbyPharmacy
// Role: Applies pharmacy endpoint and list-search defaults to shared nearby-care operations.
// Responsibilities:
// - Keep the pharmacy-only convenience API and its 20 km default.
// - Inherit common location, transport and external-action lifetime ownership.
// Attributes: Common resources are owned by CheckNearbyCare.
class CheckNearbyPharmacy extends CheckNearbyCare {
  // Function Name: CheckNearbyPharmacy
  // Description: Injects optional location/HTTP/action boundaries; the base owns only its own client.
  // Parameters: locationBoundary, client, uriLauncher, clipboardWriter: replaceable device/transport boundaries.
  // Returns: A pharmacy search control.
  CheckNearbyPharmacy({
    super.locationBoundary,
    super.client,
    super.uriLauncher,
    super.clipboardWriter,
  });

  // Function Name: nearbySearchUrl
  // Description: Uses only the backend pharmacy search endpoint.
  // Parameters: None.
  // Returns: The authenticated pharmacy search URL.
  @override
  String get nearbySearchUrl => ApiConfig.pharmacyUrl('/nearby');

  // Function Name: requestNearbyPharmacies
  // Description: Returns pharmacy records without exposing this 20 km shortcut to hospitals.
  // Parameters: searchMode, targetDateTime, maxDistanceKm: pharmacy filter, time and radius.
  // Returns: The records from the complete nearby-care search result.
  Future<List<NearbyPharmacy>> requestNearbyPharmacies({
    PharmacySearchMode searchMode = PharmacySearchMode.openAtTime,
    DateTime? targetDateTime,
    double maxDistanceKm = 20,
  }) async {
    final result = await requestNearbyCareSearch(
      searchMode: searchMode,
      targetDateTime: targetDateTime,
      maxDistanceKm: maxDistanceKm,
    );
    return result.data;
  }
}
