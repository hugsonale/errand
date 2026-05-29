import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../constants/app_constants.dart';
import '../../../providers/providers.dart';
import '../../../models/models.dart';
import '../../../services/api_service.dart';

// ─── Task Detail Screen ───────────────────────────────────────────────────────

class TaskDetailScreen extends ConsumerWidget {
  final String taskId;
  const TaskDetailScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskAsync = ref.watch(taskDetailProvider(taskId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Task Details', style: AppTextStyles.h2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go('/client/home'),
        ),
      ),
      body: taskAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text('Failed to load task', style: AppTextStyles.bodyLarge),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(taskDetailProvider(taskId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (task) => _TaskDetailBody(task: task),
      ),
    );
  }
}

class _TaskDetailBody extends ConsumerWidget {
  final TaskModel task;
  const _TaskDetailBody({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = AppColors.taskStatusColor(task.status);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status + Emergency badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(task.statusLabel,
                        style: AppTextStyles.labelMedium
                            .copyWith(color: statusColor)),
                  ],
                ),
              ),
              if (task.isEmergency) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.emergencyBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('🚨 URGENT',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.emergency)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Title
          Text('${task.categoryEmoji}  ${task.title}',
              style: AppTextStyles.h1),
          const SizedBox(height: 8),

          // Budget
          Row(
            children: [
              Text('Budget: ',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary)),
              Text('₦${task.budget.toStringAsFixed(0)}',
                  style: AppTextStyles.amountMedium),
            ],
          ),
          const SizedBox(height: 20),

          // Description card
          _InfoCard(
            title: 'Description',
            icon: Icons.description_outlined,
            child: Text(task.description, style: AppTextStyles.bodyMedium),
          ),
          const SizedBox(height: 12),

          // Location card
          _InfoCard(
            title: 'Pickup location',
            icon: Icons.location_on_outlined,
            child: Text(task.pickupAddress, style: AppTextStyles.bodyMedium),
          ),
          const SizedBox(height: 12),

          if (task.specialInstructions != null) ...[
            _InfoCard(
              title: 'Special instructions',
              icon: Icons.info_outline,
              child: Text(task.specialInstructions!,
                  style: AppTextStyles.bodyMedium),
            ),
            const SizedBox(height: 12),
          ],

          // Preferences
          _InfoCard(
            title: 'Preferences',
            icon: Icons.tune,
            child: Column(
              children: [
                _PrefRow('Gender preference',
                    task.genderPreference == 'any'
                        ? 'Any'
                        : task.genderPreference == 'female'
                            ? 'Female only'
                            : 'Male only'),
                if (task.preferredAgentsOnly)
                  _PrefRow('Agent filter', 'Preferred agents only'),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Applicants CTA
          if (task.isOpen) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: AppRadius.cardRadius,
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people_outline,
                      color: AppColors.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${task.applicationCount} agent${task.applicationCount == 1 ? '' : 's'} applied',
                            style: AppTextStyles.h3),
                        Text('Review and select the best match',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: AppColors.primary),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: task.applicationCount > 0
                  ? () => context
                      .push('/client/task/${ task.id}/applicants')
                  : null,
              child: Text(task.applicationCount > 0
                  ? 'View Applicants'
                  : 'Waiting for agents...'),
            ),
          ],

          // Active task CTA
          if (task.isActive)
            ElevatedButton(
              onPressed: () =>
                  context.push('/client/task/${task.id}/track'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary),
              child: const Text('Track Task Live'),
            ),

          // Cancel button
          if (task.isOpen || task.status == 'accepted') ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _confirmCancel(context, ref),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
              ),
              child: const Text('Cancel Task'),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _confirmCancel(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel task?'),
        content: const Text(
            'Are you sure you want to cancel this task? If payment was made, a refund will be processed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep task')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await apiService.cancelTask(task.id);
              if (context.mounted) {
                ref.invalidate(taskDetailProvider(task.id));
                context.go('/client/home');
              }
            },
            child: Text('Cancel task',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _InfoCard(
      {required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: AppShadows.subtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(title,
                  style: AppTextStyles.labelMedium
                      .copyWith(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _PrefRow extends StatelessWidget {
  final String label;
  final String value;
  const _PrefRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text('$label: ',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          Text(value, style: AppTextStyles.labelMedium),
        ],
      ),
    );
  }
}

// ─── Applicants Screen ────────────────────────────────────────────────────────

class ApplicantsScreen extends ConsumerWidget {
  final String taskId;
  const ApplicantsScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskAsync = ref.watch(taskDetailProvider(taskId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Choose an Agent', style: AppTextStyles.h2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
      ),
      body: taskAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load')),
        data: (task) {
          if (task.applications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('⏳', style: TextStyle(fontSize: 52)),
                  const SizedBox(height: 16),
                  Text('No applications yet', style: AppTextStyles.h3),
                  const SizedBox(height: 8),
                  Text('Verified agents near you will apply soon',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary),
                      textAlign: TextAlign.center),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Text(
                        '${task.applications.length} agent${task.applications.length == 1 ? '' : 's'} interested',
                        style: AppTextStyles.h3),
                    const Spacer(),
                    Text('Sorted by trust score',
                        style: AppTextStyles.labelSmall),
                  ],
                ),
              ),

              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 8),
                  itemCount: task.applications.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final app = task.applications[i];
                    return _ApplicationCard(
                      application: app,
                      onSelect: () =>
                          _selectAgent(context, ref, task, app),
                      onViewProfile: () => context.push(
                          '/agent/${app.agentId}/profile'),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _selectAgent(BuildContext context, WidgetRef ref, TaskModel task,
      ApplicationModel app) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Hire ${app.agentName ?? 'this agent'}?',
                style: AppTextStyles.h2),
            const SizedBox(height: 8),
            Text(
                'Their proposed price is ₦${app.proposedPrice.toStringAsFixed(0)}. '
                'Payment will be held in escrow until you confirm the task is complete.',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await apiService.acceptApplication(task.id, app.id);
                if (context.mounted) {
                  ref.invalidate(taskDetailProvider(task.id));
                  context.go('/client/task/${task.id}/track');
                }
              },
              child: Text(
                  'Hire for ₦${app.proposedPrice.toStringAsFixed(0)}'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  final ApplicationModel application;
  final VoidCallback onSelect;
  final VoidCallback onViewProfile;

  const _ApplicationCard({
    required this.application,
    required this.onSelect,
    required this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) {
    final trustColor =
        AppColors.trustLevelColor(application.agentTrustLevel ?? 'bronze');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Agent header
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: trustColor.withOpacity(0.15),
                child: Text(
                  (application.agentName ?? 'A')
                      .substring(0, 1)
                      .toUpperCase(),
                  style: AppTextStyles.h2.copyWith(color: trustColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(application.agentName ?? 'Agent',
                        style: AppTextStyles.labelLarge),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: trustColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${(application.agentTrustLevel ?? 'bronze').toUpperCase()}',
                            style: AppTextStyles.labelSmall
                                .copyWith(color: trustColor),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.star,
                            size: 14, color: AppColors.gold),
                        const SizedBox(width: 2),
                        Text(
                            application.agentTrustScore
                                    ?.toStringAsFixed(1) ??
                                '0.0',
                            style: AppTextStyles.labelMedium),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₦${application.proposedPrice.toStringAsFixed(0)}',
                      style: AppTextStyles.amountMedium),
                  if (application.etaMinutes != null)
                    Text('~${application.etaMinutes} min',
                        style: AppTextStyles.labelSmall),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Stats row
          Row(
            children: [
              _StatChip(
                icon: Icons.task_alt,
                label:
                    '${application.agentCompletedTasks ?? 0} tasks',
              ),
            ],
          ),

          // Message
          if (application.message != null &&
              application.message!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('"${application.message}"',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic)),
            ),
          ],

          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onViewProfile,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                  ),
                  child: const Text('View Profile'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onSelect,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                  ),
                  child: const Text('Select'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: AppTextStyles.labelSmall),
        ],
      ),
    );
  }
}

// ─── Active Task Tracking Screen ──────────────────────────────────────────────

class ActiveTaskScreen extends ConsumerStatefulWidget {
  final String taskId;
  const ActiveTaskScreen({super.key, required this.taskId});

  @override
  ConsumerState<ActiveTaskScreen> createState() => _ActiveTaskScreenState();
}

class _ActiveTaskScreenState extends ConsumerState<ActiveTaskScreen> {
  @override
  Widget build(BuildContext context) {
    final taskAsync = ref.watch(taskDetailProvider(widget.taskId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Live Tracking', style: AppTextStyles.h2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go('/client/home'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(taskDetailProvider(widget.taskId)),
          ),
        ],
      ),
      body: taskAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading task')),
        data: (task) => _ActiveTaskBody(task: task, ref: ref),
      ),
    );
  }
}

class _ActiveTaskBody extends StatelessWidget {
  final TaskModel task;
  final WidgetRef ref;
  const _ActiveTaskBody({required this.task, required this.ref});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Map placeholder (Phase 4 adds real Google Maps)
          Container(
            height: 220,
            width: double.infinity,
            color: const Color(0xFFE8F4FD),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.map, size: 80, color: Color(0xFFB0D4EF)),
                Positioned(
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text('Live map — Phase 4',
                            style: AppTextStyles.labelMedium
                                .copyWith(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Task timeline
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Task Progress', style: AppTextStyles.h3),
                const SizedBox(height: 16),
                _TimelineStep(
                  label: 'Task posted',
                  sublabel: 'Your task is live',
                  done: true,
                  isFirst: true,
                ),
                _TimelineStep(
                  label: 'Agent accepted',
                  sublabel: task.acceptedAt != null
                      ? 'Agent on the way'
                      : 'Awaiting agent selection',
                  done: task.acceptedAt != null,
                ),
                _TimelineStep(
                  label: 'Task in progress',
                  sublabel: task.startedAt != null
                      ? 'Agent is working'
                      : 'Waiting to start',
                  done: task.startedAt != null,
                ),
                _TimelineStep(
                  label: 'Proof submitted',
                  sublabel: task.status == 'proof_submitted' ||
                          task.status == 'completed'
                      ? 'Agent submitted completion proof'
                      : 'Awaiting completion',
                  done: task.status == 'proof_submitted' ||
                      task.status == 'completed',
                ),
                _TimelineStep(
                  label: 'Task completed',
                  sublabel: task.completedAt != null
                      ? 'Payment released to agent'
                      : 'Confirm to release payment',
                  done: task.completedAt != null,
                  isLast: true,
                ),

                const SizedBox(height: 24),

                // Action button based on status
                if (task.status == 'proof_submitted') ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.08),
                      borderRadius: AppRadius.cardRadius,
                      border: Border.all(
                          color: AppColors.secondary.withOpacity(0.3)),
                    ),
                    child: Text(
                      'The agent has submitted proof of completion. '
                      'Review the proof and confirm to release payment.',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.secondary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () =>
                        _confirmCompletion(context, task.id, ref),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.secondary),
                    child: const Text('Confirm & Release Payment'),
                  ),
                ],

                if (task.status == 'completed')
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.08),
                      borderRadius: AppRadius.cardRadius,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.secondary),
                        const SizedBox(width: 10),
                        Text('Task completed! Payment released.',
                            style: AppTextStyles.labelLarge
                                .copyWith(color: AppColors.secondary)),
                      ],
                    ),
                  ),

                // Dispute button
                if (['accepted', 'in_progress', 'proof_submitted']
                    .contains(task.status)) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => _raiseDispute(context, task.id, ref),
                    child: Text('Report an issue',
                        style: AppTextStyles.labelLarge
                            .copyWith(color: AppColors.error)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmCompletion(
      BuildContext context, String taskId, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) {
        final otpCtrl = TextEditingController();
        return AlertDialog(
          title: const Text('Confirm completion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Enter the 6-digit code the agent gave you, or tap confirm if you\'re satisfied with the work.'),
              const SizedBox(height: 16),
              TextField(
                controller: otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  hintText: 'OTP (optional)',
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await apiService.confirmCompletion(
                  taskId,
                  otpCode:
                      otpCtrl.text.isEmpty ? null : otpCtrl.text.trim(),
                );
                ref.invalidate(taskDetailProvider(taskId));
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  void _raiseDispute(BuildContext context, String taskId, WidgetRef ref) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Report an issue'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Describe what went wrong:'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText: 'e.g. Agent didn\'t show up...'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              if (reasonCtrl.text.trim().length < 20) return;
              Navigator.pop(context);
              await apiService.raiseDispute(taskId, {
                'reason': 'Agent issue',
                'description': reasonCtrl.text.trim(),
              });
              ref.invalidate(taskDetailProvider(taskId));
            },
            child: const Text('Submit Dispute'),
          ),
        ],
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool done;
  final bool isFirst;
  final bool isLast;

  const _TimelineStep({
    required this.label,
    required this.sublabel,
    required this.done,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline indicator
        Column(
          children: [
            if (!isFirst)
              Container(width: 2, height: 12, color: done ? AppColors.secondary : AppColors.border),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: done ? AppColors.secondary : AppColors.border,
                shape: BoxShape.circle,
              ),
              child: done
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            if (!isLast)
              Container(width: 2, height: 36, color: done ? AppColors.secondary : AppColors.border),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTextStyles.labelLarge.copyWith(
                        color: done
                            ? AppColors.textPrimary
                            : AppColors.textTertiary)),
                Text(sublabel,
                    style: AppTextStyles.bodySmall.copyWith(
                        color: done
                            ? AppColors.textSecondary
                            : AppColors.textTertiary)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
