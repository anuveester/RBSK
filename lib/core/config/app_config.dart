enum AppEnvironment { dev, prod }

/// Build-time configuration supplied via `--dart-define`.
///
/// Secrets are never hardcoded here and never committed; later phases inject
/// them the same way (docs/06_PROJECT_STRUCTURE.md §Environment/config).
abstract final class AppConfig {
  static const String _environmentName =
      String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  static AppEnvironment get environment => switch (_environmentName) {
        'prod' => AppEnvironment.prod,
        _ => AppEnvironment.dev,
      };

  static bool get isProduction => environment == AppEnvironment.prod;
}
