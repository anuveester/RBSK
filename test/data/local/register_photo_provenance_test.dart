import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/enums.dart';

import 'test_database.dart';

/// Phase 1.2 instruction §10: only the DATABASE STRUCTURES for the register-
/// photo/provenance architecture — no camera, no image processing, no OCR
/// engine. This test proves the schema can represent the full pipeline
/// (original → derivative → OCR job → OCR result → verification →
/// screening linkage) with the original conceptually immutable throughout.
void main() {
  test(
    'the full provenance chain is representable: original photo, a '
    'preprocessing derivative that does not touch the original, an OCR job, '
    'and an OCR result with an explicit unreviewed verification status',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);

      final fyId = await seeds.financialYear();
      final schoolId = await seeds.school();
      final userId = await seeds.user();
      final visitId = await seeds.visitPlanForSchool(
        financialYearId: fyId,
        schoolId: schoolId,
      );

      await db.into(db.registerPhotos).insert(
            RegisterPhotosCompanion.insert(
              id: 'photo-1',
              visitPlanId: visitId,
              capturedBy: userId,
              localFilePath: const Value('/app-private/photo-1.jpg'),
            ),
          );

      // Preprocessing writes a SEPARATE row — the original row above is
      // never updated or overwritten by this insert.
      await db.into(db.registerPhotoDerivatives).insert(
            RegisterPhotoDerivativesCompanion.insert(
              id: 'derivative-1',
              registerPhotoId: 'photo-1',
              kind: DerivativeKind.DESKEWED,
              localFilePath: const Value('/app-private/photo-1-deskewed.jpg'),
            ),
          );

      await db.into(db.ocrJobs).insert(
            OcrJobsCompanion.insert(
              id: 'job-1',
              registerPhotoId: 'photo-1',
              status: const Value(OcrJobStatus.COMPLETED),
            ),
          );

      await db.into(db.ocrResults).insert(
            OcrResultsCompanion.insert(
              id: 'result-1',
              ocrJobId: 'job-1',
              rowIndex: 0,
              extractedFields: '{"child_name":"(placeholder)"}',
            ),
          );

      final photo = await (db.select(
        db.registerPhotos,
      )..where((t) => t.id.equals('photo-1'))).getSingle();
      final derivatives = await (db.select(db.registerPhotoDerivatives)
            ..where((t) => t.registerPhotoId.equals('photo-1')))
          .get();
      final result = await (db.select(
        db.ocrResults,
      )..where((t) => t.id.equals('result-1'))).getSingle();

      // The original is untouched and still points at its own file.
      expect(photo.localFilePath, '/app-private/photo-1.jpg');
      expect(derivatives, hasLength(1));
      expect(derivatives.single.localFilePath,
          '/app-private/photo-1-deskewed.jpg');

      // Nothing is trusted data yet.
      expect(result.verificationStatus, VerificationStatus.UNREVIEWED);
      expect(result.linkedSchoolScreeningId, isNull);
      expect(result.correctedFields, isNull);
    },
  );

  test(
    'an OCR result only becomes a real screening record once confirmed — '
    'the hard rule is representable, not auto-applied by the schema',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);

      final fyId = await seeds.financialYear();
      final schoolId = await seeds.school();
      final userId = await seeds.user();
      final visitId = await seeds.visitPlanForSchool(
        financialYearId: fyId,
        schoolId: schoolId,
      );

      await db.into(db.registerPhotos).insert(
            RegisterPhotosCompanion.insert(
              id: 'photo-2',
              visitPlanId: visitId,
              capturedBy: userId,
            ),
          );
      await db.into(db.ocrJobs).insert(
            OcrJobsCompanion.insert(id: 'job-2', registerPhotoId: 'photo-2'),
          );
      await db.into(db.ocrResults).insert(
            OcrResultsCompanion.insert(
              id: 'result-2',
              ocrJobId: 'job-2',
              rowIndex: 0,
              extractedFields: '{"child_name":"A"}',
            ),
          );

      // Simulate the review step a later phase implements: a human confirms
      // the row, corrected fields are recorded SEPARATELY from the raw
      // extraction, and only then does a real screening row get created and
      // linked back.
      await (db.update(db.ocrResults)..where((t) => t.id.equals('result-2')))
          .write(
        OcrResultsCompanion(
          verificationStatus: const Value(VerificationStatus.CONFIRMED),
          correctedFields: const Value('{"child_name":"Corrected Name"}'),
          reviewedBy: Value(userId),
        ),
      );
      await db.into(db.schoolScreenings).insert(
            SchoolScreeningsCompanion.insert(
              id: 'screening-from-ocr',
              visitPlanId: visitId,
              serialNo: 1,
              screeningDate: DateTime.utc(2026, 4, 1),
              childName: 'Corrected Name',
              gender: Gender.FEMALE,
              ocrResultId: const Value('result-2'),
            ),
          );
      await (db.update(db.ocrResults)..where((t) => t.id.equals('result-2')))
          .write(
        const OcrResultsCompanion(
          linkedSchoolScreeningId: Value('screening-from-ocr'),
        ),
      );

      final result = await (db.select(
        db.ocrResults,
      )..where((t) => t.id.equals('result-2'))).getSingle();
      final screening = await (db.select(
        db.schoolScreenings,
      )..where((t) => t.id.equals('screening-from-ocr'))).getSingle();

      expect(result.extractedFields, '{"child_name":"A"}',
          reason: 'raw extraction is never overwritten by the correction');
      expect(result.correctedFields, '{"child_name":"Corrected Name"}');
      expect(result.linkedSchoolScreeningId, 'screening-from-ocr');
      expect(screening.ocrResultId, 'result-2');
    },
  );
}
