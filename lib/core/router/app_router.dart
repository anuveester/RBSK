import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/auth_status.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/auth/presentation/screens/admin_setup_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/pin_recovery_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/recovery/presentation/screens/backup_screen.dart';
import '../../features/recovery/presentation/screens/recovery_code_screen.dart';
import '../../features/recovery/presentation/screens/restore_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/more/presentation/screens/more_screen.dart';
import '../../features/referrals/presentation/screens/referrals_placeholder_screen.dart';
import '../../features/reports/presentation/screens/reports_placeholder_screen.dart';
import '../../features/visits/presentation/screens/visits_placeholder_screen.dart';
import 'app_shell.dart';
import 'auth_redirect.dart';
import 'routes.dart';

/// One router for the app's lifetime. Auth changes don't rebuild it; they
/// update [authStatus], which go_router listens to and re-runs the redirect.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authStatus = ValueNotifier<AuthStatus?>(
    ref.read(authControllerProvider).value,
  );
  ref.listen(
    authControllerProvider,
    (_, next) => authStatus.value = next.value,
  );

  final router = createRouter(authStatus: authStatus);
  ref.onDispose(() {
    router.dispose();
    authStatus.dispose();
  });
  return router;
});

GoRouter createRouter({
  required ValueListenable<AuthStatus?> authStatus,
  String initialLocation = Routes.home,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: authStatus,
    redirect: (context, state) =>
        resolveAuthRedirect(authStatus.value, state.uri.path),
    routes: <RouteBase>[
      GoRoute(
        path: Routes.splash,
        name: Routes.splashName,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.setup,
        name: Routes.setupName,
        builder: (context, state) => const AdminSetupScreen(),
      ),
      GoRoute(
        path: Routes.login,
        name: Routes.loginName,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.recoverPin,
        name: Routes.recoverPinName,
        builder: (context, state) => const PinRecoveryScreen(),
      ),
      GoRoute(
        path: Routes.restore,
        name: Routes.restoreName,
        builder: (context, state) => const RestoreScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                name: Routes.homeName,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.visits,
                name: Routes.visitsName,
                builder: (context, state) => const VisitsPlaceholderScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.referrals,
                name: Routes.referralsName,
                builder: (context, state) => const ReferralsPlaceholderScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.reports,
                name: Routes.reportsName,
                builder: (context, state) => const ReportsPlaceholderScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.more,
                name: Routes.moreName,
                builder: (context, state) => const MoreScreen(),
                routes: [
                  GoRoute(
                    path: 'recovery-code',
                    name: Routes.moreRecoveryCodeName,
                    builder: (context, state) => const RecoveryCodeScreen(),
                  ),
                  GoRoute(
                    path: 'backup',
                    name: Routes.moreBackupName,
                    builder: (context, state) => const BackupScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
