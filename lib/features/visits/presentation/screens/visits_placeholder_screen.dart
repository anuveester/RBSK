import 'package:flutter/material.dart';

import '../../../../core/widgets/placeholder_destination.dart';

/// Visits destination — placeholder only. Visit planning is Phase 1.7.
class VisitsPlaceholderScreen extends StatelessWidget {
  const VisitsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderDestination(
      title: 'Visits',
      icon: Icons.event_note_outlined,
    );
  }
}
