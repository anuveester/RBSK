abstract final class Routes {
  /// Shown only while the auth state is still being read at startup.
  static const String splash = '/splash';
  static const String splashName = 'splash';

  /// First-run Admin setup — reachable only while no user exists.
  static const String setup = '/setup';
  static const String setupName = 'setup';

  static const String login = '/login';
  static const String loginName = 'login';

  // The five shell destinations (docs/02_SCREEN_MAP.md §Navigation shell).
  static const String home = '/';
  static const String homeName = 'home';

  static const String visits = '/visits';
  static const String visitsName = 'visits';

  static const String referrals = '/referrals';
  static const String referralsName = 'referrals';

  static const String reports = '/reports';
  static const String reportsName = 'reports';

  static const String more = '/more';
  static const String moreName = 'more';

  /// Routes that exist outside the authenticated shell.
  static const Set<String> unauthenticatedOnly = {splash, setup, login};
}
