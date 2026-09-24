import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/awc_master/presentation/screens/awc_detail_screen.dart';
import '../../features/awc_master/presentation/screens/awc_duplicates_screen.dart';
import '../../features/awc_master/presentation/screens/awc_form_screen.dart';
import '../../features/awc_master/presentation/screens/awc_list_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/more/presentation/screens/more_screen.dart';
import '../../features/referrals/presentation/screens/referrals_placeholder_screen.dart';
import '../../features/reports/presentation/screens/reports_placeholder_screen.dart';
import '../../features/school_master/presentation/screens/school_detail_screen.dart';
import '../../features/school_master/presentation/screens/school_duplicates_screen.dart';
import '../../features/school_master/presentation/screens/school_form_screen.dart';
import '../../features/school_master/presentation/screens/school_list_screen.dart';
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
                routes: [
                  // School and AWC masters (docs/35_PHASE_1_5_PLAN.md §15).
                  // `add` and `duplicates` are listed before `:id` so they
                  // are never read as a record id.
                  GoRoute(
                    path: 'schools',
                    name: Routes.schoolsName,
                    builder: (context, state) => const SchoolListScreen(),
                    routes: [
                      GoRoute(
                        path: 'add',
                        name: Routes.schoolAddName,
                        builder: (context, state) => const SchoolFormScreen(),
                      ),
                      GoRoute(
                        path: 'duplicates',
                        name: Routes.schoolDuplicatesName,
                        builder: (context, state) =>
                            const SchoolDuplicatesScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        name: Routes.schoolDetailName,
                        builder: (context, state) =>
                            SchoolDetailScreen(id: state.pathParameters['id']!),
                        routes: [
                          GoRoute(
                            path: 'edit',
                            name: Routes.schoolEditName,
                            builder: (context, state) => SchoolFormScreen(
                              id: state.pathParameters['id'],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'awcs',
                    name: Routes.awcsName,
                    builder: (context, state) => const AwcListScreen(),
                    routes: [
                      GoRoute(
                        path: 'add',
                        name: Routes.awcAddName,
                        builder: (context, state) => const AwcFormScreen(),
                      ),
                      GoRoute(
                        path: 'duplicates',
                        name: Routes.awcDuplicatesName,
                        builder: (context, state) => const AwcDuplicatesScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        name: Routes.awcDetailName,
                        builder: (context, state) =>
                            AwcDetailScreen(id: state.pathParameters['id']!),
                        routes: [
                          GoRoute(
                            path: 'edit',
                            name: Routes.awcEditName,
                            builder: (context, state) => AwcFormScreen(
                              id: state.pathParameters['id'],
                            ),
                          ),
                        ],
                      ),
                    ],
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
