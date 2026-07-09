import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../entities/health_recommendation_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../viewmodels/medbuddy_view_model.dart';

// 파일명: health_recommendation_ui_boundary.dart
// 역할: 약 조합 기반 건강 관리 추천 화면을 구성한다.

// 클래스명: HealthRecommendationUI
// 역할: 식사 추천, 운동 추천, 주의사항을 카드 형태로 보여준다.
// 주요 책임:
// - 화면 진입 시 건강 관리 추천 API 요청을 시작한다.
// - 추천 생성 중, 성공, 실패 상태를 사용자에게 보여준다.
class HealthRecommendationUI extends StatefulWidget {
  const HealthRecommendationUI({super.key});

  @override
  State<HealthRecommendationUI> createState() => _HealthRecommendationUIState();
}

class _HealthRecommendationUIState extends State<HealthRecommendationUI> {
  bool _hasRequestedRecommendation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() => _hasRequestedRecommendation = true);
      context.read<MedBuddyViewModel>().fetchHealthRecommendation();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MedBuddyViewModel>();
    final text = _HealthRecommendationText(viewModel.userSetting.language);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _HealthRecommendationHeader(
            text: text,
            onBackRequested: () => Navigator.pop(context),
          ),
          Expanded(
            child: _buildContent(viewModel, text),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    MedBuddyViewModel viewModel,
    _HealthRecommendationText text,
  ) {
    if (!_hasRequestedRecommendation ||
        viewModel.isHealthRecommendationLoading) {
      return _HealthRecommendationLoading(text: text);
    }

    final recommendation = viewModel.healthRecommendation;
    if (recommendation == null) {
      return _HealthRecommendationError(
        text: text,
        message: viewModel.statusMessage,
        onRetryRequested: viewModel.fetchHealthRecommendation,
      );
    }

    return _HealthRecommendationContent(
      recommendation: recommendation,
      text: text,
    );
  }
}

class _HealthRecommendationLoading extends StatelessWidget {
  final _HealthRecommendationText text;

  const _HealthRecommendationLoading({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 326,
        padding: const EdgeInsets.fromLTRB(28, 38, 28, 34),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: MedBuddyRadii.largeCard,
          boxShadow: MedBuddyShadows.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text.loadingTitle,
              style: const TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 34),
            const SizedBox(
              width: 92,
              height: 92,
              child: CircularProgressIndicator(
                color: MedBuddyColors.primary,
                backgroundColor: MedBuddyColors.mint,
                strokeWidth: 10,
              ),
            ),
            const SizedBox(height: 34),
            Text(
              text.loadingMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.primary,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              text.loadingWait,
              style: const TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthRecommendationHeader extends StatelessWidget {
  final _HealthRecommendationText text;
  final VoidCallback onBackRequested;

  const _HealthRecommendationHeader({
    required this.text,
    required this.onBackRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: MedBuddyColors.topBar,
      padding: EdgeInsets.fromLTRB(
        18,
        MediaQuery.of(context).padding.top + 12,
        24,
        22,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: text.back,
            onPressed: onBackRequested,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 31),
          ),
          const SizedBox(width: 8),
          Text(
            text.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthRecommendationContent extends StatelessWidget {
  final HealthRecommendation recommendation;
  final _HealthRecommendationText text;

  const _HealthRecommendationContent({
    required this.recommendation,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(42, 24, 42, 28),
      children: [
        _RecommendationCard(
          title: text.diet,
          body: recommendation.dietRecommendation,
          icon: Icons.local_dining_outlined,
          iconColor: const Color(0xFFE91E63),
          headerColor: const Color(0xFFFFF1F2),
        ),
        const SizedBox(height: 16),
        _RecommendationCard(
          title: text.exercise,
          body: recommendation.exerciseRecommendation,
          icon: Icons.directions_walk_rounded,
          iconColor: const Color(0xFF006DFF),
          headerColor: const Color(0xFFEFF6FF),
        ),
        const SizedBox(height: 16),
        _CautionCard(
          title: text.caution,
          cautionItems: recommendation.cautionItems,
        ),
      ],
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;
  final Color iconColor;
  final Color headerColor;

  const _RecommendationCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.iconColor,
    required this.headerColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: const Color.fromRGBO(0, 0, 0, 0.12),
      borderRadius: MedBuddyRadii.card,
      child: ClipRRect(
        borderRadius: MedBuddyRadii.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              color: headerColor,
              padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
              child: Row(
                children: [
                  Icon(icon, color: iconColor, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              child: Text(
                body,
                style: const TextStyle(
                  color: MedBuddyColors.textBody,
                  fontSize: 17,
                  height: 1.62,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CautionCard extends StatelessWidget {
  final String title;
  final List<String> cautionItems;

  const _CautionCard({
    required this.title,
    required this.cautionItems,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E8),
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: const Color(0xFFFFD24C), width: 1.5),
        boxShadow: MedBuddyShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFFFD24C))),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFFF8A00),
                  size: 27,
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in cautionItems) ...[
                  _CautionItem(text: item),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CautionItem extends StatelessWidget {
  final String text;

  const _CautionItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(
            color: Color(0xFFF5B51B),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _HealthRecommendationError extends StatelessWidget {
  final _HealthRecommendationText text;
  final String message;
  final Future<void> Function() onRetryRequested;

  const _HealthRecommendationError({
    required this.text,
    required this.message,
    required this.onRetryRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 34),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: MedBuddyRadii.largeCard,
          boxShadow: MedBuddyShadows.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.health_and_safety_outlined,
              color: MedBuddyColors.primary,
              size: 52,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 17,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: onRetryRequested,
              style: ElevatedButton.styleFrom(
                backgroundColor: MedBuddyColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                text.retry,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthRecommendationText {
  final String language;

  const _HealthRecommendationText(this.language);

  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

  String get title => isEnglish ? 'Health Recommendations' : '건강 관리 추천';
  String get back => isEnglish ? 'Back' : '뒤로가기';
  String get loadingTitle => isEnglish ? 'Generating' : '추천 생성중';
  String get loadingMessage =>
      isEnglish ? 'Generating health recommendations' : '추천 건강 활동을 생성 중입니다';
  String get loadingWait => isEnglish ? 'Please wait a moment' : '잠시만 기다려주세요';
  String get diet => isEnglish ? 'Diet Recommendation' : '식사 추천';
  String get exercise => isEnglish ? 'Exercise Recommendation' : '운동 추천';
  String get caution => isEnglish ? 'Cautions' : '주의사항';
  String get retry => isEnglish ? 'Try Again' : '다시 불러오기';
}
