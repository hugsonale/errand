import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../constants/app_constants.dart';
import '../../../providers/providers.dart';
import '../../../models/models.dart';

class AgentHomeScreen extends ConsumerStatefulWidget {
  const AgentHomeScreen({super.key});

  @override
  ConsumerState<AgentHomeScreen> createState() => _AgentHomeScreenState();
}

class _AgentHomeScreenState extends ConsumerState<AgentHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(agentProfileProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final agentState = ref.watch(agentProfileProvider);
    final user = auth.user;
    final profile = agentState.profile;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () => ref.read(agentProfileProvider.notifier).load(),
        child: CustomScrollView(
          slivers: [
            // Header
            SliverAppBar(
              expandedHeight: 140,
              floating: true,
              snap: true,
              backgroundColor: AppColors.primary,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient,
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hi, ${user?.fullName.split(' ').first ?? 'Agent'} 👋',
                                  style: AppTextStyles.h2
                                      .copyWith(color: Colors.white),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: profile?.isAvailable == true
                                            ? AppColors.secondary
                                            : Colors.white38,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      profile?.isAvailable == true
                                          ? 'Online — ready for tasks'
                                          : 'Offline',
                                      style: AppTextStyles.bodySmall
                                          .copyWith(color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Online/offline toggle
                          if (agentState.isLoading)
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          else
                            GestureDetector(
                              onTap: () async {
                                final newVal =
                                    !(profile?.isAvailable ?? false);
                                final ok = await ref
                                    .read(agentProfileProvider.notifier)
                                    .toggleAvailability(newVal);
                                if (!ok && mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                    content: Text(
                                        'Complete verification to go online'),
                                  ));
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: profile?.isAvailable == true
                                      ? AppColors.secondary
                                      : Colors.white24,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      profile?.isAvailable == true
                                          ? Icons.wifi
                                          : Icons.wifi_off,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      profile?.isAvailable == true
                                          ? 'Online'
                                          : 'Go Online',
                                      style: AppTextStyles.labelMedium
                                          .copyWith(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
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
                  // Trust score card
                  if (profile != null)
                    _TrustScoreCard(profile: profile),

                  const SizedBox(height: 20),

                  // Quick stats
                  if (profile != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          _QuickStat(
                            label: 'Completed',
                            value: profile.completedTasks.toString(),
                            icon: Icons.task_alt,
                            color: AppColors.secondary,
                          ),
                          const SizedBox(width: 12),
                          _QuickStat(
                            label: 'Success rate',
                            value:
                                '${profile.successRate.toStringAsFixed(0)}%',
                            icon: Icons.trending_up,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 12),
                          _QuickStat(
                            label: 'Trust score',
                            value: profile.trustScore.toStringAsFixed(1),
                            icon: Icons.star,
                            color: AppColors.gold,
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Browse tasks CTA
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ElevatedButton.icon(
                      onPressed: () => context.go('/agent/browse'),
                      icon: const Icon(Icons.search, color: Colors.white),
                      label: const Text('Browse Nearby Tasks'),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Verification status if not approved
                  if (profile != null)
                    _VerificationBanner(profile: profile),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustScoreCard extends StatelessWidget {
  final AgentProfileModel profile;
  const _TrustScoreCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final levelColor = AppColors.trustLevelColor(profile.trustLevel);
    final levelEmoji = {
      'bronze': '🥉',
      'silver': '🥈',
      'gold': '🥇',
      'platinum': '💎',
    }[profile.trustLevel] ??
        '🥉';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            levelColor.withOpacity(0.12),
            levelColor.withOpacity(0.05),
          ],
        ),
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: levelColor.withOpacity(0.3)),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          // Trust badge
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: levelColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(levelEmoji,
                  style: const TextStyle(fontSize: 28)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${profile.trustLevel.toUpperCase()} AGENT',
                  style: AppTextStyles.trustLabel
                      .copyWith(color: levelColor),
                ),
                const SizedBox(height: 2),
                Text(
                  profile.trustScore.toStringAsFixed(2),
                  style:
                      AppTextStyles.trustScore.copyWith(color: levelColor),
                ),
                const SizedBox(height: 4),
                _TrustProgress(
                    level: profile.trustLevel,
                    tasks: profile.completedTasks,
                    score: profile.trustScore),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustProgress extends StatelessWidget {
  final String level;
  final int tasks;
  final double score;

  const _TrustProgress(
      {required this.level, required this.tasks, required this.score});

  double get _progress {
    if (level == 'bronze') {
      return (tasks / 10.0).clamp(0.0, 1.0);
    } else if (level == 'silver') {
      return ((tasks - 10) / 40.0).clamp(0.0, 1.0);
    } else if (level == 'gold') {
      return ((tasks - 50) / 50.0).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  String get _nextLabel {
    if (level == 'bronze') return '${10 - tasks} tasks to Silver';
    if (level == 'silver') return '${50 - tasks} tasks to Gold';
    if (level == 'gold') return '${100 - tasks} tasks to Platinum';
    return 'Platinum — highest level!';
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.trustLevelColor(level);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _progress,
            backgroundColor: color.withOpacity(0.15),
            color: color,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text(_nextLabel, style: AppTextStyles.labelSmall),
      ],
    );
  }
}

class _QuickStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _QuickStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(color: AppColors.border, width: 0.5),
          boxShadow: AppShadows.subtle,
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(value,
                style:
                    AppTextStyles.h3.copyWith(color: AppColors.textPrimary)),
            Text(label, style: AppTextStyles.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _VerificationBanner extends StatelessWidget {
  final AgentProfileModel profile;
  const _VerificationBanner({required this.profile});

  @override
  Widget build(BuildContext context) {
    // We'd check verification status here
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.warning.withOpacity(0.08),
          borderRadius: AppRadius.cardRadius,
          border:
              Border.all(color: AppColors.warning.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline,
                color: AppColors.warning, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Complete verification',
                      style: AppTextStyles.labelLarge
                          .copyWith(color: AppColors.warning)),
                  Text(
                      'Verify your identity to start earning',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => context.go('/kyc'),
              child: Text('Verify',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
  }
}
