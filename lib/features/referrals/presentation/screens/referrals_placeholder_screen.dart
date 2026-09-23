import 'package:flutter/material.dart';

import '../../../../core/widgets/placeholder_destination.dart';

/// Referrals destination — placeholder only. Referral/treatment work is not
/// yet scheduled to a numbered phase.
class ReferralsPlaceholderScreen extends StatelessWidget {
  const ReferralsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderDestination(
      title: 'Referrals',
      icon: Icons.local_hospital_outlined,
    );
  }
}
