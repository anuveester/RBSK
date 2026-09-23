import 'package:flutter/material.dart';

import '../../../../core/widgets/placeholder_destination.dart';

/// Reports destination — placeholder only. Reporting/export is not yet
/// scheduled to a numbered phase.
class ReportsPlaceholderScreen extends StatelessWidget {
  const ReportsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderDestination(
      title: 'Reports',
      icon: Icons.bar_chart_outlined,
    );
  }
}
