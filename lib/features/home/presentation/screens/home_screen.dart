import 'package:flutter/material.dart';

import '../../../../core/widgets/placeholder_destination.dart';

/// Home destination — placeholder only. Today's Visit, sync status and
/// shortcuts (docs/02_SCREEN_MAP.md screen 3) belong to later phases.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderDestination(
      title: 'Home',
      icon: Icons.home_outlined,
    );
  }
}
