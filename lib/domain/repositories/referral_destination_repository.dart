import 'package:referredline/data/local/enums.dart';
import 'package:referredline/domain/entities/referral_destination.dart';

abstract interface class ReferralDestinationRepository {
  /// Returns the destinations valid for [context] (SCHOOL or AWC), optionally
  /// narrowed by [category]. A School query never returns an AWC-only
  /// destination (DEIC, NRC) and vice versa — the two vocabularies are never
  /// merged (docs/20_REFERRAL_CONFIGURATION.md).
  Future<List<ReferralDestination>> getDestinations({
    required LocationType context,
    DiseaseCategory? category,
  });
}
