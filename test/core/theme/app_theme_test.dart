import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/theme/app_colors.dart';
import 'package:referredline/core/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('light theme uses Material 3 and a light colour scheme', () {
      final theme = AppTheme.light();

      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('dark theme uses Material 3 and a dark colour scheme', () {
      final theme = AppTheme.dark();

      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('light and dark schemes differ', () {
      expect(
        AppTheme.light().colorScheme.surface,
        isNot(AppTheme.dark().colorScheme.surface),
      );
    });

    test('sync state colours are distinct', () {
      final colours = {
        AppColors.synced,
        AppColors.pendingSync,
        AppColors.syncError,
      };

      expect(colours.length, 3);
    });
  });
}
