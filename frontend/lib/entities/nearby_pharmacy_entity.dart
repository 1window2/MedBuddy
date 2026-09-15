// 파일명: nearby_pharmacy_entity.dart
// 역할: 현재 위치와 근처 약국 조회 결과를 표현한다.

// 클래스명: DeviceCoordinate
// 역할: 위치 플러그인과 분리된 WGS84 위도·경도 값이다.
// 주요 책임:
// - 주변 약국 조회와 외부 길찾기에서 동일한 좌표 계약을 사용하게 한다.
// 속성:
// - latitude (double): WGS84 위도(도 단위)
// - longitude (double): WGS84 경도(도 단위)
class DeviceCoordinate {
  final double latitude;
  final double longitude;

  // 함수이름: DeviceCoordinate
  // 함수역할: 기기의 WGS84 위도와 경도를 외부 위치 플러그인에 의존하지 않는 값으로 묶는다.
  // 매개변수:
  // - latitude (double): WGS84 위도(도 단위)
  // - longitude (double): WGS84 경도(도 단위)
  // 반환값:
  // - DeviceCoordinate: 초기화된 인스턴스.
  const DeviceCoordinate({required this.latitude, required this.longitude});
}

// 클래스명: PharmacySearchArea
// 역할: 기기 위치·지도 중심·기본 위치의 검색 좌표와 반경을 보관한다.
class PharmacySearchArea {
  final DeviceCoordinate center;
  final double radiusKm;
  final bool isFallback;
  final bool isMapArea;

  // 함수이름: PharmacySearchArea
  // 함수역할: 검색 기준과 표시 출처를 묶는다. 매개변수: center, radiusKm, isFallback, isMapArea. 반환값: 검색 지역.
  const PharmacySearchArea({
    required this.center,
    this.radiusKm = 20,
    this.isFallback = false,
    this.isMapArea = false,
  });

  // 홍익대학교 서울캠퍼스(와우산로 94). 기기 위치로 기록하거나 캐시하지 않는다.
  static const hongik = PharmacySearchArea(
    center: DeviceCoordinate(latitude: 37.5516, longitude: 126.9250),
    isFallback: true,
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

// Class Name: PharmacySearchMode
// Role: Defines the pharmacy search filters supported by the backend.
// Responsibilities:
// - Map all-pharmacy, open-at-time, extended-hours, official late-night, and weekend/holiday choices to API wire values.
enum PharmacySearchMode {
  all('all'),
  openAtTime('open_at_time'),
  lateHours('late_hours'),
  officialLateNight('official_late_night'),
  weekendHoliday('weekend_holiday');

  final String apiValue;
  // Function Name: PharmacySearchMode
  // Description: Associates each pharmacy search choice with the exact backend query value.
  // Parameters:
  // - apiValue (String): Wire value defined by the backend contract.
  // Returns:
  // - PharmacySearchMode: the initialized instance.
  const PharmacySearchMode(this.apiValue);
}

// 클래스명: NearbyPharmacy
// 역할: 근처 약국의 영업 상태, 연락처와 위치 및 출처 정보를 표현한다.
// 주요 책임:
// - 거리·당일 시간을 표시하고 날짜별 영업 및 공공심야 지정 정보의 최신성을 구분한다.
// 속성:
// - pharmacyId (String): 공공데이터 또는 서버의 약국 식별자
// - name (String): 표시하거나 길찾기에 사용할 약국 이름
// - address (String): 복사하거나 표시할 약국 주소
// - telephone (String): 약국 전화번호 원문
// - latitude (double): WGS84 위도(도 단위)
// - longitude (double): WGS84 경도(도 단위)
// - distanceKm (double): 기준 위치에서 약국까지 거리(km)
// - todayOpenTime (String?): 조회 날짜의 영업 종료·시작 시각
// - todayCloseTime (String?): 조회 날짜의 영업 종료·시작 시각
// - isOpenNow (bool?): 기준 시각 영업 여부; 미확인은 null
// - is24Hours (bool): 24시간 운영 약국 여부
// - isOpenLate (bool): 야간 영업 조건 충족 여부
// - hasWeekendOrHolidayHours (bool): 주말 또는 공휴일 영업시간 자료 존재 여부
// - isPublicHoliday (bool): 조회 날짜의 공휴일 여부
// - isOfficialLateNight (bool): 공식 공공심야 약국 지정 여부
// - designationSourceName (String?): 공공심야 지정 정보를 제공한 기관명
// - designationSourceUrl (String?): 공공심야 지정 근거 자료의 주소
// - designationVerifiedAt (DateTime?): 공공심야 지정 정보를 확인한 시각
// - designationIsStale (bool): 공공심야 지정 정보의 최신성 초과 여부
// - scheduleDate (DateTime?): 해당 약국 영업시간이 적용되는 날짜
// - scheduleSource (String): 약국 영업시간 자료의 출처 유형
// - scheduleIsDateSpecific (bool): 특정 날짜를 확인한 영업시간인지 여부
// - minutesUntilClose (int?): 폐점까지 남은 분; 알 수 없으면 null
// - nextOpenAt (DateTime?): 다음 영업 시작 예상 시각
// - sourceUpdatedAt (DateTime?): 원본 약국 자료의 갱신 시각
// - sourceName (String): 약국 자료 제공 기관 이름
class NearbyPharmacy {
  final String pharmacyId;
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

  // 함수이름: NearbyPharmacy
  // 함수역할: 약국의 위치·연락처·거리·영업시간과 공공심야 지정 및 자료 최신성 메타데이터를 검색 결과로 보존한다.
  // 매개변수:
  // - pharmacyId (String): 공공데이터 또는 서버의 약국 식별자
  // - name (String): 표시하거나 길찾기에 사용할 약국 이름
  // - address (String): 복사하거나 표시할 약국 주소
  // - telephone (String): 약국 전화번호 원문
  // - latitude (double): WGS84 위도(도 단위)
  // - longitude (double): WGS84 경도(도 단위)
  // - distanceKm (double): 기준 위치에서 약국까지 거리(km)
  // - todayOpenTime (String?): 조회 날짜의 영업 종료·시작 시각
  // - todayCloseTime (String?): 조회 날짜의 영업 종료·시작 시각
  // - isOpenNow (bool?): 기준 시각 영업 여부; 미확인은 null
  // - is24Hours (bool): 24시간 운영 약국 여부
  // - isOpenLate (bool): 야간 영업 조건 충족 여부
  // - hasWeekendOrHolidayHours (bool): 주말 또는 공휴일 영업시간 자료 존재 여부
  // - isPublicHoliday (bool): 조회 날짜의 공휴일 여부
  // - isOfficialLateNight (bool): 공식 공공심야 약국 지정 여부
  // - designationSourceName (String?): 공공심야 지정 정보를 제공한 기관명
  // - designationSourceUrl (String?): 공공심야 지정 근거 자료의 주소
  // - designationVerifiedAt (DateTime?): 공공심야 지정 정보를 확인한 시각
  // - designationIsStale (bool): 공공심야 지정 정보의 최신성 초과 여부
  // - scheduleDate (DateTime?): 해당 약국 영업시간이 적용되는 날짜
  // - scheduleSource (String): 약국 영업시간 자료의 출처 유형
  // - scheduleIsDateSpecific (bool): 특정 날짜를 확인한 영업시간인지 여부
  // - minutesUntilClose (int?): 폐점까지 남은 분; 알 수 없으면 null
  // - nextOpenAt (DateTime?): 다음 영업 시작 예상 시각
  // - sourceUpdatedAt (DateTime?): 원본 약국 자료의 갱신 시각
  // - sourceName (String): 약국 자료 제공 기관 이름
  // 반환값:
  // - NearbyPharmacy: 초기화된 인스턴스.
  const NearbyPharmacy({
    required this.pharmacyId,
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
  });

  // 함수이름: NearbyPharmacy.fromJson
  // 함수역할: 약국 응답을 변환하고 영업 여부의 미확인 상태를 null로 유지하며 지정 출처·날짜별 일정·자료 갱신 시각을 보존한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 해당 모델의 서버 응답 또는 저장 JSON 객체
  // 반환값:
  // - NearbyPharmacy: 필드 검증과 기본값 처리를 거쳐 복원한 레코드.
  factory NearbyPharmacy.fromJson(Map<String, dynamic> json) {
    return NearbyPharmacy(
      pharmacyId: _readString(json['pharmacy_id']),
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

// Class Name: NearbyPharmacySearchResult
// Role: Bundles pharmacy results with the query time and catalog reliability metadata.
// Responsibilities:
// - Preserve the chosen search mode, stale-catalog flag, update timestamp, and holiday-schedule status for result guidance.
// Attributes:
// - data (List<NearbyPharmacy>): Retrieved pharmacy records.
// - searchMode (PharmacySearchMode): Pharmacy filter such as opening time or late-night service.
// - targetDateTime (DateTime): Reference timestamp for checking pharmacy opening status.
// - catalogUpdatedAt (DateTime?): Most recent pharmacy catalog update timestamp.
// - catalogIsStale (bool): Whether the pharmacy catalog exceeds its freshness limit.
// - holidayScheduleStatus (String): Verification status of holiday opening hours.
class NearbyPharmacySearchResult {
  final PharmacySearchArea? searchArea;
  final List<NearbyPharmacy> data;
  final PharmacySearchMode searchMode;
  final DateTime targetDateTime;
  final DateTime? catalogUpdatedAt;
  final bool catalogIsStale;
  final String holidayScheduleStatus;

  // Function Name: NearbyPharmacySearchResult
  // Description: Captures the pharmacy list together with effective search time, filter mode, and catalog freshness and holiday status.
  // Parameters:
  // - data (List<NearbyPharmacy>): Retrieved pharmacy records.
  // - searchMode (PharmacySearchMode): Pharmacy filter such as opening time or late-night service.
  // - targetDateTime (DateTime): Reference timestamp for checking pharmacy opening status.
  // - catalogUpdatedAt (DateTime?): Most recent pharmacy catalog update timestamp.
  // - catalogIsStale (bool): Whether the pharmacy catalog exceeds its freshness limit.
  // - holidayScheduleStatus (String): Verification status of holiday opening hours.
  // Returns:
  // - NearbyPharmacySearchResult: the initialized instance.
  const NearbyPharmacySearchResult({
    this.searchArea,
    required this.data,
    required this.searchMode,
    required this.targetDateTime,
    required this.catalogUpdatedAt,
    required this.catalogIsStale,
    required this.holidayScheduleStatus,
  });
}
