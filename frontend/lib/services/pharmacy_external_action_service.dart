// 파일명: pharmacy_external_action_service.dart
// 역할: 약국 전화와 외부 지도 길찾기 실행을 한곳에서 담당한다.

import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

typedef PharmacyUriLauncher = Future<bool> Function(Uri uri);
typedef PharmacyClipboardWriter = Future<void> Function(String text);

// 클래스명: PharmacyExternalActionService
// 역할:
// - 약국 화면과 채팅 카드가 같은 전화·길찾기 규칙을 재사용하게 한다.
class PharmacyExternalActionService {
  final PharmacyUriLauncher _uriLauncher;
  final PharmacyClipboardWriter _clipboardWriter;

  PharmacyExternalActionService({
    PharmacyUriLauncher? uriLauncher,
    PharmacyClipboardWriter? clipboardWriter,
  }) : _uriLauncher =
           uriLauncher ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication)),
       _clipboardWriter =
           clipboardWriter ??
           ((text) => Clipboard.setData(ClipboardData(text: text)));

  // 함수명: _tryLaunch
  // 역할: 외부 앱이 없거나 플랫폼 호출이 실패해도 화면까지 예외가 전파되지 않게 한다.
  Future<bool> _tryLaunch(Uri uri) async {
    try {
      return await _uriLauncher(uri);
    } catch (_) {
      return false;
    }
  }

  // 함수명: requestPhoneCall
  // 역할: 공공데이터 전화번호를 정규화한 뒤 시스템 전화 앱을 연다.
  // 매개변수: telephone - 약국 전화번호 원문
  // 반환값: 전화 앱 실행 요청의 성공 여부
  Future<bool> requestPhoneCall(String telephone) {
    final normalized = telephone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.isEmpty) {
      return Future.value(false);
    }
    return _tryLaunch(Uri(scheme: 'tel', path: normalized));
  }

  // 함수명: requestDirections
  // 역할: 설치된 지도 앱 선택을 먼저 요청하고 실패하면 Google 웹 지도로 보완한다.
  // 매개변수: name, latitude, longitude - 목적지 약국 이름과 좌표
  // 반환값: 길찾기 앱 또는 웹 지도 실행 요청의 성공 여부
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

  // 함수명: requestInstalledMapDirections
  // 역할: Android의 표준 지도 URI를 사용해 설치된 지도 앱 선택 화면을 연다.
  // 매개변수: name, latitude, longitude - 목적지 약국 이름과 좌표
  // 반환값: 지도 앱 선택 요청의 성공 여부
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

  // 함수명: requestGoogleMapDirections
  // 역할: 지도 앱이 없어도 브라우저에서 열 수 있는 Google 길찾기를 요청한다.
  // 매개변수: latitude, longitude - 목적지 약국 좌표
  // 반환값: Google 지도 또는 브라우저 실행 요청의 성공 여부
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

  // 함수명: copyAddress
  // 역할: 약국 주소를 다른 지도나 메모 앱에 붙여넣을 수 있도록 복사한다.
  // 매개변수: address - 복사할 주소 또는 좌표 안내문
  // 반환값: 클립보드 저장 성공 여부
  Future<bool> copyAddress(String address) async {
    try {
      await _clipboardWriter(address);
      return true;
    } catch (_) {
      return false;
    }
  }

  // 함수명: requestMapAttribution
  // 역할: 앱 내 지도 제공자인 네이버 지도의 안내 페이지를 외부 브라우저로 연다.
  // 매개변수: 없음
  // 반환값: 브라우저 실행 요청의 성공 여부
  Future<bool> requestMapAttribution() {
    return _tryLaunch(Uri.https('map.naver.com', '/'));
  }
}
