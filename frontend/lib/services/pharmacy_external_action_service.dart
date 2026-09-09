// 파일명: pharmacy_external_action_service.dart
// 역할: 약국 전화와 외부 지도 길찾기 실행을 한곳에서 담당한다.

import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

// 함수이름: PharmacyUriLauncher
// 함수역할: 전화·지도·출처 URI를 외부 앱에 전달하고 실행 성공 여부를 비동기로 제공하는 계약이다.
// 매개변수:
// - uri (Uri): 검증하거나 외부 앱으로 열 대상 URI
// 반환값:
// - Future<bool>: 전화·지도·출처 URI를 외부 앱에 전달하고 실행 성공 여부를 비동기로 제공하는 계약이다.
typedef PharmacyUriLauncher = Future<bool> Function(Uri uri);
// 함수이름: PharmacyClipboardWriter
// 함수역할: 약국 주소 등 전달받은 문자열을 기기 클립보드에 기록하는 비동기 계약이다.
// 매개변수:
// - text (String): 인식·정규화·마스킹·읽기에 사용할 문구
// 반환값:
// - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
typedef PharmacyClipboardWriter = Future<void> Function(String text);

// 클래스명: PharmacyExternalActionService
// 역할: 약국 화면과 채팅 카드가 공유할 전화·길찾기·주소 복사 경계이다.
// 주요 책임:
// - 전화번호와 지도 URI를 정리하고 설치 앱 실패 시 웹 지도로 보완하며 플랫폼 오류를 성공 여부로 변환한다.
// 속성:
// - _uriLauncher (PharmacyUriLauncher): 외부 전화·지도 앱 실행 경계
// - _clipboardWriter (PharmacyClipboardWriter): 기기 클립보드에 텍스트를 기록할 경계
class PharmacyExternalActionService {
  final PharmacyUriLauncher _uriLauncher;
  final PharmacyClipboardWriter _clipboardWriter;

  // 함수이름: PharmacyExternalActionService
  // 함수역할: 외부 URI 실행과 클립보드 기록 경계를 주입하거나 운영체제 기본 구현으로 구성한다.
  // 매개변수:
  // - uriLauncher (PharmacyUriLauncher?): 외부 전화·지도 앱 실행 경계
  // - clipboardWriter (PharmacyClipboardWriter?): 기기 클립보드에 텍스트를 기록할 경계
  // 반환값:
  // - PharmacyExternalActionService: 초기화된 인스턴스.
  PharmacyExternalActionService({
    PharmacyUriLauncher? uriLauncher,
    PharmacyClipboardWriter? clipboardWriter,
  }) : _uriLauncher =
           uriLauncher ??
           (/* 함수이름: callback 콜백
            * 함수역할: 전화 또는 지도 URI를 외부 애플리케이션으로 연다.
            * 매개변수:
            * - uri (Uri): 검증하거나 외부 앱으로 열 대상 URI
            * 반환값:
            * - 외부 앱 실행 성공 여부를 완료하는 Future.
            */(uri) => launchUrl(uri, mode: LaunchMode.externalApplication)),
       _clipboardWriter =
           clipboardWriter ??
           (/* 함수이름: callback 콜백
            * 함수역할: 약국 주소 등의 텍스트를 시스템 클립보드에 기록한다.
            * 매개변수:
            * - text (String): 인식·정규화·마스킹·읽기에 사용할 문구
            * 반환값:
            * - 클립보드 기록 완료 Future.
            */(text) => Clipboard.setData(ClipboardData(text: text)));

  // 함수이름: _tryLaunch
  // 함수역할: 외부 앱이 없거나 플랫폼 호출이 실패해도 화면까지 예외가 전파되지 않게 한다.
  // 매개변수:
  // - uri (Uri): 검증하거나 외부 앱으로 열 대상 URI
  // 반환값:
  // - Future<bool>: 외부 앱이 없거나 플랫폼 호출이 실패해도 화면까지 예외가 전파되지 않게 한다.
  Future<bool> _tryLaunch(Uri uri) async {
    try {
      return await _uriLauncher(uri);
    } catch (_) {
      return false;
    }
  }

  // 함수이름: requestPhoneCall
  // 함수역할: 공공데이터 전화번호를 정규화한 뒤 시스템 전화 앱을 연다.
  // 매개변수:
  // - telephone (String): 약국 전화번호 원문
  // 반환값:
  // - 전화 앱 실행 요청의 성공 여부
  Future<bool> requestPhoneCall(String telephone) {
    final normalized = telephone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.isEmpty) {
      return Future.value(false);
    }
    return _tryLaunch(Uri(scheme: 'tel', path: normalized));
  }

  // 함수이름: requestDirections
  // 함수역할: 설치된 지도 앱 선택을 먼저 요청하고 실패하면 Google 웹 지도로 보완한다.
  // 매개변수:
  // - name (String): 표시하거나 길찾기에 사용할 약국 이름
  // - latitude (double): WGS84 위도(도 단위)
  // - longitude (double): WGS84 경도(도 단위)
  // 반환값:
  // - 길찾기 앱 또는 웹 지도 실행 요청의 성공 여부
  Future<bool> requestDirections({
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    if (await requestInstalledMapDirections(
      name: name,
      latitude: latitude,
      longitude: longitude,
    )) {
      return true;
    }
    return requestGoogleMapDirections(latitude: latitude, longitude: longitude);
  }

  // 함수이름: requestInstalledMapDirections
  // 함수역할: Android의 표준 지도 URI를 사용해 설치된 지도 앱 선택 화면을 연다.
  // 매개변수:
  // - name (String): 표시하거나 길찾기에 사용할 약국 이름
  // - latitude (double): WGS84 위도(도 단위)
  // - longitude (double): WGS84 경도(도 단위)
  // 반환값:
  // - 지도 앱 선택 요청의 성공 여부
  Future<bool> requestInstalledMapDirections({
    required String name,
    required double latitude,
    required double longitude,
  }) {
    final coordinate =
        '${latitude.toStringAsFixed(7)},${longitude.toStringAsFixed(7)}';
    final destination = Uri.encodeComponent('$coordinate($name)');
    return _tryLaunch(Uri.parse('geo:$coordinate?q=$destination'));
  }

  // 함수이름: requestGoogleMapDirections
  // 함수역할: 지도 앱이 없어도 브라우저에서 열 수 있는 Google 길찾기를 요청한다.
  // 매개변수:
  // - latitude (double): WGS84 위도(도 단위)
  // - longitude (double): WGS84 경도(도 단위)
  // 반환값:
  // - Google 지도 또는 브라우저 실행 요청의 성공 여부
  Future<bool> requestGoogleMapDirections({
    required double latitude,
    required double longitude,
  }) {
    final coordinate = '$latitude,$longitude';
    return _tryLaunch(
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': coordinate,
      }),
    );
  }

  // 함수이름: copyAddress
  // 함수역할: 약국 주소를 다른 지도나 메모 앱에 붙여넣을 수 있도록 복사한다.
  // 매개변수:
  // - address (String): 복사하거나 표시할 약국 주소
  // 반환값:
  // - 클립보드 저장 성공 여부
  Future<bool> copyAddress(String address) async {
    try {
      await _clipboardWriter(address);
      return true;
    } catch (_) {
      return false;
    }
  }

  // 함수이름: requestMapAttribution
  // 함수역할: 앱 내 지도 제공자인 네이버 지도의 안내 페이지를 외부 브라우저로 연다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 브라우저 실행 요청의 성공 여부
  Future<bool> requestMapAttribution() {
    return _tryLaunch(Uri.https('map.naver.com', '/'));
  }
}
