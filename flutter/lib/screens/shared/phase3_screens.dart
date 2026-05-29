import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../constants/app_constants.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';

// ─── Wallet Screen (Client) ───────────────────────────────────────────────────

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  List<dynamic> _transactions = [];
  bool _loading = true;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await apiService.getPaymentHistory();
      setState(() {
        _transactions = data['transactions'] ?? [];
        _total = data['total'] ?? 0;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Compute totals
    double totalSpent = 0;
    double escrowHeld = 0;
    for (final t in _transactions) {
      final amount = (t['amount'] ?? 0).toDouble();
      final status = t['status'] ?? '';
      if (status == 'held') escrowHeld += amount;
      if (status == 'released') totalSpent += amount;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Wallet', style: AppTextStyles.h2),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Summary cards
                  Row(
                    children: [
                      _WalletCard(
                        label: 'Total spent',
                        amount: totalSpent,
                        icon: Icons.payments_outlined,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      _WalletCard(
                        label: 'In escrow',
                        amount: escrowHeld,
                        icon: Icons.lock_outline,
                        color: AppColors.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Escrow explanation
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.08),
                      borderRadius: AppRadius.cardRadius,
                      border: Border.all(
                          color: AppColors.secondary.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.security,
                            color: AppColors.secondary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Payments are held securely in escrow '
                            'and released only when you confirm task completion.',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.secondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text('Transaction history', style: AppTextStyles.h3),
                  const SizedBox(height: 12),

                  if (_transactions.isEmpty)
                    _EmptyWallet()
                  else
                    ..._transactions.map((t) => _TransactionRow(tx: t)),
                ],
              ),
            ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  final String label;
  final double amount;
  final IconData icon;
  final Color color;
  const _WalletCard(
      {required this.label,
      required this.amount,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
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
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text('₦${amount.toStringAsFixed(0)}',
                style: AppTextStyles.amountMedium.copyWith(color: color)),
            Text(label, style: AppTextStyles.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final dynamic tx;
  const _TransactionRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final status = tx['status'] ?? '';
    final amount = (tx['amount'] ?? 0).toDouble();
    Color statusColor = AppColors.taskStatusColor(status);
    String statusLabel = {
      'pending': 'Pending',
      'held': 'In escrow',
      'released': 'Released',
      'refunded': 'Refunded',
      'failed': 'Failed',
    }[status] ?? status;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              status == 'released' ? Icons.check_circle_outline
                  : status == 'refunded' ? Icons.undo
                  : Icons.lock_outline,
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Task payment',
                    style: AppTextStyles.labelLarge),
                Text(tx['paid_at'] ?? tx['created_at'] ?? '',
                    style: AppTextStyles.labelSmall),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₦${amount.toStringAsFixed(0)}',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: AppColors.primary)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(statusLabel,
                    style: AppTextStyles.labelSmall
                        .copyWith(color: statusColor)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyWallet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Text('💳', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('No transactions yet', style: AppTextStyles.h3),
          const SizedBox(height: 6),
          Text('Post a task to get started',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ─── Review Screen ────────────────────────────────────────────────────────────

class ReviewScreen extends ConsumerStatefulWidget {
  final String taskId;
  final String taskTitle;
  const ReviewScreen(
      {super.key, required this.taskId, required this.taskTitle});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  int _overall = 0;
  int _punctuality = 0;
  int _trustworthiness = 0;
  int _communication = 0;
  int _professionalism = 0;
  final _commentCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    if (_overall == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide an overall rating')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await apiService.submitReview({
        'task_id': widget.taskId,
        'overall_rating': _overall,
        'punctuality': _punctuality > 0 ? _punctuality : _overall,
        'trustworthiness': _trustworthiness > 0 ? _trustworthiness : _overall,
        'communication': _communication > 0 ? _communication : _overall,
        'professionalism': _professionalism > 0 ? _professionalism : _overall,
        'comment': _commentCtrl.text.trim().isEmpty
            ? null
            : _commentCtrl.text.trim(),
      });
      if (mounted) context.go('/client/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit review: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text('Leave a Review', style: AppTextStyles.h2),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/client/home'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How was "${widget.taskTitle}"?',
                style: AppTextStyles.h2),
            const SizedBox(height: 4),
            Text('Your review helps build trust on the platform',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 32),

            _RatingRow(
              label: 'Overall',
              value: _overall,
              required: true,
              onChanged: (v) => setState(() => _overall = v),
            ),
            const SizedBox(height: 20),
            _RatingRow(
              label: 'Punctuality',
              value: _punctuality,
              onChanged: (v) => setState(() => _punctuality = v),
            ),
            const SizedBox(height: 20),
            _RatingRow(
              label: 'Trustworthiness',
              value: _trustworthiness,
              onChanged: (v) => setState(() => _trustworthiness = v),
            ),
            const SizedBox(height: 20),
            _RatingRow(
              label: 'Communication',
              value: _communication,
              onChanged: (v) => setState(() => _communication = v),
            ),
            const SizedBox(height: 20),
            _RatingRow(
              label: 'Professionalism',
              value: _professionalism,
              onChanged: (v) => setState(() => _professionalism = v),
            ),
            const SizedBox(height: 24),

            Text('Comment (optional)', style: AppTextStyles.labelLarge),
            const SizedBox(height: 6),
            TextField(
              controller: _commentCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Tell others about your experience...',
              ),
            ),
            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit Review'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go('/client/home'),
              child: const Text('Skip for now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final String label;
  final int value;
  final bool required;
  final ValueChanged<int> onChanged;

  const _RatingRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: AppTextStyles.labelLarge),
            if (required)
              Text(' *',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: AppColors.error)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(5, (i) {
            final starVal = i + 1;
            return GestureDetector(
              onTap: () => onChanged(starVal),
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  starVal <= value ? Icons.star : Icons.star_border,
                  color: AppColors.gold,
                  size: 36,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ─── Agent Earnings Screen ────────────────────────────────────────────────────

class AgentEarningsScreen extends ConsumerStatefulWidget {
  const AgentEarningsScreen({super.key});

  @override
  ConsumerState<AgentEarningsScreen> createState() =>
      _AgentEarningsScreenState();
}

class _AgentEarningsScreenState extends ConsumerState<AgentEarningsScreen> {
  List<dynamic> _transactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await apiService.getPaymentHistory();
      setState(() {
        _transactions = data['transactions'] ?? [];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double totalEarnings = 0;
    double pendingPayout = 0;
    for (final t in _transactions) {
      final payout = (t['agent_payout'] ?? 0).toDouble();
      if (t['status'] == 'released') totalEarnings += payout;
      if (t['status'] == 'held') pendingPayout += payout;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Earnings', style: AppTextStyles.h2)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Earnings summary
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppColors.trustGradient,
                      borderRadius: AppRadius.cardRadius,
                      boxShadow: AppShadows.elevated,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total earnings',
                            style: AppTextStyles.labelMedium
                                .copyWith(color: Colors.white70)),
                        const SizedBox(height: 4),
                        Text('₦${totalEarnings.toStringAsFixed(0)}',
                            style: AppTextStyles.amountLarge
                                .copyWith(color: Colors.white)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Pending payout',
                                    style: AppTextStyles.labelSmall
                                        .copyWith(color: Colors.white60)),
                                Text(
                                    '₦${pendingPayout.toStringAsFixed(0)}',
                                    style: AppTextStyles.h3
                                        .copyWith(color: Colors.white)),
                              ],
                            ),
                            const Spacer(),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('Completed jobs',
                                    style: AppTextStyles.labelSmall
                                        .copyWith(color: Colors.white60)),
                                Text('${_transactions.where((t) => t['status'] == 'released').length}',
                                    style: AppTextStyles.h3
                                        .copyWith(color: Colors.white)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text('Payout history', style: AppTextStyles.h3),
                  const SizedBox(height: 12),

                  if (_transactions.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            const Text('💰', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            Text('No earnings yet', style: AppTextStyles.h3),
                            const SizedBox(height: 6),
                            Text('Complete tasks to start earning',
                                style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._transactions.map((t) => _EarningRow(tx: t)),
                ],
              ),
            ),
    );
  }
}

class _EarningRow extends StatelessWidget {
  final dynamic tx;
  const _EarningRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final status = tx['status'] ?? '';
    final payout = (tx['agent_payout'] ?? 0).toDouble();
    final isReleased = status == 'released';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isReleased
                  ? AppColors.secondary.withOpacity(0.1)
                  : AppColors.warning.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isReleased ? Icons.check_circle_outline : Icons.hourglass_top,
              color: isReleased ? AppColors.secondary : AppColors.warning,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Task payout', style: AppTextStyles.labelLarge),
                Text(
                    isReleased
                        ? tx['released_at'] ?? ''
                        : 'Pending client confirmation',
                    style: AppTextStyles.labelSmall),
              ],
            ),
          ),
          Text(
            '₦${payout.toStringAsFixed(0)}',
            style: AppTextStyles.labelLarge.copyWith(
              color: isReleased ? AppColors.secondary : AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Notifications Screen ─────────────────────────────────────────────────────

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<dynamic> _notifications = [];
  int _unreadCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await apiService.getNotifications();
      setState(() {
        _notifications = data['notifications'] ?? [];
        _unreadCount = data['unread_count'] ?? 0;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    await apiService.markAllNotificationsRead();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Text('Notifications', style: AppTextStyles.h2),
            if (_unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$_unreadCount',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: Colors.white)),
              ),
            ],
          ],
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text('Mark all read',
                  style: AppTextStyles.labelMedium
                      .copyWith(color: AppColors.primary)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🔔', style: TextStyle(fontSize: 52)),
                      const SizedBox(height: 16),
                      Text('No notifications yet', style: AppTextStyles.h3),
                      const SizedBox(height: 8),
                      Text("You're all caught up!",
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _NotificationCard(n: _notifications[i]),
                  ),
                ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final dynamic n;
  const _NotificationCard({required this.n});

  IconData _iconForType(String type) {
    switch (type) {
      case 'agent_applied': return Icons.person_add_outlined;
      case 'application_accepted': return Icons.check_circle_outline;
      case 'task_started': return Icons.play_circle_outline;
      case 'proof_submitted': return Icons.camera_alt_outlined;
      case 'task_completed': return Icons.task_alt;
      case 'payment_released': return Icons.payments_outlined;
      case 'review_received': return Icons.star_outline;
      case 'level_up': return Icons.military_tech_outlined;
      case 'verification_approved': return Icons.verified_outlined;
      case 'verification_rejected': return Icons.cancel_outlined;
      case 'dispute_raised': return Icons.report_outlined;
      default: return Icons.notifications_outlined;
    }
  }

  Color _colorForType(String type) {
    if (type.contains('approved') || type.contains('accepted') ||
        type.contains('completed') || type.contains('released')) {
      return AppColors.secondary;
    }
    if (type.contains('rejected') || type.contains('dispute')) {
      return AppColors.error;
    }
    if (type == 'level_up') return AppColors.gold;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final type = n['type'] ?? '';
    final isRead = n['is_read'] ?? true;
    final color = _colorForType(type);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isRead ? AppColors.white : AppColors.primary.withOpacity(0.04),
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: isRead ? AppColors.border : AppColors.primary.withOpacity(0.2),
          width: isRead ? 0.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(_iconForType(type), color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(n['title'] ?? '',
                          style: AppTextStyles.labelLarge
                              .copyWith(
                                fontWeight: isRead
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                              )),
                    ),
                    if (!isRead)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(n['body'] ?? '',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Level-Up Celebration Screen ─────────────────────────────────────────────

class LevelUpScreen extends StatelessWidget {
  final String newLevel;
  const LevelUpScreen({super.key, required this.newLevel});

  @override
  Widget build(BuildContext context) {
    final levelColor = AppColors.trustLevelColor(newLevel);
    final levelEmoji = {
      'bronze': '🥉',
      'silver': '🥈',
      'gold': '🥇',
      'platinum': '💎',
    }[newLevel] ?? '🏆';

    final benefits = {
      'silver': [
        'Higher visibility in task searches',
        'Access to mid-tier tasks',
        'Silver badge on your profile',
      ],
      'gold': [
        'Priority placement in searches',
        'Access to premium tasks',
        'Gold badge + higher client trust',
        'Reduced platform fee (12%)',
      ],
      'platinum': [
        'Top placement in all searches',
        'Access to all task types',
        'Platinum badge — highest trust',
        'Reduced platform fee (10%)',
        'Featured on the homepage',
      ],
    }[newLevel] ?? [];

    return Scaffold(
      backgroundColor: levelColor.withOpacity(0.06),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Celebration animation placeholder
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.5, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, scale, child) => Transform.scale(
                  scale: scale,
                  child: child,
                ),
                child: Text(levelEmoji,
                    style: const TextStyle(fontSize: 96)),
              ),
              const SizedBox(height: 24),
              Text(
                'You levelled up!',
                style: AppTextStyles.displayMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                newLevel.toUpperCase(),
                style: AppTextStyles.trustLabel
                    .copyWith(color: levelColor, fontSize: 20),
              ),
              const SizedBox(height: 32),

              // Benefits
              if (benefits.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: AppRadius.cardRadius,
                    border:
                        Border.all(color: levelColor.withOpacity(0.3)),
                    boxShadow: AppShadows.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your new benefits',
                          style: AppTextStyles.h3),
                      const SizedBox(height: 12),
                      ...benefits.map((b) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle,
                                    color: levelColor, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(b,
                                      style: AppTextStyles.bodyMedium),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],

              ElevatedButton(
                onPressed: () => context.go('/agent/home'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: levelColor),
                child: const Text('Continue Earning'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
