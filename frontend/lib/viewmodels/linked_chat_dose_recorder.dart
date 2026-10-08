// File Name: linked_chat_dose_recorder.dart
// Role: Plans and records the patient's "taken" confirmation chosen in a linked chat.

import '../controls/manage_linked_chat_control.dart';
import '../entities/chat_message_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../services/dose_sync_service.dart';
import 'medbuddy_view_model.dart';

// Class Name: ChatDosePlanStatus
// Role: Tells the chat screen whether a selection can be recorded as chosen.
// Responsibilities:
// - ready: every selected dose exists on the selected day; scheduleChanged: a selected dose or
//   its day is no longer in the schedule; noSchedule: the selection names no dose slot.
enum ChatDosePlanStatus { ready, scheduleChanged, noSchedule }

// Class Name: ChatDoseRequest
// Role: One dose write, for one day and one slot, exactly as the patient confirmed it.
// Responsibilities:
// - Keep the request stable between a failed attempt and its retry.
// Attributes:
// - scheduleDate (String): Dose day (YYYY-MM-DD) the selection was made for.
// - slotKey (String): morning, lunch, evening or bedtime.
// - medicationIds (List<int>): Selected medication IDs of this slot, ascending without duplicates.
// - medicationNames (List<String>): Display names of those medications for the outbox status.
class ChatDoseRequest {
  final String scheduleDate;
  final String slotKey;
  final List<int> medicationIds;
  final List<String> medicationNames;

  // Function Name: ChatDoseRequest
  // Description: Stores one planned dose write.
  // Parameters: scheduleDate, slotKey, medicationIds, medicationNames - see the class attributes.
  // Returns: The request.
  const ChatDoseRequest({
    required this.scheduleDate,
    required this.slotKey,
    required this.medicationIds,
    this.medicationNames = const [],
  });

  // Function Name: signature
  // Description: Identifies the same day, slot and medications across retries.
  // Parameters: None. Returns: "<date>:<slot>:<id,id,...>".
  String get signature =>
      '$scheduleDate:$slotKey:${medicationIds.join(',')}';
}

// Class Name: ChatDosePlan
// Role: Result of validating a chat selection against the current schedule.
// Responsibilities:
// - Carry the per-slot requests only when the whole selection is valid, so nothing is written
//   for a selection that is partly stale.
// Attributes:
// - status (ChatDosePlanStatus): Whether the selection can be recorded.
// - requests (List<ChatDoseRequest>): Writes in slot order; empty unless status is ready.
class ChatDosePlan {
  final ChatDosePlanStatus status;
  final List<ChatDoseRequest> requests;

  // Function Name: ChatDosePlan
  // Description: Stores the validation result.
  // Parameters: status - validation outcome; requests - planned writes for a ready plan.
  // Returns: The plan.
  const ChatDosePlan(this.status, [this.requests = const []]);
}

// Class Name: LinkedChatDoseRecorder
// Role: Owns dose recording for one account/link chat session outside the widget library.
// Responsibilities:
// - Record through the device outbox (DoseSyncService), the same path as the schedule screen,
//   whenever the session view model has one attached; production always does.
// - Fall back to the chat endpoint only without an outbox, reusing one request ID per dose
//   until that request succeeds.
// - Never write a dose or a day other than the one the patient selected.
// Attributes:
// - linkId/currentUserHash: Immutable conversation and account scope.
// - _control: Borrowed chat adapter; its owner disposes it.
// - _createRequestId: Source of chat request IDs for the fallback path.
// - _pendingRequestIds: Request IDs of fallback writes that have not succeeded yet.
class LinkedChatDoseRecorder {
  final int linkId;
  final String currentUserHash;
  final ManageLinkedChat _control;
  final String Function() _createRequestId;
  final Map<String, String> _pendingRequestIds = {};

  // Function Name: LinkedChatDoseRecorder
  // Description: Binds the recorder to one conversation and its borrowed chat adapter.
  // Parameters: linkId - conversation; currentUserHash - signed-in account; control - chat
  //   adapter; createRequestId - request ID generator for the fallback path.
  // Returns: A recorder without pending retries.
  LinkedChatDoseRecorder({
    required this.linkId,
    required this.currentUserHash,
    required ManageLinkedChat control,
    required String Function() createRequestId,
  }) : _control = control,
       _createRequestId = createRequestId;

  // Function Name: contextsFromDoseCache
  // Description:
  // - Groups the device's same-day schedule cache into the four slot contexts the chat uses,
  //   so a selection can be validated without a server request.
  // Parameters: schedules - projected schedules of the dose cache; day - dose day of that cache.
  // Returns: One context per slot in slot order; schedules without a numeric ID are left out.
  static List<ChatScheduleContext> contextsFromDoseCache(
    List<MedicationSchedule> schedules,
    String day,
  ) {
    return [
      for (final slotKey in medicationScheduleSlotKeys)
        ChatScheduleContext(
          scheduleDate: day,
          slotKey: slotKey,
          alarmTime: '',
          alarmEnabled: false,
          completedCount: 0,
          totalCount: schedules
              .where((schedule) => schedule.slotKeys.contains(slotKey))
              .length,
          medications: [
            for (final schedule in schedules)
              if (schedule.slotKeys.contains(slotKey))
                ?ChatMedicationContext.fromSchedule(schedule),
          ],
        ),
    ];
  }

  // Function Name: plan
  // Description:
  // - Splits the selection into one request per selected slot and checks every request against
  //   the schedule of the selected day before anything is written.
  // - Another dose or another day is never substituted for a stale selection.
  // Parameters: selected - medications with their selected slots; selectedDate - dose day the
  //   selection was made for; contexts - current slot contexts from the cache or the server.
  // Returns: A ready plan in slot order, scheduleChanged when a selected dose is missing on that
  //   day, or noSchedule when the selection contains no slot.
  static ChatDosePlan plan(
    List<ChatMedicationContext> selected,
    String? selectedDate,
    List<ChatScheduleContext> contexts,
  ) {
    final requests = <ChatDoseRequest>[];
    for (final slotKey in medicationScheduleSlotKeys) {
      final ids =
          selected
              .where((m) => m.scheduleSlotKeys.contains(slotKey))
              .map((m) => m.medicationId)
              .toSet()
              .toList()
            ..sort();
      if (ids.isEmpty) continue;
      final slot = contexts
          .where(
            (slot) =>
                slot.slotKey == slotKey && slot.scheduleDate == selectedDate,
          )
          .firstOrNull;
      final availableIds =
          slot?.medications.map((m) => m.medicationId).toSet() ?? <int>{};
      if (slot == null || !ids.every(availableIds.contains)) {
        return const ChatDosePlan(ChatDosePlanStatus.scheduleChanged);
      }
      requests.add(
        ChatDoseRequest(
          scheduleDate: slot.scheduleDate,
          slotKey: slot.slotKey,
          medicationIds: List.unmodifiable(ids),
          medicationNames: List.unmodifiable(
            selected
                .where((m) => ids.contains(m.medicationId))
                .map((m) => m.medicationName),
          ),
        ),
      );
    }
    if (requests.isEmpty) {
      return const ChatDosePlan(ChatDosePlanStatus.noSchedule);
    }
    return ChatDosePlan(ChatDosePlanStatus.ready, List.unmodifiable(requests));
  }

  // Function Name: _syncFor
  // Description: Uses the outbox only when it belongs to the account that opened this chat.
  // Parameters: viewModel - session view model read by the screen, if any.
  // Returns: The account's dose outbox, or null when none is attached for this account.
  DoseSyncService? _syncFor(MedBuddyViewModel? viewModel) {
    final sync = viewModel?.doseSync;
    return sync != null && sync.owner == currentUserHash ? sync : null;
  }

  // Function Name: cachedMedicationContexts
  // Description: Offers the device's same-day schedule as selectable medications when the
  //   server list cannot be loaded.
  // Parameters: viewModel - session view model read by the screen, if any.
  // Returns: Medications of the current-day cache, or null without such a cache.
  List<ChatMedicationContext>? cachedMedicationContexts(
    MedBuddyViewModel? viewModel,
  ) {
    final sync = _syncFor(viewModel);
    if (sync == null || !sync.hasCache) return null;
    return [
      for (final schedule in sync.schedules)
        ?ChatMedicationContext.fromSchedule(schedule),
    ];
  }

  // Function Name: selectionDay
  // Description: Names the dose day a new selection refers to, using the same source that
  //   loadScheduleContexts will validate it against.
  // Parameters: viewModel - session view model, if any; serverContexts - slot contexts the
  //   screen last received from the server.
  // Returns: The cache day, else the server's day, else today's dose day by the device clock.
  String selectionDay(
    MedBuddyViewModel? viewModel,
    List<ChatScheduleContext> serverContexts,
  ) {
    final sync = _syncFor(viewModel);
    if (sync != null && sync.hasCache) return doseScheduleDay(sync.clock());
    return serverContexts
            .map((context) => context.scheduleDate)
            .where((date) => date.isNotEmpty)
            .firstOrNull ??
        doseScheduleDay(DateTime.now());
  }

  // Function Name: loadScheduleContexts
  // Description: Reads the schedule a selection must match: the device cache of the current
  //   dose day when there is one, otherwise the server's slot contexts.
  // Parameters: viewModel - session view model read by the screen, if any.
  // Returns: Current slot contexts; a failed server request throws.
  Future<List<ChatScheduleContext>> loadScheduleContexts(
    MedBuddyViewModel? viewModel,
  ) async {
    final sync = _syncFor(viewModel);
    if (sync != null && sync.hasCache) {
      return contextsFromDoseCache(
        sync.schedules,
        doseScheduleDay(sync.clock()),
      );
    }
    return _control.requestScheduleContexts(linkId: linkId);
  }

  // Function Name: record
  // Description:
  // - With an outbox: stores the dose on the device with this link ID; the outbox uploads it
  //   and retries with one operation ID, and the confirmation message arrives from the server.
  // - Without an outbox: posts to the chat endpoint, reusing the request ID of an earlier
  //   failed attempt for the same dose, and applies the returned schedules to the view model
  //   of the same account.
  // Parameters: request - planned dose write; viewModel - session view model, if any.
  // Returns: The server-confirmed message of the fallback path, or null when the dose was
  //   stored in the outbox. Throws when the dose was not stored; the caller keeps the
  //   selection so the same request can be retried.
  Future<ChatMessage?> record(
    ChatDoseRequest request, {
    MedBuddyViewModel? viewModel,
  }) async {
    final sync = _syncFor(viewModel);
    if (sync != null) {
      await _queue(sync, request);
      return null;
    }
    final requestId = _pendingRequestIds.putIfAbsent(
      request.signature,
      _createRequestId,
    );
    final result = await _control.recordMedicationTaken(
      linkId: linkId,
      clientMessageId: requestId,
      scheduleDate: request.scheduleDate,
      slotKey: request.slotKey,
      medicationIds: request.medicationIds,
    );
    if (viewModel != null && viewModel.patientHash == currentUserHash) {
      viewModel.applyConfirmedTodaySchedules(result.schedules);
    }
    _pendingRequestIds.remove(request.signature);
    return result.message;
  }

  // Function Name: _queue
  // Description:
  // - Stores one dose in the outbox. When the service fails after it may already have stored
  //   the operation, the outbox is read again: a stored operation counts as success, so a
  //   retry cannot queue the same dose (and its chat message) twice.
  // Parameters: sync - this account's outbox; request - planned dose write.
  // Returns: Completion once the dose is stored; throws when it is not.
  Future<void> _queue(DoseSyncService sync, ChatDoseRequest request) async {
    final knownIds = {for (final op in sync.operations) op['operation_id']};
    final bool stored;
    try {
      stored = await sync.record(
        medicationIds: request.medicationIds,
        slotKey: request.slotKey,
        completed: true,
        scheduleDate: request.scheduleDate,
        linkId: linkId,
        medicationNames: request.medicationNames,
      );
    } catch (_) {
      if (await _wasStored(sync, request, knownIds)) return;
      rethrow;
    }
    if (!stored) throw StateError('Dose was not queued.');
  }

  // Function Name: _wasStored
  // Description: Checks the outbox for a new operation equal to the request after a failure.
  // Parameters: sync - this account's outbox; request - attempted write; knownIds - operation
  //   IDs that were waiting before the attempt.
  // Returns: True only when exactly this dose was stored by the failed attempt; an unreadable
  //   outbox counts as not stored.
  Future<bool> _wasStored(
    DoseSyncService sync,
    ChatDoseRequest request,
    Set<Object?> knownIds,
  ) async {
    try {
      await sync.reload();
    } catch (_) {
      return false;
    }
    return sync.operations.any((op) {
      final ids = op['medication_ids'];
      return !knownIds.contains(op['operation_id']) &&
          op['schedule_date'] == request.scheduleDate &&
          op['slot_key'] == request.slotKey &&
          op['completed'] == true &&
          op['link_id'] == linkId &&
          ids is List &&
          ids.join(',') == request.medicationIds.join(',');
    });
  }
}
