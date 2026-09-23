import 'package:flutter/material.dart';

abstract final class AppColors {
  /// Seed for the Material 3 colour scheme.
  static const Color seed = Color(0xFF00695C);

  /// Semantic colours for sync state, shown on records throughout the app
  /// (docs/07_OFFLINE_SYNC_ARCHITECTURE.md §Sync status surfaced to the user).
  static const Color synced = Color(0xFF2E7D32);
  static const Color pendingSync = Color(0xFFEF6C00);
  static const Color syncError = Color(0xFFC62828);
}
