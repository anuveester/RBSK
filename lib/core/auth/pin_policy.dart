/// The approved credential format: a 6-digit numeric PIN
/// (docs/27_PHASE_1_4_PLAN.md §0, decision 5).
abstract final class PinPolicy {
  static const int length = 6;

  static final RegExp _pattern = RegExp(r'^[0-9]{6}$');

  static bool isValid(String pin) => _pattern.hasMatch(pin);
}
