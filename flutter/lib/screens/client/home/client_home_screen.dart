import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../constants/app_constants.dart';
import '../../../providers/providers.dart';
import '../../../models/models.dart';

class ClientHomeScreen extends ConsumerStatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(taskListProvider.notifier).loadTasks(refresh: true);
    });
  }

  final _categories = [
    ('shopping', '🛒', 'Shopping'),
    ('food_pickup', '🍔', 'Food'),
    ('cleaning', '🧹', 'Cleaning'),
    ('office_errand', '🏢', 'Office'),
    ('car_wash', '🚗', 'Car Wash'),
    ('custom', '✨', 'Custom'),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final taskState = ref.watch(taskListProvider);
    final user = auth.user;

    final activeTasks = taskState.tasks
        .where((t) => t.isActive || t.isOpen)
        .take(3)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(taskListProvider.notifier).loadTasks(refresh: true),
        child: CustomScrollView(
          slivers: [
            // App bar
            SliverAppBar(
              expandedHeight: 120,
              floating: true,
              snap: true,
              backgroundColor: AppColors.primary,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration:
                      const BoxDecoration(gradient: AppColors.primaryGradient),
                  padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Good ${_greeting()}, ${user?.fullName.split(' ').first ?? ''}! 👋',
                              style: AppTextStyles.h3
                                  .copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'What help do you need today?',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.white24,
                        child: user?.avatarUrl != null
                            ? null
                            : Text(
                                user?.fullName.substring(0, 1).toUpperCase() ?? 'U',
                                style: AppTextStyles.h3
                                    .copyWith(color: Colors.white),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Emergency banner
                  _EmergencyBanner(),
                  const SizedBox(height: 20),

                  // Quick actions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text('Quick actions', style: AppTextStyles.h3),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        final (id, emoji, label) = _categories[i];
                        return _QuickActionCard(
                          emoji: emoji,
                          label: label,
                          onTap: () => context.push(
                              '/client/post-task',
                              extra: id),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Active tasks
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('My tasks', style: AppTextStyles.h3),
                        if (taskState.tasks.isNotEmpty)
                          TextButton(
                            onPressed: () {},
                            child: Text('See all',
                                style: AppTextStyles.labelLarge
                                    .copyWith(color: AppColors.primary)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (taskState.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (activeTasks.isEmpty)
                    _EmptyTasksState()
                  else
                    ...activeTasks.map((t) => Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 6),
                          child: _TaskCard(task: t),
                        )),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),

      // FAB — Post task
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/client/post-task'),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Post Task',
            style: AppTextStyles.buttonMedium),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }
}

class _EmergencyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/client/post-task', extra: {'emergency': true}),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.emergency, AppColors.emergency.withOpacity(0.8)],
          ),
          borderRadius: AppRadius.cardRadius,
          boxShadow: [
            BoxShadow(
              color: AppColors.emergency.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Text('🚨', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Emergency errand?',
                      style: AppTextStyles.h3
                          .copyWith(color: Colors.white)),
                  Text('Get urgent help in minutes',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: Colors.white70)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Urgent',
                  style: AppTextStyles.labelMedium
                      .copyWith(color: AppColors.emergency)),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;
  const _QuickActionCard(
      {required this.emoji, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.cardRadius,
          boxShadow: AppShadows.subtle,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 4),
            Text(label,
                style: AppTextStyles.labelSmall,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskModel task;
  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final statusColor = AppColors.taskStatusColor(task.status);

    return GestureDetector(
      onTap: () => context.push('/client/task/${task.id}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.cardRadius,
          boxShadow: AppShadows.card,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(task.categoryEmoji,
                    style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(task.title,
                      style: AppTextStyles.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (task.isEmergency)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.emergencyBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('URGENT',
                        style: AppTextStyles.labelSmall
                            .copyWith(color: AppColors.emergency)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(task.statusLabel,
                      style: AppTextStyles.labelSmall
                          .copyWith(color: statusColor)),
                ),
                const Spacer(),
                Text('₦${task.budget.toStringAsFixed(0)}',
                    style: AppTextStyles.labelLarge
                        .copyWith(color: AppColors.primary)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    size: 18, color: AppColors.textTertiary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTasksState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            const Text('📭', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            Text('No tasks yet',
                style: AppTextStyles.h3),
            const SizedBox(height: 6),
            Text('Post your first task and get help from\nverified agents near you',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            SizedBox(
              width: 160,
              child: ElevatedButton(
                onPressed: () => context.go('/client/post-task'),
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(160, 44)),
                child: const Text('Post a Task'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
