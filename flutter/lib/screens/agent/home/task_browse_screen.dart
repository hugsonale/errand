import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../constants/app_constants.dart';
import '../../../providers/providers.dart';
import '../../../models/models.dart';
import '../../../services/api_service.dart';

class TaskBrowseScreen extends ConsumerStatefulWidget {
  const TaskBrowseScreen({super.key});

  @override
  ConsumerState<TaskBrowseScreen> createState() => _TaskBrowseScreenState();
}

class _TaskBrowseScreenState extends ConsumerState<TaskBrowseScreen> {
  String? _selectedCategory;
  bool _emergencyOnly = false;
  double _radiusKm = 10.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(taskListProvider.notifier).loadTasks(
            refresh: true,
            category: _selectedCategory,
            isEmergency: _emergencyOnly ? true : null,
            lat: 6.5244,  // Phase 4: use real GPS
            lng: 3.3792,
          );
    });
  }

  void _applyFilters() {
    ref.read(taskListProvider.notifier).loadTasks(
          refresh: true,
          category: _selectedCategory,
          isEmergency: _emergencyOnly ? true : null,
          lat: 6.5244,
          lng: 3.3792,
        );
  }

  @override
  Widget build(BuildContext context) {
    final taskState = ref.watch(taskListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Nearby Tasks', style: AppTextStyles.h2),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => _showFilters(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Category chips
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _selectedCategory == null,
                  onTap: () => setState(() {
                    _selectedCategory = null;
                    _applyFilters();
                  }),
                ),
                const SizedBox(width: 8),
                ...['shopping', 'food_pickup', 'cleaning', 'delivery',
                    'office_errand', 'pharmacy']
                    .map((cat) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _FilterChip(
                            label: _catLabel(cat),
                            selected: _selectedCategory == cat,
                            onTap: () => setState(() {
                              _selectedCategory = cat;
                              _applyFilters();
                            }),
                          ),
                        ))
                    .toList(),
              ],
            ),
          ),

          // Emergency toggle bar
          if (_emergencyOnly)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.emergencyBg,
              child: Row(
                children: [
                  const Text('🚨', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text('Emergency tasks only',
                      style: AppTextStyles.labelMedium
                          .copyWith(color: AppColors.emergency)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _emergencyOnly = false;
                      _applyFilters();
                    }),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),

          // Task list
          Expanded(
            child: taskState.isLoading && taskState.tasks.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : taskState.tasks.isEmpty
                    ? _EmptyTasksState(onRefresh: () => _applyFilters())
                    : RefreshIndicator(
                        onRefresh: () async => _applyFilters(),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: taskState.tasks.length +
                              (taskState.hasMore ? 1 : 0),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            if (i == taskState.tasks.length) {
                              // Load more trigger
                              ref
                                  .read(taskListProvider.notifier)
                                  .loadTasks(
                                    category: _selectedCategory,
                                    lat: 6.5244,
                                    lng: 3.3792,
                                  );
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            return _AgentTaskCard(
                              task: taskState.tasks[i],
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _showFilters(BuildContext context) {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Filter Tasks', style: AppTextStyles.h2),
            const SizedBox(height: 20),
            Text('Search radius', style: AppTextStyles.labelLarge),
            Slider(
              value: _radiusKm,
              min: 1,
              max: 30,
              divisions: 29,
              label: '${_radiusKm.toStringAsFixed(0)} km',
              activeColor: AppColors.primary,
              onChanged: (v) => setState(() => _radiusKm = v),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: Text('Emergency tasks only',
                  style: AppTextStyles.labelLarge),
              subtitle: Text('Higher pay, immediate response needed',
                  style: AppTextStyles.bodySmall),
              value: _emergencyOnly,
              activeColor: AppColors.emergency,
              onChanged: (v) => setState(() => _emergencyOnly = v),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _applyFilters();
              },
              child: const Text('Apply Filters'),
            ),
          ],
        ),
      ),
    );
  }

  String _catLabel(String cat) {
    final labels = {
      'shopping': '🛒 Shopping',
      'food_pickup': '🍔 Food',
      'cleaning': '🧹 Cleaning',
      'delivery': '📦 Delivery',
      'office_errand': '🏢 Office',
      'pharmacy': '💊 Pharmacy',
    };
    return labels[cat] ?? cat;
  }
}

// ─── Agent Task Card ──────────────────────────────────────────────────────────

class _AgentTaskCard extends ConsumerWidget {
  final TaskModel task;
  const _AgentTaskCard({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showTaskBottomSheet(context, ref),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(
            color: task.isEmergency
                ? AppColors.emergency.withOpacity(0.4)
                : AppColors.border,
            width: task.isEmergency ? 1.5 : 0.5,
          ),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text(task.categoryEmoji,
                    style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title,
                          style: AppTextStyles.labelLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(task.categoryLabel,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₦${task.budget.toStringAsFixed(0)}',
                        style: AppTextStyles.amountMedium),
                    if (task.isEmergency)
                      Text('+15% fee',
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.emergency)),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Location and badges
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(task.pickupAddress,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (task.isEmergency)
                  _Badge(label: '🚨 URGENT', color: AppColors.emergency),
                if (task.isEmergency) const SizedBox(width: 8),
                _Badge(
                    label:
                        '${task.applicationCount} applied',
                    color: AppColors.primary),
                const SizedBox(width: 8),
                _Badge(
                    label: task.genderPreference == 'any'
                        ? 'Any gender'
                        : task.genderPreference == 'female'
                            ? '👩 Female pref'
                            : '👨 Male pref',
                    color: AppColors.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTaskBottomSheet(BuildContext context, WidgetRef ref) {
    final proposedPriceCtrl =
        TextEditingController(text: task.budget.toStringAsFixed(0));
    final messageCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('${task.categoryEmoji} ${task.title}',
                style: AppTextStyles.h2),
            const SizedBox(height: 4),
            Text(task.pickupAddress,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            Text(task.description,
                style:
                    AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 20),

            Text('Your proposed price (₦)',
                style: AppTextStyles.labelLarge),
            const SizedBox(height: 6),
            TextField(
              controller: proposedPriceCtrl,
              keyboardType: TextInputType.number,
              style: AppTextStyles.amountMedium,
              decoration: const InputDecoration(prefixText: '₦ '),
            ),
            const SizedBox(height: 16),

            Text('Message to client (optional)',
                style: AppTextStyles.labelLarge),
            const SizedBox(height: 6),
            TextField(
              controller: messageCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Tell the client why you\'re the right person...',
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: () async {
                final price = double.tryParse(proposedPriceCtrl.text);
                if (price == null || price < 500) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Minimum price is ₦500')),
                  );
                  return;
                }
                Navigator.pop(context);
                try {
                  await apiService.applyToTask(task.id, {
                    'proposed_price': price,
                    if (messageCtrl.text.isNotEmpty)
                      'message': messageCtrl.text.trim(),
                    'eta_minutes': 30,
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Application submitted! ✅'),
                        backgroundColor: AppColors.secondary,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed: $e')),
                    );
                  }
                }
              },
              child: const Text('Apply for Task'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style:
              AppTextStyles.labelSmall.copyWith(color: color)),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _EmptyTasksState extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyTasksState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🔍', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            Text('No tasks nearby', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            Text(
              'No tasks match your filters right now.\nCheck back soon or expand your search radius.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onRefresh,
              child: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}
