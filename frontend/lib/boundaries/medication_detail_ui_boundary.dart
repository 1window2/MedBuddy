import 'package:flutter/material.dart';

import '../controls/request_voice_guide_control.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: medication_detail_ui_boundary.dart
// 역할: 약 상세정보 화면을 구성하고 음성 안내 요청을 처리한다.

// 클래스명: MedicationDetailUI
// 역할: 효능, 복용방법, 주의사항, 상세 복용 가이드를 한 화면에서 보여준다.
// 주요 책임:
// - 저장 목록과 오늘 일정에서 공통으로 사용할 상세정보 화면을 제공한다.
// - 환경설정의 읽기 속도와 언어를 반영해 큰소리 읽기 기능을 실행한다.
class MedicationDetailUI extends StatefulWidget {
  final MedicationDetail medicationDetail;
  final UserSetting userSetting;

  const MedicationDetailUI({
    super.key,
    required this.medicationDetail,
    required this.userSetting,
  });

  @override
  State<MedicationDetailUI> createState() => _MedicationDetailUIState();
}

class _MedicationDetailUIState extends State<MedicationDetailUI> {
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
              padding: const EdgeInsets.fromLTRB(42, 20, 42, 104),
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
                _DetailSection(
                  icon: Icons.info_outline,
                  title: '효능',
                  body: widget.medicationDetail.efficacy,
                  scale: scale,
                ),
                _DetailSection(
                  icon: Icons.schedule_outlined,
                  title: '복용 방법',
                  body: widget.medicationDetail.usageMethod,
                  scale: scale,
                ),
                _DetailSection(
                  icon: Icons.warning_amber_outlined,
                  title: '주의사항',
                  body: widget.medicationDetail.warning,
                  scale: scale,
                  tone: _DetailSectionTone.warning,
                ),
                _DetailedDosageGuideCard(
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
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 25),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        children: [
          _MedicationImageBox(imageUrl: medicationDetail.imageUrl),
          const SizedBox(height: 20),
          Text(
            medicationDetail.displayName,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 18 * scale,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
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
                color: Color(0xFFE5E7EB),
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
                    color: Color(0xFFE5E7EB),
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

enum _DetailSectionTone {
  normal,
  warning,
}

class _DetailSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final double scale;
  final _DetailSectionTone tone;

  const _DetailSection({
    required this.icon,
    required this.title,
    required this.body,
    required this.scale,
    this.tone = _DetailSectionTone.normal,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedBody = body.trim().isEmpty ? '정보 없음' : body.trim();
    final backgroundColor = tone == _DetailSectionTone.warning
        ? const Color(0xFFFFEEF5)
        : const Color(0xFFF8FAFC);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(20, 19, 20, 20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: MedBuddyColors.primary, size: 23),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 15 * scale,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  normalizedBody,
                  style: TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 14 * scale,
                    height: 1.55,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ],
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
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '상세 복용 가이드',
            style: TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 16 * scale,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          for (final line in medicationDetail.detailedDosageGuideLines) ...[
            Text(
              line,
              style: TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 14 * scale,
                height: 1.45,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }
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
