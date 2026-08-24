// 파일명: pharmacy_external_action_service.dart
// 역할: 약국 전화와 외부 지도 길찾기 실행을 한곳에서 담당한다.

import 'package:url_launcher/url_launcher.dart';

typedef PharmacyUriLauncher = Future<bool> Function(Uri uri);

// 클래스명: PharmacyExternalActionService
// 역할:
// - 약국 화면과 채팅 카드가 같은 전화·길찾기 규칙을 재사용하게 한다.
class PharmacyExternalActionService {
  final PharmacyUriLauncher _uriLauncher;

  PharmacyExternalActionService({PharmacyUriLauncher? uriLauncher})
    : _uriLauncher =
          uriLauncher ??
          ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  // 함수명: requestPhoneCall
  // 역할: 공공데이터 전화번호를 정규화한 뒤 시스템 전화 앱을 연다.
  // 매개변수: telephone - 약국 전화번호 원문
  // 반환값: 전화 앱 실행 요청의 성공 여부
  Future<bool> requestPhoneCall(String telephone) {
    final normalized = telephone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.isEmpty) {
      return Future.value(false);
    }
    return _uriLauncher(Uri(scheme: 'tel', path: normalized));
  }

  // 함수명: requestDirections
  // 역할: 약국 좌표를 검증된 네이버 지도 URI로 열고 실패하면 웹 지도로 보완한다.
  // 매개변수: name, latitude, longitude - 목적지 약국 이름과 좌표
  // 반환값: 길찾기 앱 또는 웹 지도 실행 요청의 성공 여부
  Future<bool> requestDirections({
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    final coordinate = '$latitude,$longitude';
    final naverMapsUri = Uri(
      scheme: 'nmap',
      host: 'route',
      path: '/public',
      queryParameters: {
        'dlat': latitude.toStringAsFixed(7),
        'dlng': longitude.toStringAsFixed(7),
        'dname': name,
        'appname': 'com.medbuddy.app',
      },
    );
    if (await _uriLauncher(naverMapsUri)) {
      return true;
    }
    return _uriLauncher(
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': coordinate,
      }),
    );
  }

  // 함수명: requestMapAttribution
  // 역할: 앱 내 지도 제공자인 네이버 지도의 안내 페이지를 외부 브라우저로 연다.
  // 매개변수: 없음
  // 반환값: 브라우저 실행 요청의 성공 여부
  Future<bool> requestMapAttribution() {
    return _uriLauncher(Uri.https('map.naver.com', '/'));
  }
}
