import 'package:flutter/material.dart';

import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: manage_user_setting_ui_boundary.dart
// 역할: 글씨 크기, 읽기 속도, 언어 설정 화면을 구성한다.

// 클래스명: ManageUserSettingUI
// 역할: 사용자가 접근성 관련 표시 설정을 선택하고 저장할 수 있게 한다.
// 주요 책임:
// - 현재 저장된 설정을 초기 선택값으로 표시한다.
// - 설정 변경 시 미리보기 문구에 즉시 반영한다.
// - 저장 버튼을 통해 변경값을 ViewModel로 전달한다.
class ManageUserSettingUI extends StatefulWidget {
  final UserSetting initialSetting;
  final Future<void> Function({
    required String fontSizeOption,
    required String readingSpeedOption,
    required String language,
  }) onSettingSaveRequested;

  const ManageUserSettingUI({
    super.key,
    required this.initialSetting,
    required this.onSettingSaveRequested,
  });

  @override
  State<ManageUserSettingUI> createState() => _ManageUserSettingUIState();
}

class _ManageUserSettingUIState extends State<ManageUserSettingUI> {
  late String _fontSize;
  late String _readingSpeed;
  late String _language;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.initialSetting.fontSizeOption;
    _readingSpeed = widget.initialSetting.readingSpeedOption;
    _language = widget.initialSetting.language;
  }

  @override
  Widget build(BuildContext context) {
    final text = _SettingText(_language);
    final contentScale =
        UserSetting(fontSize: UserSetting.fontSizeFromOption(_fontSize))
            .contentTextScale;

    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(40, 26, 40, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _CloseButton(
                              tooltip: text.close,
                              onTap: () => Navigator.maybePop(context),
                            ),
                            const Spacer(),
                            Container(
                              width: 54,
                              height: 54,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _SettingTitle(text.fontSizeTitle),
                        const SizedBox(height: 22),
                        _OptionRow(
                          options: [
                            _SettingOption(value: 'small', label: text.small),
                            _SettingOption(
                              value: 'medium',
                              label: text.medium,
                            ),
                            _SettingOption(value: 'large', label: text.large),
                          ],
                          selectedValue: _fontSize,
                          contentScale: contentScale,
                          onSelected: (value) =>
                              setState(() => _fontSize = value),
                        ),
                        const SizedBox(height: 45),
                        _SettingTitle(text.readingSpeedTitle),
                        const SizedBox(height: 22),
                        _OptionRow(
                          options: [
                            _SettingOption(value: 'slow', label: text.slow),
                            _SettingOption(
                              value: 'medium',
                              label: text.medium,
                            ),
                            _SettingOption(value: 'fast', label: text.fast),
                          ],
                          selectedValue: _readingSpeed,
                          contentScale: contentScale,
                          onSelected: (value) =>
                              setState(() => _readingSpeed = value),
                        ),
                        const SizedBox(height: 45),
                        _SettingTitle(text.languageTitle),
                        const SizedBox(height: 22),
                        _OptionRow(
                          options: const [
                            _SettingOption(value: 'ko', label: '한국어'),
                            _SettingOption(value: 'en', label: 'English'),
                          ],
                          selectedValue: _language,
                          contentScale: contentScale,
                          onSelected: (value) =>
                              setState(() => _language = value),
                        ),
                        const SizedBox(height: 42),
                        _PreviewPanel(
                          text: text,
                          fontSize: _fontSize,
                          readingSpeed: _readingSpeed,
                          language: _language,
                        ),
                      ],
                    ),
                  ),
                ),
                _SettingSaveFooter(
                  text: text,
                  isSaving: _isSaving,
                  onSaveRequested: _handleSaveRequested,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSaveRequested() async {
    setState(() => _isSaving = true);
    await widget.onSettingSaveRequested(
      fontSizeOption: _fontSize,
      readingSpeedOption: _readingSpeed,
      language: _language,
    );
    if (!mounted) {
      return;
    }

    final text = _SettingText(_language);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.saved)),
    );
    Navigator.maybePop(context);
  }
}

class _CloseButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;

  const _CloseButton({
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      tooltip: tooltip,
      onPressed: onTap,
      icon: const Icon(
        Icons.close,
        color: Color(0xFF4A5565),
        size: 31,
      ),
    );
  }
}

class _SettingSaveFooter extends StatelessWidget {
  final _SettingText text;
  final bool isSaving;
  final Future<void> Function() onSaveRequested;

  const _SettingSaveFooter({
    required this.text,
    required this.isSaving,
    required this.onSaveRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(40, 14, 40, 20),
      decoration: const BoxDecoration(
        color: MedBuddyColors.pageBackground,
        border: Border(top: BorderSide(color: MedBuddyColors.divider)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: MedBuddyColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: MedBuddyColors.primary.withAlpha(150),
            shape: RoundedRectangleBorder(
              borderRadius: MedBuddyRadii.card,
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          onPressed: isSaving ? null : onSaveRequested,
          child: Text(isSaving ? text.saving : text.save),
        ),
      ),
    );
  }
}

class _SettingTitle extends StatelessWidget {
  final String text;

  const _SettingTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: MedBuddyColors.textStrong,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        height: 1,
        letterSpacing: 0,
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final List<_SettingOption> options;
  final String selectedValue;
  final double contentScale;
  final ValueChanged<String> onSelected;

  const _OptionRow({
    required this.options,
    required this.selectedValue,
    required this.contentScale,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int index = 0; index < options.length; index++) ...[
          Expanded(
            child: _SegmentButton(
              option: options[index],
              selected: options[index].value == selectedValue,
              contentScale: contentScale,
              onTap: () => onSelected(options[index].value),
            ),
          ),
          if (index != options.length - 1) const SizedBox(width: 11),
        ],
      ],
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final _SettingOption option;
  final bool selected;
  final double contentScale;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.option,
    required this.selected,
    required this.contentScale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? MedBuddyColors.primary : Colors.white,
      borderRadius: MedBuddyRadii.card,
      elevation: selected ? 7 : 0,
      shadowColor: const Color.fromRGBO(0, 0, 0, 0.18),
      child: InkWell(
        borderRadius: MedBuddyRadii.card,
        onTap: onTap,
        child: Container(
          height: 77,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.card,
            border: Border.all(
              color: MedBuddyColors.primary,
              width: selected ? 0 : 2.7,
            ),
          ),
          child: Text(
            option.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : MedBuddyColors.textStrong,
              fontSize: 16 * contentScale,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  final _SettingText text;
  final String fontSize;
  final String readingSpeed;
  final String language;

  const _PreviewPanel({
    required this.text,
    required this.fontSize,
    required this.readingSpeed,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final sampleText = language == 'ko'
        ? '아스피린 100mg을 하루 3회 식후 30분에 복용하세요.'
        : 'Take aspirin 100mg three times daily after meals.';
    final speedLabel = switch (readingSpeed) {
      'slow' => text.slowLabel,
      'fast' => text.fastLabel,
      _ => text.normalLabel,
    };
    final textSize = switch (fontSize) {
      'small' => 13.0,
      'large' => 18.0,
      _ => 15.0,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAFBF3),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text.preview,
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: MedBuddyRadii.card,
            ),
            child: Text(
              sampleText,
              style: TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: textSize,
                height: 1.55,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '${text.readingSpeedLabel}: $speedLabel',
              style: const TextStyle(
                color: MedBuddyColors.textLight,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingOption {
  final String value;
  final String label;

  const _SettingOption({
    required this.value,
    required this.label,
  });
}

class _SettingText {
  final String language;

  const _SettingText(this.language);

  bool get isEnglish => language == 'en';

  String get close => isEnglish ? 'Close' : '닫기';
  String get fontSizeTitle => isEnglish ? 'Text Size' : '글씨크기';
  String get readingSpeedTitle => isEnglish ? 'Reading Speed' : '읽기속도';
  String get languageTitle => isEnglish ? 'Language' : '언어';
  String get small => isEnglish ? 'Small' : '작게';
  String get medium => isEnglish ? 'Medium' : '중간';
  String get large => isEnglish ? 'Large' : '크게';
  String get slow => isEnglish ? 'Slow' : '느리게';
  String get fast => isEnglish ? 'Fast' : '빠르게';
  String get preview => isEnglish ? 'Preview' : '미리보기';
  String get readingSpeedLabel => isEnglish ? 'Reading speed' : '읽기 속도';
  String get slowLabel => isEnglish ? 'Slow' : '느림';
  String get normalLabel => isEnglish ? 'Normal' : '보통';
  String get fastLabel => isEnglish ? 'Fast' : '빠름';
  String get save => isEnglish ? 'Save' : '저장하기';
  String get saving => isEnglish ? 'Saving...' : '저장 중...';
  String get saved => isEnglish ? 'Settings saved.' : '설정이 저장되었습니다.';
}
