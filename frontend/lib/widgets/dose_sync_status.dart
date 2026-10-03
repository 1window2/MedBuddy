// 파일명: dose_sync_status.dart
// 역할: 홈·일정·채팅에서 전송 대기와 확인이 필요한 복약 기록을 같은 방식으로 표시한다.
import 'package:flutter/material.dart';
import '../services/dose_sync_service.dart';
import '../theme/medbuddy_theme.dart';

class DoseSyncStatus extends StatelessWidget {
  final DoseSyncService service;
  final bool isEnglish;
  const DoseSyncStatus({
    super.key,
    required this.service,
    this.isEnglish = false,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      if (service.pendingCount == 0) return const SizedBox.shrink();
      return Material(
        color: MedBuddyColors.primary.withValues(alpha: 0.08),
        child: ListTile(
          dense: true,
          leading: Icon(
            service.hasBlocked
                ? Icons.error_outline
                : Icons.cloud_upload_outlined,
            color: MedBuddyColors.primary,
          ),
          title: Text(
            service.hasBlocked
                ? (isEnglish ? 'Dose sync needs attention' : '복용 기록 전송 확인 필요')
                : (isEnglish
                      ? '${service.pendingCount} dose records waiting to sync'
                      : '복용 기록 ${service.pendingCount}건 전송 대기'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (context) => SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.5,
                child: ListenableBuilder(
                  listenable: service,
                  builder: (context, _) => Column(
                    children: [
                      ListTile(
                        title: Text(
                          isEnglish ? 'Dose sync' : '복용 기록 전송',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: isEnglish ? 'Retry' : '다시 전송',
                          icon: const Icon(Icons.sync),
                          onPressed: service.retryNow,
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final op in service.operations)
                              ListTile(
                                trailing: op['state'] == 'blocked'
                                    ? IconButton(
                                        tooltip: isEnglish
                                            ? 'Remove rejected record'
                                            : '저장되지 않은 기록 지우기',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () async {
                                          final remove = await showDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: Text(
                                                isEnglish
                                                    ? 'Remove rejected record?'
                                                    : '저장되지 않은 기록을 지울까요?',
                                              ),
                                              content: Text(
                                                isEnglish
                                                    ? 'This removes only the record rejected by the server.'
                                                    : '서버가 저장하지 못한 이 기기의 대기 기록만 지웁니다.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        false,
                                                      ),
                                                  child: Text(
                                                    isEnglish ? 'Cancel' : '취소',
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        true,
                                                      ),
                                                  child: Text(
                                                    isEnglish
                                                        ? 'Remove'
                                                        : '지우기',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (remove == true) {
                                            await service.discardRejected(
                                              op['operation_id'] as String,
                                            );
                                          }
                                        },
                                      )
                                    : null,
                                title: Text(
                                  (op['medication_names'] as List?)?.join(
                                        ', ',
                                      ) ??
                                      '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${op['schedule_date']} · ${_slot(op['slot_key'] as String)} · ${op['completed'] == true ? (isEnglish ? 'Taken' : '복용') : (isEnglish ? 'Undone' : '복용 취소')}\n${op['state'] == 'blocked' ? (isEnglish ? 'Schedule or access changed. Not saved to server.' : '일정 또는 연동이 변경되어 서버에 저장하지 못했습니다.') : (isEnglish ? 'Saved on this device. Waiting to sync.' : '기기에 저장됨 · 서버 전송 대기')}',
                                ),
                              ),
                            if (service.operations.isEmpty)
                              ListTile(
                                title: Text(
                                  isEnglish
                                      ? 'All records saved to server.'
                                      : '서버에 모두 저장했습니다.',
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
          ),
        ),
      );
    },
  );

  String _slot(String key) => isEnglish
      ? key
      : const {
              'morning': '아침',
              'lunch': '점심',
              'evening': '저녁',
              'bedtime': '취침 전',
            }[key] ??
            key;
}
