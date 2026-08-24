// 파일명: check_nearby_pharmacy_ui_boundary.dart
// 역할: 현재 위치 주변 약국 목록과 전화·길찾기 동작을 제공한다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../controls/check_nearby_pharmacy_control.dart';
import '../entities/nearby_pharmacy_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/device_location_service.dart';
import '../services/pharmacy_favorite_service.dart';
import '../theme/medbuddy_theme.dart';
import 'nearby_pharmacy_map_widget.dart';

enum _PharmacyFilter {
  openNow,
  officialLateNight,
  lateHours,
  weekendHoliday,
  all,
}

const _refreshCooldownDuration = Duration(seconds: 10);

// 클래스명: NearbyPharmacySelection
// 역할: 채팅에 공유할 약국과 사용자의 전화 확인 여부를 함께 반환한다.
class NearbyPharmacySelection {
  final NearbyPharmacy pharmacy;
  final bool phoneVerified;

  const NearbyPharmacySelection({
    required this.pharmacy,
    required this.phoneVerified,
  });
}

// 타입명: NearbyPharmacyMapBuilder
// 역할: 지도 구현을 화면의 목록·필터 로직과 분리하고 테스트 대체 지점을 제공한다.
typedef NearbyPharmacyMapBuilder =
    Widget Function({
      required List<NearbyPharmacy> pharmacies,
      required String? selectedPharmacyId,
      required ValueChanged<NearbyPharmacy> onPharmacySelected,
      required VoidCallback onAttributionRequested,
      required String? statusText,
      required String selectMarkerHint,
      required String zoomInTooltip,
      required String zoomOutTooltip,
      required String configurationUnavailableText,
      required String unavailableText,
    });

// 클래스명: CheckNearbyPharmacyUI
// 역할: 사용자가 현재 위치 주변의 운영 약국을 확인하게 한다.
// 주요 책임:
// - 위치 권한, 로딩, 빈 결과, 오류 상태를 구분해 안내한다.
// - 영업 중 약국 필터와 새로고침을 제공한다.
// - 약국별 전화 및 외부 지도 길찾기 요청을 Control에 전달한다.
class CheckNearbyPharmacyUI extends StatefulWidget {
  final UserSetting userSetting;
  final CheckNearbyPharmacy? control;
  final NearbyPharmacyMapBuilder? mapBuilder;
  final PharmacyFavoriteService? favoriteService;
  final bool selectionMode;

  const CheckNearbyPharmacyUI({
    super.key,
    required this.userSetting,
    this.control,
    this.mapBuilder,
    this.favoriteService,
  }) : selectionMode = false;

  // 생성자명: CheckNearbyPharmacyUI.selection
  // 역할: 채팅에 공유할 약국을 고르는 동안에도 지도, 전화와 길찾기를 재사용한다.
  const CheckNearbyPharmacyUI.selection({
    super.key,
    required this.userSetting,
    this.control,
    this.mapBuilder,
    this.favoriteService,
  }) : selectionMode = true;

  @override
  State<CheckNearbyPharmacyUI> createState() => _CheckNearbyPharmacyUIState();
}

class _CheckNearbyPharmacyUIState extends State<CheckNearbyPharmacyUI> {
  late final CheckNearbyPharmacy _control;
  late final bool _ownsControl;
  late final PharmacyFavoriteService _favoriteService;
  List<NearbyPharmacy> _pharmacies = const [];
  Set<String> _favoritePharmacyIds = const {};
  DeviceLocationFailure? _locationFailure;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isRefreshCoolingDown = false;
  Timer? _refreshCooldownTimer;
  _PharmacyFilter _filter = _PharmacyFilter.openNow;
  String? _selectedPharmacyId;
  DateTime _targetDateTime = DateTime.now();
  bool _catalogIsStale = false;
  String _holidayScheduleStatus = 'not_applicable';
  DateTime? _lastRefreshedAt;
  bool _selectedPhoneVerified = false;

  _NearbyPharmacyText get _text =>
      _NearbyPharmacyText(widget.userSetting.language);

  @override
  void initState() {
    super.initState();
    _ownsControl = widget.control == null;
    _control = widget.control ?? CheckNearbyPharmacy();
    _favoriteService =
        widget.favoriteService ??
        PharmacyFavoriteService(userHash: widget.userSetting.userHash);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadFavorites());
      unawaited(_loadPharmacies());
    });
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
      final result = await _control.requestNearbyPharmacySearch(
        searchMode: _searchModeForFilter(_filter),
        targetDateTime: _targetDateTime,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _pharmacies = result.data;
        _catalogIsStale = result.catalogIsStale;
        _holidayScheduleStatus = result.holidayScheduleStatus;
        final selectedStillExists = result.data.any(
          (pharmacy) => pharmacy.pharmacyId == _selectedPharmacyId,
        );
        if (!selectedStillExists) {
          _selectedPharmacyId = null;
          _selectedPhoneVerified = false;
        }
        _lastRefreshedAt = DateTime.now();
      });
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
    if (_filter == _PharmacyFilter.openNow) {
      _targetDateTime = DateTime.now();
    }
    _refreshCooldownTimer?.cancel();
    _refreshCooldownTimer = Timer(_refreshCooldownDuration, () {
      _isRefreshCoolingDown = false;
    });
    await _loadPharmacies();
  }

  List<NearbyPharmacy> get _visiblePharmacies {
    final visiblePharmacies = List<NearbyPharmacy>.of(_pharmacies);
    visiblePharmacies.sort((left, right) {
      final leftFavorite = _favoritePharmacyIds.contains(left.pharmacyId);
      final rightFavorite = _favoritePharmacyIds.contains(right.pharmacyId);
      if (leftFavorite != rightFavorite) {
        return leftFavorite ? -1 : 1;
      }
      return left.distanceKm.compareTo(right.distanceKm);
    });
    return visiblePharmacies;
  }

  Future<void> _loadFavorites() async {
    final favoriteIds = await _favoriteService.loadFavoriteIds();
    if (mounted) {
      setState(() => _favoritePharmacyIds = favoriteIds);
    }
  }

  Future<void> _toggleFavorite(NearbyPharmacy pharmacy) async {
    final updatedIds = Set<String>.of(_favoritePharmacyIds);
    final isFavorite = updatedIds.remove(pharmacy.pharmacyId);
    if (!isFavorite) {
      updatedIds.add(pharmacy.pharmacyId);
    }
    setState(() => _favoritePharmacyIds = updatedIds);
    if (!await _favoriteService.saveFavoriteIds(updatedIds) && mounted) {
      final restoredIds = Set<String>.of(_favoritePharmacyIds);
      if (isFavorite) {
        restoredIds.add(pharmacy.pharmacyId);
      } else {
        restoredIds.remove(pharmacy.pharmacyId);
      }
      setState(() => _favoritePharmacyIds = restoredIds);
      _showActionFailure(_text.favoriteSaveFailed);
    }
  }

  PharmacySearchMode _searchModeForFilter(_PharmacyFilter filter) {
    return switch (filter) {
      _PharmacyFilter.openNow => PharmacySearchMode.openAtTime,
      _PharmacyFilter.officialLateNight => PharmacySearchMode.officialLateNight,
      _PharmacyFilter.lateHours => PharmacySearchMode.lateHours,
      _PharmacyFilter.weekendHoliday => PharmacySearchMode.weekendHoliday,
      _PharmacyFilter.all => PharmacySearchMode.all,
    };
  }

  Future<void> _selectFilter(_PharmacyFilter nextFilter) async {
    setState(() {
      _filter = nextFilter;
      _selectedPharmacyId = null;
      if (nextFilter == _PharmacyFilter.openNow) {
        _targetDateTime = DateTime.now();
      }
    });
    await _loadPharmacies();
  }

  // 함수명: _showFilterPicker
  // 역할: 여러 조회 조건을 한곳에 모아 현재 조건을 명확하게 선택하게 한다.
  Future<void> _showFilterPicker() async {
    final selectedFilter = await showModalBottomSheet<_PharmacyFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.78,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _text.filterPickerTitle,
                            style: const TextStyle(
                              color: MedBuddyColors.textStrong,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _text.filterPickerDescription,
                            style: const TextStyle(
                              color: MedBuddyColors.textMuted,
                              fontSize: 14,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: _text.close,
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _PharmacyFilter.values.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final filter = _PharmacyFilter.values[index];
                    final isSelected = filter == _filter;
                    return Semantics(
                      selected: isSelected,
                      button: true,
                      child: Material(
                        color: isSelected
                            ? MedBuddyColors.successSurface
                            : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected
                                ? MedBuddyColors.primary
                                : MedBuddyColors.outline,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: InkWell(
                          key: ValueKey(
                            'pharmacy-filter-option-${filter.name}',
                          ),
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => Navigator.pop(sheetContext, filter),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: isSelected
                                      ? MedBuddyColors.primary
                                      : MedBuddyColors.textSubtle,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _filterLabel(filter),
                                        style: const TextStyle(
                                          color: MedBuddyColors.textStrong,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _text.filterDescription(filter),
                                        style: const TextStyle(
                                          color: MedBuddyColors.textMuted,
                                          fontSize: 14,
                                          height: 1.35,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || selectedFilter == null || selectedFilter == _filter) {
      return;
    }
    await _selectFilter(selectedFilter);
  }

  String _filterLabel(_PharmacyFilter filter) {
    return switch (filter) {
      _PharmacyFilter.openNow => _text.openFilter,
      _PharmacyFilter.officialLateNight => _text.officialLateNight,
      _PharmacyFilter.lateHours => _text.lateHours,
      _PharmacyFilter.weekendHoliday => _text.weekendHoliday,
      _PharmacyFilter.all => _text.allPharmacies,
    };
  }

  Future<void> _pickSearchDate() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _targetDateTime,
      firstDate: today.subtract(const Duration(days: 7)),
      lastDate: today.add(const Duration(days: 366)),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _targetDateTime = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _filter == _PharmacyFilter.openNow ? today.hour : 12,
        _filter == _PharmacyFilter.openNow ? today.minute : 0,
      );
    });
    await _loadPharmacies();
  }

  Future<void> _pickSearchTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_targetDateTime),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _targetDateTime = DateTime(
        _targetDateTime.year,
        _targetDateTime.month,
        _targetDateTime.day,
        selected.hour,
        selected.minute,
      );
    });
    await _loadPharmacies();
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
        if (visiblePharmacies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: _buildPharmacyMap(visiblePharmacies),
          ),
        if (_lastRefreshedAt != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.update_outlined,
                  size: 17,
                  color: MedBuddyColors.textSubtle,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    text.refreshedAt(_lastRefreshedAt!),
                    style: const TextStyle(
                      color: MedBuddyColors.textSubtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                Text(
                  text.callBeforeVisit,
                  style: const TextStyle(
                    color: MedBuddyColors.primaryDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            visiblePharmacies.isEmpty ? 18 : 2,
            20,
            10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickSearchDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(text.searchDate(_targetDateTime)),
                  ),
                  if (_filter == _PharmacyFilter.openNow)
                    OutlinedButton.icon(
                      onPressed: _pickSearchTime,
                      icon: const Icon(Icons.schedule_outlined),
                      label: Text(text.searchTime(_targetDateTime)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('pharmacy-filter-selector'),
                  onPressed: _showFilterPicker,
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    side: const BorderSide(color: MedBuddyColors.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.filter_alt_outlined,
                        color: MedBuddyColors.primaryDark,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          text.selectedFilter(_filterLabel(_filter)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MedBuddyColors.textStrong,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        color: MedBuddyColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: visiblePharmacies.isEmpty
              ? _PharmacyMessageState(
                  icon: Icons.local_pharmacy_outlined,
                  title: switch (_filter) {
                    _PharmacyFilter.openNow => text.noOpenPharmacy,
                    _PharmacyFilter.officialLateNight =>
                      text.noOfficialLateNightPharmacy,
                    _PharmacyFilter.lateHours => text.noLateNightPharmacy,
                    _PharmacyFilter.weekendHoliday =>
                      text.noWeekendHolidayPharmacy,
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
                      : () => _selectFilter(_PharmacyFilter.all),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  itemCount: visiblePharmacies.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index == visiblePharmacies.length) {
                      return _PharmacySourceNotice(
                        message: text.sourceNotice(
                          catalogIsStale: _catalogIsStale,
                          holidayScheduleStatus: _holidayScheduleStatus,
                        ),
                      );
                    }
                    final pharmacy = visiblePharmacies[index];
                    return _PharmacyCard(
                      pharmacy: pharmacy,
                      text: text,
                      isSelected: pharmacy.pharmacyId == _selectedPharmacyId,
                      isFavorite: _favoritePharmacyIds.contains(
                        pharmacy.pharmacyId,
                      ),
                      onSelected: () => _selectPharmacy(pharmacy),
                      onFavoriteRequested: () => _toggleFavorite(pharmacy),
                      onPhoneRequested: pharmacy.telephone.isEmpty
                          ? null
                          : () => _requestPhoneCall(pharmacy),
                      onDirectionsRequested: () => _requestDirections(pharmacy),
                    );
                  },
                ),
        ),
        if (widget.selectionMode && _selectedPharmacyId != null)
          _buildSelectionFooter(visiblePharmacies),
      ],
    );
  }

  Widget _buildSelectionFooter(List<NearbyPharmacy> visiblePharmacies) {
    final selectedPharmacy = _findSelectedPharmacy(visiblePharmacies);
    if (selectedPharmacy == null) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.white,
      elevation: 10,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selectedPharmacy.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              CheckboxListTile(
                value: _selectedPhoneVerified,
                onChanged: (value) {
                  setState(() => _selectedPhoneVerified = value == true);
                },
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(_text.phoneVerified),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      NearbyPharmacySelection(
                        pharmacy: selectedPharmacy,
                        phoneVerified: _selectedPhoneVerified,
                      ),
                    );
                  },
                  icon: const Icon(Icons.send_outlined),
                  label: Text(_text.shareInChat),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPharmacyMap(List<NearbyPharmacy> pharmacies) {
    final text = _text;
    final selectedPharmacy = _findSelectedPharmacy(pharmacies);
    final statusText = selectedPharmacy == null ? text.mapInstruction : null;
    final mapBuilder = widget.mapBuilder;
    if (mapBuilder != null) {
      return mapBuilder(
        pharmacies: pharmacies,
        selectedPharmacyId: _selectedPharmacyId,
        onPharmacySelected: _selectPharmacy,
        onAttributionRequested: _requestMapAttribution,
        statusText: statusText,
        selectMarkerHint: text.selectMarkerHint,
        zoomInTooltip: text.zoomInTooltip,
        zoomOutTooltip: text.zoomOutTooltip,
        configurationUnavailableText: text.mapConfigurationUnavailable,
        unavailableText: text.mapUnavailable,
      );
    }
    return NearbyPharmacyMap(
      pharmacies: pharmacies,
      selectedPharmacyId: _selectedPharmacyId,
      onPharmacySelected: _selectPharmacy,
      onAttributionRequested: _requestMapAttribution,
      statusText: statusText,
      selectMarkerHint: text.selectMarkerHint,
      zoomInTooltip: text.zoomInTooltip,
      zoomOutTooltip: text.zoomOutTooltip,
      configurationUnavailableText: text.mapConfigurationUnavailable,
      unavailableText: text.mapUnavailable,
    );
  }

  NearbyPharmacy? _findSelectedPharmacy(List<NearbyPharmacy> pharmacies) {
    for (final pharmacy in pharmacies) {
      if (pharmacy.pharmacyId == _selectedPharmacyId) {
        return pharmacy;
      }
    }
    return null;
  }

  void _selectPharmacy(NearbyPharmacy pharmacy) {
    setState(() {
      if (_selectedPharmacyId != pharmacy.pharmacyId) {
        _selectedPhoneVerified = false;
      }
      _selectedPharmacyId = pharmacy.pharmacyId;
    });
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

  Future<void> _requestMapAttribution() async {
    if (!await _control.requestMapAttribution() && mounted) {
      _showActionFailure(_text.mapAttributionFailed);
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
  final bool isSelected;
  final bool isFavorite;
  final VoidCallback onSelected;
  final VoidCallback onFavoriteRequested;
  final VoidCallback? onPhoneRequested;
  final VoidCallback onDirectionsRequested;

  const _PharmacyCard({
    required this.pharmacy,
    required this.text,
    required this.isSelected,
    required this.isFavorite,
    required this.onSelected,
    required this.onFavoriteRequested,
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
    final operatingStatusDetail = text.operatingStatusDetail(pharmacy);

    return Semantics(
      container: true,
      button: true,
      selected: isSelected,
      label: '${pharmacy.name}, $statusLabel, ${pharmacy.distanceLabel}',
      hint: text.showOnMap,
      child: Material(
        key: ValueKey('pharmacy-card-${pharmacy.pharmacyId}'),
        color: isSelected ? MedBuddyColors.successSurface : Colors.white,
        elevation: isSelected ? 2 : 1,
        shadowColor: Colors.black.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: MedBuddyRadii.card,
          side: BorderSide(
            color: isSelected ? MedBuddyColors.primary : MedBuddyColors.outline,
            width: isSelected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelected,
          child: Padding(
            padding: const EdgeInsets.all(18),
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
                    IconButton(
                      tooltip: isFavorite
                          ? text.removeFavorite
                          : text.addFavorite,
                      onPressed: onFavoriteRequested,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        isFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: isFavorite
                            ? const Color(0xFFF2A900)
                            : MedBuddyColors.textSubtle,
                      ),
                    ),
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
                if (operatingStatusDetail != null) ...[
                  const SizedBox(height: 7),
                  _PharmacyInfoLine(
                    icon: pharmacy.isOpenNow == true
                        ? Icons.timer_outlined
                        : Icons.event_available_outlined,
                    text: operatingStatusDetail,
                  ),
                ],
                if (pharmacy.isOfficialLateNight ||
                    pharmacy.isOpenLate ||
                    pharmacy.hasWeekendOrHolidayHours) ...[
                  const SizedBox(height: 7),
                  _PharmacyInfoLine(
                    icon: Icons.nightlight_outlined,
                    text: text.scheduleTags(pharmacy),
                  ),
                ],
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
  String get openFilter => isEnglish ? 'Open at selected time' : '선택 시각에 영업';
  String get officialLateNight =>
      isEnglish ? 'Official late-night pharmacy' : '공공심야약국';
  String get lateHours => isEnglish ? 'Open late' : '늦게까지 영업';
  String get weekendHoliday =>
      isEnglish ? 'Open on weekends / holidays' : '주말·공휴일 영업';
  String get all => isEnglish ? 'All' : '전체';
  String get allPharmacies => isEnglish ? 'All pharmacies' : '전체 약국';
  String get close => isEnglish ? 'Close' : '닫기';
  String get filterPickerTitle => isEnglish ? 'Search filter' : '조회 조건';
  String get filterPickerDescription => isEnglish
      ? 'Choose one condition for the pharmacy list.'
      : '약국 목록에 적용할 조건을 하나 선택해주세요.';
  String selectedFilter(String label) =>
      isEnglish ? 'Search filter: $label' : '조회 조건: $label';
  String filterDescription(_PharmacyFilter filter) {
    return switch (filter) {
      _PharmacyFilter.openNow =>
        isEnglish
            ? 'Find pharmacies open at the selected date and time.'
            : '선택한 날짜와 시간에 문을 여는 약국을 찾습니다.',
      _PharmacyFilter.officialLateNight =>
        isEnglish
            ? 'Find officially designated public late-night pharmacies.'
            : '공식 지정된 공공심야약국을 찾습니다.',
      _PharmacyFilter.lateHours =>
        isEnglish
            ? 'Find pharmacies with reported late operating hours.'
            : '등록된 운영시간을 기준으로 늦게까지 여는 약국을 찾습니다.',
      _PharmacyFilter.weekendHoliday =>
        isEnglish
            ? 'Find pharmacies operating on the selected weekend or holiday.'
            : '선택한 주말이나 공휴일에 운영하는 약국을 찾습니다.',
      _PharmacyFilter.all =>
        isEnglish
            ? 'Show every nearby pharmacy regardless of operating hours.'
            : '운영시간과 관계없이 주변 약국을 모두 표시합니다.',
    };
  }

  String get noOpenPharmacy => isEnglish
      ? 'No open pharmacies were found within 20 km'
      : '20km 안에 영업 중인 약국이 없습니다';
  String get noLateNightPharmacy => isEnglish
      ? 'No late-night pharmacies were found within 20 km'
      : '20km 안에 심야 운영 약국이 없습니다';
  String get noOfficialLateNightPharmacy => isEnglish
      ? 'No officially designated late-night pharmacies were found within 20 km'
      : '20km 안에 공식 지정 공공심야약국이 없습니다';
  String get noWeekendHolidayPharmacy => isEnglish
      ? 'No pharmacies with weekend or holiday hours were found within 20 km'
      : '20km 안에 주말·공휴일 운영 약국이 없습니다';
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
  String get mapAttributionFailed => isEnglish
      ? 'Could not open the map copyright information.'
      : '지도 저작권 정보를 열 수 없습니다.';
  String get mapInstruction => isEnglish
      ? 'Tap a pharmacy below to view its location'
      : '아래 약국을 누르면 지도에서 위치를 확인할 수 있습니다';
  String get selectMarkerHint =>
      isEnglish ? 'Show this pharmacy on the map' : '이 약국을 지도에서 보기';
  String get showOnMap =>
      isEnglish ? 'Tap to show on the map' : '누르면 지도에서 위치를 표시합니다';
  String get zoomInTooltip => isEnglish ? 'Zoom in' : '지도 확대';
  String get zoomOutTooltip => isEnglish ? 'Zoom out' : '지도 축소';
  String get mapConfigurationUnavailable => isEnglish
      ? 'The in-app map is not configured for this build.'
      : '이 실행 환경에는 앱 내 지도 설정이 없습니다.';
  String get mapUnavailable => isEnglish
      ? 'Map coordinates are unavailable for these pharmacies.'
      : '표시할 수 있는 약국 좌표가 없습니다.';
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

  String scheduleTags(NearbyPharmacy pharmacy) {
    final labels = <String>[];
    if (pharmacy.isOfficialLateNight) {
      labels.add(
        isEnglish ? 'Official public late-night pharmacy' : '공식 공공심야약국',
      );
      if (pharmacy.designationIsStale) {
        labels.add(isEnglish ? 'Designation needs rechecking' : '지정 현황 재확인 필요');
      }
    }
    if (pharmacy.isOpenLate) {
      labels.add(isEnglish ? 'Late-night hours today' : '오늘 심야 운영');
    }
    if (pharmacy.hasWeekendOrHolidayHours) {
      labels.add(isEnglish ? 'Weekend/holiday hours available' : '주말·공휴일 운영');
    }
    return labels.join(' · ');
  }

  String searchDate(DateTime value) {
    final formatted =
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    return isEnglish ? 'Search date: $formatted' : '조회 날짜: $formatted';
  }

  String searchTime(DateTime value) {
    final formatted =
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    return isEnglish ? 'Time: $formatted' : '시각: $formatted';
  }

  String get phone => isEnglish ? 'Call' : '전화';
  String get directions => isEnglish ? 'Directions' : '길찾기';
  String get addFavorite => isEnglish ? 'Add to favorites' : '즐겨찾기 추가';
  String get removeFavorite => isEnglish ? 'Remove favorite' : '즐겨찾기 해제';
  String get favoriteSaveFailed => isEnglish
      ? 'Could not save the pharmacy favorite.'
      : '약국 즐겨찾기를 저장하지 못했습니다.';
  String get phoneVerified => isEnglish
      ? 'I called and confirmed the opening hours'
      : '전화로 운영 여부를 확인했어요';
  String get shareInChat => isEnglish ? 'Share in chat' : '채팅에 공유';
  String get callBeforeVisit =>
      isEnglish ? 'Call before visiting' : '방문 전 전화 확인';

  String refreshedAt(DateTime value) {
    final local = value.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return isEnglish ? 'Updated $time' : '최근 조회 $time';
  }

  String? operatingStatusDetail(NearbyPharmacy pharmacy) {
    final remainingMinutes = pharmacy.minutesUntilClose;
    if (pharmacy.isOpenNow == true &&
        remainingMinutes != null &&
        remainingMinutes > 0 &&
        remainingMinutes <= 60) {
      return isEnglish
          ? 'Closes in $remainingMinutes min'
          : '$remainingMinutes분 후 영업 종료';
    }
    final nextOpenAt = pharmacy.nextOpenAt?.toLocal();
    if (pharmacy.isOpenNow == false && nextOpenAt != null) {
      const koreanWeekdays = ['월', '화', '수', '목', '금', '토', '일'];
      const englishWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final weekday = isEnglish
          ? englishWeekdays[nextOpenAt.weekday - 1]
          : '${koreanWeekdays[nextOpenAt.weekday - 1]}요일';
      final time =
          '${nextOpenAt.hour.toString().padLeft(2, '0')}:'
          '${nextOpenAt.minute.toString().padLeft(2, '0')}';
      return isEnglish
          ? 'Next opening: $weekday $time'
          : '다음 영업: $weekday $time';
    }
    return null;
  }

  String sourceNotice({
    required bool catalogIsStale,
    required String holidayScheduleStatus,
  }) {
    final warning = catalogIsStale
        ? (isEnglish
              ? ' The synchronized catalog is older than expected.'
              : ' 동기화된 약국 목록이 예상보다 오래되었습니다.')
        : '';
    final holidayWarning = switch (holidayScheduleStatus) {
      'stale_fallback' =>
        isEnglish
            ? ' A cached holiday roster is being used.'
            : ' 저장된 명절 비상운영 목록을 사용 중입니다.',
      'weekly_fallback' =>
        isEnglish
            ? ' Exact-date holiday data is unavailable; weekly reported hours are shown.'
            : ' 날짜별 명절 정보가 없어 주간 신고 영업시간을 표시합니다.',
      _ => '',
    };
    final base = isEnglish
        ? 'Information is based on National Emergency Medical Center public data. Official late-night designations currently cover verified Seoul records.'
        : '국립중앙의료원 공공데이터를 기준으로 표시하며, 공식 공공심야 지정은 현재 검증된 서울시 목록을 제공합니다.';
    final callFirst = isEnglish
        ? ' Call before visiting to confirm actual opening hours.'
        : ' 방문 전 전화로 실제 운영 여부를 확인해주세요.';
    return '$base$warning$holidayWarning$callFirst';
  }
}
