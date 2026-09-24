import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/more/presentation/screens/more_screen.dart';
import '../../features/referrals/presentation/screens/referrals_placeholder_screen.dart';
import '../../features/reports/presentation/screens/reports_placeholder_screen.dart';
import '../../features/visits/presentation/screens/visits_placeholder_screen.dart';
import 'app_shell.dart';
import 'routes.dart';

/// The app starts directly in the five-destination shell. There is no
/// authentication: the Phase 1.4 implementation was intentionally removed
/// and will be redesigned after the functional application is complete.
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = createRouter();
  ref.onDispose(router.dispose);
  return router;
});

GoRouter createRouter({String initialLocation = Routes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
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
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
