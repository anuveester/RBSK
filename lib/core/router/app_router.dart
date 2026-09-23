import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/screens/home_placeholder_screen.dart';
import 'routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) => createRouter());

GoRouter createRouter({String initialLocation = Routes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: Routes.home,
        name: Routes.homeName,
        builder: (context, state) => const HomePlaceholderScreen(),
      ),
    ],
  );
}
