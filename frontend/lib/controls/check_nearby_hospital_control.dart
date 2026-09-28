// 병원 검색의 진료과목 조건을 공통 위치·지도 조회 흐름에 연결한다.
import '../services/api_config.dart';
import 'check_nearby_pharmacy_control.dart';

class CheckNearbyHospital extends CheckNearbyPharmacy {
  String? department;

  CheckNearbyHospital({
    this.department,
    super.locationBoundary,
    super.client,
    super.uriLauncher,
    super.clipboardWriter,
  });

  @override
  String get nearbySearchUrl => ApiConfig.hospitalUrl('/nearby');

  // 전체 진료과목은 조건을 보내지 않고, 선택한 과목만 서버에서 필터링한다.
  @override
  Map<String, String> get additionalSearchParameters => {
    if (department != null && department!.isNotEmpty) 'department': department!,
  };
}
