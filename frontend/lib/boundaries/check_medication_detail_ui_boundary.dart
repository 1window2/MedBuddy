import 'package:flutter/material.dart';

import '../controls/request_voice_guide_control.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: check_medication_detail_ui_boundary.dart
// 역할: 약 상세정보 화면을 구성하고 음성 안내 요청을 처리한다.

// 클래스명: CheckMedicationDetailUI
// 역할: 효능, 복용방법, 주의사항, 상세 복용 가이드를 한 화면에서 보여준다.
// 주요 책임:
// - 저장 목록과 오늘 일정에서 공통으로 사용할 상세정보 화면을 제공한다.
// - 환경설정의 읽기 속도와 언어를 반영해 큰소리 읽기 기능을 실행한다.
class CheckMedicationDetailUI extends StatefulWidget {
  final MedicationDetail medicationDetail;
  final UserSetting userSetting;

  const CheckMedicationDetailUI({
    super.key,
    required this.medicationDetail,
    required this.userSetting,
  });

  @override
  State<CheckMedicationDetailUI> createState() =>
      _CheckMedicationDetailUIState();
}

class _CheckMedicationDetailUIState extends State<CheckMedicationDetailUI> {
  final RequestVoiceGuide _requestVoiceGuide = RequestVoiceGuide();
  bool _isSpeaking = false;

  @override
  void dispose() {
    _requestVoiceGuide.stop();
    _requestVoiceGuide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.userSetting.contentTextScale;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(42, 32, 42, 104),
              children: [
                _DetailHeader(
                  title: '약 상세정보',
                  onBackRequested: () => Navigator.pop(context),
                ),
                const SizedBox(height: 28),
                _MedicationHeroCard(
                  medicationDetail: widget.medicationDetail,
                  scale: scale,
                ),
                const SizedBox(height: 24),
                _DetailQuestionSection(
                  title: '이 약은 어디가 좋아지나요?',
                  values: _summaryValues(widget.medicationDetail.efficacy),
                  scale: scale,
                ),
                const SizedBox(height: 24),
                _DetailQuestionSection(
                  title: '어떻게 먹나요?',
                  values: [
                    _dailyFrequencyLabel(
                      widget.medicationDetail.dailyFrequency,
                    ),
                    _summaryValue(widget.medicationDetail.usageMethod),
                  ],
                  scale: scale,
                ),
                const SizedBox(height: 24),
                _RecommendedDosageCard(
                  medicationDetail: widget.medicationDetail,
                  scale: scale,
                ),
                const SizedBox(height: 22),
                _DetailedDosageGuideCard(
                  medicationDetail: widget.medicationDetail,
                  scale: scale,
                ),
                const SizedBox(height: 18),
                _MedicationRiskCard(
                  medicationDetail: widget.medicationDetail,
                  scale: scale,
                ),
                const SizedBox(height: 18),
                _MedicationChecklistCard(
                  medicationDetail: widget.medicationDetail,
                  scale: scale,
                ),
              ],
            ),
            Positioned(
              left: 42,
              right: 42,
              bottom: 22,
              child: _TtsButton(
                isSpeaking: _isSpeaking,
                onPressed: _handleTtsButtonPressed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleTtsButtonPressed() async {
    if (_isSpeaking) {
      await _requestVoiceGuide.stop();
      if (mounted) {
        setState(() => _isSpeaking = false);
      }
      return;
    }

    setState(() => _isSpeaking = true);
    try {
      await _requestVoiceGuide.requestVoiceGuide(
        medicationDetail: widget.medicationDetail,
        userSetting: widget.userSetting,
        onComplete: () {
          if (mounted) {
            setState(() => _isSpeaking = false);
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _isSpeaking = false);
      }
    }
  }
}

class _DetailHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBackRequested;

  const _DetailHeader({
    required this.title,
    required this.onBackRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: '뒤로가기',
          onPressed: onBackRequested,
          icon: const Icon(Icons.arrow_back_ios_new, size: 28),
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }
}

class _MedicationHeroCard extends StatelessWidget {
  final MedicationDetail medicationDetail;
  final double scale;

  const _MedicationHeroCard({
    required this.medicationDetail,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 226),
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF4FF), Color(0xFFDFECFE)],
        ),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        children: [
          _MedicationImageBox(imageUrl: medicationDetail.imageUrl),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.medication_rounded,
                color: MedBuddyColors.primary,
                size: 22,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  medicationDetail.displayName,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF0A0A0A),
                    fontSize: 18 * scale,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MedicationImageBox extends StatelessWidget {
  final String imageUrl;

  const _MedicationImageBox({
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedImageUrl = imageUrl.trim();

    return Container(
      width: 112,
      height: 112,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.16),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: normalizedImageUrl.isEmpty
            ? const ColoredBox(
                color: MedBuddyColors.divider,
                child: Icon(
                  Icons.medication_outlined,
                  color: MedBuddyColors.textLight,
                  size: 42,
                ),
              )
            : Image.network(
                normalizedImageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const ColoredBox(
                    color: MedBuddyColors.divider,
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: MedBuddyColors.textLight,
                      size: 38,
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _DetailQuestionSection extends StatelessWidget {
  final String title;
  final List<String> values;
  final double scale;

  const _DetailQuestionSection({
    required this.title,
    required this.values,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final visibleValues = values
        .map((value) => _summaryValue(value))
        .take(2)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: const Color(0xFF0A0A0A),
            fontSize: 16 * scale,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (int index = 0; index < visibleValues.length; index++) ...[
              Expanded(
                child: _DetailValueTile(
                  value: visibleValues[index],
                  scale: scale,
                ),
              ),
              if (index != visibleValues.length - 1) const SizedBox(width: 12),
            ],
          ],
        ),
      ],
    );
  }
}

class _DetailValueTile extends StatelessWidget {
  final String value;
  final double scale;

  const _DetailValueTile({
    required this.value,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: MedBuddyColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MedBuddyColors.divider, width: 1.5),
      ),
      child: Text(
        value,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: MedBuddyColors.textLight,
          fontSize: 14 * scale,
          height: 1.35,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _RecommendedDosageCard extends StatelessWidget {
  final MedicationDetail medicationDetail;
  final double scale;

  const _RecommendedDosageCard({
    required this.medicationDetail,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final dosageLines = medicationDetail.detailedDosageGuideLines;
    final warning = _summaryValue(medicationDetail.warning);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        color: MedBuddyColors.successSurface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '권장된 복용방법',
            style: TextStyle(
              color: const Color(0xFF0A0A0A),
              fontSize: 16 * scale,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          for (int index = 0; index < dosageLines.length; index++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: index == 0
                      ? const Icon(
                          Icons.add_box_rounded,
                          color: MedBuddyColors.primary,
                          size: 18,
                        )
                      : null,
                ),
                Expanded(
                  child: Text(
                    dosageLines[index],
                    style: TextStyle(
                      color: const Color(0xFF0A0A0A),
                      fontSize: 14 * scale,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            if (index != dosageLines.length - 1) const SizedBox(height: 8),
          ],
          const SizedBox(height: 20),
          Text(
            '주의사항',
            style: TextStyle(
              color: const Color(0xFF0A0A0A),
              fontSize: 16 * scale,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 17, 18, 17),
            decoration: BoxDecoration(
              color: const Color(0xFFFCE7F3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              warning,
              style: TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 14 * scale,
                height: 1.55,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailedDosageGuideCard extends StatelessWidget {
  final MedicationDetail medicationDetail;
  final double scale;

  const _DetailedDosageGuideCard({
    required this.medicationDetail,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return _DetailListCard(
      title: '상세 복용 가이드',
      items: medicationDetail.detailedDosageGuideLines,
      scale: scale,
    );
  }
}

class _MedicationRiskCard extends StatelessWidget {
  final MedicationDetail medicationDetail;
  final double scale;

  const _MedicationRiskCard({
    required this.medicationDetail,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return _DetailListCard(
      title: '주요 주의사항 및 부작용',
      items: _uniqueNonEmptyValues([
        medicationDetail.warning,
        medicationDetail.precaution,
        medicationDetail.interaction,
        medicationDetail.sideEffect,
      ]),
      scale: scale,
      useInsetSurface: true,
    );
  }
}

class _MedicationChecklistCard extends StatelessWidget {
  final MedicationDetail medicationDetail;
  final double scale;

  const _MedicationChecklistCard({
    required this.medicationDetail,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return _DetailListCard(
      title: '간편한 가이드 (Checklist)',
      items: _uniqueNonEmptyValues([
        medicationDetail.storageMethod,
        medicationDetail.aiGuide,
      ]),
      scale: scale,
    );
  }
}

class _DetailListCard extends StatelessWidget {
  final String title;
  final List<String> items;
  final double scale;
  final bool useInsetSurface;

  const _DetailListCard({
    required this.title,
    required this.items,
    required this.scale,
    this.useInsetSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.isEmpty ? const ['정보 없음'] : items;
    final itemList = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int index = 0; index < visibleItems.length; index++) ...[
          Text(
            visibleItems[index],
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 14 * scale,
              height: 1.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          if (index != visibleItems.length - 1) const SizedBox(height: 10),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        color: MedBuddyColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: const Color(0xFF0A0A0A),
              fontSize: 16 * scale,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          if (useInsetSurface)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: itemList,
            )
          else
            itemList,
        ],
      ),
    );
  }
}

List<String> _summaryValues(String value) {
  final normalizedValue = value.trim();
  if (normalizedValue.isEmpty) {
    return const ['정보 없음'];
  }

  final values = normalizedValue
      .split(RegExp(r'[,/;·\n]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .take(2)
      .toList(growable: false);
  return values.isEmpty ? [normalizedValue] : values;
}

String _summaryValue(String value) {
  final normalizedValue = value.trim();
  return normalizedValue.isEmpty ? '정보 없음' : normalizedValue;
}

String _dailyFrequencyLabel(String value) {
  final normalizedValue = value.trim();
  if (normalizedValue.isEmpty) {
    return '정보 없음';
  }
  if (normalizedValue.contains('일') || normalizedValue.contains('하루')) {
    return normalizedValue;
  }

  final count = RegExp(r'\d+').firstMatch(normalizedValue)?.group(0);
  return count == null ? normalizedValue : '1일 $count회';
}

List<String> _uniqueNonEmptyValues(List<String> values) {
  final uniqueValues = <String>{};
  for (final value in values) {
    final normalizedValue = value.trim();
    if (normalizedValue.isNotEmpty) {
      uniqueValues.add(normalizedValue);
    }
  }
  return uniqueValues.toList(growable: false);
}

class _TtsButton extends StatelessWidget {
  final bool isSpeaking;
  final Future<void> Function() onPressed;

  const _TtsButton({
    required this.isSpeaking,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up),
      label: Text(isSpeaking ? '읽기 중지' : '큰 소리로 읽어주세요'),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        backgroundColor: MedBuddyColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
