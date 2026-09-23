import 'package:drift/drift.dart';
import 'package:referredline/data/local/app_database.dart' as db;
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/domain/entities/referral_destination.dart';
import 'package:referredline/domain/repositories/referral_destination_repository.dart';

/// See drift_financial_year_repository.dart for why `app_database.dart` is
/// imported with a `db.` prefix here — the generated `ReferralDestination`
/// and `ReferralDestinationContext` row classes collide with this project's
/// own domain entity names.
class DriftReferralDestinationRepository
    implements ReferralDestinationRepository {
  DriftReferralDestinationRepository(this._db);

  final db.AppDatabase _db;

  @override
  Future<List<ReferralDestination>> getDestinations({
    required LocationType context,
    DiseaseCategory? category,
  }) async {
    final query =
        _db.select(_db.referralDestinationContexts).join([
            innerJoin(
              _db.referralDestinations,
              _db.referralDestinations.id.equalsExp(
                _db.referralDestinationContexts.referralDestinationId,
              ),
            ),
          ])
          ..where(_db.referralDestinationContexts.context.equalsValue(context));

    // A context row with a NULL finding_category applies to every category
    // (School's rows). A row with a specific category applies only when the
    // caller asks for that exact category. Asking for AWC routing with no
    // category returns nothing — deliberately: AWC routing is genuinely
    // category-dependent, so there is no honest "all AWC destinations"
    // answer to give (docs/20_REFERRAL_CONFIGURATION.md §3).
    if (category != null) {
      query.where(
        _db.referralDestinationContexts.findingCategory.equalsValue(
              category,
            ) |
            _db.referralDestinationContexts.findingCategory.isNull(),
      );
    } else {
      query.where(_db.referralDestinationContexts.findingCategory.isNull());
    }

    final rows = await query.get();
    return rows.map((row) {
      final dest = row.readTable(_db.referralDestinations);
      return ReferralDestination(
        id: dest.id,
        code: dest.code,
        label: dest.label,
        description: dest.description,
      );
    }).toList();
  }
}
