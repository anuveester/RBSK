import 'package:flutter/material.dart';

import '../../../../core/widgets/placeholder_destination.dart';

/// More destination — placeholder only. Its entries (settings, user and
/// staff management, backup, audit log) belong to later phases.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderDestination(
      title: 'More',
      icon: Icons.more_horiz,
    );
  }
}
