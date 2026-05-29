// Phase 3 route additions — integrate into router.dart GoRoute list:
//
// GoRoute(path: '/client/wallet', builder: (_, __) => const WalletScreen()),
// GoRoute(path: '/agent/earnings', builder: (_, __) => const AgentEarningsScreen()),
// GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
// GoRoute(path: '/agent/level-up/:level', builder: (_, state) =>
//     LevelUpScreen(newLevel: state.pathParameters['level']!)),
// GoRoute(path: '/client/task/:taskId/review', builder: (_, state) {
//     final extra = state.extra as Map<String, dynamic>? ?? {};
//     return ReviewScreen(taskId: state.pathParameters['taskId']!, taskTitle: extra['title'] ?? '');
// }),

export 'router.dart';
