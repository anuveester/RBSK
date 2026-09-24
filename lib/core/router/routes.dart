abstract final class Routes {
  /// Shown only while the auth state is still being read at startup, or when
  /// it could not be read (e.g. the database key is unavailable).
  static const String splash = '/splash';
  static const String splashName = 'splash';

  /// First-run Admin setup — reachable only while no user exists.
  static const String setup = '/setup';
  static const String setupName = 'setup';

  static const String login = '/login';
  static const String loginName = 'login';

  /// Reset the Admin PIN with the Admin Recovery Code.
  static const String recoverPin = '/recover-pin';
  static const String recoverPinName = 'recover-pin';

  /// Restore from an encrypted recovery package, and set Admin access
  /// afterwards.
  static const String restore = '/restore';
  static const String restoreName = 'restore';

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

  /// Admin-only screens under More (docs/04 §3: users manage, backup export
  /// — ADMIN only).
  static const String moreRecoveryCode = '/more/recovery-code';
  static const String moreRecoveryCodeName = 'more-recovery-code';
  static const String moreBackup = '/more/backup';
  static const String moreBackupName = 'more-backup';

  /// Routes that exist outside the authenticated shell.
  static const Set<String> unauthenticatedOnly = {
    splash,
    setup,
    login,
    recoverPin,
    restore,
  };

  /// Routes only an Admin may open, even by direct navigation.
  static const Set<String> adminOnly = {moreRecoveryCode, moreBackup};
}
