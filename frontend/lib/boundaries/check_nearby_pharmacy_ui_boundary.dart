// 파일명: check_nearby_pharmacy_ui_boundary.dart
// 역할: 현재 위치 주변 약국 목록과 전화·길찾기 동작을 제공한다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../controls/check_nearby_pharmacy_control.dart';
import '../entities/nearby_pharmacy_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/device_location_service.dart';
import '../theme/medbuddy_theme.dart';

enum _PharmacyFilter { openNow, all }

const _refreshCooldownDuration = Duration(seconds: 10);

// 클래스명: CheckNearbyPharmacyUI
// 역할: 사용자가 현재 위치 주변의 운영 약국을 확인하게 한다.
// 주요 책임:
// - 위치 권한, 로딩, 빈 결과, 오류 상태를 구분해 안내한다.
// - 영업 중 약국 필터와 새로고침을 제공한다.
// - 약국별 전화 및 외부 지도 길찾기 요청을 Control에 전달한다.
class CheckNearbyPharmacyUI extends StatefulWidget {
  final UserSetting userSetting;
  final CheckNearbyPharmacy? control;

  const CheckNearbyPharmacyUI({
    super.key,
    required this.userSetting,
    this.control,
  });

  @override
  State<CheckNearbyPharmacyUI> createState() => _CheckNearbyPharmacyUIState();
}

class _CheckNearbyPharmacyUIState extends State<CheckNearbyPharmacyUI> {
  late final CheckNearbyPharmacy _control;
  late final bool _ownsControl;
  List<NearbyPharmacy> _pharmacies = const [];
  DeviceLocationFailure? _locationFailure;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isRefreshCoolingDown = false;
  Timer? _refreshCooldownTimer;
  _PharmacyFilter _filter = _PharmacyFilter.openNow;

  _NearbyPharmacyText get _text =>
      _NearbyPharmacyText(widget.userSetting.language);

  @override
  void initState() {
    super.initState();
    _ownsControl = widget.control == null;
    _control = widget.control ?? CheckNearbyPharmacy();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPharmacies());
  }

  @override
  void dispose() {
    _refreshCooldownTimer?.cancel();
    if (_ownsControl) {
      _control.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPharmacies() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = true;
      _locationFailure = null;
      _errorMessage = null;
    });
    try {
      final pharmacies = await _control.requestNearbyPharmacies();
      if (!mounted) {
        return;
      }
      setState(() => _pharmacies = pharmacies);
    } on DeviceLocationException catch (error) {
      if (mounted) {
        setState(() => _locationFailure = error.failure);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = _text.loadFailed;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 함수명: _requestRefresh
  // 역할: 연속 새로고침을 제한하고 허용된 경우에만 약국 목록을 다시 요청한다.
  Future<void> _requestRefresh() async {
    if (_isLoading) {
      _showActionFailure(_text.loadingAction);
      return;
    }
    if (_isRefreshCoolingDown) {
      _showActionFailure(_text.refreshLimited);
      return;
    }

    _isRefreshCoolingDown = true;
    _refreshCooldownTimer?.cancel();
    _refreshCooldownTimer = Timer(_refreshCooldownDuration, () {
      _isRefreshCoolingDown = false;
    });
    await _loadPharmacies();
  }

  List<NearbyPharmacy> get _visiblePharmacies {
    return switch (_filter) {
      _PharmacyFilter.openNow =>
        _pharmacies
            .where((pharmacy) => pharmacy.isOpenNow == true)
            .toList(growable: false),
      _PharmacyFilter.all => _pharmacies,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final text = _text;
    return Container(
      width: double.infinity,
      color: MedBuddyColors.topBar,
      padding: EdgeInsets.fromLTRB(
        18,
        MediaQuery.paddingOf(context).top + 14,
        18,
        20,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: text.back,
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  text.subtitle,
                  maxLines: 2,
                  style: TextStyle(
                    color: Color(0xFFE7FFF5),
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: text.refreshTooltip,
            onPressed: _requestRefresh,
            icon: const Icon(Icons.refresh, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final text = _text;
    if (_isLoading) {
      return _PharmacyLoadingState(message: text.findingNearby);
    }
    if (_locationFailure != null) {
      return _buildLocationFailure(_locationFailure!);
    }
    if (_errorMessage != null) {
      return _PharmacyMessageState(
        icon: Icons.cloud_off_outlined,
        title: text.unavailableTitle,
        message: _errorMessage!,
        actionLabel: text.retry,
        onAction: _requestRefresh,
      );
    }

    final visiblePharmacies = _visiblePharmacies;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<_PharmacyFilter>(
              segments: [
                ButtonSegment(
                  value: _PharmacyFilter.openNow,
                  label: Text(text.openNow),
                ),
                ButtonSegment(
                  value: _PharmacyFilter.all,
                  label: Text(text.all),
                ),
              ],
              selected: {_filter},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() => _filter = selection.first);
              },
            ),
          ),
        ),
        Expanded(
          child: visiblePharmacies.isEmpty
              ? _PharmacyMessageState(
                  icon: Icons.local_pharmacy_outlined,
                  title: switch (_filter) {
                    _PharmacyFilter.openNow => text.noOpenPharmacy,
                    _PharmacyFilter.all => text.noNearbyPharmacy,
                  },
                  message: _filter == _PharmacyFilter.all
                      ? text.checkLocation
                      : text.tryAllPharmacies,
                  actionLabel: _filter == _PharmacyFilter.all
                      ? text.refresh
                      : text.showAll,
                  onAction: _filter == _PharmacyFilter.all
                      ? _requestRefresh
                      : () => setState(() => _filter = _PharmacyFilter.all),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  itemCount: visiblePharmacies.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index == visiblePharmacies.length) {
                      return _PharmacySourceNotice(message: text.sourceNotice);
                    }
                    final pharmacy = visiblePharmacies[index];
                    return _PharmacyCard(
                      pharmacy: pharmacy,
                      text: text,
                      onPhoneRequested: pharmacy.telephone.isEmpty
                          ? null
                          : () => _requestPhoneCall(pharmacy),
                      onDirectionsRequested: () => _requestDirections(pharmacy),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLocationFailure(DeviceLocationFailure failure) {
    final text = _text;
    final (title, message, actionLabel, action) = switch (failure) {
      DeviceLocationFailure.serviceDisabled => (
        text.locationDisabledTitle,
        text.locationDisabledMessage,
        text.openLocationSettings,
        _openLocationSettings,
      ),
      DeviceLocationFailure.deniedForever => (
        text.locationBlockedTitle,
        text.locationBlockedMessage,
        text.openAppSettings,
        _openApplicationSettings,
      ),
      DeviceLocationFailure.denied => (
        text.locationPermissionTitle,
        text.locationPermissionMessage,
        text.requestAgain,
        _loadPharmacies,
      ),
      DeviceLocationFailure.unavailable => (
        text.locationUnavailableTitle,
        text.locationUnavailableMessage,
        text.retry,
        _loadPharmacies,
      ),
    };
    return _PharmacyMessageState(
      icon: Icons.location_off_outlined,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: action,
    );
  }

  Future<void> _openApplicationSettings() async {
    await _control.openApplicationSettings();
  }

  Future<void> _openLocationSettings() async {
    await _control.openDeviceLocationSettings();
  }

  Future<void> _requestPhoneCall(NearbyPharmacy pharmacy) async {
    if (!await _control.requestPhoneCall(pharmacy.telephone) && mounted) {
      _showActionFailure(_text.phoneAppFailed);
    }
  }

  Future<void> _requestDirections(NearbyPharmacy pharmacy) async {
    if (!await _control.requestDirections(pharmacy) && mounted) {
      _showActionFailure(_text.mapAppFailed);
    }
  }

  void _showActionFailure(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PharmacyLoadingState extends StatelessWidget {
  final String message;

  const _PharmacyLoadingState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: MedBuddyColors.primary),
          const SizedBox(height: 18),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MedBuddyColors.textBody,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _PharmacyMessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _PharmacyMessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 58, color: MedBuddyColors.textLight),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textSubtle,
                fontSize: 15,
                height: 1.5,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _PharmacyCard extends StatelessWidget {
  final NearbyPharmacy pharmacy;
  final _NearbyPharmacyText text;
  final VoidCallback? onPhoneRequested;
  final VoidCallback onDirectionsRequested;

  const _PharmacyCard({
    required this.pharmacy,
    required this.text,
    required this.onPhoneRequested,
    required this.onDirectionsRequested,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = pharmacy.isOpenNow == true
        ? MedBuddyColors.primaryDark
        : MedBuddyColors.textSubtle;
    final statusSurface = pharmacy.isOpenNow == true
        ? MedBuddyColors.successSurface
        : MedBuddyColors.surfaceSubtle;
    final statusLabel = switch (pharmacy.isOpenNow) {
      true => text.openNow,
      false => text.closed,
      null => text.hoursNeedCheck,
    };

    return Semantics(
      container: true,
      label: '${pharmacy.name}, $statusLabel, ${pharmacy.distanceLabel}',
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: MedBuddyRadii.card,
          border: Border.all(color: MedBuddyColors.outline),
          boxShadow: MedBuddyShadows.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    pharmacy.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 20,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusSurface,
                    borderRadius: MedBuddyRadii.pill,
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PharmacyInfoLine(
              icon: Icons.near_me_outlined,
              text: text.distance(pharmacy.distanceLabel),
            ),
            const SizedBox(height: 7),
            _PharmacyInfoLine(
              icon: Icons.schedule_outlined,
              text: text.todayHours(pharmacy),
            ),
            if (pharmacy.address.isNotEmpty) ...[
              const SizedBox(height: 7),
              _PharmacyInfoLine(
                icon: Icons.location_on_outlined,
                text: pharmacy.address,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPhoneRequested,
                    icon: const Icon(Icons.call_outlined),
                    label: Text(text.phone),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onDirectionsRequested,
                    icon: const Icon(Icons.directions_outlined),
                    label: Text(text.directions),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PharmacyInfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PharmacyInfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: MedBuddyColors.primary, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: MedBuddyColors.textBody,
              fontSize: 15,
              height: 1.4,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _PharmacySourceNotice extends StatelessWidget {
  final String message;

  const _PharmacySourceNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: MedBuddyColors.textSubtle,
          fontSize: 13,
          height: 1.45,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

// 클래스명: _NearbyPharmacyText
// 역할: 근처 약국 화면의 사용자 문구를 설정 언어에 맞게 제공한다.
class _NearbyPharmacyText {
  final String language;

  const _NearbyPharmacyText(this.language);

  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

  String get back => isEnglish ? 'Back' : '뒤로 가기';
  String get title => isEnglish ? 'Nearby Pharmacies' : '근처 운영 약국';
  String get subtitle => isEnglish
      ? 'Find pharmacies near your current location'
      : '현재 위치에서 가까운 약국을 확인하세요';
  String get refreshTooltip =>
      isEnglish ? 'Refresh pharmacy list' : '약국 목록 새로고침';
  String get loadFailed => isEnglish
      ? 'Could not load pharmacy information.\nPlease try again shortly.'
      : '약국 정보를 불러오지 못했습니다.\n잠시 후 다시 시도해주세요.';
  String get loadingAction =>
      isEnglish ? 'Pharmacy information is loading.' : '약국 정보를 불러오는 중입니다.';
  String get refreshLimited => isEnglish
      ? 'Too many refresh requests. Please try again shortly.'
      : '새로고침 요청이 많습니다. 잠시 후 다시 시도해주세요.';
  String get unavailableTitle =>
      isEnglish ? 'Pharmacy information is unavailable' : '약국 정보를 확인할 수 없습니다';
  String get retry => isEnglish ? 'Try again' : '다시 시도';
  String get openNow => isEnglish ? 'Open now' : '영업 중';
  String get all => isEnglish ? 'All' : '전체';
  String get noOpenPharmacy => isEnglish
      ? 'No open pharmacies were found within 20 km'
      : '20km 안에 영업 중인 약국이 없습니다';
  String get noNearbyPharmacy =>
      isEnglish ? 'No nearby pharmacies were found' : '주변 약국을 찾지 못했습니다';
  String get checkLocation => isEnglish
      ? 'Check your location and refresh the list.'
      : '위치를 확인한 뒤 목록을 새로고침해주세요.';
  String get tryAllPharmacies => isEnglish
      ? 'Switch to all pharmacies or try again shortly.'
      : '전체 약국으로 전환하거나 잠시 후 다시 확인해주세요.';
  String get refresh => isEnglish ? 'Refresh' : '새로고침';
  String get showAll => isEnglish ? 'Show all pharmacies' : '전체 약국 보기';
  String get locationDisabledTitle =>
      isEnglish ? 'Device location is turned off' : '기기 위치가 꺼져 있습니다';
  String get locationDisabledMessage => isEnglish
      ? 'Turn on device location to find pharmacies near you.'
      : '현재 위치에서 가까운 약국을 찾으려면 기기 위치를 켜주세요.';
  String get openLocationSettings =>
      isEnglish ? 'Open location settings' : '위치 설정 열기';
  String get locationBlockedTitle =>
      isEnglish ? 'Location permission is blocked' : '위치 권한이 차단되어 있습니다';
  String get locationBlockedMessage => isEnglish
      ? 'Allow MedBuddy to use location in the app settings.'
      : '앱 설정에서 MedBuddy의 위치 권한을 허용해주세요.';
  String get openAppSettings => isEnglish ? 'Open app settings' : '앱 설정 열기';
  String get locationPermissionTitle =>
      isEnglish ? 'Location permission is required' : '위치 권한이 필요합니다';
  String get locationPermissionMessage => isEnglish
      ? 'Location is used only to find nearby pharmacies and is not stored in the server database.'
      : '위치는 근처 약국을 찾을 때만 사용하며 서버 DB에 저장하지 않습니다.';
  String get requestAgain => isEnglish ? 'Request again' : '다시 요청';
  String get locationUnavailableTitle => isEnglish
      ? 'Could not determine your current location'
      : '현재 위치를 확인하지 못했습니다';
  String get locationUnavailableMessage => isEnglish
      ? 'Move briefly or try again where the location signal is stronger.'
      : '잠시 이동한 뒤 또는 위치 신호가 좋은 곳에서 다시 시도해주세요.';
  String get phoneAppFailed =>
      isEnglish ? 'Could not open the phone app.' : '전화 앱을 열 수 없습니다.';
  String get mapAppFailed =>
      isEnglish ? 'Could not open the map app.' : '지도 앱을 열 수 없습니다.';
  String get findingNearby => isEnglish
      ? 'Finding pharmacies near your current location'
      : '현재 위치 주변 약국을 찾고 있습니다';
  String get closed => isEnglish ? 'Closed' : '영업 종료';
  String get hoursNeedCheck => isEnglish ? 'Check opening hours' : '시간 확인 필요';
  String distance(String value) => isEnglish ? '$value away' : '$value 거리';
  String todayHours(NearbyPharmacy pharmacy) {
    if (pharmacy.is24Hours) {
      return isEnglish ? 'Open 24 hours' : '24시간 운영';
    }
    if (pharmacy.todayOpenTime == null || pharmacy.todayCloseTime == null) {
      return isEnglish ? 'Check today\'s opening hours' : '오늘 영업시간 확인 필요';
    }
    return isEnglish
        ? 'Today ${pharmacy.todayOpenTime} - ${pharmacy.todayCloseTime}'
        : '오늘 ${pharmacy.todayOpenTime} - ${pharmacy.todayCloseTime}';
  }

  String get phone => isEnglish ? 'Call' : '전화';
  String get directions => isEnglish ? 'Directions' : '길찾기';
  String get sourceNotice => isEnglish
      ? 'Information is based on National Medical Center public data. Call before visiting to confirm actual opening hours.'
      : '국립중앙의료원 공공데이터를 기준으로 표시합니다. 방문 전 전화로 실제 운영 여부를 확인해주세요.';
}
