import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/auth/onboarding_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/otp_screen.dart';
import '../screens/auth/account_type_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/client/home/client_home_screen.dart';
import '../screens/client/post_task/post_task_screen.dart';
import '../screens/client/tracking/task_detail_screen.dart';
import '../screens/client/tracking/applicants_screen.dart';
import '../screens/client/tracking/active_task_screen.dart';
import '../screens/agent/home/agent_home_screen.dart';
import '../screens/agent/home/task_browse_screen.dart';
import '../screens/agent/job/active_job_screen.dart';
import '../screens/shared/agent_profile_screen.dart';
import '../screens/shared/verification_pending_screen.dart';
import '../screens/shared/kyc_flow_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final isAuth = authState.status == AuthStatus.authenticated;
      final isLoading = authState.status == AuthStatus.unknown;
      final path = state.matchedLocation;

      // Wait for auth check
      if (isLoading) return '/splash';

      // Public routes — always accessible
      final publicRoutes = ['/splash', '/onboarding', '/login', '/register', '/otp', '/account-type'];
      if (publicRoutes.contains(path)) {
        if (isAuth) {
          // Redirect logged-in users away from auth screens
          final user = authState.user;
          if (user == null) return '/login';
          if (user.isAgent) return '/agent/home';
          return '/client/home';
        }
        return null;
      }

      // Protected routes
      if (!isAuth) return '/login';

      // Role-based routing
      final user = authState.user!;
      if (path.startsWith('/client') && !user.isClient) return '/agent/home';
      if (path.startsWith('/agent') && !user.isAgent) return '/client/home';

      return null;
    },
    routes: [
      // ── Auth ──────────────────────────────────────────────────────────────
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
        path: '/otp',
        builder: (_, state) {
          final phone = state.extra as String? ?? '';
          return OtpScreen(phone: phone);
        },
      ),
      GoRoute(
        path: '/account-type',
        builder: (_, state) {
          final phone = state.extra as String? ?? '';
          return AccountTypeScreen(phone: phone);
        },
      ),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),

      // ── Shared (authenticated) ────────────────────────────────────────────
      GoRoute(path: '/kyc', builder: (_, __) => const KycFlowScreen()),
      GoRoute(path: '/verification-pending', builder: (_, __) => const VerificationPendingScreen()),
      GoRoute(
        path: '/agent/:agentId/profile',
        builder: (_, state) => AgentProfileScreen(
          agentId: state.pathParameters['agentId']!,
        ),
      ),

      // ── Client Shell ──────────────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => ClientShell(child: child),
        routes: [
          GoRoute(path: '/client/home', builder: (_, __) => const ClientHomeScreen()),
          GoRoute(path: '/client/post-task', builder: (_, __) => const PostTaskScreen()),
          GoRoute(
            path: '/client/task/:taskId',
            builder: (_, state) => TaskDetailScreen(
              taskId: state.pathParameters['taskId']!,
            ),
          ),
          GoRoute(
            path: '/client/task/:taskId/applicants',
            builder: (_, state) => ApplicantsScreen(
              taskId: state.pathParameters['taskId']!,
            ),
          ),
          GoRoute(
            path: '/client/task/:taskId/track',
            builder: (_, state) => ActiveTaskScreen(
              taskId: state.pathParameters['taskId']!,
            ),
          ),
        ],
      ),

      // ── Agent Shell ───────────────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => AgentShell(child: child),
        routes: [
          GoRoute(path: '/agent/home', builder: (_, __) => const AgentHomeScreen()),
          GoRoute(path: '/agent/browse', builder: (_, __) => const TaskBrowseScreen()),
          GoRoute(
            path: '/agent/task/:taskId',
            builder: (_, state) => ActiveJobScreen(
              taskId: state.pathParameters['taskId']!,
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.error}')),
    ),
  );
});

// ─── Client Shell — Bottom Navigation ────────────────────────────────────────

class ClientShell extends StatelessWidget {
  final Widget child;
  const ClientShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: _ClientBottomNav(),
    );
  }
}

class _ClientBottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    int currentIndex = 0;
    if (location.startsWith('/client/home')) currentIndex = 0;
    else if (location.startsWith('/client/post')) currentIndex = 1;
    else if (location.contains('/task')) currentIndex = 2;

    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (i) {
        switch (i) {
          case 0: context.go('/client/home'); break;
          case 1: context.go('/client/post-task'); break;
          case 2: context.go('/client/home'); break;
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), activeIcon: Icon(Icons.add_circle), label: 'Post Task'),
        BottomNavigationBarItem(icon: Icon(Icons.task_alt_outlined), activeIcon: Icon(Icons.task_alt), label: 'My Tasks'),
      ],
    );
  }
}

// ─── Agent Shell — Bottom Navigation ─────────────────────────────────────────

class AgentShell extends StatelessWidget {
  final Widget child;
  const AgentShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: _AgentBottomNav(),
    );
  }
}

class _AgentBottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    int currentIndex = 0;
    if (location == '/agent/home') currentIndex = 0;
    else if (location == '/agent/browse') currentIndex = 1;

    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (i) {
        switch (i) {
          case 0: context.go('/agent/home'); break;
          case 1: context.go('/agent/browse'); break;
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Dashboard'),
        BottomNavigationBarItem(icon: Icon(Icons.search), activeIcon: Icon(Icons.search), label: 'Browse Tasks'),
      ],
    );
  }
}

// Phase 3 screen imports — add these to the import block at top of router.dart
// import '../screens/shared/phase3_screens.dart';
