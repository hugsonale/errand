import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../constants/app_constants.dart';
import '../../providers/providers.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';

// ─── Active Job Screen (Agent) ────────────────────────────────────────────────

class ActiveJobScreen extends ConsumerWidget {
  final String taskId;
  const ActiveJobScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskAsync = ref.watch(taskDetailProvider(taskId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Active Job', style: AppTextStyles.h2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go('/agent/home'),
        ),
      ),
      body: taskAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading job: $e')),
        data: (task) => _ActiveJobBody(task: task, ref: ref),
      ),
    );
  }
}

class _ActiveJobBody extends StatelessWidget {
  final TaskModel task;
  final WidgetRef ref;
  const _ActiveJobBody({required this.task, required this.ref});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
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
                Text('${task.categoryEmoji} ${task.title}', style: AppTextStyles.h2),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(task.pickupAddress,
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('₦${(task.finalPrice ?? task.budget).toStringAsFixed(0)}',
                    style: AppTextStyles.amountMedium),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Task details', style: AppTextStyles.h3),
          const SizedBox(height: 8),
          Text(task.description,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          if (task.specialInstructions != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.08),
                borderRadius: AppRadius.cardRadius,
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(task.specialInstructions!, style: AppTextStyles.bodySmall)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (task.status == 'accepted') ...[
            ElevatedButton.icon(
              onPressed: () async {
                await apiService.startTask(task.id);
                ref.invalidate(taskDetailProvider(task.id));
              },
              icon: const Icon(Icons.play_arrow, color: Colors.white),
              label: const Text('Start Task'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
            ),
          ],
          if (task.status == 'in_progress') ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.08),
                borderRadius: AppRadius.cardRadius,
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: AppColors.secondary),
                  const SizedBox(width: 10),
                  Text('Task in progress',
                      style: AppTextStyles.labelLarge.copyWith(color: AppColors.secondary)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _submitProof(context),
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              label: const Text('Submit Proof of Completion'),
            ),
          ],
          if (task.status == 'proof_submitted')
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: AppRadius.cardRadius,
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Proof submitted. Waiting for client to confirm.',
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary)),
                  ),
                ],
              ),
            ),
          if (task.status == 'completed')
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.08),
                borderRadius: AppRadius.cardRadius,
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.secondary),
                  const SizedBox(width: 10),
                  Text(
                      'Task completed! ₦${(task.finalPrice ?? task.budget).toStringAsFixed(0)} paid.',
                      style: AppTextStyles.labelLarge.copyWith(color: AppColors.secondary)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _submitProof(BuildContext context) {
    final notesCtrl = TextEditingController();
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
                    color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text('Submit Proof', style: AppTextStyles.h2),
            const SizedBox(height: 8),
            Text(
              'An OTP will be sent to the client to confirm the task is done.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Text('Notes (optional)', style: AppTextStyles.labelLarge),
            const SizedBox(height: 6),
            TextField(
              controller: notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Describe what was done...'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final formData = FormData.fromMap({
                  if (notesCtrl.text.isNotEmpty) 'notes': notesCtrl.text.trim(),
                });
                await apiService.submitProof(task.id, formData);
                ref.invalidate(taskDetailProvider(task.id));
              },
              child: const Text('Submit Completion'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Agent Profile Screen ─────────────────────────────────────────────────────

class AgentProfileScreen extends ConsumerStatefulWidget {
  final String agentId;
  const AgentProfileScreen({super.key, required this.agentId});

  @override
  ConsumerState<AgentProfileScreen> createState() => _AgentProfileScreenState();
}

class _AgentProfileScreenState extends ConsumerState<AgentProfileScreen> {
  AgentProfileModel? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await apiService.getAgentProfile(widget.agentId);
      setState(() {
        _profile = AgentProfileModel.fromJson(data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _ProfileBody(profile: _profile!),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final AgentProfileModel profile;
  const _ProfileBody({required this.profile});

  @override
  Widget build(BuildContext context) {
    final levelColor = AppColors.trustLevelColor(profile.trustLevel);
    final levelEmoji = {
      'bronze': '🥉',
      'silver': '🥈',
      'gold': '🥇',
      'platinum': '💎',
    }[profile.trustLevel] ?? '🥉';

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => Navigator.of(context).pop(),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [levelColor.withOpacity(0.85), levelColor.withOpacity(0.55)],
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 32),
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.white24,
                      child: Text(levelEmoji, style: const TextStyle(fontSize: 36)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${profile.trustLevel.toUpperCase()} AGENT',
                        style: AppTextStyles.trustLabel.copyWith(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: AppRadius.cardRadius,
                    border: Border.all(color: AppColors.border, width: 0.5),
                    boxShadow: AppShadows.card,
                  ),
                  child: Column(
                    children: [
                      Text(profile.trustScore.toStringAsFixed(2),
                          style: AppTextStyles.trustScore.copyWith(color: levelColor)),
                      Text('Trust Score',
                          style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _StatColumn(value: profile.completedTasks.toString(), label: 'Tasks done', icon: Icons.task_alt),
                          _StatColumn(value: '${profile.successRate.toStringAsFixed(0)}%', label: 'Success rate', icon: Icons.trending_up),
                          _StatColumn(value: profile.repeatClientCount.toString(), label: 'Repeat clients', icon: Icons.favorite_outline),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: AppRadius.cardRadius,
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.history, color: AppColors.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${profile.completedTasks} completed errands · '
                          '${profile.repeatClientCount} repeat clients · '
                          '${profile.yearsActive.toStringAsFixed(1)} years active',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (profile.bio != null) ...[
                  Text('About', style: AppTextStyles.h3),
                  const SizedBox(height: 8),
                  Text(profile.bio!,
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                ],
                if (profile.skillTags != null && profile.skillTags!.isNotEmpty) ...[
                  Text('Skills', style: AppTextStyles.h3),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: profile.skillTags!
                        .map((skill) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                              ),
                              child: Text(skill,
                                  style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  const _StatColumn({required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(height: 4),
        Text(value, style: AppTextStyles.h2),
        Text(label, style: AppTextStyles.labelSmall, textAlign: TextAlign.center),
      ],
    );
  }
}

// ─── KYC Flow Screen ──────────────────────────────────────────────────────────

class KycFlowScreen extends ConsumerStatefulWidget {
  const KycFlowScreen({super.key});

  @override
  ConsumerState<KycFlowScreen> createState() => _KycFlowScreenState();
}

class _KycFlowScreenState extends ConsumerState<KycFlowScreen> {
  int _step = 1;
  final _ninCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _guarantorNameCtrl = TextEditingController();
  final _guarantorPhoneCtrl = TextEditingController();
  final _guarantorRelCtrl = TextEditingController();
  bool _isLoading = false;

  Future<void> _submit() async {
    if (_ninCtrl.text.trim().length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NIN must be 11 digits')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final formData = FormData.fromMap({
        'nin_number': _ninCtrl.text.trim(),
        'address_text': _addressCtrl.text.trim(),
        'guarantor_name': _guarantorNameCtrl.text.trim(),
        'guarantor_phone': _guarantorPhoneCtrl.text.trim(),
        'guarantor_relationship': _guarantorRelCtrl.text.trim(),
      });
      await apiService.submitKyc(formData);
      if (mounted) context.go('/verification-pending');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text('Identity Verification', style: AppTextStyles.h2),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: _step / 3,
            backgroundColor: AppColors.surfaceVariant,
            color: AppColors.primary,
            minHeight: 3,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Step $_step of 3',
                style: AppTextStyles.labelMedium.copyWith(color: AppColors.secondary)),
            const SizedBox(height: 8),
            if (_step == 1) ...[
              Text('Your NIN details', style: AppTextStyles.h2),
              const SizedBox(height: 4),
              Text('Your National Identification Number',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              Text('NIN Number', style: AppTextStyles.labelLarge),
              const SizedBox(height: 6),
              TextField(
                controller: _ninCtrl,
                keyboardType: TextInputType.number,
                maxLength: 11,
                style: AppTextStyles.bodyLarge,
                decoration: const InputDecoration(hintText: '12345678901'),
              ),
            ],
            if (_step == 2) ...[
              Text('Your address', style: AppTextStyles.h2),
              const SizedBox(height: 24),
              Text('Home address', style: AppTextStyles.labelLarge),
              const SizedBox(height: 6),
              TextField(
                controller: _addressCtrl,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Full home address'),
              ),
            ],
            if (_step == 3) ...[
              Text('Guarantor info', style: AppTextStyles.h2),
              const SizedBox(height: 4),
              Text('Someone who can vouch for you',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              Text('Guarantor name', style: AppTextStyles.labelLarge),
              const SizedBox(height: 6),
              TextField(
                  controller: _guarantorNameCtrl,
                  decoration: const InputDecoration(hintText: 'Full name')),
              const SizedBox(height: 16),
              Text('Guarantor phone', style: AppTextStyles.labelLarge),
              const SizedBox(height: 6),
              TextField(
                controller: _guarantorPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(hintText: '08012345678'),
              ),
              const SizedBox(height: 16),
              Text('Relationship', style: AppTextStyles.labelLarge),
              const SizedBox(height: 6),
              TextField(
                controller: _guarantorRelCtrl,
                decoration: const InputDecoration(hintText: 'e.g. Family friend, Employer'),
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      if (_step < 3) {
                        setState(() => _step++);
                      } else {
                        _submit();
                      }
                    },
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_step < 3 ? 'Continue' : 'Submit for Review'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Verification Pending Screen ──────────────────────────────────────────────

class VerificationPendingScreen extends StatelessWidget {
  const VerificationPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_top, size: 52, color: AppColors.warning),
              ),
              const SizedBox(height: 28),
              Text('Verification under review',
                  style: AppTextStyles.h1, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'Our team is reviewing your documents. '
                'This typically takes 24–48 hours. '
                "You'll receive a notification once approved.",
                style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: AppRadius.cardRadius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('While you wait:', style: AppTextStyles.labelLarge),
                    const SizedBox(height: 12),
                    _WaitItem(icon: '🔔', text: 'Enable notifications for instant updates'),
                    _WaitItem(icon: '📱', text: 'Explore the app and learn how tasks work'),
                    _WaitItem(icon: '⭐', text: 'Once approved, you can go online and start earning'),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () => context.go('/agent/home'),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaitItem extends StatelessWidget {
  final String icon;
  final String text;
  const _WaitItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTextStyles.bodySmall)),
        ],
      ),
    );
  }
}