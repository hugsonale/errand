import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../constants/app_constants.dart';
import '../../../providers/providers.dart';

class PostTaskScreen extends ConsumerWidget {
  const PostTaskScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(postTaskProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () {
            if (state.step > 1) {
              ref.read(postTaskProvider.notifier).goBack();
            } else {
              ref.read(postTaskProvider.notifier).reset();
              context.go('/client/home');
            }
          },
        ),
        title: Text('Post a Task', style: AppTextStyles.h2),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: _StepProgressBar(step: state.step, total: 5),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: switch (state.step) {
          1 => const _StepCategory(),
          2 => const _StepDetails(),
          3 => const _StepBudget(),
          4 => const _StepReview(),
          5 => const _StepSuccess(),
          _ => const _StepCategory(),
        },
      ),
    );
  }
}

// ─── Progress Bar ─────────────────────────────────────────────────────────────

class _StepProgressBar extends StatelessWidget {
  final int step;
  final int total;
  const _StepProgressBar({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      value: step / total,
      backgroundColor: AppColors.surfaceVariant,
      color: AppColors.primary,
      minHeight: 3,
    );
  }
}

// ─── Step 1: Category ─────────────────────────────────────────────────────────

class _StepCategory extends ConsumerWidget {
  const _StepCategory();

  static const _categories = [
    ('shopping', '🛒', 'Shopping', 'Groceries, supermarket'),
    ('food_pickup', '🍔', 'Food Pickup', 'Restaurant, fast food'),
    ('cleaning', '🧹', 'Cleaning', 'House, office cleaning'),
    ('delivery', '📦', 'Delivery', 'Pick up & drop off'),
    ('office_errand', '🏢', 'Office Errand', 'Business tasks'),
    ('car_wash', '🚗', 'Car Wash', 'Clean your vehicle'),
    ('document_submission', '📄', 'Documents', 'Submissions, filings'),
    ('pharmacy', '💊', 'Pharmacy', 'Medicine pickup'),
    ('market_shopping', '🏪', 'Market', 'Open market shopping'),
    ('personal_assistance', '🤝', 'Personal Help', 'Assistance tasks'),
    ('queue_standing', '⏳', 'Queue', 'Stand in line for you'),
    ('elderly_care', '👴', 'Elderly Care', 'Help for family'),
    ('cooking_help', '🍳', 'Cooking', 'Meal preparation'),
    ('custom', '✨', 'Custom Task', 'Describe your need'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          child: Text('What type of task?', style: AppTextStyles.h2),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('Select a category to get started',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.5,
            ),
            itemCount: _categories.length,
            itemBuilder: (_, i) {
              final (id, emoji, label, sub) = _categories[i];
              return GestureDetector(
                onTap: () =>
                    ref.read(postTaskProvider.notifier).setCategory(id),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: AppRadius.cardRadius,
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppShadows.subtle,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(emoji,
                          style: const TextStyle(fontSize: 26)),
                      const SizedBox(height: 4),
                      Text(label, style: AppTextStyles.labelLarge),
                      Text(sub,
                          style: AppTextStyles.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Step 2: Details ──────────────────────────────────────────────────────────

class _StepDetails extends ConsumerStatefulWidget {
  const _StepDetails();

  @override
  ConsumerState<_StepDetails> createState() => _StepDetailsState();
}

class _StepDetailsState extends ConsumerState<_StepDetails> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _instrCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _instrCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(postTaskProvider.notifier).setDetails(
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          specialInstructions: _instrCtrl.text.trim().isEmpty
              ? null
              : _instrCtrl.text.trim(),
          pickupAddress: _addressCtrl.text.trim().isEmpty
              ? 'Lagos, Nigeria'
              : _addressCtrl.text.trim(),
          // In Phase 4, use geolocator to get real coordinates
          lat: 6.5244,
          lng: 3.3792,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(postTaskProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Describe your task', style: AppTextStyles.h2),
            const SizedBox(height: 4),
            Text('Category: ${state.category ?? ''}',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.secondary)),
            const SizedBox(height: 24),

            Text('Task title', style: AppTextStyles.labelLarge),
            const SizedBox(height: 6),
            TextFormField(
              controller: _titleCtrl,
              style: AppTextStyles.bodyLarge,
              validator: (v) => (v?.trim().length ?? 0) < 5
                  ? 'Title must be at least 5 characters'
                  : null,
              decoration: const InputDecoration(
                  hintText: 'e.g. Buy groceries from Shoprite'),
            ),
            const SizedBox(height: 20),

            Text('Description', style: AppTextStyles.labelLarge),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descCtrl,
              maxLines: 4,
              style: AppTextStyles.bodyLarge,
              validator: (v) => (v?.trim().length ?? 0) < 10
                  ? 'Please describe the task in more detail'
                  : null,
              decoration: const InputDecoration(
                hintText:
                    'Describe exactly what you need done, including any important details...',
              ),
            ),
            const SizedBox(height: 20),

            Text('Pickup location', style: AppTextStyles.labelLarge),
            const SizedBox(height: 6),
            TextFormField(
              controller: _addressCtrl,
              style: AppTextStyles.bodyLarge,
              decoration: const InputDecoration(
                hintText: 'Enter address or area',
                prefixIcon:
                    Icon(Icons.location_on, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 20),

            Text('Special instructions (optional)',
                style: AppTextStyles.labelLarge),
            const SizedBox(height: 6),
            TextFormField(
              controller: _instrCtrl,
              maxLines: 2,
              style: AppTextStyles.bodyLarge,
              decoration: const InputDecoration(
                hintText: 'Any specific requirements?',
              ),
            ),
            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: _next,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step 3: Budget ───────────────────────────────────────────────────────────

class _StepBudget extends ConsumerStatefulWidget {
  const _StepBudget();

  @override
  ConsumerState<_StepBudget> createState() => _StepBudgetState();
}

class _StepBudgetState extends ConsumerState<_StepBudget> {
  final _budgetCtrl = TextEditingController(text: '2000');
  bool _isEmergency = false;
  String _genderPref = 'any';

  void _next() {
    final budget = double.tryParse(_budgetCtrl.text);
    if (budget == null || budget < 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum budget is ₦500')),
      );
      return;
    }
    ref.read(postTaskProvider.notifier).setBudget(
          budget: budget,
          isEmergency: _isEmergency,
          genderPreference: _genderPref,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(postTaskProvider);
    final emergencyFee = (double.tryParse(_budgetCtrl.text) ?? 0) * 0.15;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Budget & preferences', style: AppTextStyles.h2),
          const SizedBox(height: 4),
          Text('Set your budget and task preferences',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 24),

          // Budget
          Text('Your budget (₦)', style: AppTextStyles.labelLarge),
          const SizedBox(height: 6),
          TextFormField(
            controller: _budgetCtrl,
            keyboardType: TextInputType.number,
            style: AppTextStyles.amountLarge,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixText: '₦ ',
              hintText: '2000',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Agents will see your budget and propose their price',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),

          // Emergency toggle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isEmergency
                  ? AppColors.emergencyBg
                  : AppColors.surfaceVariant,
              borderRadius: AppRadius.cardRadius,
              border: Border.all(
                color: _isEmergency
                    ? AppColors.emergency.withOpacity(0.4)
                    : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                const Text('🚨', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Emergency mode',
                          style: AppTextStyles.labelLarge
                              .copyWith(
                                  color: _isEmergency
                                      ? AppColors.emergency
                                      : AppColors.textPrimary)),
                      if (_isEmergency)
                        Text(
                            '+₦${emergencyFee.toStringAsFixed(0)} urgency fee',
                            style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.emergency)),
                    ],
                  ),
                ),
                Switch(
                  value: _isEmergency,
                  onChanged: (v) => setState(() => _isEmergency = v),
                  activeColor: AppColors.emergency,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Gender preference
          Text('Agent gender preference', style: AppTextStyles.labelLarge),
          const SizedBox(height: 10),
          Row(
            children: [
              ('any', 'Any'),
              ('female', 'Female only'),
              ('male', 'Male only'),
            ].map((opt) {
              final (val, label) = opt;
              final selected = _genderPref == val;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () => setState(() => _genderPref = val),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withOpacity(0.1)
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : AppColors.border,
                      ),
                    ),
                    child: Text(label,
                        style: AppTextStyles.labelMedium.copyWith(
                            color: selected
                                ? AppColors.primary
                                : AppColors.textSecondary)),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),

          ElevatedButton(
            onPressed: _next,
            child: const Text('Review Task'),
          ),
        ],
      ),
    );
  }
}

// ─── Step 4: Review ───────────────────────────────────────────────────────────

class _StepReview extends ConsumerWidget {
  const _StepReview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(postTaskProvider);
    final platformFee = state.budget * 0.15;
    final total = state.budget + (state.isEmergency ? state.budget * 0.15 : 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review your task', style: AppTextStyles.h2),
          const SizedBox(height: 4),
          Text('Confirm everything is correct before posting',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 24),

          _ReviewRow('Category', state.category ?? ''),
          _ReviewRow('Title', state.title ?? ''),
          _ReviewRow('Description', state.description ?? ''),
          _ReviewRow('Location', state.pickupAddress ?? 'Lagos, Nigeria'),
          _ReviewRow('Budget', '₦${state.budget.toStringAsFixed(0)}'),
          if (state.isEmergency)
            _ReviewRow('Emergency fee', '₦${(state.budget * 0.15).toStringAsFixed(0)}',
                valueColor: AppColors.emergency),
          _ReviewRow('Platform fee (15%)',
              '₦${platformFee.toStringAsFixed(0)}',
              valueColor: AppColors.textSecondary),
          const Divider(height: 24),
          _ReviewRow('Total charged now',
              '₦${total.toStringAsFixed(0)}',
              isTotal: true),
          const SizedBox(height: 8),

          // Escrow explanation
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.secondary.withOpacity(0.08),
              borderRadius: AppRadius.cardRadius,
              border: Border.all(
                  color: AppColors.secondary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline,
                    color: AppColors.secondary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Payment is held securely in escrow. '
                    'The agent is only paid after you confirm completion.',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.secondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(state.error!,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.error)),
            ),

          ElevatedButton(
            onPressed: state.isLoading
                ? null
                : () async {
                    final task = await ref
                        .read(postTaskProvider.notifier)
                        .submit();
                    if (task != null && context.mounted) {
                      ref.read(postTaskProvider.notifier).goToReview();
                    }
                  },
            child: state.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Post Task & Pay'),
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isTotal;

  const _ReviewRow(this.label, this.value,
      {this.valueColor, this.isTotal = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: isTotal
                  ? AppTextStyles.h3.copyWith(color: AppColors.primary)
                  : AppTextStyles.labelLarge.copyWith(
                      color: valueColor ?? AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Step 5: Success ──────────────────────────────────────────────────────────

class _StepSuccess extends ConsumerWidget {
  const _StepSuccess();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle,
                  color: AppColors.secondary, size: 56),
            ),
            const SizedBox(height: 24),
            Text('Task Posted!', style: AppTextStyles.displayMedium),
            const SizedBox(height: 8),
            Text(
              'Your task is live. Verified agents near you will apply shortly.',
              style: AppTextStyles.bodyLarge
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                ref.read(postTaskProvider.notifier).reset();
                ref
                    .read(taskListProvider.notifier)
                    .loadTasks(refresh: true);
                context.go('/client/home');
              },
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}
