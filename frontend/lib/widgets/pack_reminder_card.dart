// 파일명: pack_reminder_card.dart
// 역할: 일정 화면의 "외출 전 약 챙기기 알림" 줄과 설정 창(켜기, 시각, 요일). 저장하면 바로 다시 예약된다.

import 'package:flutter/material.dart';

import '../boundaries/set_notification_ui_boundary.dart';
import '../controls/pack_reminder_control.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import 'keep_words_text.dart';

// 클래스명: PackReminderCard
// 역할: 현재 설정을 한 줄로 보여 주고, 누르면 설정 창을 연다.
// 속성: userSetting: 언어·시각 표기; loadSetting/saveSetting: 설정 읽기·저장(저장 실패·권한 거부는 false).
class PackReminderCard extends StatefulWidget {
  final UserSetting userSetting;
  final Future<PackReminderSetting> Function() loadSetting;
  final Future<bool> Function(PackReminderSetting setting) saveSetting;

  const PackReminderCard({
    super.key,
    required this.userSetting,
    required this.loadSetting,
    required this.saveSetting,
  });

  @override
  State<PackReminderCard> createState() => _PackReminderCardState();
}

class _PackReminderCardState extends State<PackReminderCard> {
  PackReminderSetting? _setting;
  bool _saving = false;

  _PackReminderText get _text => _PackReminderText(widget.userSetting.language);

  @override
  void initState() {
    super.initState();
    _load();
  }

  // 함수이름: _load
  // 함수역할: 저장한 설정을 읽어 줄에 반영한다. 읽지 못하면 기본값(꺼짐)으로 둔다.
  Future<void> _load() async {
    PackReminderSetting setting;
    try {
      setting = await widget.loadSetting();
    } catch (_) {
      setting = const PackReminderSetting();
    }
    if (mounted) setState(() => _setting = setting);
  }

  // 함수이름: _open
  // 함수역할: 설정 창을 열고 저장을 누르면 저장한다. 켤 때 권한이 거부되면 안내한다.
  Future<void> _open() async {
    final current = _setting ?? const PackReminderSetting();
    final draft = await showDialog<PackReminderSetting>(
      context: context,
      builder: (context) => _PackReminderDialog(
        initial: current,
        userSetting: widget.userSetting,
      ),
    );
    if (!mounted || draft == null || draft == current) return;
    setState(() => _saving = true);
    var saved = false;
    try {
      saved = await widget.saveSetting(draft);
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved) _setting = draft;
    });
    if (!saved) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            draft.enabled ? _text.permissionNeeded : _text.saveFailed,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final setting = _setting ?? const PackReminderSetting();
    final text = _text;
    final summary = setting.enabled
        ? text.summary(setting, widget.userSetting)
        : text.off;
    return Semantics(
      button: true,
      label: '${text.title}, $summary',
      excludeSemantics: true,
      child: Material(
        color: MedBuddyColors.surface,
        borderRadius: MedBuddyRadii.card,
        child: InkWell(
          key: const Key('schedule-pack-reminder'),
          borderRadius: MedBuddyRadii.card,
          onTap: _setting == null || _saving ? null : _open,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: MedBuddyRadii.card,
              border: Border.all(color: MedBuddyColors.cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: MedBuddyColors.butterSurface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.backpack_outlined,
                    color: MedBuddyColors.reminderAccent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KeepWordsText(
                        text.title,
                        style: const TextStyle(
                          color: MedBuddyColors.textStrong,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      KeepWordsText(
                        summary,
                        style: TextStyle(
                          color: setting.enabled
                              ? MedBuddyColors.primaryDark
                              : MedBuddyColors.textSubtle,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_saving)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: MedBuddyColors.textSubtle,
                    size: 28,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 클래스명: _PackReminderDialog
// 역할: 켜기, 알림 시각, 요일(월~일, 최소 하루)을 고르는 창. 저장하면 초안을 돌려준다.
class _PackReminderDialog extends StatefulWidget {
  final PackReminderSetting initial;
  final UserSetting userSetting;

  const _PackReminderDialog({required this.initial, required this.userSetting});

  @override
  State<_PackReminderDialog> createState() => _PackReminderDialogState();
}

class _PackReminderDialogState extends State<_PackReminderDialog> {
  late PackReminderSetting _draft = widget.initial;

  @override
  Widget build(BuildContext context) {
    final text = _PackReminderText(widget.userSetting.language);
    return AlertDialog(
      key: const Key('schedule-pack-reminder-dialog'),
      backgroundColor: MedBuddyColors.surface,
      scrollable: true,
      title: KeepWordsText(text.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeepWordsText(
            text.explanation,
            style: const TextStyle(
              color: MedBuddyColors.textSubtle,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            key: const Key('schedule-pack-reminder-enabled'),
            contentPadding: EdgeInsets.zero,
            title: KeepWordsText(text.enabled),
            value: _draft.enabled,
            activeTrackColor: MedBuddyColors.primary,
            onChanged: (enabled) =>
                setState(() => _draft = _draft.copyWith(enabled: enabled)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('schedule-pack-reminder-time'),
            icon: const Icon(Icons.schedule_outlined),
            label: KeepWordsText(
              '${text.time} ${widget.userSetting.formatTime(_draft.hour, _draft.minute)}',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: MedBuddyColors.primaryDark,
            ),
            onPressed: () async {
              final time = await SetNotificationUI.showNotificationPopup(
                context,
                language: widget.userSetting.language,
                slotTitle: text.title,
                initialTime: TimeOfDay(
                  hour: _draft.hour,
                  minute: _draft.minute,
                ),
              );
              if (!mounted || time == null) return;
              setState(
                () => _draft = _draft.copyWith(
                  hour: time.hour,
                  minute: time.minute,
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          KeepWordsText(
            text.days,
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          // 월~일을 같은 너비로 한 줄에 둔다. 토요일은 파란색, 일요일은 빨간색 글씨.
          Row(
            children: [
              for (var day = 1; day <= 7; day++) ...[
                if (day > 1) const SizedBox(width: 4),
                Expanded(
                  child: _WeekdayToggle(
                    key: Key('schedule-pack-reminder-day-$day'),
                    label: text.weekday(day),
                    day: day,
                    selected: _draft.weekdays.contains(day),
                    // 마지막 남은 요일은 끌 수 없다(copyWith가 빈 요일을 무시한다).
                    onTap: () => setState(() {
                      final days = Set<int>.of(_draft.weekdays);
                      days.contains(day) ? days.remove(day) : days.add(day);
                      _draft = _draft.copyWith(weekdays: days);
                    }),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('schedule-pack-reminder-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(text.cancel),
        ),
        FilledButton(
          key: const Key('schedule-pack-reminder-save'),
          onPressed: () => Navigator.pop(context, _draft),
          child: Text(text.save),
        ),
      ],
    );
  }
}

// 클래스명: _WeekdayToggle
// 역할: 요일 하나를 켜고 끄는 버튼. 줄 너비를 일곱 칸이 나눠 쓰고, 글자는 칸에 맞게 줄어든다.
// 속성: label: 요일 이름; day: 월=1 … 일=7; selected: 선택 여부; onTap: 누르면 호출.
class _WeekdayToggle extends StatelessWidget {
  final String label;
  final int day;
  final bool selected;
  final VoidCallback onTap;

  const _WeekdayToggle({
    super.key,
    required this.label,
    required this.day,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor = switch (day) {
      6 => MedBuddyColors.saturdayBlue,
      7 => MedBuddyColors.danger,
      _ => selected ? MedBuddyColors.primaryDark : MedBuddyColors.textStrong,
    };
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: selected ? MedBuddyColors.primary : MedBuddyColors.cardBorder,
        width: selected ? 1.5 : 1,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? MedBuddyColors.successSurface
            : MedBuddyColors.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 클래스명: _PackReminderText
// 역할: 외출 전 약 챙기기 알림 화면 문구(한국어·영어).
class _PackReminderText {
  final bool isEnglish;

  _PackReminderText(String language) : isEnglish = isEnglishLanguage(language);

  String get title =>
      isEnglish ? 'Pack-your-medicines reminder' : '외출 전 약 챙기기 알림';
  String get off => isEnglish ? 'Off' : '꺼짐';
  String get explanation => isEnglish
      ? 'On days with lunch or evening medicines, a reminder in the morning to take them with you.'
      : '점심·저녁 약이 있는 날, 아침에 약을 챙겨 가라고 한 번 알려 드려요.';
  String get enabled => isEnglish ? 'Get this reminder' : '알림 받기';
  String get time => isEnglish ? 'Time' : '알림 시각';
  String get days => isEnglish ? 'Days' : '요일';
  String get cancel => isEnglish ? 'Cancel' : '취소';
  String get save => isEnglish ? 'Save' : '저장';
  String get permissionNeeded => isEnglish
      ? 'Allow notifications to turn this reminder on.'
      : '알림을 허용해야 켤 수 있어요.';
  String get saveFailed =>
      isEnglish ? 'The setting could not be saved.' : '설정을 저장하지 못했어요.';

  // 함수이름: weekday
  // 함수역할: 요일 번호(월=1 … 일=7)의 짧은 이름.
  String weekday(int day) => isEnglish
      ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day - 1]
      : const ['월', '화', '수', '목', '금', '토', '일'][day - 1];

  // 함수이름: summary
  // 함수역할: 켜진 설정을 한 줄로 요약한다("매일 07:30", "월 화 수 목 금 · 07:30").
  String summary(PackReminderSetting setting, UserSetting userSetting) {
    final time = userSetting.formatTime(setting.hour, setting.minute);
    if (setting.weekdays.length == 7) {
      return isEnglish ? 'Every day $time' : '매일 $time';
    }
    final days = (setting.weekdays.toList()..sort()).map(weekday).join(' ');
    return '$days · $time';
  }
}
