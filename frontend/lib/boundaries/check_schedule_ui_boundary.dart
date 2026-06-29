import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../entities/medication_schedule_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../viewmodels/medbuddy_view_model.dart';

class CheckScheduleUI extends StatefulWidget {
  const CheckScheduleUI({super.key});

  void clickSchedule() {}

  Widget showSchedule() {
    return this;
  }

  @override
  State<CheckScheduleUI> createState() => _CheckScheduleUIState();
}

class _CheckScheduleUIState extends State<CheckScheduleUI> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MedBuddyViewModel>().fetchTodayMedicationSchedule();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MedBuddyViewModel>();
    final schedules = viewModel.todayMedicationScheduleList;

    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _ScheduleHeader(onBackRequested: () => Navigator.pop(context)),
            if (schedules.isNotEmpty) _ScheduleProgress(schedules: schedules),
            Expanded(child: _buildContent(viewModel, schedules)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    MedBuddyViewModel viewModel,
    List<MedicationSchedule> schedules,
  ) {
    if (viewModel.isTodayScheduleLoading && schedules.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: MedBuddyColors.primary),
      );
    }

    if (schedules.isEmpty) {
      return const _ScheduleEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 32),
      itemCount: schedules.length,
      itemBuilder: (context, index) {
        final schedule = schedules[index];
        return _ScheduleCard(
          schedule: schedule,
          onStatusChanged: (medicationStatus) async {
            final success = await viewModel.requestMedicationStatusUpdate(
              schedule,
              medicationStatus,
            );
            if (!context.mounted || success) {
              return;
            }

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Status update failed.'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        );
      },
    );
  }
}

class _ScheduleHeader extends StatelessWidget {
  final VoidCallback onBackRequested;

  const _ScheduleHeader({required this.onBackRequested});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 94,
      width: double.infinity,
      color: MedBuddyColors.primary,
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: onBackRequested,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 31),
          ),
          const Expanded(
            child: Text(
              '\uC624\uB298 \uBCF5\uC57D \uC77C\uC815',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _ScheduleProgress extends StatelessWidget {
  final List<MedicationSchedule> schedules;

  const _ScheduleProgress({required this.schedules});

  @override
  Widget build(BuildContext context) {
    final completedCount =
        schedules.where((schedule) => schedule.medicationStatus).length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: const Color(0xFFA4F4CF), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.08),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: MedBuddyColors.mint,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              color: MedBuddyColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '\uBCF5\uC57D \uC644\uB8CC',
                  style: TextStyle(
                    color: MedBuddyColors.primaryDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$completedCount / ${schedules.length}',
                  style: const TextStyle(
                    color: MedBuddyColors.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
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

class _ScheduleEmptyState extends StatelessWidget {
  const _ScheduleEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 328,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 42),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: MedBuddyRadii.largeCard,
          border: Border.all(color: MedBuddyColors.mint, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.10),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule_outlined,
              size: 54,
              color: MedBuddyColors.primary,
            ),
            SizedBox(height: 18),
            Text(
              '\uC624\uB298 \uC77C\uC815 \uC5C6\uC74C',
              style: TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final MedicationSchedule schedule;
  final Future<void> Function(bool medicationStatus) onStatusChanged;

  const _ScheduleCard({
    required this.schedule,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = schedule.medicationStatus;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.largeCard,
        border: Border.all(color: const Color(0xFFF3F4F6), width: 2),
        boxShadow: MedBuddyShadows.card,
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
            decoration: BoxDecoration(
              color: isCompleted ? const Color(0xFFECFDF5) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              border: const Border(
                bottom: BorderSide(color: MedBuddyColors.mint, width: 2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? MedBuddyColors.primary
                        : MedBuddyColors.textLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isCompleted
                        ? Icons.check_circle_outline
                        : Icons.schedule_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    schedule.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: isCompleted ? 'Undo' : 'Complete',
                  icon: Icon(
                    isCompleted
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: MedBuddyColors.primary,
                  ),
                  onPressed: () => onStatusChanged(!isCompleted),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Row(
              children: [
                _ScheduleChip(
                  icon: Icons.medical_information_outlined,
                  label: '\uC6A9\uB7C9',
                  value: schedule.dosage,
                ),
                const SizedBox(width: 8),
                _ScheduleChip(
                  icon: Icons.access_time_outlined,
                  label: '\uD69F\uC218',
                  value: schedule.intakeTime,
                ),
                const SizedBox(width: 8),
                _ScheduleChip(
                  icon: Icons.calendar_today_outlined,
                  label: '\uAE30\uAC04',
                  value: schedule.medicationTimeLabel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ScheduleChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue =
        value.trim().isEmpty ? '\uC815\uBCF4 \uC5C6\uC74C' : value.trim();

    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: MedBuddyColors.primary, size: 18),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '$label $displayValue',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MedBuddyColors.primaryDark,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
