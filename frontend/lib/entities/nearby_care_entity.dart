// File Name: nearby_care_entity.dart
// Role: Defines provider-neutral nearby-care search, display and selection contracts.

import 'device_coordinate_entity.dart';

// Class Name: NearbyCareSearchArea
// Role: Preserves an explicit search radius and the provenance of its center.
// Responsibilities: Validate coordinates/radius without choosing a provider's radius policy.
// Attributes: center, radiusKm, isFallback and isMapArea: immutable search scope.
class NearbyCareSearchArea {
  final DeviceCoordinate center;
  final double radiusKm;
  final bool isFallback;
  final bool isMapArea;

  // Function Name: NearbyCareSearchArea
  // Description: Captures a caller-selected center and radius without a provider default.
  // Parameters: center/radiusKm: explicit search scope; isFallback/isMapArea: location provenance.
  // Returns: A search area; isValid separately checks the backend's allowed bounds.
  const NearbyCareSearchArea({
    required this.center,
    required this.radiusKm,
    this.isFallback = false,
    this.isMapArea = false,
  });

  // 홍익대학교 서울캠퍼스(와우산로 94). 기기 위치로 기록하거나 캐시하지 않는다.
  static const fallbackCenter = DeviceCoordinate(
    latitude: 37.5516,
    longitude: 126.9250,
  );

  // 함수이름: isValid
  // 함수역할: 서버가 받는 유한한 좌표와 반경 범위를 검증한다. 매개변수: 없음. 반환값: 유효 여부.
  bool get isValid =>
      center.latitude.isFinite &&
      center.longitude.isFinite &&
      center.latitude >= -90 &&
      center.latitude <= 90 &&
      center.longitude >= -180 &&
      center.longitude <= 180 &&
      (center.latitude != 0 || center.longitude != 0) &&
      radiusKm.isFinite &&
      radiusKm >= 0.1 &&
      radiusKm <= 50;
}

// Class Name: NearbyCareSearchMode
// Role: Defines the wire-level search choices shared by nearby-care controls.
// Responsibilities:
// - Preserve backend values; concrete providers and their UI own applicable choices.
enum NearbyCareSearchMode {
  all('all'),
  openAtTime('open_at_time'),
  lateHours('late_hours'),
  officialLateNight('official_late_night'),
  weekendHoliday('weekend_holiday');

  final String apiValue;
  // Function Name: NearbyCareSearchMode
  // Description: Associates each nearby-care search choice with the exact backend query value.
  // Parameters:
  // - apiValue (String): Wire value defined by the backend contract.
  // Returns:
  // - NearbyCareSearchMode: the initialized instance.
  const NearbyCareSearchMode(this.apiValue);
}

// Class Name: NearbyCarePlace
// Role: Represents a hospital or pharmacy for shared map, list and contact display.
// Note: placeId is a display identifier, never a choice of authenticated server route.
// Responsibilities: Preserve operating uncertainty, source freshness and provider-specific metadata.
// Attributes: placeId: original hospital/pharmacy identifier; contact, coordinate, schedule and source fields.
// Note: Optional late-night designation applies to pharmacies; departments apply to hospitals.
class NearbyCarePlace {
  final String placeId;
  final String name;
  final String address;
  final String telephone;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final String? todayOpenTime;
  final String? todayCloseTime;
  final bool? isOpenNow;
  final bool is24Hours;
  final bool isOpenLate;
  final bool hasWeekendOrHolidayHours;
  final bool isPublicHoliday;
  final bool isOfficialLateNight;
  final String? designationSourceName;
  final String? designationSourceUrl;
  final DateTime? designationVerifiedAt;
  final bool designationIsStale;
  final DateTime? scheduleDate;
  final String scheduleSource;
  final bool scheduleIsDateSpecific;
  final int? minutesUntilClose;
  final DateTime? nextOpenAt;
  final DateTime? sourceUpdatedAt;
  final String sourceName;
  // 병원 화면에서만 쓰는 진료과목과 기관 구분. 약국 응답은 기존 값을 유지한다.
  final List<String> departments;
  final String? institutionType;

  // Function Name: NearbyCarePlace
  // Description: Captures a display snapshot without authorizing a server route or guaranteeing availability.
  // Parameters:
  // - placeId/name/address/telephone: original provider identifier and public contact fields.
  // - latitude/longitude/distanceKm: WGS84 location and query-relative distance.
  // - todayOpenTime/todayCloseTime/isOpenNow/is24Hours and optional schedule fields: reported operating evidence.
  // - Optional designation/source fields: pharmacy designation, provenance and freshness.
  // - departments/institutionType: optional hospital metadata.
  // Returns: A nearby-care place; unknown opening status remains nullable.
  const NearbyCarePlace({
    required this.placeId,
    required this.name,
    required this.address,
    required this.telephone,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.todayOpenTime,
    required this.todayCloseTime,
    required this.isOpenNow,
    required this.is24Hours,
    this.isOpenLate = false,
    this.hasWeekendOrHolidayHours = false,
    this.isPublicHoliday = false,
    this.isOfficialLateNight = false,
    this.designationSourceName,
    this.designationSourceUrl,
    this.designationVerifiedAt,
    this.designationIsStale = false,
    this.scheduleDate,
    this.scheduleSource = 'nemc_weekly_report',
    this.scheduleIsDateSpecific = false,
    this.minutesUntilClose,
    this.nextOpenAt,
    this.sourceUpdatedAt,
    this.sourceName = 'National Emergency Medical Center',
    this.departments = const [],
    this.institutionType,
  });

  // Function Name: NearbyCarePlace.fromJson
  // Description: Decodes original pharmacy_id or hospital_id without changing provider wire contracts.
  // Parameters: json: authenticated backend display payload with optional operating/source metadata.
  // Returns: A neutral display place preserving unknown status, specialty and freshness evidence.
  // Note: Legacy pharmacy_id precedence is retained if both identifiers are supplied.
  factory NearbyCarePlace.fromJson(Map<String, dynamic> json) {
    return NearbyCarePlace(
      placeId: _readString(json['pharmacy_id'] ?? json['hospital_id']),
      departments: json['departments'] is List
          ? List<String>.unmodifiable(
              (json['departments'] as List).whereType<String>(),
            )
          : const [],
      institutionType: _readNullableString(json['institution_type']),
      name: _readString(json['name']),
      address: _readString(json['address']),
      telephone: _readString(json['telephone']),
      latitude: _readDouble(json['latitude']),
      longitude: _readDouble(json['longitude']),
      distanceKm: _readDouble(json['distance_km']),
      todayOpenTime: _readNullableString(json['today_open_time']),
      todayCloseTime: _readNullableString(json['today_close_time']),
      isOpenNow: json['is_open_now'] is bool
          ? json['is_open_now'] as bool
          : null,
      is24Hours: json['is_24_hours'] is bool && json['is_24_hours'] as bool,
      isOpenLate: json['is_open_late'] is bool && json['is_open_late'] as bool,
      hasWeekendOrHolidayHours:
          json['has_weekend_or_holiday_hours'] is bool &&
          json['has_weekend_or_holiday_hours'] as bool,
      isPublicHoliday:
          json['is_public_holiday'] is bool &&
          json['is_public_holiday'] as bool,
      isOfficialLateNight:
          json['is_official_late_night'] is bool &&
          json['is_official_late_night'] as bool,
      designationSourceName: _readNullableString(
        json['designation_source_name'],
      ),
      designationSourceUrl: _readNullableString(json['designation_source_url']),
      designationVerifiedAt: _readDate(json['designation_verified_at']),
      designationIsStale:
          json['designation_is_stale'] is bool &&
          json['designation_is_stale'] as bool,
      scheduleDate: _readDate(json['schedule_date']),
      scheduleSource: _readString(json['schedule_source']).isEmpty
          ? 'nemc_weekly_report'
          : _readString(json['schedule_source']),
      scheduleIsDateSpecific:
          json['schedule_is_date_specific'] is bool &&
          json['schedule_is_date_specific'] as bool,
      minutesUntilClose: _readNullableInt(json['minutes_until_close']),
      nextOpenAt: DateTime.tryParse(_readString(json['next_open_at'])),
      sourceUpdatedAt: DateTime.tryParse(
        _readString(json['source_updated_at']),
      ),
      sourceName: _readString(json['source_name']).isEmpty
          ? 'National Emergency Medical Center'
          : _readString(json['source_name']),
    );
  }

  // 함수이름: distanceLabel
  // 함수역할: 1km 미만은 반올림한 미터로, 10km 미만은 소수 한 자리 km로, 그 이상은 정수 km로 표시한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 1km 미만은 반올림한 미터로, 10km 미만은 소수 한 자리 km로, 그 이상은 정수 km로 표시한다.
  String get distanceLabel {
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).round()}m';
    }
    return '${distanceKm.toStringAsFixed(distanceKm < 10 ? 1 : 0)}km';
  }

  // 함수이름: todayHoursLabel
  // 함수역할: 24시간 운영, 당일 영업시간 미확인, 시작·종료 시각을 구분해 한국어 표시문을 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 24시간 운영, 당일 영업시간 미확인, 시작·종료 시각을 구분해 한국어 표시문을 만든다.
  String get todayHoursLabel {
    if (is24Hours) {
      return '24시간 운영';
    }
    if (todayOpenTime == null || todayCloseTime == null) {
      return '오늘 영업시간 확인 필요';
    }
    return '오늘 $todayOpenTime - $todayCloseTime';
  }

  // 함수이름: _readString
  // 함수역할: 선택적 필드를 공백 정리한 문자열로 바꾸고 없는 값은 빈 문자열로 처리한다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // 반환값:
  // - String: 공백 정리한 필드 문자열; null이면 빈 문자열.
  static String _readString(dynamic value) => value?.toString().trim() ?? '';

  // 함수이름: _readNullableString
  // 함수역할: 입력의 공백을 정리하고 없거나 비어 있으면 null로 처리한다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // 반환값:
  // - String?: 공백 정리한 문자열; 없거나 비어 있으면 null.
  static String? _readNullableString(dynamic value) {
    final normalized = _readString(value);
    return normalized.isEmpty ? null : normalized;
  }

  // 함수이름: _readDouble
  // 함수역할: 숫자 또는 숫자 문자열을 실수로 변환하고 실패하면 0을 사용한다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // 반환값:
  // - double: 숫자 또는 숫자 문자열을 실수로 변환하고 실패하면 0을 사용한다.
  static double _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  // Function Name: _readDate
  // Description: Parses nonempty date text and returns null for absent or malformed dates.
  // Parameters:
  // - value (dynamic): Raw response field to decode into the documented return type.
  // Returns:
  // - DateTime?: Parses nonempty date text and returns null for absent or malformed dates.
  static DateTime? _readDate(dynamic value) {
    final normalized = _readString(value);
    return normalized.isEmpty ? null : DateTime.tryParse(normalized);
  }

  // 함수이름: _readNullableInt
  // 함수역할: 정수 또는 숫자 문자열을 읽고 변환할 수 없으면 null을 사용한다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // 반환값:
  // - int?: 정수 또는 숫자 문자열을 읽고 변환할 수 없으면 null을 사용한다.
  static int? _readNullableInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(_readString(value));
  }
}

// Class Name: NearbyCareSearchResult
// Role: Bundles nearby-care places with search scope and reliability metadata.
// Responsibilities: Preserve catalog/calendar freshness, partial-result and sampled-region uncertainty separately.
// Attributes: data: display places; searchArea/searchMode/targetDateTime: effective query; remaining fields: reliability.
class NearbyCareSearchResult {
  final NearbyCareSearchArea? searchArea;
  final List<NearbyCarePlace> data;
  final NearbyCareSearchMode searchMode;
  final DateTime targetDateTime;
  final DateTime? catalogUpdatedAt;
  final bool catalogIsStale;
  final String holidayScheduleStatus;
  final bool searchTruncated;
  // 병원 검색의 주소 표본 한계이며 실제 목록 조회 제한과 구별한다.
  final bool regionScopeUncertain;

  // Function Name: NearbyCareSearchResult
  // Description: Preserves the provider's effective query scope and uncertainty without treating unknown as closed.
  // Parameters: data/searchArea/searchMode/targetDateTime: result/query; catalog and holiday fields: reliability.
  // - searchTruncated/regionScopeUncertain: result incompleteness and region-sampling evidence, respectively.
  // Returns: A display result whose optional searchArea supports existing injected controller responses.
  const NearbyCareSearchResult({
    this.searchArea,
    required this.data,
    required this.searchMode,
    required this.targetDateTime,
    required this.catalogUpdatedAt,
    required this.catalogIsStale,
    required this.holidayScheduleStatus,
    this.searchTruncated = false,
    this.regionScopeUncertain = false,
  });
}

// Class Name: NearbyCareSelection
// Role: Returns a chosen display place and user confirmation without owning a UI or server route.
// Responsibilities: Preserve the exact phone-confirmation and selected-date provenance for chat preview.
// Attributes: place, phoneVerified, scheduleDate: immutable user selection values.
// Note: The caller's captured provider choice still selects hospitalId versus pharmacyId on send.
class NearbyCareSelection {
  final NearbyCarePlace place;
  final bool phoneVerified;
  final DateTime? scheduleDate;

  // Function Name: NearbyCareSelection
  // Description: Captures display data and user confirmation for one selected search date.
  // Parameters: place: selected result; phoneVerified: explicit confirmation; scheduleDate: queried date.
  // Returns: A provider-neutral selection; no message is sent and no route is inferred from its ID.
  const NearbyCareSelection({
    required this.place,
    required this.phoneVerified,
    this.scheduleDate,
  });
}
